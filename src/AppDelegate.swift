import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var popoverController: PopoverController!
    private var usageMonitor: ClaudeUsageMonitor!
    private var timer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // アプリをUIElementとして設定（Dockに表示しない）
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize core components
        usageMonitor = ClaudeUsageMonitor()
        
        // Initialize menu bar controller first
        menuBarController = MenuBarController(monitor: usageMonitor) { [weak self] in
            self?.popoverController.togglePopover()
        }
        
        // Initialize popover controller with status button
        popoverController = PopoverController(
            contentView: ContentView().environmentObject(usageMonitor),
            statusButton: menuBarController.statusItem.button!
        )
        
        // タイマーを設定（6秒間隔）
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.scheduleUpdate()
        }
        
        // 初回の使用量を更新
        scheduleUpdate()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        menuBarController?.cleanup()
        popoverController?.cleanup()
    }
    
    @MainActor
    private func updateUsage() async {
        await usageMonitor.updateUsage()
        menuBarController.updateDisplay()
    }
    
    private func scheduleUpdate() {
        Task { await updateUsage() }
    } 
}