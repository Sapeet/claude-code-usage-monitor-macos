import Foundation
import SwiftUI

class ClaudeUsageMonitor: ObservableObject {
    @Published var currentTokens: Int = 0
    @Published var tokenLimit: Int = 44000
    @Published var burnRate: Double = 0.0
    @Published var timeRemaining: String = ""
    @Published var sessionResetTime: String = ""
    @Published var planType: String = "Pro"
    @Published var sessionStartTime: Date = Date()
    @Published var sessionEndTime: Date = Date()
    @Published var hasActiveSession: Bool = false
    @Published var showModelBreakdown: Bool = false
    @Published var modelBreakdown: [ModelBreakdown] = []
    @Published var isManualPlanMode: Bool = false
    @Published var detectedPlanType: String = "Pro"
    
    private let dataLoader = ClaudeDataLoader()
    private var currentSessionBlock: SessionBlock?
    private let userDefaults = UserDefaults.standard
    
    init() {
        // Load saved preferences
        self.isManualPlanMode = userDefaults.bool(forKey: "isManualPlanMode")
        if let savedPlanType = userDefaults.string(forKey: "manualPlanType") {
            self.planType = savedPlanType
            // Apply the correct token limit for the saved plan type
            switch savedPlanType {
            case "Pro":
                self.tokenLimit = 44000
            case "Max5":
                self.tokenLimit = 220000
            case "Max20":
                self.tokenLimit = 880000
            default:
                self.tokenLimit = 44000
            }
        }
    }
    
    // DateFormatterのキャッシュ
    private static let sharedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    struct SessionBlock {
        let id: String
        let startTime: Date
        let endTime: Date
        var firstEntry: UsageEntry?
        var lastEntry: UsageEntry?
        var perModelStats: [String: ModelStats] = [:]
        let isGap: Bool
        
        var actualEndTime: Date {
            return lastEntry?.timestamp ?? startTime
        }
        
        var isActive: Bool {
            return Date() < endTime && !isGap
        }
        
        // Calculate display tokens with model-specific rules
        var displayTokens: Int {
            var total = 0
            for (modelName, stats) in perModelStats {
                if modelName.lowercased().contains("opus") {
                    // Apply 5x multiplier for Opus models
                    total += (stats.inputTokens + stats.outputTokens) * 5
                } else if modelName.lowercased().contains("sonnet") {
                    // Normal calculation for Sonnet models
                    total += stats.inputTokens + stats.outputTokens
                }
                // Other models are ignored (not added to total)
            }
            return total
        }
        
        // Raw tokens for burn rate calculation
        var rawTokens: Int {
            var total = 0
            for stats in perModelStats.values {
                total += stats.inputTokens + stats.outputTokens
            }
            return total
        }
    }
    
    struct ModelStats {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var entriesCount: Int = 0
    }
    
    struct ModelBreakdown: Identifiable {
        let id = UUID()
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let rawTokens: Int
        let weightedTokens: Int
    }
    
    @MainActor
    func updateUsage() async {
        
        let usageData = await dataLoader.loadUsageData()
        
        let now = Date()
        
        // セッションブロックを識別
        let sessionBlocks = identifySessionBlocks(from: usageData)
        
        // アクティブなセッションを見つける
        if let activeSession = sessionBlocks.first(where: { $0.isActive }) {
            // @Publishedが自動的に変更検知を行うため、直接代入
            hasActiveSession = true
            currentTokens = activeSession.displayTokens
            sessionStartTime = activeSession.startTime
            sessionEndTime = activeSession.endTime
            currentSessionBlock = activeSession
            
            // モデル別の詳細を更新
            updateModelBreakdown(from: activeSession)
        } else {
            // アクティブセッションがない場合は初期化
            // データがない場合
            hasActiveSession = false
            currentTokens = 0
            sessionStartTime = now
            sessionEndTime = now
            burnRate = 0.0
            timeRemaining = "N/A"
            sessionResetTime = "N/A"
            return
        }
        
        // 過去1時間のバーンレート計算
        calculateBurnRate(from: sessionBlocks, now: now)
        
        // プラン検出（セッション単位の最大値）
        detectPlanFromSessions(sessionBlocks)
        
        // セッションリセット時刻を設定（ローカル時間で表示）
        sessionResetTime = Self.sharedTimeFormatter.string(from: sessionEndTime)
        
        calculateTimeRemaining()
        
        // 更新後の値をログ出力
        // print("Updated values - Tokens: \(currentTokens), BurnRate: \(burnRate), Percentage: \(getUsagePercentage())%")
    }
    
