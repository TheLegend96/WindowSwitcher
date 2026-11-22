import AppKit
import ScreenCaptureKit

public class SwitcherWindow: Identifiable, ObservableObject {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public var windowTitle: String
    public let appIcon: NSImage?
    public let bounds: CGRect
    public var isMinimized: Bool
    public var isHidden: Bool
    public var scWindow: SCWindow?
    
    @Published public var thumbnail: NSImage? = nil
    @Published public var isCapturing: Bool = false
    @Published public var isHovered: Bool = false

    public init(
        id: CGWindowID,
        pid: pid_t,
        appName: String,
        windowTitle: String,
        appIcon: NSImage?,
        bounds: CGRect,
        isMinimized: Bool = false,
        isHidden: Bool = false,
        scWindow: SCWindow? = nil
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.windowTitle = windowTitle.isEmpty ? appName : windowTitle
        self.appIcon = appIcon
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.scWindow = scWindow
    }
}
