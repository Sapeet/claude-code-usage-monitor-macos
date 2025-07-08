import AppKit
import SwiftUI

// メニューバーのUI管理を担当
class MenuBarController {
    let statusItem: NSStatusItem
    private weak var usageMonitor: ClaudeUsageMonitor?
    private let clickHandler: () -> Void
    
    init(monitor: ClaudeUsageMonitor, clickHandler: @escaping () -> Void) {
        self.usageMonitor = monitor
        self.clickHandler = clickHandler
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        if let button = statusItem.button {
            button.title = "Claude ⏸"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func statusItemClicked() {
        clickHandler()
    }
    
    func updateDisplay() {
        guard let monitor = usageMonitor,
              let button = statusItem.button else { return }
        
        if monitor.hasActiveSession || monitor.currentTokens > 0 {
            let percentage = monitor.getUsagePercentage()
            button.attributedTitle = createAttributedTitle(percentage: percentage)
        } else {
            button.title = "Claude ⏸"
        }
    }
    
    // MARK: - Gauge Creation
    
    private func createAttributedTitle(percentage: Double) -> NSAttributedString {
        let tokenColor = usageMonitor?.getUsageColor() ?? .systemGray
        let attributedString = NSMutableAttributedString()
        
        // Add percentage (white color)
        let percentageText = String(format: "%.0f%% ", percentage)
        let percentageAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.append(NSAttributedString(string: percentageText, attributes: percentageAttributes))
        
        // Add separator
        attributedString.append(NSAttributedString(string: " ", attributes: [:]))
        
        // Add gauge
        let gauge = createGauge(
            tokenPercentage: percentage,
            sessionProgress: calculateSessionProgress()
        )
        let gaugeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: tokenColor
        ]
        attributedString.append(NSAttributedString(string: gauge, attributes: gaugeAttributes))
        
        // Add burn rate emoji
        if let monitor = usageMonitor {
            let emoji = " " + monitor.getBurnRateEmoji()
            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            attributedString.append(NSAttributedString(string: emoji, attributes: emojiAttributes))
        }
        
        return attributedString
    }
    
    private func calculateSessionProgress() -> Double {
        guard let monitor = usageMonitor else { return 0.0 }
        
        let elapsed = Date().timeIntervalSince(monitor.sessionStartTime)
        let sessionDuration = monitor.sessionEndTime.timeIntervalSince(monitor.sessionStartTime)
        
        guard sessionDuration > 0 else { return 0.0 }
        
        return min(max(elapsed / sessionDuration * 100.0, 0), 100)
    }
    
    private func createGauge(tokenPercentage: Double, sessionProgress: Double) -> String {
        // Braille dots layout:
        // Upper 4 dots (token usage): ⠀ → ⠃ (0-5%) → ⠛ (5-10%)
        // Lower 4 dots (session progress): ⠀ → ⡄ (0-5%) → ⣤ (5-10%)
        
        let gauge = (0..<10).map { i in
            let charStart = Double(i) * 10.0
            let upperFill = min(max(tokenPercentage - charStart, 0), 10)
            let lowerFill = min(max(sessionProgress - charStart, 0), 10)
            return getBrailleChar(upperFill: upperFill, lowerFill: lowerFill)
        }
        
        return "[\(String(gauge))]"
    }
    
    private func getBrailleChar(upperFill: Double, lowerFill: Double) -> Character {
        // Braille Unicode base: U+2800
        // Dot positions (1-based):
        // 1 4
        // 2 5
        // 3 6
        // 7 8
        
        var dots: UInt8 = 0
        
        // Upper dots (1, 2, 4, 5 for token usage)
        if upperFill >= 5.0 {
            // 5% or more: Left 2 dots (dots 1, 2)
            dots |= 0x01  // dot 1
            dots |= 0x02  // dot 2
        }
        if upperFill >= 10.0 {
            // 10%: Add right 2 dots (dots 4, 5)
            dots |= 0x08  // dot 4
            dots |= 0x10  // dot 5
        }
        
        // Lower dots (3, 6, 7, 8 for session progress)
        if lowerFill >= 5.0 {
            // 5% or more: Left 2 dots (dots 3, 7)
            dots |= 0x04  // dot 3
            dots |= 0x40  // dot 7
        }
        if lowerFill >= 10.0 {
            // 10%: Add right 2 dots (dots 6, 8)
            dots |= 0x20  // dot 6
            dots |= 0x80  // dot 8
        }
        
        let brailleCodePoint = 0x2800 + UInt32(dots)
        if let scalar = Unicode.Scalar(brailleCodePoint) {
            return Character(scalar)
        }
        
        return "⠀"  // Empty braille pattern as fallback
    }
    
    func cleanup() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}