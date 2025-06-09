import SwiftUI

struct ContinuousPageView: View {
    @ObservedObject var djvuDocument: DJVUDocument
    let pageIndex: Int
    let geometry: GeometryProxy
    @State private var isVisible = false
    @State private var loadTask: Task<Void, Never>?
    @State private var hasBeenVisible = false
    
    var body: some View {
        Group {
            if let image = djvuDocument.getImageForPage(pageIndex) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width)
                    .background(Color.white)
            } else if hasBeenVisible {
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
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .aspectRatio(0.75, contentMode: .fit)
                    .frame(maxWidth: geometry.size.width)
            }
        }
        .onAppear {
            isVisible = true
            hasBeenVisible = true
            loadTask?.cancel()
            loadTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if isVisible && !Task.isCancelled {
                    let _ = djvuDocument.getImageForPage(pageIndex)
                }
            }
        }
        .onDisappear {
            isVisible = false
            loadTask?.cancel()
            loadTask = nil
        }
    }
}
