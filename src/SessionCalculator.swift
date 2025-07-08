import Foundation

// セッション関連の計算ロジックを担当
struct SessionCalculator {
    
    // 使用状況のスナップショットを計算
    func calculateUsageSnapshot(from entries: [UsageEntry], tokenLimit: Int, now: Date) -> UsageSnapshot? {
        let sessionBlocks = identifySessionBlocks(from: entries)
        
        // アクティブなセッションを見つける
        guard let activeSession = sessionBlocks.first(where: { $0.isActive }) else {
            return nil
        }
        
        let burnRate = calculateBurnRate(from: sessionBlocks, now: now)
        let sessionResetTime = formatTime(activeSession.endTime)
        let timeRemaining = calculateTimeRemaining(
            currentTokens: activeSession.displayTokens,
            tokenLimit: tokenLimit,
            burnRate: burnRate,
            sessionEndTime: activeSession.endTime
        )
        let modelBreakdown = calculateModelBreakdown(from: activeSession)
        let (detectedType, detectedLimit) = detectPlan(from: sessionBlocks)
        
        return UsageSnapshot(
            hasActiveSession: true,
            currentTokens: activeSession.displayTokens,
            sessionStartTime: activeSession.startTime,
            sessionEndTime: activeSession.endTime,
            burnRate: burnRate,
            timeRemaining: timeRemaining,
            sessionResetTime: sessionResetTime,
            modelBreakdown: modelBreakdown,
            currentSessionBlock: activeSession,
            detectedPlanType: detectedType,
            detectedTokenLimit: detectedLimit
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    // セッションブロックを識別
    func identifySessionBlocks(from entries: [UsageEntry]) -> [SessionBlock] {
        guard !entries.isEmpty else { return [] }
        
        var blocks: [SessionBlock] = []
        var currentBlock: SessionBlock?
        let sessionDuration: TimeInterval = 5 * 60 * 60 // 5 hours
        
        for entry in entries {
            if let block = currentBlock {
                if shouldCreateNewBlock(block: block, entry: entry) {
                    blocks.append(block)
                    
                    if let gapBlock = checkForGap(lastBlock: block, nextEntry: entry) {
                        blocks.append(gapBlock)
                    }
                    
                    let startTime = roundToHour(entry.timestamp)
                    currentBlock = SessionBlock(
                        id: "session-\(startTime.timeIntervalSince1970)",
                        startTime: startTime,
                        endTime: startTime.addingTimeInterval(sessionDuration),
                        isGap: false
                    )
                    addEntryToBlock(&currentBlock!, entry)
                } else {
                    addEntryToBlock(&currentBlock!, entry)
                }
            } else {
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
    
    // バーンレート計算（過去1時間）
    func calculateBurnRate(from sessionBlocks: [SessionBlock], now: Date) -> Double {
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        var totalTokensInHour: Double = 0
        
        for block in sessionBlocks where !block.isGap {
            let sessionActualEnd = block.isActive ? now : block.actualEndTime
            let sessionStart = block.startTime
            
            let sessionStartInHour = max(sessionStart, oneHourAgo)
            let sessionEndInHour = min(sessionActualEnd, now)
            
            if sessionStartInHour < sessionEndInHour {
                let hourDuration = sessionEndInHour.timeIntervalSince(sessionStartInHour)
                let totalSessionDuration = sessionActualEnd.timeIntervalSince(sessionStart)
                
                if totalSessionDuration > 0 && hourDuration > 0 {
                    let sessionTokens = Double(block.displayTokens)
                    let tokensInHour = sessionTokens * (hourDuration / totalSessionDuration)
                    totalTokensInHour += tokensInHour
                }
            }
        }
        
        return totalTokensInHour / 60.0
    }
    
    // プラン検出
    func detectPlan(from blocks: [SessionBlock]) -> (planType: PlanType, tokenLimit: Int) {
        let maxSessionTokens = blocks.map { $0.displayTokens }.max() ?? 0
        let (type, limit) = PlanType.detect(from: maxSessionTokens)
        return (planType: type, tokenLimit: limit)
    }
    
    // モデル別の詳細を計算
    func calculateModelBreakdown(from sessionBlock: SessionBlock) -> [ModelBreakdown] {
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
        
        return breakdowns
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
    
    // 残り時間計算
    func calculateTimeRemaining(currentTokens: Int, tokenLimit: Int, burnRate: Double, sessionEndTime: Date) -> String {
        guard currentTokens < tokenLimit else {
            return "Exceeded"
        }
        
        guard burnRate > 0 else {
            return "∞"
        }
        
        let tokensLeft = tokenLimit - currentTokens
        let minutesRemaining = Double(tokensLeft) / burnRate
        let minutesUntilReset = sessionEndTime.timeIntervalSince(Date()) / 60.0
        let effectiveMinutesRemaining = min(minutesRemaining, minutesUntilReset)
        
        if effectiveMinutesRemaining < 0 {
            return "Exceeded"
        } else if effectiveMinutesRemaining > 300 {
            return "5h+"
        } else {
            let hours = Int(effectiveMinutesRemaining) / 60
            let minutes = Int(effectiveMinutesRemaining) % 60
            return String(format: "%dh %dm", hours, minutes)
        }
    }
    
    // MARK: - Private Helpers
    
    private func shouldCreateNewBlock(block: SessionBlock, entry: UsageEntry) -> Bool {
        if entry.timestamp >= block.endTime {
            return true
        }
        
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        
        return calendar.date(from: components) ?? date
    }
    
    private func addEntryToBlock(_ block: inout SessionBlock, _ entry: UsageEntry) {
        if block.firstEntry == nil {
            block.firstEntry = entry
            block.lastEntry = entry
        } else {
            block.lastEntry = entry
        }
        
        let modelName = entry.model ?? "unknown"
        
        var stats = block.perModelStats[modelName, default: ModelStats()]
        stats.inputTokens += entry.inputTokens
        stats.outputTokens += entry.outputTokens
        stats.cacheCreationTokens += entry.cacheCreationTokens
        stats.cacheReadTokens += entry.cacheReadTokens
        stats.entriesCount += 1
        block.perModelStats[modelName] = stats
    }
}