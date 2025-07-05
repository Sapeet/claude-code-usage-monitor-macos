import Foundation

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