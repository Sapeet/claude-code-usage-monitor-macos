import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var eventMonitor: EventMonitor?
    private var timer: Timer?
    private var usageMonitor: ClaudeUsageMonitor!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // アプリをUIElementとして設定（Dockに表示しない）
        NSApp.setActivationPolicy(.accessory)
        
        usageMonitor = ClaudeUsageMonitor()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "Claude ⏸"
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(usageMonitor))
        
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover(event)
            }
        }
        
        // タイマーを設定（6秒間隔）
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.updateUsage()
        }
        
        // 初回更新を少し遅延
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateUsage()
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                closePopover(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                eventMonitor?.start()
            }
        }
    }
    
    func closePopover(_ sender: Any?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    func updateUsage() {
        
        Task { @MainActor in
            await usageMonitor.updateUsage()
            
            if let button = statusItem.button {
                if usageMonitor.hasActiveSession || usageMonitor.currentTokens > 0 {
                    let percentage = usageMonitor.getUsagePercentage()
                    // メニューバーにBrailleゲージを表示
                    button.attributedTitle = createAttributedTitle(percentage: percentage)
                } else {
                    button.title = "Claude ⏸"
                }
            }
        }
    }
    
    // MARK: - Gauge Creation
    
    func createAttributedTitle(percentage: Double) -> NSAttributedString {
        let tokenColor: NSColor
        if percentage >= 90 {
            tokenColor = .systemRed
        } else if percentage >= 50 {
            tokenColor = .systemYellow
        } else {
            tokenColor = .systemGreen
        }
        
        let attributedString = NSMutableAttributedString()
        
        // Add percentage
        let percentText = String(format: "%.0f%% ", percentage)
        let percentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.append(NSAttributedString(string: percentText, attributes: percentAttributes))
        
        // Create Braille pattern gauge
        let brailleGauge = createBrailleGauge(
            tokenPercentage: usageMonitor.getUsagePercentage(),
            sessionPercentage: getSessionPercentage()
        )
        
        // Gauge with brackets
        let gaugeWithBrackets = "[" + brailleGauge + "]"
        let gaugeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: tokenColor
        ]
        attributedString.append(NSAttributedString(string: gaugeWithBrackets, attributes: gaugeAttributes))
        
        // Add burn rate emoji
        let emoji = " " + usageMonitor.getBurnRateEmoji()
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.append(NSAttributedString(string: emoji, attributes: emojiAttributes))
        
        return attributedString
    }
    
    // Brailleパターンのルックアップテーブル
    private static let braillePatterns: [[Character]] = [
        ["\u{2800}", "\u{2803}", "\u{281B}"],  // session 0%, token 0/5/10%
        ["\u{2844}", "\u{2847}", "\u{285F}"],  // session 5%, token 0/5/10%
        ["\u{28E4}", "\u{28E7}", "\u{28FF}"]   // session 10%, token 0/5/10%
    ]
    
    func createBrailleGauge(tokenPercentage: Double, sessionPercentage: Double) -> String {
        let width = 10  // 10 characters = 100%
        let tokenIndex = Int(tokenPercentage / 10.0)
        let sessionIndex = Int(sessionPercentage / 10.0)
        
        // 高速化: 事前に文字配列を作成してから結合
        var chars: [Character] = []
        chars.reserveCapacity(width)
        
        for i in 0..<width {
            // より効率的な計算
            let tokenFill: Int
            if i < tokenIndex {
                tokenFill = 2  // 10%
            } else if i == tokenIndex && (tokenPercentage.truncatingRemainder(dividingBy: 10.0) >= 5.0) {
                tokenFill = 1  // 5%
            } else {
                tokenFill = 0  // 0%
            }
            
            let sessionFill: Int
            if i < sessionIndex {
                sessionFill = 2  // 10%
            } else if i == sessionIndex && (sessionPercentage.truncatingRemainder(dividingBy: 10.0) >= 5.0) {
                sessionFill = 1  // 5%
            } else {
                sessionFill = 0  // 0%
            }
            
            // ルックアップテーブルから安全に取得
            if sessionFill < Self.braillePatterns.count && tokenFill < Self.braillePatterns[sessionFill].count {
                chars.append(Self.braillePatterns[sessionFill][tokenFill])
            } else {
                chars.append("⠀") // フォールバック
            }
        }
        
        return String(chars)
    }
    
    func getSessionPercentage() -> Double {
        let sessionDuration: TimeInterval = 5 * 60 * 60 // 5 hours in seconds
        let elapsed = Date().timeIntervalSince(usageMonitor.sessionStartTime)
        return min(100, (elapsed / sessionDuration) * 100)
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        eventMonitor?.stop()
    }
    
}

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}