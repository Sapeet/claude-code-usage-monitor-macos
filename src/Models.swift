import Foundation

// MARK: - Enums

enum PlanType: String, CaseIterable {
    case pro = "Pro"
    case max5 = "Max5"
    case max20 = "Max20"
    case customMax = "Custom Max"
    
    var tokenLimit: Int {
        switch self {
        case .pro:
            return 44000
        case .max5:
            return 220000
        case .max20:
            return 880000
        case .customMax:
            return 890000  // Default for custom, actual value calculated dynamically
        }
    }
    
    static func detect(from maxTokens: Int) -> (type: PlanType, limit: Int) {
        if maxTokens > 880000 {
            let customLimit = ((maxTokens / 10000) + 1) * 10000
            return (.customMax, customLimit)
        } else if maxTokens > 220000 {
            return (.max20, 880000)
        } else if maxTokens > 44000 {
            return (.max5, 220000)
        } else {
            return (.pro, 44000)
        }
    }
}

// MARK: - Data Models

struct UsageEntry {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let model: String?
    let messageId: String?
    let requestId: String?
    
    var uniqueHash: String? {
        guard let messageId = messageId, let requestId = requestId else { return nil }
        return "\(messageId):\(requestId)"
    }
}

// MARK: - Session Models

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

// MARK: - Snapshot Models

struct UsageSnapshot {
    let hasActiveSession: Bool
    let currentTokens: Int
    let sessionStartTime: Date
    let sessionEndTime: Date
    let burnRate: Double
    let timeRemaining: String
    let sessionResetTime: String
    let modelBreakdown: [ModelBreakdown]
    let currentSessionBlock: SessionBlock?
    let detectedPlanType: PlanType
    let detectedTokenLimit: Int
}