//
//  DJVUDocument.swift
//  DJVUReader-iOS
//
//  Created by Никита Кривоносов on 07.06.2025.
//

import Foundation
import UIKit
import PDFKit

class DJVUDocument: ObservableObject {
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 0
    @Published var currentImage: UIImage?
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    
    private var documentURL: URL?
    private var imageCache: [Int: UIImage] = [:]
    private var djvuContext: OpaquePointer?
    private var pdfDocument: PDFDocument?
    private var isPDF: Bool = false
    
    private let backgroundQueue = DispatchQueue(label: "djvu.background", qos: .userInitiated)
    private var tempFileURL: URL?
    
    private func copyToTempDirectory(from sourceURL: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = sourceURL.lastPathComponent
        let tempURL = tempDir.appendingPathComponent("djvu_\(UUID().uuidString)_\(fileName)")
        
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            
            // Сохраняем ссылку для последующего удаления
            self.tempFileURL = tempURL
            
            NSLog("📋 Файл скопирован во временную директорию: %@", tempURL.path)
            return tempURL
        } catch {
            NSLog("❌ Ошибка копирования файла: %@", error.localizedDescription)
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
        djvuContext = djvu_init()
        
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
        
        // Загружаем документ
        let result = djvu_load_document(context, path)
        
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
        self.isPDF = djvu_is_pdf(context)
        
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
            let pageCount = djvu_get_page_count(context)
            
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
        
        // Кэшируем изображение
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
        
        // Получаем размеры страницы
        var width: Int32 = 0
        var height: Int32 = 0
        
        let sizeResult = djvu_get_page_size(context, Int32(pageIndex), &width, &height)
        if sizeResult != 0 {
            DispatchQueue.main.async {
                self.errorMessage = "Не удалось получить размер страницы"
                self.isLoading = false
            }
            return
        }
        
        // Рендерим страницу
        let scale: Float = 2.0 // Масштаб для качества
        let scaledWidth = Int32(Float(width) * scale)
        let scaledHeight = Int32(Float(height) * scale)
        
        // Выделяем память для пикселей (RGBA)
        let bytesPerPixel = 4
        let dataSize = Int(scaledWidth * scaledHeight * Int32(bytesPerPixel))
        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        
        defer {
            pixelData.deallocate()
        }
        
        let renderResult = djvu_render_page(
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
        
        // Создаем UIImage из пиксельных данных
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
        
        // Кэшируем изображение
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
    
    deinit {
        if let context = djvuContext {
            djvu_cleanup(context)
        }
        
        // Удаляем временный файл
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}