//
//  djvu_c_interface.mm
//  DJVUReader-iOS
//
//  Created by Никита Кривоносов on 07.06.2025.
//

#include "djvu_c_interface.h"
#include <memory>
#include <string>
#include <Foundation/Foundation.h>

struct djvu_context_t {
    ddjvu_context_t* ddjvu_context = nullptr;
    ddjvu_document_t* document = nullptr;
    std::string file_path;
    bool is_pdf = false;
    int page_count = 0;
    
    djvu_context_t() {
        ddjvu_context = ddjvu_context_create("DJVUReader-iOS");
    }
    
    ~djvu_context_t() {
        if (document) {
            ddjvu_document_release(document);
        }
        if (ddjvu_context) {
            ddjvu_context_release(ddjvu_context);
        }
    }
};

extern "C" {

djvu_context_t* djvu_context_init(void) {
    try {
        djvu_context_t* ctx = new djvu_context_t();
        if (!ctx->ddjvu_context) {
            delete ctx;
            return nullptr;
        }
        NSLog(@"✅ djvulibre context initialized successfully");
        return ctx;
    } catch (...) {
        NSLog(@"❌ Failed to initialize djvulibre context");
        return nullptr;
    }
}

int32_t djvu_load_document_from_file(djvu_context_t* ctx, const char* file_path) {
    if (!ctx || !file_path || !ctx->ddjvu_context) {
        NSLog(@"❌ Invalid context or file path");
        return -1;
    }
    
    ctx->file_path = file_path;
    
    NSString *nsFilePath = [NSString stringWithUTF8String:file_path];
    if (!nsFilePath) {
        NSLog(@"❌ Failed to convert file path to NSString: %s", file_path);
        return -1;
    }
    
    NSString *fileExtension = [[nsFilePath pathExtension] lowercaseString];
    
    NSLog(@"📁 Processing file: %@", nsFilePath);
    NSLog(@"📁 File extension: %@", fileExtension);
    
    if ([fileExtension isEqualToString:@"pdf"]) {
        NSLog(@"📄 PDF file detected, marking as PDF");
        ctx->is_pdf = true;
        ctx->page_count = 1; // Will be determined by PDFKit in Swift layer
        return 0;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:nsFilePath]) {
        NSLog(@"❌ DJVU file does not exist: %@", nsFilePath);
        return -1;
    }
    
    NSData *fileData = [NSData dataWithContentsOfFile:nsFilePath];
    if (!fileData || fileData.length < 16) {
        NSLog(@"❌ Cannot read DJVU file or file too small: %@ (size: %lu)", nsFilePath, (unsigned long)fileData.length);
        return -1;
    }
    
    NSLog(@"📖 Loading DJVU file: %@ (size: %lu bytes)", nsFilePath, (unsigned long)fileData.length);
    
    const char* utf8_path = [nsFilePath UTF8String];
    if (!utf8_path) {
        NSLog(@"❌ Failed to get UTF8 representation of path");
        return -1;
    }
    
    ctx->document = ddjvu_document_create_by_filename(ctx->ddjvu_context, utf8_path, FALSE);
    if (!ctx->document) {
        NSLog(@"❌ Failed to create djvu document for path: %@", nsFilePath);
        return -1;
    }
    
    NSLog(@"✅ DJVU document object created, waiting for info...");
    
    ddjvu_message_t *message;
    int timeout_count = 0;
    const int max_timeout = 50;
    
    while (timeout_count < max_timeout) {
        message = ddjvu_message_peek(ctx->ddjvu_context);
        if (!message) {
            usleep(100000);
            timeout_count++;
            continue;
        }
        
        if (message->m_any.tag == DDJVU_DOCINFO) {
            if (message->m_any.document == ctx->document) {
                NSLog(@"✅ Document info received");
                ddjvu_message_pop(ctx->ddjvu_context);
                break;
            }
        } else if (message->m_any.tag == DDJVU_ERROR) {
            NSLog(@"❌ DJVU error: %s", message->m_error.message);
            ddjvu_message_pop(ctx->ddjvu_context);
            return -1;
        }
        ddjvu_message_pop(ctx->ddjvu_context);
        timeout_count++;
    }
    
    if (timeout_count >= max_timeout) {
        NSLog(@"❌ Timeout waiting for document info");
        return -1;
    }
    
    ctx->page_count = ddjvu_document_get_pagenum(ctx->document);
    if (ctx->page_count <= 0) {
        NSLog(@"❌ Invalid page count: %d", ctx->page_count);
        return -1;
    }
    
    NSLog(@"✅ DJVU document loaded successfully with %d pages", ctx->page_count);
    return 0;
}

int32_t djvu_get_document_page_count(djvu_context_t* ctx) {
    if (!ctx) {
        return -1;
    }
    
    return ctx->page_count;
}

int32_t djvu_get_page_dimensions(djvu_context_t* ctx, int32_t page_index, 
                                int32_t* width, int32_t* height) {
    if (!ctx || !width || !height || page_index < 0 || page_index >= ctx->page_count) {
        return -1;
    }
    
    if (ctx->is_pdf) {
        *width = 612;
        *height = 792;
        return 0;
    }
    
    if (!ctx->document) {
        return -1;
    }
    
    ddjvu_pageinfo_t info;
    ddjvu_status_t status = ddjvu_document_get_pageinfo(ctx->document, page_index, &info);
    
    if (status == DDJVU_JOB_OK) {
        *width = info.width;
        *height = info.height;
        return 0;
    } else {
        *width = 612;
        *height = 792;
        return 0;
    }
}