    private func identifySessionBlocks(from entries: [UsageEntry]) -> [SessionBlock] {
        guard !entries.isEmpty else { return [] }
        
        // entries are already sorted by timestamp from ClaudeDataLoader
        var blocks: [SessionBlock] = []
        var currentBlock: SessionBlock?
        let sessionDuration: TimeInterval = 5 * 60 * 60 // 5 hours
        
        for entry in entries {
            if let block = currentBlock {
                // Check if we need a new block
                if shouldCreateNewBlock(block: block, entry: entry) {
                    blocks.append(block)
                    
                    // Check for gap
                    if let gapBlock = checkForGap(lastBlock: block, nextEntry: entry) {
                        blocks.append(gapBlock)
                    }
                    
                    // Create new block
                    let startTime = roundToHour(entry.timestamp)
                    currentBlock = SessionBlock(
                        id: "session-\(startTime.timeIntervalSince1970)",
                        startTime: startTime,
                        endTime: startTime.addingTimeInterval(sessionDuration),
                        isGap: false
                    )
                    addEntryToBlock(&currentBlock!, entry)
                } else {
                    // Add to existing block
                    addEntryToBlock(&currentBlock!, entry)
                }
            } else {
                // First block
                let startTime = roundToHour(entry.timestamp)
                currentBlock = SessionBlock(
                    id: "session-\(startTime.timeIntervalSince1970)",
                    startTime: startTime,
                    endTime: startTime.addingTimeInterval(sessionDuration),
                    isGap: false
                )
                addEntryToBlock(&currentBlock!, entry)
            }
        }
        
        if let finalBlock = currentBlock {
            blocks.append(finalBlock)
        }
        
        return blocks
    }
    
    private func shouldCreateNewBlock(block: SessionBlock, entry: UsageEntry) -> Bool {
        // Condition 1: Entry timestamp is at or after block end time
        if entry.timestamp >= block.endTime {
            return true
        }
        
        // Condition 2: 5+ hour gap since last entry
        if let lastEntry = block.lastEntry {
            if entry.timestamp.timeIntervalSince(lastEntry.timestamp) >= 5 * 60 * 60 {
                return true
            }
        }
        
        return false
    }
    
    private func checkForGap(lastBlock: SessionBlock, nextEntry: UsageEntry) -> SessionBlock? {
        let gapDuration = nextEntry.timestamp.timeIntervalSince(lastBlock.actualEndTime)
        
        if gapDuration >= 5 * 60 * 60 {
            return SessionBlock(
                id: "gap-\(lastBlock.actualEndTime.timeIntervalSince1970)",
                startTime: lastBlock.actualEndTime,
                endTime: nextEntry.timestamp,
                isGap: true
            )
        }
        
        return nil
    }
    
    private func roundToHour(_ date: Date) -> Date {
        // UTC時間で時間単位に丸める（元の実装と同じ）
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        
        return calendar.date(from: components) ?? date
    }
    
    private func addEntryToBlock(_ block: inout SessionBlock, _ entry: UsageEntry) {
        // 最初のエントリの場合は両方に、それ以外はlastEntryのみ更新
        if block.firstEntry == nil {
            block.firstEntry = entry
            block.lastEntry = entry
        } else {
            block.lastEntry = entry
        }
        
        let modelName = entry.model ?? "unknown"
        
        // 辞書のデフォルト値を使用して初期化とアクセスを最適化
        var stats = block.perModelStats[modelName, default: ModelStats()]
        stats.inputTokens += entry.inputTokens
        stats.outputTokens += entry.outputTokens
        stats.cacheCreationTokens += entry.cacheCreationTokens
        stats.cacheReadTokens += entry.cacheReadTokens
        stats.entriesCount += 1
        block.perModelStats[modelName] = stats
    }
    
    private func calculateBurnRate(from sessionBlocks: [SessionBlock], now: Date) {
        // 時系列バーンレート計算（過去1時間のセッションを按分）
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        
        var totalTokensInHour: Double = 0
        
        for block in sessionBlocks where !block.isGap {
            // セッションの実際の終了時刻（最後のエントリまたは現在時刻）
            let sessionActualEnd = block.isActive ? now : block.actualEndTime
            let sessionStart = block.firstEntry?.timestamp ?? block.startTime
            
            // セッションが過去1時間と重複する部分を計算
            let sessionStartInHour = max(sessionStart, oneHourAgo)
            let sessionEndInHour = min(sessionActualEnd, now)
            
            // 重複する時間がある場合
            if sessionStartInHour < sessionEndInHour {
                let hourDuration = sessionEndInHour.timeIntervalSince(sessionStartInHour)
                let totalSessionDuration = sessionActualEnd.timeIntervalSince(sessionStart)
                
                if totalSessionDuration > 0 && hourDuration > 0 {
                    // 重複時間の割合でトークンを按分（重み付けトークンを使用、仕様書4.2準拠）
                    let sessionTokens = Double(block.displayTokens)
                    let tokensInHour = sessionTokens * (hourDuration / totalSessionDuration)
                    totalTokensInHour += tokensInHour
                }
            }
        }
        
        // tokens/minute を計算
        burnRate = totalTokensInHour / 60.0
    }
    
