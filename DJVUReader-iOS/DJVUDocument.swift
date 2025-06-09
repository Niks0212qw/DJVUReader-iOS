import Foundation
import UIKit
import PDFKit
import SwiftUI

enum ViewMode: String, CaseIterable {
    case singlePage = "single"
    case continuous = "continuous"
}

class DJVUDocument: ObservableObject {
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 0
    @Published var currentImage: UIImage?
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var allPages: [UIImage] = []
    @Published var continuousImages: [Int: UIImage] = [:]
    @Published var isContinuousLoading: Bool = false
    @Published var continuousLoadingProgress: Float = 0.0
    @Published var viewMode: ViewMode = .singlePage
    
    @Published var continuousLoadingQueue = Set<Int>()
    private let batchSize = 3
    
    // Memory management
    private let maxCacheSize = 10 // Maximum pages to keep in cache
    private let maxMemoryMB = 150 // Maximum memory usage in MB
    private var cacheAccessOrder: [Int] = [] // LRU tracking
    
    private var documentURL: URL?
    private var imageCache: [Int: UIImage] = [:]
    private var djvuContext: OpaquePointer?
    private var pdfDocument: PDFDocument?
    private var isPDF: Bool = false
    
    private let backgroundQueue = DispatchQueue(label: "djvu.background", qos: .userInitiated)
    private let progressiveQueue = DispatchQueue(label: "djvu.progressive", qos: .userInitiated)
    private var tempFileURL: URL?
    private var progressiveLoadingTask: DispatchWorkItem?
    
    // Memory monitoring
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Memory Management
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = self.memoryPressureSource?.mask
            
