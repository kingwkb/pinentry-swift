import Cocoa
import SwiftUI

class WindowManager {
    static let shared = WindowManager()
    
    private var window: NSWindow?
    // private var retainingWindow: NSWindow?
    
    // MARK: - Public API
    
    func showInput(
        title: String,
        desc: String,
        prompt: String,
        keyInfo: String,
        okText: String,
        cancelText: String,
        isError: Bool,
        allowKeychain: Bool,
        repeatPrompt: String?,
        repeatError: String,
        completion: @escaping (String?, Bool) -> Void
    ) {
        let view = PinentryView(
            mode: .input,
            title: title,
            desc: desc,
            prompt: prompt,
            keyInfo: keyInfo,
            okText: okText,
            cancelText: cancelText,
            isError: isError,
            allowKeychain: allowKeychain,
            repeatPrompt: repeatPrompt,
            repeatError: repeatError,
            onCommitInput: { p, s in self.safeClose { completion(p, s) } }
        )
        present(view: view, title: title)
    }
    
    func showConfirm(
        title: String,
        desc: String,
        okText: String,
        cancelText: String,
        completion: @escaping (Bool) -> Void
    ) {
        let view = PinentryView(
            mode: .confirm,
            title: title,
            desc: desc,
            prompt: "",
            keyInfo: nil,
            okText: okText,
            cancelText: cancelText,
            isError: false,
            allowKeychain: false,
            repeatPrompt: nil,
            repeatError: "",
            onConfirm: { result in self.safeClose { completion(result) } }
        )
        present(view: view, title: title)
    }
    
    func showMessage(
        title: String,
        desc: String,
        okText: String,
        completion: @escaping () -> Void
    ) {
        let view = PinentryView(
            mode: .message,
            title: title,
            desc: desc,
            prompt: "",
            keyInfo: nil,
            okText: okText,
            cancelText: "",
            isError: false,
            allowKeychain: false,
            repeatPrompt: nil,
            repeatError: "",
            onMessageDismiss: { self.safeClose { completion() } }
        )
        present(view: view, title: title)
    }
    
    // Used by ProtocolParser to close window on timeout
    func forceClose() {
        guard let currentWindow = window else { return }
        currentWindow.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        self.window = nil
    }
    
    // MARK: - Private Helpers
    
    private func present<Content: View>(view: Content, title: String) {
        if let oldWin = window { oldWin.close() }
        
        // Increased height slightly to support double input fields
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.center()
        win.title = title
        // Security: Floating level ensures it stays above standard windows
        win.level = .floating
        // Security: Allow joining all spaces (desktops) and display over full-screen apps
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        win.contentViewController = NSHostingController(rootView: view)
        
        self.window = win
        
//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }
    
    private func safeClose(completion: @escaping () -> Void) {
        guard let currentWindow = window else {
            completion()
            return
        }
        
        currentWindow.makeFirstResponder(nil)
        currentWindow.orderOut(nil)
//        NSApp.setActivationPolicy(.accessory)
        
        completion()
        
        // self.retainingWindow = currentWindow
        self.window = nil
        
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        //     self.retainingWindow = nil
        // }
    }
}
