import AppKit
import SwiftUI
import CoreVideo

// MARK: - CVDisplayLink Wrapper

class CVDisplayLinkWrapper {
    private var displayLink: CVDisplayLink?
    var callback: (() -> Bool)?

    init() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    }

    func start(callback: @escaping () -> Bool) {
        self.callback = callback
        guard let displayLink else { return }

        let opaquePtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnError }
            let wrapper = Unmanaged<CVDisplayLinkWrapper>.fromOpaque(userInfo).takeUnretainedValue()
            let shouldContinue = wrapper.callback?() ?? false
            if !shouldContinue {
                DispatchQueue.main.async {
                    wrapper.stop()
                }
            }
            return kCVReturnSuccess
        }, opaquePtr)

        CVDisplayLinkStart(displayLink)
    }

    func stop() {
        guard let displayLink else { return }
        if CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
    }

    deinit {
        stop()
    }
}

// MARK: - Notch Pill View

class NotchPillView: NSView {
    private let shapeLayer = CAShapeLayer()
    var earProtrusion: CGFloat = 0 {
        didSet { updateShape() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.fillColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        updateShape()
    }

    private func updateShape() {
        let rect = bounds
        let radius: CGFloat = 9.5
        let ear = earProtrusion

        if ear < 0.5 {
            shapeLayer.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: rect.height - radius))
        path.addArc(tangent1End: CGPoint(x: 0, y: rect.height),
                     tangent2End: CGPoint(x: radius, y: rect.height),
                     radius: radius)
        path.addLine(to: CGPoint(x: rect.width - radius, y: rect.height))
        path.addArc(tangent1End: CGPoint(x: rect.width, y: rect.height),
                     tangent2End: CGPoint(x: rect.width, y: rect.height - radius),
                     radius: radius)
        path.addLine(to: CGPoint(x: rect.width, y: radius))
        path.addArc(tangent1End: CGPoint(x: rect.width, y: 0),
                     tangent2End: CGPoint(x: rect.width - radius, y: 0),
                     radius: radius)
        path.addQuadCurve(to: CGPoint(x: rect.width + ear, y: -ear),
                          control: CGPoint(x: rect.width, y: -ear))
        path.addLine(to: CGPoint(x: -ear, y: -ear))
        path.addQuadCurve(to: CGPoint(x: 0, y: radius),
                          control: CGPoint(x: 0, y: -ear))
        path.closeSubpath()
        shapeLayer.path = path
    }
}

// MARK: - Notch Pill Content (SwiftUI overlay)

struct NotchPillContent: View {
    let status: TerminalStatus

    var body: some View {
        HStack(spacing: 4) {
            CrystalBallView(status: status, size: 14)

            if status != .idle {
                statusIndicator
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .working:
            SpinnerView(size: 12, color: .amber)
        case .waitingForInput:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#C0392B"))
        case .taskCompleted:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#FFD700"))
        case .idle, .interrupted:
            EmptyView()
        }
    }
}

struct SpinnerView: View {
    let size: CGFloat
    let color: SpinnerColor

    @State private var rotation: Double = 0

    enum SpinnerColor {
        case amber, white

        var colorValue: Color {
            switch self {
            case .amber: Color(hex: "#D4A843")
            case .white: .white
            }
        }
    }

