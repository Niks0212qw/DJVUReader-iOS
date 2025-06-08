//
//  djvu_c_interface.h
//  DJVUReader-iOS
//
//  Created by Никита Кривоносов on 07.06.2025.
//

#ifndef DJVU_C_INTERFACE_H
#define DJVU_C_INTERFACE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

// Include real djvulibre headers
#include "libdjvu/ddjvuapi.h"
#include "libdjvu/miniexp.h"

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

// Непрозрачный тип для контекста DjVu
typedef struct djvu_context_t djvu_context_t;

/**
 * Инициализирует новый контекст DjVu
 * @return Указатель на контекст или NULL в случае ошибки
 */
djvu_context_t* djvu_context_init(void);

/**
 * Загружает DjVu документ из файла
 * @param ctx Контекст DjVu
 * @param file_path Путь к файлу DjVu
 * @return 0 в случае успеха, иначе код ошибки
 */
int32_t djvu_load_document_from_file(djvu_context_t* ctx, const char* file_path);

/**
 * Получает количество страниц в документе
 * @param ctx Контекст DjVu
 * @return Количество страниц или -1 в случае ошибки
 */
int32_t djvu_get_document_page_count(djvu_context_t* ctx);

/**
 * Получает размеры страницы
 * @param ctx Контекст DjVu
 * @param page_index Индекс страницы (начиная с 0)
 * @param width Указатель для записи ширины
 * @param height Указатель для записи высоты
 * @return 0 в случае успеха, иначе код ошибки
 */
int32_t djvu_get_page_dimensions(djvu_context_t* ctx, int32_t page_index, 
                                int32_t* width, int32_t* height);

/**
 * Рендерит страницу в буфер пикселей RGBA
 * @param ctx Контекст DjVu
 * @param page_index Индекс страницы (начиная с 0)
 * @param width Ширина результирующего изображения
 * @param height Высота результирующего изображения
 * @param pixel_buffer Буфер для пикселей (должен быть размером width * height * 4)
 * @return 0 в случае успеха, иначе код ошибки
 */
int32_t djvu_render_page_to_buffer(djvu_context_t* ctx, int32_t page_index,
                                  int32_t width, int32_t height,
                                  uint8_t* pixel_buffer);

/**
 * Проверяет, является ли документ PDF файлом
 * @param ctx Контекст DjVu
 * @return 1 если PDF, 0 если DJVU
 */
int32_t djvu_is_pdf_document(djvu_context_t* ctx);

/**
 * Освобождает ресурсы контекста DjVu
 * @param ctx Контекст DjVu
 */
void djvu_context_cleanup(djvu_context_t* ctx);

#ifdef __cplusplus
}
#endif

#endif // DJVU_C_INTERFACE_H