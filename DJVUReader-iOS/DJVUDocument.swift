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
    
    private var documentURL: URL?
    private var imageCache: [Int: UIImage] = [:]
    private var djvuContext: OpaquePointer?
    private var pdfDocument: PDFDocument?
    private var isPDF: Bool = false
    
    private let backgroundQueue = DispatchQueue(label: "djvu.background", qos: .userInitiated)
    private let progressiveQueue = DispatchQueue(label: "djvu.progressive", qos: .userInitiated)
    private var tempFileURL: URL?
    private var progressiveLoadingTask: DispatchWorkItem?
    
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
        
        if let cachedImage = imageCache[pageIndex] {
            DispatchQueue.main.async {
                self.currentImage = cachedImage
                self.currentPage = pageIndex
                self.isLoading = false
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.currentPage = pageIndex
        }
        
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
        let scale: CGFloat = 2.0 // Масштаб для качества
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        imageCache[pageIndex] = image
        
        DispatchQueue.main.async {
            if self.currentPage == pageIndex {
                self.currentImage = image
                self.isLoading = false
                self.errorMessage = ""
                print("✅ PDF страница \(pageIndex + 1) загружена")
            }
        }
    }
    
    private func loadDJVUPageImage(pageIndex: Int) {
        guard let context = djvuContext else { return }
        
        var width: Int32 = 0
        var height: Int32 = 0
        
        let sizeResult = djvu_get_page_dimensions(context, Int32(pageIndex), &width, &height)
        if sizeResult != 0 {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось получить размер страницы"
                self.isLoading = false
            }
            return
        }
        
        let scale: Float = 2.0 // Масштаб для качества
        let scaledWidth = Int32(Float(width) * scale)
        let scaledHeight = Int32(Float(height) * scale)
        
        let bytesPerPixel = 4
        let dataSize = Int(scaledWidth * scaledHeight * Int32(bytesPerPixel))
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
            // PDF file - should be handled by PDFKit, this shouldn't happen
            DispatchQueue.main.async {
                self.errorMessage = "PDF файлы должны обрабатываться PDFKit"
                self.isLoading = false
            }
            return
        } else if renderResult != 0 {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось отрендерить DJVU страницу"
                self.isLoading = false
            }
            return
        }
        
        guard let image = createUIImage(
            from: pixelData,
            width: Int(scaledWidth),
            height: Int(scaledHeight)
        ) else {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось создать изображение"
                self.isLoading = false
            }
            return
        }
        
        imageCache[pageIndex] = image
        
        DispatchQueue.main.async {
            if self.currentPage == pageIndex {
                self.currentImage = image
                self.isLoading = false
                self.errorMessage = ""
                print("✅ DJVU страница \(pageIndex + 1) загружена с djvulibre")
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
        if currentPage < totalPages - 1 {
            loadPage(currentPage + 1)
        }
    }
    
    func previousPage() {
        if currentPage > 0 {
            loadPage(currentPage - 1)
        }
    }
    
    func goToPage(_ page: Int) {
        if page >= 0 && page < totalPages {
            loadPage(page)
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
        guard let context = djvuContext else { return nil }
        
        var width: Int32 = 0
        var height: Int32 = 0
        
        let sizeResult = djvu_get_page_dimensions(context, Int32(pageIndex), &width, &height)
        if sizeResult != 0 {
            return nil
        }
        
        let scale: Float = 2.0
        let scaledWidth = Int32(Float(width) * scale)
        let scaledHeight = Int32(Float(height) * scale)
        
        let bytesPerPixel = 4
        let dataSize = Int(scaledWidth * scaledHeight * Int32(bytesPerPixel))
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
            // PDF file - should be handled by PDFKit
            return nil
        } else if renderResult != 0 {
            return nil
        }
        
        guard let image = createUIImage(
            from: pixelData,
            width: Int(scaledWidth),
            height: Int(scaledHeight)
        ) else {
            return nil
        }
        
        imageCache[pageIndex] = image
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
    
    
    deinit {
        progressiveLoadingTask?.cancel()
        
        if let context = djvuContext {
            djvu_context_cleanup(context)
        }
        
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
