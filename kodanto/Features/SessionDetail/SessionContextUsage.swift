import Foundation

struct SessionContextUsage {
    let tokenTotal: Int
    let usagePercent: Int?
    let totalCost: Double
    let modelID: String
    let providerID: String
}

extension SessionContextUsage {
    static func compute(
        messages: [OpenCodeMessageEnvelope],
        modelContextLimit: Int?
    ) -> SessionContextUsage? {
        var lastAssistant: OpenCodeMessage.Assistant?
        for envelope in messages.reversed() {
            if case .assistant(let assistant) = envelope.info, assistant.tokens.output > 0 {
                lastAssistant = assistant
                break
            }
        }
        
        guard let lastAssistant = lastAssistant else { return nil }
        
        let tokens = lastAssistant.tokens
        let tokenTotal = tokens.input + tokens.output + tokens.reasoning + tokens.cache.read + tokens.cache.write
        
        let usagePercent: Int?
        if let limit = modelContextLimit, limit > 0 {
            usagePercent = min(100, Int(round(Double(tokenTotal) / Double(limit) * 100)))
        } else {
            usagePercent = nil
        }
        
        let totalCost = messages.reduce(0.0) { sum, envelope in
            guard case .assistant(let assistant) = envelope.info else { return sum }
            return sum + assistant.cost
        }
        
        return SessionContextUsage(
            tokenTotal: tokenTotal,
            usagePercent: usagePercent,
            totalCost: totalCost,
            modelID: lastAssistant.modelID,
            providerID: lastAssistant.providerID
        )
    }
}