    private func detectPlanFromSessions(_ blocks: [SessionBlock]) {
        // セッション単位の最大トークン数を見つける（表示用トークン）
        let maxSessionTokens = blocks.map { $0.displayTokens }.max() ?? 0
        
        if maxSessionTokens > 880000 {
            // Max20制限を超えている場合はカスタム最大値
            detectedPlanType = "Custom Max"
            if !isManualPlanMode {
                planType = "Custom Max"
                tokenLimit = ((maxSessionTokens / 10000) + 1) * 10000 // 10000単位で切り上げ
            }
        } else if maxSessionTokens > 220000 {
            detectedPlanType = "Max20"
            if !isManualPlanMode {
                planType = "Max20"
                tokenLimit = 880000
            }
        } else if maxSessionTokens > 44000 {
            detectedPlanType = "Max5"
            if !isManualPlanMode {
                planType = "Max5"
                tokenLimit = 220000
            }
        } else {
            detectedPlanType = "Pro"
            if !isManualPlanMode {
                planType = "Pro"
                tokenLimit = 44000
            }
        }
    }
    
    private func calculateTimeRemaining() {
        // トークンが既に上限に達している場合
        guard currentTokens < tokenLimit else {
            timeRemaining = "Exceeded"
            return
        }
        
        guard burnRate > 0 else {
            timeRemaining = "∞"
            return
        }
        
        let tokensLeft = tokenLimit - currentTokens
        let minutesRemaining = Double(tokensLeft) / burnRate
        
        // セッションリセットまでの時間も計算
        let minutesUntilReset = sessionEndTime.timeIntervalSince(Date()) / 60.0
        
        // どちらか早い方を使用
        let effectiveMinutesRemaining = min(minutesRemaining, minutesUntilReset)
        
        if effectiveMinutesRemaining < 0 {
            timeRemaining = "Exceeded"
        } else if effectiveMinutesRemaining > 300 {
            timeRemaining = "5h+"
        } else {
            let hours = Int(effectiveMinutesRemaining) / 60
            let minutes = Int(effectiveMinutesRemaining) % 60
            timeRemaining = String(format: "%dh %dm", hours, minutes)
        }
    }
    
    func getUsagePercentage() -> Double {
        return (Double(currentTokens) / Double(tokenLimit)) * 100
    }
    
    func getUsageColor() -> Color {
        let percentage = getUsagePercentage()
        if percentage < 50 {
            return .green
        } else if percentage < 80 {
            return .yellow
        } else {
            return .red
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
    
    private func updateModelBreakdown(from sessionBlock: SessionBlock) {
        var breakdowns: [ModelBreakdown] = []
        
        // Sort models by weighted tokens (descending)
        let sortedModels = sessionBlock.perModelStats.sorted { (first, second) in
            let firstWeighted = calculateWeightedTokens(model: first.key, stats: first.value)
            let secondWeighted = calculateWeightedTokens(model: second.key, stats: second.value)
            return firstWeighted > secondWeighted
        }
        
        for (modelName, stats) in sortedModels {
            let rawTokens = stats.inputTokens + stats.outputTokens
            let weightedTokens = calculateWeightedTokens(model: modelName, stats: stats)
            
            // Only include models that contribute to the total
            if modelName.lowercased().contains("opus") || modelName.lowercased().contains("sonnet") {
                breakdowns.append(ModelBreakdown(
                    model: modelName,
                    inputTokens: stats.inputTokens,
                    outputTokens: stats.outputTokens,
                    cacheCreationTokens: stats.cacheCreationTokens,
                    cacheReadTokens: stats.cacheReadTokens,
                    rawTokens: rawTokens,
                    weightedTokens: weightedTokens
                ))
            }
        }
        
        modelBreakdown = breakdowns
    }
    
    private func calculateWeightedTokens(model: String, stats: ModelStats) -> Int {
        let rawTokens = stats.inputTokens + stats.outputTokens
        
        if model.lowercased().contains("opus") {
            return rawTokens * 5
        } else if model.lowercased().contains("sonnet") {
            return rawTokens
        } else {
            return 0
        }
    }
    
    // Manual plan selection
    func setPlanType(_ plan: String) {
        if plan == "Auto" {
            isManualPlanMode = false
            planType = detectedPlanType
            userDefaults.set(false, forKey: "isManualPlanMode")
            userDefaults.removeObject(forKey: "manualPlanType")
            
            // Apply auto-detected limits
            switch detectedPlanType {
            case "Pro":
                tokenLimit = 44000
            case "Max5":
                tokenLimit = 220000
            case "Max20":
                tokenLimit = 880000
            default:
                tokenLimit = 44000
            }
        } else {
            isManualPlanMode = true
            planType = plan
            userDefaults.set(true, forKey: "isManualPlanMode")
            userDefaults.set(plan, forKey: "manualPlanType")
            
            // Apply manual limits
            switch plan {
            case "Pro":
                tokenLimit = 44000
            case "Max5":
                tokenLimit = 220000
            case "Max20":
                tokenLimit = 880000
            default:
                tokenLimit = 44000
            }
        }
    }
}
