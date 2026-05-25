import Foundation

struct InferenceEngine {
    func classify(text: String) -> [String: Double] {
        let lower = text.lowercased()
        let words = lower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordSet = Set(words)

        var scores: [String: Double] = [:]

        scores["safe"] = 1.0
        scores["toxic"] = 0.0
        scores["harassment"] = 0.0
        scores["spam"] = 0.0

        let toxicWords: Set = [
            "fuck", "fucking", "fucked", "shit", "bitch", "asshole", "bastard",
            "damn", "dammit", "piss", "slut", "whore", "cunt", "dick", "cock",
            "motherfucker", "motherfucking",
        ]
        let harassmentWords: Set = [
            "kill yourself", "die", "kys", "retard", "retarded", "idiot", "moron",
            "stupid", "dumbass", "worthless", "trash", "garbage",
        ]
        let spamIndicators: Set = [
            "http", "https", "www.", ".com", ".org", ".net",
            "subscribe", "follow", "click", "link", "free", "win",
            "crypto", "bitcoin", "eth", "nft", "invest", "money",
            "buy", "sell", "promotion", "discount", "limited",
        ]

        for word in wordSet {
            if toxicWords.contains(word) {
                scores["toxic"] = min(scores["toxic"]! + 0.25, 1.0)
                scores["safe"] = max(scores["safe"]! - 0.2, 0.0)
            }
            if harassmentWords.contains(word) {
                scores["harassment"] = min(scores["harassment"]! + 0.35, 1.0)
                scores["safe"] = max(scores["safe"]! - 0.3, 0.0)
            }
        }

        for indicator in spamIndicators {
            if lower.contains(indicator) {
                scores["spam"] = min(scores["spam"]! + 0.15, 1.0)
                scores["safe"] = max(scores["safe"]! - 0.1, 0.0)
            }
        }

        let linkCount = words.count(where: { $0.hasPrefix("http") || $0.hasPrefix("www") })
        if linkCount >= 3 {
            scores["spam"] = min(scores["spam"]! + 0.3, 1.0)
            scores["safe"] = max(scores["safe"]! - 0.25, 0.0)
        }

        let uppercaseCount = text.filter(\.isUppercase).count
        let uppercaseRatio = Double(uppercaseCount) / Double(max(text.count, 1))
        if uppercaseRatio > 0.6, text.count > 20 {
            scores["toxic"] = min(scores["toxic"]! + 0.15, 1.0)
        }

        let mentionCount = words.count(where: { $0.hasPrefix("@") })
        if mentionCount >= 5 {
            scores["spam"] = min(scores["spam"]! + 0.2, 1.0)
        }

        return scores
    }

    func analyze(text: String) -> String {
        let lower = text.lowercased()
        let words = lower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count

        var parts: [String] = []

        parts.append("Post analysis for \(wordCount)-word post:")

        let topics = detectTopics(text: lower)
        if !topics.isEmpty {
            parts.append("Topics detected: \(topics.formatted(.list(type: .and))))")
        }

        let sentiment = detectSentiment(text: lower)
        parts.append("Sentiment: \(sentiment)")

        if let risk = assessRisk(text: lower, wordCount: wordCount) {
            parts.append("Risk assessment: \(risk)")
        }

        parts.append("Recommendation: \(recommendation(sentiment: sentiment, wordCount: wordCount))")

        return parts.joined(separator: "\n")
    }

    private func detectTopics(text: String) -> [String] {
        var topics: [String] = []
        let topicKeywords: [(String, [String])] = [
            ("Technology", ["ai", "software", "code", "app", "ios", "apple", "google", "computer", "programming", "data"]),
            ("Politics", ["government", "election", "vote", "policy", "political", "democrat", "republican", "law"]),
            ("Health", ["health", "medical", "doctor", "hospital", "disease", "covid", "vaccine", "mental"]),
            ("Sports", ["sport", "game", "team", "player", "win", "score", "football", "basketball", "soccer"]),
            ("Business", ["business", "market", "economy", "stock", "startup", "company", "revenue", "profit"]),
            ("Entertainment", ["movie", "music", "film", "show", "game", "album", "song", "celebrity"]),
            ("Social Media", ["twitter", "bluesky", "mastodon", "threads", "instagram", "tiktok", "post", "follow"]),
        ]
        for (topic, keywords) in topicKeywords {
            if keywords.contains(where: { text.contains($0) }) {
                topics.append(topic)
            }
        }
        return topics
    }

    private func detectSentiment(text: String) -> String {
        let positiveWords: Set = [
            "good", "great", "awesome", "amazing", "love", "wonderful", "excellent",
            "happy", "beautiful", "fantastic", "nice", "best", "brilliant", "superb",
            "thank", "thanks", "appreciate", "enjoy", "fun", "exciting",
        ]
        let negativeWords: Set = [
            "bad", "terrible", "awful", "hate", "horrible", "worst", "disgusting",
            "angry", "sad", "depressing", "ugly", "stupid", "waste", "disaster",
            "pathetic", "offensive", "disgrace",
        ]
        let wordSet = Set(text.components(separatedBy: .whitespacesAndNewlines))
        let positiveCount = positiveWords.intersection(wordSet).count
        let negativeCount = negativeWords.intersection(wordSet).count
        if positiveCount > negativeCount { return "Positive" }
        if negativeCount > positiveCount { return "Negative" }
        return "Neutral"
    }

    private func assessRisk(text: String, wordCount: Int) -> String? {
        let lower = text.lowercased()
        var risks: [String] = []
        if lower.contains("kill") || lower.contains("die") || lower.contains("hurt") || lower.contains("attack") {
            risks.append("Violent language detected")
        }
        if lower.contains("bomb") || lower.contains("weapon") || lower.contains("shoot") {
            risks.append("Weapons reference detected")
        }
        let slurWords = ["nigger", "faggot", "kike", "spic", "chink", "raghead"]
        if slurWords.contains(where: { lower.contains($0) }) {
            risks.append("Hate speech detected")
        }
        if lower.contains("http"), wordCount < 5 {
            risks.append("Link-only post (potential spam)")
        }
        return risks.isEmpty ? nil : risks.joined(separator: "; ")
    }

    private func recommendation(sentiment: String, wordCount: Int) -> String {
        if sentiment == "Negative" || wordCount < 3 {
            return "Review for moderation"
        }
        return "No action needed"
    }
}