    var body: some View {
        Circle()
            .trim(from: 0.05, to: 0.8)
            .stroke(color.colorValue, lineWidth: 1.5)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - NotchWindow

class NotchWindow: NSPanel {
    private let pillView = NotchPillView(frame: .zero)
    private var pillContentHost: NSHostingView<NotchPillContent>?
    private let sessionStore: SessionStore

    private var onHover: () -> Void
    private var onEndHover: () -> Void

    var isHovered = false
    private var hideDebounce: DispatchWorkItem?

    private var notchRect: NSRect = .zero
    private var baseWidth: CGFloat = 180
    private var expandedWidth: CGFloat = 260
    private var isExpanded = false

    private let displayLink = CVDisplayLinkWrapper()
    private var expandDebounce: DispatchWorkItem?
    private var currentStatus: TerminalStatus = .idle

    init(
        onHover: @escaping () -> Void,
        onEndHover: @escaping () -> Void,
        sessionStore: SessionStore
    ) {
        self.onHover = onHover
        self.onEndHover = onEndHover
        self.sessionStore = sessionStore

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        setupNotchGeometry()
        setupPillView()
        setupDragDestination()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notchStatusChanged),
            name: .leoNotchStatusChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Geometry

    private func setupNotchGeometry() {
        guard let screen = NSScreen.builtIn else {
            if let main = NSScreen.main {
                let x = main.frame.midX - baseWidth / 2
                let y = main.frame.maxY - 24
                notchRect = NSRect(x: x, y: y, width: baseWidth, height: 24)
            }
            return
        }

        let frame = screen.frame
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchLeft = leftArea.maxX
            let notchRight = rightArea.minX
            let notchWidth = notchRight - notchLeft
            let notchTop = frame.maxY
            let notchBottom = max(leftArea.maxY, rightArea.maxY)
            notchRect = NSRect(
                x: notchLeft,
                y: notchBottom,
                width: notchWidth,
                height: notchTop - notchBottom
            )
        } else {
            let menuBarHeight = screen.frame.height - screen.visibleFrame.height - (screen.visibleFrame.minY - screen.frame.minY)
            let x = frame.midX - baseWidth / 2
            let y = frame.maxY - menuBarHeight
            notchRect = NSRect(x: x, y: y, width: baseWidth, height: menuBarHeight)
        }

        setFrame(notchRect, display: true)
        orderFront(nil)
    }

    private func setupPillView() {
        guard let contentView else { return }

        let pillFrame = NSRect(
            x: (contentView.bounds.width - baseWidth) / 2,
            y: 0,
            width: baseWidth,
            height: contentView.bounds.height
        )
        pillView.frame = pillFrame
        contentView.addSubview(pillView)

        let pillContent = NotchPillContent(status: .idle)
        let hostView = NSHostingView(rootView: pillContent)
        hostView.frame = pillView.bounds
        hostView.autoresizingMask = [.width, .height]
        pillView.addSubview(hostView)
        pillContentHost = hostView
    }

    // MARK: - Mouse Tracking

    func checkMouse(event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        let margin: CGFloat = 15

        let hoverWidth = isExpanded ? expandedWidth : baseWidth
        let hoverRect = NSRect(
            x: notchRect.midX - hoverWidth / 2 - margin,
            y: notchRect.minY - margin,
            width: hoverWidth + margin * 2,
            height: notchRect.height + margin * 2
        )

        let panelContainsMouse: Bool = {
            if let appDelegate = NSApp.delegate as? AppDelegate,
               let panel = appDelegate.terminalPanel,
               panel.isVisible {
                let panelRect = panel.frame.insetBy(dx: -margin, dy: -margin)
                return panelRect.contains(mouseLocation)
            }
            return false
        }()

        let isInHoverArea = hoverRect.contains(mouseLocation) || panelContainsMouse

        if isInHoverArea && !isHovered {
            isHovered = true
            hideDebounce?.cancel()
            animateEars(to: 10, duration: 0.15)
            onHover()
        } else if !isInHoverArea && isHovered {
            hideDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.isHovered = false
                self?.animateEars(to: 0, duration: 0.15)
                self?.onEndHover()
            }
            hideDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        }
    }

    // MARK: - Ear Animation

    private func animateEars(to target: CGFloat, duration: TimeInterval) {
        let startValue = pillView.earProtrusion
        let startTime = CACurrentMediaTime()

        displayLink.start { [weak self] in
            guard let self else { return false }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            let eased = self.cubicEaseInOut(progress)
            let value = startValue + (target - startValue) * CGFloat(eased)

            DispatchQueue.main.async {
                self.pillView.earProtrusion = value
            }

            return progress < 1.0
        }
    }

    // MARK: - Expansion Animation

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        animateWidth(from: baseWidth, to: expandedWidth, duration: 0.35)
        updatePillContent()
    }

    func collapse() {
        guard isExpanded else { return }
        expandDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded else { return }
            self.isExpanded = false
            self.animateWidth(from: self.expandedWidth, to: self.baseWidth, duration: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.updatePillContent()
            }
        }
        expandDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func animateWidth(from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        let startTime = CACurrentMediaTime()

        displayLink.start { [weak self] in
            guard let self else { return false }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            let eased = self.cubicEaseInOut(progress)
            let width = from + (to - from) * CGFloat(eased)

            DispatchQueue.main.async {
                let pillFrame = NSRect(
                    x: (self.frame.width - width) / 2,
                    y: 0,
                    width: width,
                    height: self.frame.height
                )
                self.pillView.frame = pillFrame
            }

            return progress < 1.0
        }
    }

    // MARK: - Status Updates

    @objc private func notchStatusChanged() {
        guard let activeSession = sessionStore.sessions.first(where: { $0.id == sessionStore.activeSessionId }) else {
            currentStatus = .idle
            collapse()
            return
        }

        let newStatus = activeSession.terminalStatus
        if newStatus != currentStatus {
            currentStatus = newStatus
            if newStatus == .working || newStatus == .waitingForInput {
                expand()
            } else if newStatus == .idle {
                collapse()
            }
            updatePillContent()
        }
    }

    private func updatePillContent() {
        let content = NotchPillContent(status: currentStatus)
        pillContentHost?.rootView = content
    }

    // MARK: - Drag Destination

    private func setupDragDestination() {
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !isHovered {
            isHovered = true
            onHover()
        }
        return .none
    }

    // MARK: - Screen Changes

    @objc private func screenDidChange() {
        setupNotchGeometry()
    }

    // MARK: - Easing

    private func cubicEaseInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            return 1 - pow(-2 * t + 2, 3) / 2
        }
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    static var builtIn: NSScreen? {
        screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return CGDisplayIsBuiltin(id) != 0
        }
    }
}