int32_t djvu_render_page_to_buffer(djvu_context_t* ctx, int32_t page_index,
                                  int32_t width, int32_t height,
                                  uint8_t* pixel_buffer) {
    if (!ctx || !pixel_buffer || page_index < 0 || page_index >= ctx->page_count) {
        NSLog(@"❌ Invalid render parameters");
        return -1;
    }
    
    // Validate dimensions to prevent memory issues
    if (width <= 0 || height <= 0 || width > 10000 || height > 10000) {
        NSLog(@"❌ Invalid or too large dimensions: %dx%d", width, height);
        return -1;
    }
    
    // Check if the total memory requirement is reasonable (max ~100MB)
    long long total_pixels = (long long)width * height;
    if (total_pixels > 25000000) { // 25M pixels = ~100MB
        NSLog(@"❌ Image too large: %lld pixels would require too much memory", total_pixels);
        return -1;
    }
    
    if (ctx->is_pdf) {
        NSLog(@"📄 PDF rendering delegated to PDFKit");
        return -2;
    }
    
    if (!ctx->document) {
        NSLog(@"❌ No DJVU document loaded");
        return -1;
    }
    
    NSLog(@"🎨 Rendering DJVU page %d at %dx%d (%lld pixels)", page_index + 1, width, height, total_pixels);
    
    ddjvu_page_t* page = ddjvu_page_create_by_pageno(ctx->document, page_index);
    if (!page) {
        NSLog(@"❌ Failed to create page object for page %d", page_index + 1);
        return -1;
    }
    
    ddjvu_message_t *message;
    int page_timeout_count = 0;
    const int max_page_timeout = 100;
    
    bool page_ready = false;
    while (page_timeout_count < max_page_timeout) {
        ddjvu_status_t status = ddjvu_page_decoding_status(page);
        
        if (status == DDJVU_JOB_OK) {
            NSLog(@"✅ Page %d decoded successfully", page_index + 1);
            page_ready = true;
            break;
        } else if (status == DDJVU_JOB_FAILED || status == DDJVU_JOB_STOPPED) {
            NSLog(@"❌ Page %d decoding failed with status: %d", page_index + 1, status);
            ddjvu_page_release(page);
            return -1;
        }
        
        message = ddjvu_message_peek(ctx->ddjvu_context);
        if (message) {
            if (message->m_any.tag == DDJVU_ERROR) {
                NSLog(@"❌ Page %d error: %s", page_index + 1, message->m_error.message);
                ddjvu_message_pop(ctx->ddjvu_context);
                ddjvu_page_release(page);
                return -1;
            }
            ddjvu_message_pop(ctx->ddjvu_context);
        }
        
        usleep(100000);
        page_timeout_count++;
    }
    
    if (!page_ready) {
        NSLog(@"❌ Timeout waiting for page %d to decode (status: %d)", page_index + 1, ddjvu_page_decoding_status(page));
        ddjvu_page_release(page);
        return -1;
    }
    
    ddjvu_rect_t prect = {0, 0, (unsigned int)width, (unsigned int)height};
    ddjvu_rect_t rrect = {0, 0, (unsigned int)width, (unsigned int)height};
    
    ddjvu_format_t* format = ddjvu_format_create(DDJVU_FORMAT_RGB24, 0, nullptr);
    if (!format) {
        NSLog(@"❌ Failed to create format");
        ddjvu_page_release(page);
        return -1;
    }
    
    ddjvu_format_set_row_order(format, 1);
    ddjvu_format_set_y_direction(format, 1);
    
    // Use safer memory allocation with error checking
    size_t rgb_size = (size_t)width * height * 3;
    unsigned char* rgb_buffer = (unsigned char*)calloc(rgb_size, 1);
    if (!rgb_buffer) {
        NSLog(@"❌ Failed to allocate RGB buffer of size %zu bytes", rgb_size);
        ddjvu_format_release(format);
        ddjvu_page_release(page);
        return -1;
    }
    
    int result = ddjvu_page_render(page, DDJVU_RENDER_COLOR, &prect, &rrect, format, 
                                   width * 3, (char*)rgb_buffer);
    
    if (result) {
        // Convert RGB to RGBA safely
        size_t total_pixels = (size_t)width * height;
        for (size_t i = 0; i < total_pixels; i++) {
            pixel_buffer[i * 4 + 0] = rgb_buffer[i * 3 + 0];
            pixel_buffer[i * 4 + 1] = rgb_buffer[i * 3 + 1];
            pixel_buffer[i * 4 + 2] = rgb_buffer[i * 3 + 2];
            pixel_buffer[i * 4 + 3] = 255;
        }
        NSLog(@"✅ DJVU page %d rendered successfully (%zu pixels)", page_index + 1, total_pixels);
    } else {
        NSLog(@"❌ ddjvu_page_render failed for page %d", page_index + 1);
    }
    
    free(rgb_buffer);
    
    ddjvu_format_release(format);
    ddjvu_page_release(page);
    
    return result ? 0 : -1;
}

int32_t djvu_is_pdf_document(djvu_context_t* ctx) {
    if (!ctx) {
        return 0;
    }
    return ctx->is_pdf ? 1 : 0;
}

void djvu_context_cleanup(djvu_context_t* ctx) {
    if (ctx) {
        NSLog(@"🧹 Cleaning up djvulibre context");
        delete ctx; // Destructor will handle djvulibre cleanup
    }
}

} // extern "C"