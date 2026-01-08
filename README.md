# DJVU Reader for iOS

A modern iOS DJVU document viewer with djvulibre library integration.

## ✨ Features

- 📱 **Native iOS Support** - optimized for iPhone and iPad
- 📄 **DJVU File Display** - integration with djvulibre 3.5.28
- 🔍 **Flexible Zooming** - from 50% to 300% with smooth animations
- 👆 **Intuitive Gestures** - pinch, double tap, swipes
- 🚀 **High Performance** - optimized file processing

## 🖼️ Screenshots

### Start Page
<img src= "https://github.com/user-attachments/assets/d4d23ae6-dd81-47c6-b482-412761cb8c89" width = "325">

### Page-by-Page View Mode
<img src = "https://github.com/user-attachments/assets/1f202185-fd52-411a-8b93-bf812e9a3466" width = "325">

### Continuous View Mode
<img src = "https://github.com/user-attachments/assets/9b032b2f-a3f0-418c-82ed-380636721e85" width ="325">

## 📥 Installation

### Via TestFlight
*Coming soon*

### Building from Source Code

#### System Requirements
- **For Development:**
  - macOS 13.0 or higher
  - Xcode 15.0 or higher
  - iOS Deployment Target: 16.0+

- **For Usage:**
  - iPhone: iOS 16.0 or higher
  - iPad: iPadOS 16.0 or higher

#### Build Instructions

1. **Clone the repository**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/DJVUReader-iOS.git
   cd DJVUReader-iOS
   ```

2. **Open in Xcode**:
   ```bash
   open DJVUReader-iOS.xcodeproj
   ```

3. **Build and run**:
   - Select simulator or device
   - Press ⌘+R to run

## 📖 Usage

1. **Opening a File**: Tap 📁 to select a DJVU or PDF file
2. **Zooming**: 
   - Buttons [-🔍][+🔍] for precise control
   - Pinch gesture for free zooming
   - Double tap for quick toggle 100%↔200%
3. **Navigation**: Use buttons [←][→] or swipes
4. **Reset**: Button [📐] returns to 100% and centers the page

## 🏗️ Architecture

### Main Components

```
DJVUReader-iOS/
├── 📱 DJVUReader_iOSApp.swift    # Entry point
├── 🎨 ContentView.swift          # Main UI with floating elements
├── 📄 DJVUDocument.swift         # Document model
└── 📚 LibDJVU/                   # djvulibre integration
    ├── djvu_c_interface.h/mm     # C++ bridge
    ├── DJVUNativeReader.swift    # Swift wrapper
    └── include/libdjvu/          # djvulibre headers
```

### Technologies

- **SwiftUI** - modern UI framework
- **djvulibre 3.5.28** - DJVU document rendering
- **PDFKit** - PDF file support
- **Objective-C++** - bridge between Swift and C++

## ⚙️ Technical Implementation

### DJVU Integration
- ✅ djvulibre library
- ✅ Optimized for iOS sandbox
- ✅ Timeouts and error handling
- ✅ Multithreaded processing

### Zooming
- **Range**: 50% - 300%
- **Default**: 100%
- **Button Step**: 25%
- **Auto-reset**: when changing pages

## 🔧 Building djvulibre

The project includes automatic djvulibre building for iOS:

```bash
./build_djvulibre_ios.sh
```

The script automatically:
- Downloads djvulibre 3.5.28
- Compiles for iOS Simulator (arm64, x86_64)
- Creates universal library
- Copies to project

## 📄 License

This project is distributed under the MIT License. See the [LICENSE](LICENSE) file for more information.

## 👨‍💻 Author

**Nikita Krivonosov** - nikskrivonosovv@gmail.com
