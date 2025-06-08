//
//  ContinuousPageView.swift
//  DJVUReader-iOS
//
//  Created by Никита Кривоносов on 08.06.2025.
//

import SwiftUI

struct ContinuousPageView: View {
    @ObservedObject var djvuDocument: DJVUDocument
    let pageIndex: Int
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if let image = djvuDocument.getImageForPage(pageIndex) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            } else {
                // Placeholder для загружающейся страницы в стиле Preview
                Rectangle()
                    .fill(Color.secondary.opacity(0.05))
                    .aspectRatio(0.75, contentMode: .fit)
                    .frame(maxWidth: geometry.size.width)
                    .overlay(
                        VStack(spacing: 8) {
                            if djvuDocument.continuousLoadingQueue.contains(pageIndex) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                            } else {
                                Image(systemName: "doc.text")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Страница \(pageIndex + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if djvuDocument.continuousLoadingQueue.contains(pageIndex) {
                                Text("Загрузка...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            // Запрашиваем загрузку страницы, если она еще не загружена
            let _ = djvuDocument.getImageForPage(pageIndex)
        }
    }
}