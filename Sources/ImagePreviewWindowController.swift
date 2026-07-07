import AppKit
import SwiftUI

final class ImagePreviewWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var hostingView: NSHostingView<ImagePreviewWindowView>?

    init(image: NoteImage, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let initialContentSize = Self.initialContentSize(for: image)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "檢視圖片"
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.center()

        super.init(window: window)
        window.delegate = self

        let hostingView = NSHostingView(rootView: ImagePreviewWindowView(image: image))
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        self.hostingView = hostingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NoteImage) {
        hostingView?.rootView = ImagePreviewWindowView(image: image)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private static func initialContentSize(for image: NoteImage) -> NSSize {
        let imageSize = originalImageSize(for: image)
        let toolbarHeight: CGFloat = 54
        let minimumSize = NSSize(width: 420, height: 320)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maximumSize = NSSize(
            width: min(1100, visibleFrame.width * 0.85),
            height: min(820, visibleFrame.height * 0.85)
        )

        return NSSize(
            width: min(max(imageSize.width, minimumSize.width), maximumSize.width),
            height: min(max(imageSize.height + toolbarHeight, minimumSize.height), maximumSize.height)
        )
    }

    private static func originalImageSize(for image: NoteImage) -> NSSize {
        guard let bitmap = NSBitmapImageRep(data: image.data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else {
            return NSSize(width: max(1, image.width), height: max(1, image.height))
        }
        return NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
}

private struct ImagePreviewWindowView: View {
    let image: NoteImage
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("檢視圖片")
                    .font(.headline)

                Text("按住 Cmd 並滾動來放大/縮小")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    zoom = max(0.25, zoom - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("縮小檢視")

                Button {
                    zoom = min(4.0, zoom + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("放大檢視")

                Text("\(Int(zoom * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            CommandZoomImageScrollView(image: image, zoom: $zoom)
                .background(Color.black.opacity(0.06))
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}

private struct CommandZoomImageScrollView: NSViewRepresentable {
    let image: NoteImage
    @Binding var zoom: Double

    func makeNSView(context: Context) -> CommandZoomScrollView {
        let scrollView = CommandZoomScrollView()
        scrollView.onZoomChange = { newZoom in
            zoom = newZoom
        }
        scrollView.configure(image: image, zoom: zoom)
        return scrollView
    }

    func updateNSView(_ scrollView: CommandZoomScrollView, context: Context) {
        scrollView.onZoomChange = { newZoom in
            zoom = newZoom
        }
        scrollView.configure(image: image, zoom: zoom)
    }
}

private final class CommandZoomScrollView: NSScrollView {
    private let imageView = PreviewImageDocumentView()
    private var originalSize = CGSize(width: 1, height: 1)
    private var imageID: UUID?
    private var currentZoom = 1.0
    var onZoomChange: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = imageView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image noteImage: NoteImage, zoom: Double) {
        let clampedZoom = Self.clampedZoom(zoom)
        if imageID != noteImage.id {
            imageID = noteImage.id
            imageView.image = NSImage(data: noteImage.data)
            originalSize = Self.originalSize(for: noteImage)
            currentZoom = clampedZoom
            updateImageFrame(zoom: clampedZoom)
            scrollToBoundedOrigin(.zero)
            return
        }

        if abs(currentZoom - clampedZoom) > 0.001 {
            applyZoom(clampedZoom, anchorDocumentPoint: visibleCenterDocumentPoint())
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let direction = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            guard direction != 0 else { return }
            let factor = direction > 0 ? 1.1 : 0.9
            let anchorPoint = imageView.convert(event.locationInWindow, from: nil)
            let newZoom = Self.clampedZoom(currentZoom * factor)
            applyZoom(newZoom, anchorDocumentPoint: anchorPoint)
            onZoomChange?(newZoom)
            return
        }

        super.scrollWheel(with: event)
    }

    private func updateImageFrame(zoom: Double) {
        let clampedZoom = Self.clampedZoom(zoom)
        currentZoom = clampedZoom
        let displaySize = NSSize(
            width: originalSize.width * clampedZoom,
            height: originalSize.height * clampedZoom
        )
        imageView.displaySize = displaySize
        imageView.frame = documentFrame(for: displaySize)
    }

    private func applyZoom(_ zoom: Double, anchorDocumentPoint: CGPoint) {
        let oldZoom = max(0.001, currentZoom)
        let visibleRect = contentView.bounds
        let visibleOffset = CGPoint(
            x: anchorDocumentPoint.x - visibleRect.origin.x,
            y: anchorDocumentPoint.y - visibleRect.origin.y
        )
        let scaleFactor = Self.clampedZoom(zoom) / oldZoom

        updateImageFrame(zoom: zoom)

        let newOrigin = CGPoint(
            x: anchorDocumentPoint.x * scaleFactor - visibleOffset.x,
            y: anchorDocumentPoint.y * scaleFactor - visibleOffset.y
        )
        scrollToBoundedOrigin(newOrigin)
    }

    private func visibleCenterDocumentPoint() -> CGPoint {
        let visibleRect = contentView.bounds
        return CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    private func scrollToBoundedOrigin(_ origin: CGPoint) {
        let maximumX = max(0, imageView.frame.width - contentView.bounds.width)
        let maximumY = max(0, imageView.frame.height - contentView.bounds.height)
        let boundedOrigin = CGPoint(
            x: min(max(0, origin.x), maximumX),
            y: min(max(0, origin.y), maximumY)
        )
        contentView.scroll(to: boundedOrigin)
        reflectScrolledClipView(contentView)
    }

    override func tile() {
        super.tile()
        imageView.frame = documentFrame(for: imageView.displaySize)
    }

    private func documentFrame(for displaySize: NSSize) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: max(displaySize.width, contentView.bounds.width),
            height: max(displaySize.height, contentView.bounds.height)
        )
    }

    private static func clampedZoom(_ zoom: Double) -> Double {
        max(0.25, min(4.0, zoom))
    }

    private static func originalSize(for image: NoteImage) -> CGSize {
        guard let bitmap = NSBitmapImageRep(data: image.data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else {
            return CGSize(width: max(1, image.width), height: max(1, image.height))
        }
        return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
}

private final class PreviewImageDocumentView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var displaySize = NSSize(width: 1, height: 1) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }

        image.draw(
            in: NSRect(origin: .zero, size: displaySize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
