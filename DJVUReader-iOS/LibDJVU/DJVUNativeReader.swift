//
//  DJVUNativeReader.swift
//  DJVUReader-iOS
//
//  Created by Никита Кривоносов on 07.06.2025.
//

import Foundation

// MARK: - C Functions Bridge
// Эти функции будут реализованы в C wrapper

/// Инициализирует DjVu контекст
/// - Returns: Указатель на контекст или nil в случае ошибки
func djvu_init() -> OpaquePointer? {
    return djvu_context_init()
}

/// Загружает DjVu документ
/// - Parameters:
///   - context: Контекст DjVu
///   - filePath: Путь к файлу
/// - Returns: 0 в случае успеха, иначе код ошибки
func djvu_load_document(_ context: OpaquePointer, _ filePath: String) -> Int32 {
    return filePath.withCString { cPath in
        return djvu_load_document_from_file(context, cPath)
    }
}

/// Получает количество страниц в документе
/// - Parameter context: Контекст DjVu
/// - Returns: Количество страниц
func djvu_get_page_count(_ context: OpaquePointer) -> Int32 {
    return djvu_get_document_page_count(context)
}

/// Получает размеры страницы
/// - Parameters:
///   - context: Контекст DjVu
///   - pageIndex: Индекс страницы
///   - width: Указатель для записи ширины
///   - height: Указатель для записи высоты
/// - Returns: 0 в случае успеха, иначе код ошибки
func djvu_get_page_size(_ context: OpaquePointer, 
                       _ pageIndex: Int32, 
                       _ width: UnsafeMutablePointer<Int32>, 
                       _ height: UnsafeMutablePointer<Int32>) -> Int32 {
    return djvu_get_page_dimensions(context, pageIndex, width, height)
}

/// Рендерит страницу в буфер пикселей
/// - Parameters:
///   - context: Контекст DjVu
///   - pageIndex: Индекс страницы
///   - width: Ширина изображения
///   - height: Высота изображения
///   - pixelBuffer: Буфер для пикселей (RGBA)
/// - Returns: 0 в случае успеха, иначе код ошибки
func djvu_render_page(_ context: OpaquePointer, 
                     _ pageIndex: Int32, 
                     _ width: Int32, 
                     _ height: Int32, 
                     _ pixelBuffer: UnsafeMutablePointer<UInt8>) -> Int32 {
    return djvu_render_page_to_buffer(context, pageIndex, width, height, pixelBuffer)
}

/// Проверяет, является ли документ PDF файлом
/// - Parameter context: Контекст DjVu
/// - Returns: true если PDF, false если DJVU
func djvu_is_pdf(_ context: OpaquePointer) -> Bool {
    return djvu_is_pdf_document(context) == 1
}

/// Освобождает ресурсы контекста
/// - Parameter context: Контекст DjVu
func djvu_cleanup(_ context: OpaquePointer) {
    djvu_context_cleanup(context)
}