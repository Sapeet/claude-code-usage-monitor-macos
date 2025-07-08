import Foundation
import SwiftUI

class ClaudeUsageMonitor: ObservableObject {
    @Published var currentTokens: Int = 0
    @Published var tokenLimit: Int = 44000
    @Published var burnRate: Double = 0.0
    @Published var timeRemaining: String = ""
    @Published var sessionResetTime: String = ""
    @Published var planType: PlanType = .pro
    @Published var sessionStartTime: Date = Date()
    @Published var sessionEndTime: Date = Date()
    @Published var hasActiveSession: Bool = false
    @Published var showModelBreakdown: Bool = false
    @Published var modelBreakdown: [ModelBreakdown] = []
    @Published var isManualPlanMode: Bool = false
    @Published var detectedPlanType: PlanType = .pro
    
    private let dataLoader = ClaudeDataLoader()
    private var currentSessionBlock: SessionBlock?
    private let userDefaults = UserDefaults.standard
    private let sessionCalculator = SessionCalculator()
    
    init() {
        // Load saved preferences
        self.isManualPlanMode = userDefaults.bool(forKey: "isManualPlanMode")
        if let savedPlanTypeString = userDefaults.string(forKey: "manualPlanType"),
           let savedPlanType = PlanType(rawValue: savedPlanTypeString) {
            self.planType = savedPlanType
            self.tokenLimit = savedPlanType.tokenLimit
        }
    }
    
    // DateFormatterのキャッシュ
    private static let sharedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    @MainActor
    func updateUsage() async {
        let usageData = await dataLoader.loadUsageData()
        let now = Date()
        
        // スナップショットを計算
        guard let snapshot = sessionCalculator.calculateUsageSnapshot(from: usageData, tokenLimit: tokenLimit, now: now) else {
            // アクティブセッションがない場合
            resetSession(now: now)
            return
        }
        
        // 全プロパティを原子的に更新
        applySnapshot(snapshot)
    }
    
    private func applySnapshot(_ snapshot: UsageSnapshot) {
        hasActiveSession = snapshot.hasActiveSession
        currentTokens = snapshot.currentTokens
        sessionStartTime = snapshot.sessionStartTime
        sessionEndTime = snapshot.sessionEndTime
        burnRate = snapshot.burnRate
        timeRemaining = snapshot.timeRemaining
        sessionResetTime = snapshot.sessionResetTime
        modelBreakdown = snapshot.modelBreakdown
        currentSessionBlock = snapshot.currentSessionBlock
        
        // プランの更新
        detectedPlanType = snapshot.detectedPlanType
        if !isManualPlanMode {
            planType = snapshot.detectedPlanType
            tokenLimit = snapshot.detectedTokenLimit
        }
    }
    
    private func resetSession(now: Date) {
        hasActiveSession = false
        currentTokens = 0
        sessionStartTime = now
        sessionEndTime = now
        burnRate = 0.0
        timeRemaining = "N/A"
        sessionResetTime = "N/A"
        modelBreakdown = []
        currentSessionBlock = nil
    }
    
    func getUsagePercentage() -> Double {
        return (Double(currentTokens) / Double(tokenLimit)) * 100
    }
    
    func getUsageColor() -> NSColor {
        let percentage = getUsagePercentage()
        if percentage < 50 {
            return .systemGreen
        } else if percentage < 90 {
            return .systemYellow
        } else {
            return .systemRed
        }
    }
    
    func getBurnRateEmoji() -> String {
        if burnRate < 100 {
            return "🐌"
        } else if burnRate < 300 {
            return "🚶"
        } else if burnRate < 600 {
            return "🏃"
        } else if burnRate < 1000 {
            return "🚗"
        } else if burnRate < 2000 {
            return "✈️"
        } else {
            return "🚀"
        }
    }
    
    func willExceedBeforeReset() -> Bool {
        guard burnRate > 0 else { return false }
        
        let tokensLeft = tokenLimit - currentTokens
        let minutesRemaining = Double(tokensLeft) / burnRate
        let minutesUntilReset = sessionEndTime.timeIntervalSince(Date()) / 60.0
        
        return minutesRemaining < minutesUntilReset
    }
    
    // Manual plan selection
    func setPlanType(_ plan: String) {
        if plan == "Auto" {
            isManualPlanMode = false
            planType = detectedPlanType
            userDefaults.set(false, forKey: "isManualPlanMode")
            userDefaults.removeObject(forKey: "manualPlanType")
            tokenLimit = detectedPlanType.tokenLimit
        } else if let selectedPlan = PlanType(rawValue: plan) {
            isManualPlanMode = true
            planType = selectedPlan
            userDefaults.set(true, forKey: "isManualPlanMode")
            userDefaults.set(selectedPlan.rawValue, forKey: "manualPlanType")
            tokenLimit = selectedPlan.tokenLimit
        }
    }
}