            if event?.contains(.warning) == true {
                print("⚠️ Memory pressure warning - clearing half of cache")
                self.clearMemoryCache(aggressive: false)
            } else if event?.contains(.critical) == true {
                print("🚨 Memory pressure critical - aggressive cache cleanup")
                self.clearMemoryCache(aggressive: true)
            }
        }
        memoryPressureSource?.resume()
    }
    
    private func clearMemoryCache(aggressive: Bool) {
        let targetSize = aggressive ? 2 : maxCacheSize / 2
        
        // Keep only most recently accessed pages
        while imageCache.count > targetSize && !cacheAccessOrder.isEmpty {
            let oldestPage = cacheAccessOrder.removeFirst()
            imageCache.removeValue(forKey: oldestPage)
            print("🗑️ Removed page \(oldestPage + 1) from cache")
        }
        
        // Clear continuous images if aggressive
        if aggressive {
            continuousImages.removeAll()
            print("🗑️ Cleared continuous images cache")
        }
        
        // Force garbage collection
        DispatchQueue.global(qos: .background).async {
            autoreleasepool {
                // Empty autoreleasepool to encourage cleanup
            }
        }
    }
    
    private func updateCacheAccess(pageIndex: Int) {
        // Remove if already exists
        cacheAccessOrder.removeAll { $0 == pageIndex }
        // Add to end (most recent)
        cacheAccessOrder.append(pageIndex)
        
        // Limit cache size
        while imageCache.count > maxCacheSize && !cacheAccessOrder.isEmpty {
            let oldestPage = cacheAccessOrder.removeFirst()
            if oldestPage != pageIndex { // Don't remove the page we just accessed
                imageCache.removeValue(forKey: oldestPage)
                print("💾 LRU: Removed page \(oldestPage + 1) from cache")
            }
        }
    }
    
    private func estimateMemoryUsage() -> Double {
        var totalBytes: Double = 0
        for (_, image) in imageCache {
            let bytes = image.size.width * image.size.height * image.scale * image.scale * 4 // RGBA
            totalBytes += bytes
        }
        for (_, image) in continuousImages {
            let bytes = image.size.width * image.size.height * image.scale * image.scale * 4
            totalBytes += bytes
        }
        return totalBytes / (1024 * 1024) // Convert to MB
    }
    
    private func copyToTempDirectory(from sourceURL: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension
        
        // Создаем безопасное имя файла, сохраняя расширение
        let safeFileName = "djvu_\(UUID().uuidString).\(fileExtension)"
        let tempURL = tempDir.appendingPathComponent(safeFileName)
        
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            
            // Сохраняем ссылку для последующего удаления
            self.tempFileURL = tempURL
            
            NSLog("📋 Файл '%@' скопирован во временную директорию: %@", fileName, tempURL.path)
            NSLog("📋 Временное имя файла: %@", safeFileName)
            return tempURL
        } catch {
            NSLog("❌ Ошибка копирования файла '%@': %@", fileName, error.localizedDescription)
            return nil
        }
    }
    
    func loadDocument(from url: URL) {
        documentURL = url
        errorMessage = ""
        
        // Clear previous caches
        imageCache.removeAll()
        continuousImages.removeAll() 
        cacheAccessOrder.removeAll()
        
        // Setup memory monitoring
        setupMemoryPressureMonitoring()
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.isLoaded = false
            self.currentImage = nil
        }
        
        backgroundQueue.async {
            self.loadDJVUDocument(from: url)
        }
    }
    
    private func loadDJVUDocument(from url: URL) {
        // Сохраняем доступ к файлу на время работы
        guard url.startAccessingSecurityScopedResource() else {
            DispatchQueue.main.async {
                self.errorMessage = "Нет доступа к выбранному файлу"
                self.isLoading = false
            }
            return
        }
        
        // Инициализируем DjVu контекст
        djvuContext = djvu_context_init()
        
        guard let context = djvuContext else {
            url.stopAccessingSecurityScopedResource()
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось инициализировать DjVu библиотеку"
                self.isLoading = false
            }
            return
        }
        
        // Копируем файл во временную директорию для надежного доступа
        let tempURL = copyToTempDirectory(from: url)
        let path = tempURL?.path ?? url.path
        
        NSLog("📁 Loading DJVU from path: %@", path)
        NSLog("📁 Original file name: %@", url.lastPathComponent)
        
        // Убеждаемся, что путь правильно кодируется в UTF-8
        guard let utf8Path = path.cString(using: .utf8) else {
            DispatchQueue.main.async {
                self.errorMessage = "Ошибка кодирования пути к файлу"
                self.isLoading = false
            }
            return
        }
        
        // Загружаем документ
        let result = djvu_load_document_from_file(context, utf8Path)
        
        // Освобождаем доступ к оригинальному файлу
        url.stopAccessingSecurityScopedResource()
        
        if result != 0 {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось загрузить DJVU файл. Код ошибки: \(result)"
                self.isLoading = false
            }
            return
        }
        
        print("✅ Файл успешно загружен: \(path)")
        
        // Проверяем, это PDF или DJVU
        self.isPDF = djvu_is_pdf_document(context) == 1
        
        if self.isPDF {
            // Для PDF используем PDFKit
            self.pdfDocument = PDFDocument(url: url)
            let pageCount = self.pdfDocument?.pageCount ?? 1
            
            DispatchQueue.main.async {
                self.totalPages = pageCount
                self.isLoaded = true
                print("📖 PDF документ готов: \(pageCount) страниц")
                self.loadPage(0)
            }
        } else {
            // Для DJVU используем наш парсер
            let pageCount = djvu_get_document_page_count(context)
            
            DispatchQueue.main.async {
                self.totalPages = Int(pageCount)
                self.isLoaded = true
                print("📖 DJVU документ готов: \(pageCount) страниц")
                self.loadPage(0)
            }
        }
    }
    
    func loadPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        
        print("🔄 Loading page \(pageIndex + 1)")
        
        // First update current page and loading state
        DispatchQueue.main.async {
            self.currentPage = pageIndex
            self.isLoading = true
        }
        
        // Check cache first
        if let cachedImage = imageCache[pageIndex] {
            updateCacheAccess(pageIndex: pageIndex) // Update LRU
            DispatchQueue.main.async {
                self.currentImage = cachedImage
                self.isLoading = false
                self.errorMessage = ""
                print("📋 Page \(pageIndex + 1) loaded from cache")
                // Force UI update
                self.objectWillChange.send()
            }
            return
        }
        
        // Load in background
        backgroundQueue.async {
            self.loadPageImage(pageIndex: pageIndex)
        }
    }
    
    private func loadPageImage(pageIndex: Int) {
        if isPDF {
            loadPDFPageImage(pageIndex: pageIndex)
        } else {
            loadDJVUPageImage(pageIndex: pageIndex)
        }
    }
    
    private func loadPDFPageImage(pageIndex: Int) {
        guard let pdfDocument = pdfDocument,
              let page = pdfDocument.page(at: pageIndex) else {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось получить PDF страницу"
                self.isLoading = false
            }
            return
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        // Adaptive scaling based on available memory and page size
        let baseArea = pageRect.width * pageRect.height
        let maxArea: CGFloat = 2000000 // 2M pixels max for PDFs
        let scale: CGFloat = baseArea > maxArea ? sqrt(maxArea / baseArea) : min(2.0, UIScreen.main.scale)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        imageCache[pageIndex] = image
        updateCacheAccess(pageIndex: pageIndex)
        
        let memoryUsage = estimateMemoryUsage()
        print("💾 Memory usage: \(String(format: "%.1f", memoryUsage))MB")
        
        DispatchQueue.main.async {
            // Always update current image if this is the requested page
            if self.currentPage == pageIndex {
                self.currentImage = image
                self.isLoading = false
                self.errorMessage = ""
                print("✅ PDF страница \(pageIndex + 1) загружена и отображена")
                // Force UI update
                self.objectWillChange.send()
            } else {
                print("✅ PDF страница \(pageIndex + 1) загружена в кэш")
            }
        }
    }
    
    private func loadDJVUPageImage(pageIndex: Int) {
        guard let image = loadDJVUPageImageSync(pageIndex: pageIndex) else {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось загрузить DJVU страницу \(pageIndex + 1)"
                self.isLoading = false
                // Set failed page image if this is the current page
                if self.currentPage == pageIndex {
                    self.currentImage = self.createFailedPageImage(pageIndex: pageIndex, reason: "Ошибка загрузки")
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            // Always update current image if this is the requested page
            if self.currentPage == pageIndex {
                self.currentImage = image
                self.isLoading = false
                self.errorMessage = ""
                print("✅ DJVU страница \(pageIndex + 1) загружена и отображена")
                // Force UI update
                self.objectWillChange.send()
            } else {
                print("✅ DJVU страница \(pageIndex + 1) загружена в кэш")
            }
        }
    }
    
    private func createUIImage(from pixelData: UnsafeMutablePointer<UInt8>, 
                              width: Int, 
                              height: Int) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Navigation
    func nextPage() {
        let nextPageIndex = currentPage + 1
        if nextPageIndex < totalPages {
            print("➡️ Next page: \(nextPageIndex + 1)")
            loadPage(nextPageIndex)
        } else {
            print("⚠️ Already at last page: \(currentPage + 1)")
        }
    }
    
    func previousPage() {
        let prevPageIndex = currentPage - 1
        if prevPageIndex >= 0 {
            print("⬅️ Previous page: \(prevPageIndex + 1)")
            loadPage(prevPageIndex)
        } else {
            print("⚠️ Already at first page: \(currentPage + 1)")
        }
    }
    
    func goToPage(_ page: Int) {
        if page >= 0 && page < totalPages && page != currentPage {
            print("🎯 Go to page: \(page + 1)")
            loadPage(page)
        } else if page == currentPage {
            print("📋 Already on page: \(page + 1)")
        }
    }
    
    func loadAllPages() {
        guard totalPages > 0 else { return }
        
        // Отменяем предыдущую задачу, если она выполняется
        progressiveLoadingTask?.cancel()
        
        DispatchQueue.main.async {
            self.isContinuousLoading = true
            self.continuousLoadingProgress = 0.0
            self.continuousImages = [:]
            self.allPages = []
        }
        
        // Создаем новую задачу для прогрессивной загрузки
        let loadingTask = DispatchWorkItem { [weak self] in
            self?.performProgressiveLoading()
        }
        
        progressiveLoadingTask = loadingTask
        progressiveQueue.async(execute: loadingTask)
    }
    
    // MARK: - View Mode Management
    func setViewMode(_ mode: ViewMode) {
        print("📱 Переключаем режим просмотра с \(viewMode.rawValue) на \(mode.rawValue)")
        
        DispatchQueue.main.async {
            self.viewMode = mode
            
            if mode == .continuous {
                // Очищаем и заново заполняем continuousImages
                self.continuousImages.removeAll()
                
                // Сначала заполняем continuousImages из кэша
                self.populateContinuousFromCache()
                
                // Принудительно обновляем UI
                self.objectWillChange.send()
                
                // Запускаем загрузку остальных страниц
                self.loadAllPagesForContinuousView()
            }
        }
    }
    
    private func populateContinuousFromCache() {
        print("📋 Заполняем непрерывный режим из кэша: \(imageCache.count) страниц")
        
        for (pageIndex, image) in imageCache {
            continuousImages[pageIndex] = image
            print("✅ Страница \(pageIndex + 1) добавлена из кэша")
        }
    }
    
    private func loadAllPagesForContinuousView() {
        guard totalPages > 0 else { return }
        
        // Отменяем предыдущую задачу
        progressiveLoadingTask?.cancel()
        
        DispatchQueue.main.async {
            self.isContinuousLoading = true
            self.continuousLoadingProgress = 0.0
        }
        
        // Определяем какие страницы нужно загрузить
        let pagesToLoad = Array(0..<totalPages).filter { !continuousImages.keys.contains($0) }
        
        print("🚀 Начинаем загрузку \(pagesToLoad.count) страниц для непрерывного режима")
        
        let loadingTask = DispatchWorkItem { [weak self] in
            self?.performBatchLoading(pages: pagesToLoad)
        }
        
        progressiveLoadingTask = loadingTask
        progressiveQueue.async(execute: loadingTask)
    }
    
    private func performBatchLoading(pages: [Int]) {
        guard !pages.isEmpty else {
            DispatchQueue.main.async {
                self.isContinuousLoading = false
                self.continuousLoadingProgress = 1.0
            }
            return
        }
        
        let totalBatches = (pages.count + batchSize - 1) / batchSize
        
        for batchIndex in 0..<totalBatches {
            // Проверяем, не была ли задача отменена
            guard let task = progressiveLoadingTask, !task.isCancelled else {
                print("❌ Батчевая загрузка отменена")
                return
            }
            
            let startIndex = batchIndex * batchSize
            let endIndex = min(startIndex + batchSize, pages.count)
            let batchPages = Array(pages[startIndex..<endIndex])
            
            print("📦 Загружаем батч \(batchIndex + 1)/\(totalBatches): страницы \(batchPages.map { $0 + 1 })")
            
            let group = DispatchGroup()
            
            for pageIndex in batchPages {
                group.enter()
                
                DispatchQueue.main.async {
                    self.continuousLoadingQueue.insert(pageIndex)
                }
                
                backgroundQueue.async {
                    if let image = self.loadPageImageSync(pageIndex: pageIndex) {
                        DispatchQueue.main.async {
                            self.continuousImages[pageIndex] = image
                            self.continuousLoadingQueue.remove(pageIndex)
                            
                            let loadedCount = self.continuousImages.count
                            let progress = Float(loadedCount) / Float(self.totalPages)
                            self.continuousLoadingProgress = progress
                            
                            print("✅ Страница \(pageIndex + 1) загружена (\(loadedCount)/\(self.totalPages))")
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.continuousLoadingQueue.remove(pageIndex)
                        }
                        print("⚠️ Не удалось загрузить страницу \(pageIndex + 1)")
                    }
                    group.leave()
                }
            }
            
            group.wait()
            
            // Небольшая пауза между батчами
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        DispatchQueue.main.async {
            self.isContinuousLoading = false
            self.continuousLoadingProgress = 1.0
            print("🎉 Батчевая загрузка завершена")
        }
    }
    
    func getImageForPage(_ pageIndex: Int) -> UIImage? {
        if let image = continuousImages[pageIndex] {
            return image
        }
        
        // Если изображения нет, но не идет загрузка, запускаем загрузку
        if !continuousLoadingQueue.contains(pageIndex) && viewMode == .continuous {
            DispatchQueue.main.async {
                self.continuousLoadingQueue.insert(pageIndex)
            }
            
            backgroundQueue.async {
                if let image = self.loadPageImageSync(pageIndex: pageIndex) {
                    DispatchQueue.main.async {
                        self.continuousImages[pageIndex] = image
                        self.continuousLoadingQueue.remove(pageIndex)
                        print("🔄 Страница \(pageIndex + 1) загружена по требованию")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.continuousLoadingQueue.remove(pageIndex)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func performProgressiveLoading() {
        print("🚀 Начинаем прогрессивную загрузку для \(totalPages) страниц")
        
        for pageIndex in 0..<totalPages {
            // Проверяем, не была ли задача отменена
            guard let task = progressiveLoadingTask, !task.isCancelled else {
                print("❌ Прогрессивная загрузка отменена")
                return
            }
            
            // Сначала добавляем страницы из кэша или загружаем новые
            if let cachedImage = imageCache[pageIndex] {
                // Страница уже в кэше
                DispatchQueue.main.async {
                    self.continuousImages[pageIndex] = cachedImage
                    self.updateProgressiveProgress(pageIndex: pageIndex)
                    print("📋 Страница \(pageIndex + 1) загружена из кэша")
                }
            } else {
                // Загружаем страницу в фоне
                if let image = loadPageImageSync(pageIndex: pageIndex) {
                    DispatchQueue.main.async {
                        self.continuousImages[pageIndex] = image
                        self.updateProgressiveProgress(pageIndex: pageIndex)
                        print("✅ Страница \(pageIndex + 1) загружена и добавлена")
                    }
                } else {
                    // Если загрузка не удалась, добавляем плейсхолдер
                    let placeholder = createPlaceholderImage(pageIndex: pageIndex)
                    DispatchQueue.main.async {
                        self.continuousImages[pageIndex] = placeholder
                        self.updateProgressiveProgress(pageIndex: pageIndex)
                        print("⚠️ Страница \(pageIndex + 1) не загружена, добавлен плейсхолдер")
                    }
                }
            }
            
            // Небольшая пауза между загрузками для плавности UI
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        DispatchQueue.main.async {
            self.isContinuousLoading = false
            self.continuousLoadingProgress = 1.0
            print("🎉 Прогрессивная загрузка завершена")
        }
    }
    
    private func updateProgressiveProgress(pageIndex: Int) {
        DispatchQueue.main.async {
            let progress = Float(pageIndex + 1) / Float(self.totalPages)
            self.continuousLoadingProgress = progress
            print("📊 Прогресс загрузки: \(pageIndex + 1)/\(self.totalPages) (\(Int(progress * 100))%)")
        }
    }
    
    private func loadPageImageSync(pageIndex: Int) -> UIImage? {
        guard pageIndex >= 0 && pageIndex < totalPages else { return nil }
        
        if isPDF {
            return loadPDFPageImageSync(pageIndex: pageIndex)
        } else {
            return loadDJVUPageImageSync(pageIndex: pageIndex)
        }
    }
    
    private func loadPDFPageImageSync(pageIndex: Int) -> UIImage? {
        guard let pdfDocument = pdfDocument,
              let page = pdfDocument.page(at: pageIndex) else {
            return nil
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        imageCache[pageIndex] = image
        return image
    }
    
    private func loadDJVUPageImageSync(pageIndex: Int) -> UIImage? {
        guard let context = djvuContext else { 
            print("❌ No DJVU context for page \(pageIndex + 1)")
            return nil 
        }
        
        var width: Int32 = 0
        var height: Int32 = 0
        
        let sizeResult = djvu_get_page_dimensions(context, Int32(pageIndex), &width, &height)
        if sizeResult != 0 {
            print("❌ Failed to get dimensions for page \(pageIndex + 1)")
            return nil
        }
        
        if width <= 0 || height <= 0 {
            print("❌ Invalid dimensions for page \(pageIndex + 1): \(width)x\(height)")
            return nil
        }
        
        let baseArea = Float(width * height)
        let maxArea: Float = 2000000 // Reduced from 4M to 2M pixels to save memory
        let scale: Float = baseArea > maxArea ? sqrt(maxArea / baseArea) : min(2.0, Float(UIScreen.main.scale))
        
        let scaledWidth = Int32(Float(width) * scale)
        let scaledHeight = Int32(Float(height) * scale)
        
        if scaledWidth > 5000 || scaledHeight > 5000 {
            print("⚠️ Page \(pageIndex + 1) too large: \(scaledWidth)x\(scaledHeight)")
            return createFailedPageImage(pageIndex: pageIndex, reason: "Страница слишком большая")
        }
        
        let bytesPerPixel = 4
        let dataSize = Int(scaledWidth * scaledHeight * Int32(bytesPerPixel))
        
        guard dataSize > 0 && dataSize < 50_000_000 else { // Reduced from 100MB to 50MB
            print("❌ Page \(pageIndex + 1) requires too much memory: \(dataSize) bytes")
            return createFailedPageImage(pageIndex: pageIndex, reason: "Недостаточно памяти")
        }
        
        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        
        defer {
            pixelData.deallocate()
        }
        
        let renderResult = djvu_render_page_to_buffer(
            context,
            Int32(pageIndex),
            scaledWidth,
            scaledHeight,
            pixelData
        )
        
        if renderResult == -2 {
            print("❌ Page \(pageIndex + 1) is PDF, should use PDFKit")
            return nil
        } else if renderResult != 0 {
            print("❌ Failed to render page \(pageIndex + 1), error code: \(renderResult)")
            return createFailedPageImage(pageIndex: pageIndex, reason: "Ошибка рендеринга")
        }
        
        guard let image = createUIImage(
            from: pixelData,
            width: Int(scaledWidth),
            height: Int(scaledHeight)
        ) else {
            print("❌ Failed to create UIImage for page \(pageIndex + 1)")
            return createFailedPageImage(pageIndex: pageIndex, reason: "Ошибка создания изображения")
        }
        
        print("✅ Successfully rendered page \(pageIndex + 1) at \(scaledWidth)x\(scaledHeight) (scale: \(scale))")
        imageCache[pageIndex] = image
        updateCacheAccess(pageIndex: pageIndex)
        
        // Additional validation and memory monitoring
        print("🖼️ Image created: \(image.size.width)x\(image.size.height), scale: \(image.scale)")
        let memoryUsage = estimateMemoryUsage()
        print("💾 Memory usage: \(String(format: "%.1f", memoryUsage))MB")
        
        // Proactive memory management
        if memoryUsage > Double(maxMemoryMB) {
            print("⚠️ Memory usage exceeded \(maxMemoryMB)MB, clearing cache")
            DispatchQueue.main.async {
                self.clearMemoryCache(aggressive: false)
            }
        }
        
        return image
    }
    
    private func createPlaceholderImage(pageIndex: Int) -> UIImage {
        let size = CGSize(width: 400, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Белый фон
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            
            UIColor.lightGray.set()
            context.stroke(CGRect(origin: .zero, size: size))
            
            let text = "Страница \(pageIndex + 1)\nНе загружена"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.gray
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func createFailedPageImage(pageIndex: Int, reason: String) -> UIImage {
        let size = CGSize(width: 400, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            
            UIColor.red.withAlphaComponent(0.1).set()
            context.fill(CGRect(origin: .zero, size: size))
            
            UIColor.red.set()
            context.stroke(CGRect(origin: .zero, size: size))
            
            let text = "Страница \(pageIndex + 1)\n\(reason)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
                .foregroundColor: UIColor.red
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    deinit {
        progressiveLoadingTask?.cancel()
        
        // Clean up memory monitoring
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        
        // Clear all caches
        imageCache.removeAll()
        continuousImages.removeAll()
        cacheAccessOrder.removeAll()
        
        if let context = djvuContext {
            djvu_context_cleanup(context)
        }
        
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        print("🧹 DJVUDocument deallocated, memory cleaned up")
    }
}
