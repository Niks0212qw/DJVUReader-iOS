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

// Real djvulibre implementation for iOS
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
    NSString *fileExtension = [[nsFilePath pathExtension] lowercaseString];
    
    // Check if it's a PDF file first
    if ([fileExtension isEqualToString:@"pdf"]) {
        NSLog(@"📄 PDF file detected, marking as PDF");
        ctx->is_pdf = true;
        ctx->page_count = 1; // Will be determined by PDFKit in Swift layer
        return 0;
    }
    
    // Check if file exists and is accessible
    if (![[NSFileManager defaultManager] fileExistsAtPath:nsFilePath]) {
        NSLog(@"❌ DJVU file does not exist: %s", file_path);
        return -1;
    }
    
    // Try to read file data to ensure we have access
    NSData *fileData = [NSData dataWithContentsOfFile:nsFilePath];
    if (!fileData || fileData.length < 16) {
        NSLog(@"❌ Cannot read DJVU file or file too small: %s", file_path);
        return -1;
    }
    
    NSLog(@"📖 Loading DJVU file: %s (size: %lu bytes)", file_path, (unsigned long)fileData.length);
    
    // Create document from file data instead of filename
    ctx->document = ddjvu_document_create_by_filename(ctx->ddjvu_context, file_path, FALSE);
    if (!ctx->document) {
        NSLog(@"❌ Failed to create djvu document");
        return -1;
    }
    
    NSLog(@"✅ DJVU document object created, waiting for info...");
    
    // Wait for document to be ready with timeout
    ddjvu_message_t *message;
    int timeout_count = 0;
    const int max_timeout = 50; // ~5 seconds timeout
    
    while (timeout_count < max_timeout) {
        message = ddjvu_message_peek(ctx->ddjvu_context);
        if (!message) {
            usleep(100000); // Wait 100ms
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
    
    // Get page count
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
        // For PDF files, return standard dimensions (will be handled by PDFKit)
        *width = 612;
        *height = 792;
        return 0;
    }
    
    if (!ctx->document) {
        return -1;
    }
    
    // Get page info using djvulibre
    ddjvu_pageinfo_t info;
    ddjvu_status_t status = ddjvu_document_get_pageinfo(ctx->document, page_index, &info);
    
    if (status == DDJVU_JOB_OK) {
        *width = info.width;
        *height = info.height;
        return 0;
    } else {
        // Fallback to default dimensions
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
    
    if (ctx->is_pdf) {
        // PDF files will be handled by PDFKit in Swift layer
        NSLog(@"📄 PDF rendering delegated to PDFKit");
        return -2; // Special code to indicate PDF should use PDFKit
    }
    
    if (!ctx->document) {
        NSLog(@"❌ No DJVU document loaded");
        return -1;
    }
    
    NSLog(@"🎨 Rendering DJVU page %d at %dx%d", page_index + 1, width, height);
    
    // Create page object
    ddjvu_page_t* page = ddjvu_page_create_by_pageno(ctx->document, page_index);
    if (!page) {
        NSLog(@"❌ Failed to create page object");
        return -1;
    }
    
    // Wait for page to be ready with timeout
    ddjvu_message_t *message;
    int page_timeout_count = 0;
    const int max_page_timeout = 100; // ~10 seconds timeout
    
    while (page_timeout_count < max_page_timeout) {
        message = ddjvu_message_peek(ctx->ddjvu_context);
        if (!message) {
            usleep(100000); // Wait 100ms
            page_timeout_count++;
            continue;
        }
        
        if (message->m_any.tag == DDJVU_PAGEINFO) {
            if (message->m_any.page == page) {
                NSLog(@"✅ Page info received");
                ddjvu_message_pop(ctx->ddjvu_context);
                break;
            }
        } else if (message->m_any.tag == DDJVU_ERROR) {
            NSLog(@"❌ Page error: %s", message->m_error.message);
            ddjvu_message_pop(ctx->ddjvu_context);
            ddjvu_page_release(page);
            return -1;
        }
        ddjvu_message_pop(ctx->ddjvu_context);
        page_timeout_count++;
    }
    
    if (page_timeout_count >= max_page_timeout) {
        NSLog(@"❌ Timeout waiting for page info");
        ddjvu_page_release(page);
        return -1;
    }
    
    // Set up rendering parameters
    ddjvu_rect_t prect = {0, 0, (unsigned int)width, (unsigned int)height};
    ddjvu_rect_t rrect = {0, 0, (unsigned int)width, (unsigned int)height};
    
    // Create format for RGB rendering
    ddjvu_format_t* format = ddjvu_format_create(DDJVU_FORMAT_RGB24, 0, nullptr);
    if (!format) {
        NSLog(@"❌ Failed to create format");
        ddjvu_page_release(page);
        return -1;
    }
    
    ddjvu_format_set_row_order(format, 1); // Top to bottom
    ddjvu_format_set_y_direction(format, 1); // Normal Y direction
    
    // Allocate temporary RGB buffer (3 bytes per pixel)
    int rgb_size = width * height * 3;
    unsigned char* rgb_buffer = (unsigned char*)malloc(rgb_size);
    if (!rgb_buffer) {
        NSLog(@"❌ Failed to allocate RGB buffer");
        ddjvu_format_release(format);
        ddjvu_page_release(page);
        return -1;
    }
    
    // Render the page to RGB buffer
    int result = ddjvu_page_render(page, DDJVU_RENDER_COLOR, &prect, &rrect, format, 
                                   width * 3, (char*)rgb_buffer);
    
    if (result) {
        // Convert RGB to RGBA
        for (int i = 0; i < width * height; i++) {
            pixel_buffer[i * 4 + 0] = rgb_buffer[i * 3 + 0]; // R
            pixel_buffer[i * 4 + 1] = rgb_buffer[i * 3 + 1]; // G
            pixel_buffer[i * 4 + 2] = rgb_buffer[i * 3 + 2]; // B
            pixel_buffer[i * 4 + 3] = 255;                    // A (fully opaque)
        }
    }
    
    free(rgb_buffer);
    
    ddjvu_format_release(format);
    ddjvu_page_release(page);
    
    if (result) {
        NSLog(@"✅ DJVU page %d rendered successfully", page_index + 1);
        return 0;
    } else {
        NSLog(@"❌ Failed to render DJVU page %d", page_index + 1);
        return -1;
    }
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