import SwiftUI

struct ContentView: View {
    @StateObject private var djvuDocument = DJVUDocument()
    @State private var showingDocumentPicker = false
    @State private var zoomLevel: Double = 1.0
    @State private var isScrollMode: Bool = false
    
    var body: some View {
        ZStack {
            if djvuDocument.isLoaded {
                DocumentView(
                    djvuDocument: djvuDocument,
                    zoomLevel: $zoomLevel,
                    isScrollMode: isScrollMode
                )
                
                VStack {
                    HStack {
                        HStack(spacing: 12) {
                            Button(action: {
                                showingDocumentPicker = true
                            }) {
                                Image(systemName: "folder")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    let newMode: ViewMode = djvuDocument.viewMode == .singlePage ? .continuous : .singlePage
                                    djvuDocument.setViewMode(newMode)
                                    isScrollMode = (newMode == .continuous)
                                }
                            }) {
                                Image(systemName: djvuDocument.viewMode == .continuous ? "rectangle.split.3x1" : "doc.plaintext")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring()) {
                                    zoomLevel = max(0.5, zoomLevel - 0.25)
                                }
                            }) {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .disabled(zoomLevel <= 0.5)
                            
                            Text("\(Int(zoomLevel * 100))%")
                                .font(.caption)
                                .frame(width: 35)
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    zoomLevel = min(3.0, zoomLevel + 0.25)
                                }
                            }) {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .disabled(zoomLevel >= 3.0)
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    zoomLevel = 1.0
                                }
                            }) {
                                Image(systemName: "rectangle.compress.vertical")
                            }
                            .disabled(abs(zoomLevel - 1.0) < 0.01)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    
                    Spacer()
                    
                    if djvuDocument.viewMode == .singlePage {
                        HStack(spacing: 20) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    djvuDocument.previousPage()
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            .disabled(djvuDocument.currentPage <= 0)
                            
                            Text("\(djvuDocument.currentPage + 1) / \(djvuDocument.totalPages)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    djvuDocument.nextPage()
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            .disabled(djvuDocument.currentPage >= djvuDocument.totalPages - 1)
                        }
                        .padding(.bottom, 50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            } else {
                WelcomeView(
                    djvuDocument: djvuDocument,
                    showingDocumentPicker: $showingDocumentPicker
                )
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(djvuDocument: djvuDocument)
        }
    }
}

struct DocumentView: View {
    @ObservedObject var djvuDocument: DJVUDocument
    @Binding var zoomLevel: Double
    let isScrollMode: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var currentPageIndex: Int = 0
    @State private var scrollOffset: CGPoint = .zero
    @State private var isUserScrolling = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.gray.opacity(0.1)
                    .ignoresSafeArea()
                
                if djvuDocument.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Загрузка страницы \(djvuDocument.currentPage + 1)")
                            .font(.caption)
                    }
                } else if djvuDocument.viewMode == .continuous {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<djvuDocument.totalPages, id: \.self) { pageIndex in
                                    ContinuousPageView(
                                        djvuDocument: djvuDocument,
                                        pageIndex: pageIndex,
                                        geometry: geometry
                                    )
                                    .id("page-\(pageIndex)")
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            if djvuDocument.currentPage != pageIndex && djvuDocument.viewMode == .continuous && !isUserScrolling {
                                                isUserScrolling = true
                                                djvuDocument.currentPage = pageIndex
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    isUserScrolling = false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .scaleEffect(zoomLevel)
                            .padding(.vertical, 20)
                        }
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if zoomLevel <= 1.0 {
                                    zoomLevel = 2.0
                                } else {
                                    zoomLevel = 1.0
                                }
                            }
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newZoomLevel = max(0.5, min(3.0, value))
                                    zoomLevel = newZoomLevel
                                }
                        )
                        .onAppear {
                            if djvuDocument.currentPage < djvuDocument.totalPages {
                                proxy.scrollTo("page-\(djvuDocument.currentPage)", anchor: .top)
                            }
                        }
                        .onChange(of: djvuDocument.currentPage) { oldValue, newValue in
                            if oldValue != newValue && djvuDocument.viewMode == .continuous && !isUserScrolling {
                                withAnimation(.easeInOut) {
                                    proxy.scrollTo("page-\(newValue)", anchor: .top)
                                }
                            }
                        }
                    }
                    if djvuDocument.isContinuousLoading {
                        VStack {
                            Spacer()
                            
                            HStack {
                                Text("Загрузка страниц: \(djvuDocument.continuousImages.count)/\(djvuDocument.totalPages)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                ProgressView(value: djvuDocument.continuousLoadingProgress, total: 1.0)
                                    .frame(width: 100)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 100)
                        }
                    }
                } else if let image = djvuDocument.currentImage {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomLevel)
                            .offset(x: panOffset.width + dragOffset.width, 
                                   y: panOffset.height + dragOffset.height)
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                    }
                    .contentShape(Rectangle())
                    .clipped()
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if zoomLevel <= 1.0 {
                                zoomLevel = 2.0
                            } else {
                                zoomLevel = 1.0
                                panOffset = .zero
                                lastPanOffset = .zero
                            }
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if zoomLevel > 1.0 {
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                } else {
                                    let threshold: CGFloat = 50
                                    if abs(value.translation.width) > threshold {
                                        dragOffset = CGSize(width: value.translation.width * 0.3, height: 0)
                                    }
                                }
                            }
                            .onEnded { value in
                                if zoomLevel > 1.0 {
                                    lastPanOffset = panOffset
                                } else {
                                    withAnimation(.spring()) {
                                        dragOffset = .zero
                                    }
                                    
                                    let threshold: CGFloat = 80
                                    if abs(value.translation.width) > threshold {
                                        withAnimation(.easeInOut) {
                                            if value.translation.width > 0 {
                                                djvuDocument.previousPage()
                                            } else {
                                                djvuDocument.nextPage()
                                            }
                                        }
                                    }
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoomLevel = max(0.5, min(3.0, value))
                                zoomLevel = newZoomLevel
                                
                                if newZoomLevel <= 1.0 {
                                    panOffset = .zero
                                    lastPanOffset = .zero
                                }
                            }
                            .onEnded { _ in
                                if zoomLevel <= 1.0 {
                                    withAnimation(.spring()) {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                            }
                    )
                } else {
                    Text("Документ не загружен")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: djvuDocument.currentPage) { oldValue, newValue in
            if oldValue != newValue && djvuDocument.viewMode == .singlePage {
                withAnimation(.easeInOut(duration: 0.3)) {
                    zoomLevel = 1.0
                    panOffset = .zero
                    lastPanOffset = .zero
                    dragOffset = .zero
                }
                currentPageIndex = newValue
            }
        }
        .onChange(of: djvuDocument.viewMode) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                zoomLevel = 1.0
                panOffset = .zero
                lastPanOffset = .zero
                dragOffset = .zero
            }
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var djvuDocument: DJVUDocument
    @Binding var showingDocumentPicker: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 10) {
                Text("DJVU Reader")
                    .font(.largeTitle)
                    .fontWeight(.light)
                
                Text("Просмотрщик DJVU документов для iOS")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if !djvuDocument.errorMessage.isEmpty {
                Text(djvuDocument.errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Button(action: {
                showingDocumentPicker = true
            }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Выбрать документ")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let djvuDocument: DJVUDocument
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .init(filenameExtension: "djvu") ?? .data,
            .init(filenameExtension: "djv") ?? .data,
            .pdf
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.djvuDocument.loadDocument(from: url)
        }
    }
}

#Preview {
    ContentView()
}
