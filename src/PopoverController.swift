import AppKit
import SwiftUI

// ポップオーバーの管理を担当
class PopoverController {
    private let popover: NSPopover
    private var eventMonitor: EventMonitor?
    private weak var statusButton: NSStatusBarButton?
    
    init(contentView: some View, statusButton: NSStatusBarButton) {
        self.statusButton = statusButton
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        setupEventMonitor()
    }
    
    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self = self, self.popover.isShown {
                self.close()
            }
        }
    }
    
    func togglePopover() {
        if popover.isShown {
            close()
        } else {
            show()
        }
    }
    
    private func show() {
        guard let button = statusButton else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
    }
    
    private func close() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }
    
    func cleanup() {
        eventMonitor?.stop()
    }
}