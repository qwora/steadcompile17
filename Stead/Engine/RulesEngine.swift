import Foundation

/// One warning sign the rules found, in words an older adult understands.
struct Signal: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let points: Int
}

struct RuleResult: Codable, Hashable {
    enum Decision: String, Codable { case analyze, skip, ignored }

    let decision: Decision
    let score: Int
    let signals: [Signal]
    let ignoreReason: String?
    /// A one-time code from a bank or service. Harmless alone, but a red flag right after a scam thread.
    var isOneTimeCode = false

    static func ignored(_ reason: String) -> RuleResult {
        RuleResult(decision: .ignored, score: 0, signals: [], ignoreReason: reason)
    }
}

/// Deterministic, on-device first pass. It only decides "worth an AI look?".
/// A saved contact never lowers the score: hacked accounts message from familiar names.
enum RulesEngine {
    static let threshold = 3

    private struct Rule {
        let id: String
        let label: String
        let points: Int
        let keywords: [String]
    }

    private static let rules: [Rule] = [
        Rule(id: "abroad", label: "Sent from overseas", points: 2,
             keywords: ["[국외발신]", "[국제발신]", "[해외발신]", "국외발신", "국제발신", "해외발신"]),
        Rule(id: "payment", label: "Asks for a payment or fee", points: 2,
             keywords: ["pay ", "payment", " fee", "a fine", "the fine", "your fine", "fined", "traffic fine", "transfer", "overdue", "unpaid", "refund",
                        "납부", "결제", "벌금", "과태료", "미납", "송금", "입금", "이체", "환불",
                        "bayar", "denda", "pindahan", "saman", "tunggakan"]),
        Rule(id: "authority", label: "Claims to be a bank, courier or government", points: 2,
             keywords: ["delivery", "parcel", "customs", "courier", "police", "bank", "tax", "court", "prosecutor",
                        "택배", "배송", "우체국", "세관", "경찰", "검찰", "법원", "국세청", "은행", "도로", "단속", "관리공단",
                        "jpj", "lhdn", "pdrm", "polis", "mahkamah", "pos laju", "poslaju"]),
        Rule(id: "urgency", label: "Rushes you to act now", points: 1,
             keywords: ["urgent", "immediately", "asap", "within 24", "within 30", "today only", "final notice", "last chance",
                        "신속히", "즉시", "긴급", "오늘까지", "급하게", "급히", "segera", "hari ini sahaja", "notis terakhir"]),
        Rule(id: "attachment", label: "Sends an unexpected file", points: 2,
             keywords: [".zip", ".apk", ".exe", "attached", "attachment", "statement of account", "invoice", "첨부", "lampiran"]),
        Rule(id: "computer", label: "Says to open it on a computer", points: 2,
             keywords: ["open it on a computer", "on your computer", "on a pc", "not visible on mobile", "on a laptop", "use a computer"]),
        Rule(id: "forward", label: "Asks you to forward it to finance", points: 1,
             keywords: ["finance manager", "accounts department", "forward this to", "finance team"]),
        Rule(id: "credentials", label: "Asks for a code or password", points: 2,
             keywords: ["otp", "password", " pin", "verify your account", "verification code", "login", "log in",
                        "인증번호", "비밀번호", "계좌번호", "보안카드", "kata laluan", "kod pengesahan"]),
        Rule(id: "investment", label: "Promises easy profit", points: 3,
             keywords: ["guaranteed return", "guaranteed profit", "monthly return", "% monthly", "investment group", "double your",
                        "수익 보장", "고수익", "리딩방", "원금 보장", "pelaburan", "untung"]),
        Rule(id: "nocall", label: "Tells you not to call", points: 2,
             keywords: ["don't call", "dont call", "do not call", "can't talk", "cant talk", "cannot talk", "can't call",
                        "can't pick up", "in a meeting", "text only", "jangan call", "jangan telefon", "tak boleh cakap",
                        "tak boleh angkat", "전화 안 돼", "전화하지 마", "전화 하지 마", "통화 안", "통화가 안", "전화 못", "전화는 안"]),
        Rule(id: "newphone", label: "Says they have a new phone or number", points: 2,
             keywords: ["new number", "lost my phone", "phone broke", "broken phone", "my new phone", "temporary phone",
                        "폰 고장", "폰이 고장", "액정", "임시폰", "번호 바뀌", "새 번호", "nombor baru", "telefon rosak"]),
    ]

    private static let shortHosts = ["bit.ly", "tinyurl", "t.co/", "goo.gl", "is.gd", "han.gl", "me2.do", "vo.la", "url.kr", "sw.run", "cutt.ly", "s.id/"]

    private static let summaryPatterns = [#"^\d+ new messages?$"#, #"^\d+ (more )?notifications?$"#, #"^새 메시지 \d+개"#]
    private static let systemTitles = ["message failed to send", "not delivered", "메시지 전송 실패"]

    static func evaluate(app: String, title: String, subtitle: String, body rawBody: String) -> RuleResult {
        let body = TextCleaner.clean(rawBody)
        let cleanTitle = TextCleaner.clean(title)

        // Things that are not a message from a person.
        if body.isEmpty { return .ignored("Empty message") }
        if app.lowercased().contains("stead") { return .ignored("Stead's own alert") }
        if systemTitles.contains(where: { cleanTitle.lowercased().contains($0) }) { return .ignored("System notice") }
        if summaryPatterns.contains(where: { body.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
            return .ignored("Notification summary")
        }

        let lower = " " + body.lowercased() + " "
        var signals: [Signal] = []

        // A genuine one-time code ("Your OTP is 482913. Do not share it.") is skipped,
        // but remembered so the thread tracker can spot "code arrived right after a scam".
        if isOneTimeCode(lower) {
            return RuleResult(decision: .skip, score: 0, signals: [], ignoreReason: nil, isOneTimeCode: true)
        }

        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            signals.append(Signal(id: rule.id, label: rule.label, points: rule.points))
        }
        // Money amounts count as a payment request even without the words.
        if !signals.contains(where: { $0.id == "payment" }),
           lower.range(of: #"(rm|₩|\$|usd|krw)\s?\d|\d+\s?(원|만원|ringgit)"#, options: .regularExpression) != nil {
            signals.append(Signal(id: "payment", label: "Asks for a payment or fee", points: 2))
        }

        if let link = linkSignal(lower) { signals.append(contentsOf: link) }

        if TextCleaner.hiddenCharactersInsideWords(rawBody) > 0 {
            signals.append(Signal(id: "hidden", label: "Hides invisible characters in the text", points: 2))
        }
        if isPhoneNumber(cleanTitle) {
            signals.append(Signal(id: "number", label: "From a number you haven't saved", points: 1))
        }

        let score = signals.reduce(0) { $0 + $1.points }
        return RuleResult(decision: score >= threshold ? .analyze : .skip, score: score, signals: signals, ignoreReason: nil)
    }

    /// Any link scores 2; a short link adds 1.
    private static func linkSignal(_ text: String) -> [Signal]? {
        let hasURL = text.range(of: #"(https?://|www\.)\S+"#, options: .regularExpression) != nil
            || text.range(of: #"\b[a-z0-9-]+\.(com|net|org|kr|my|co|io|ly|me|xyz|top|site|link|info|shop|app|example)(/\S*)?\b"#,
                          options: .regularExpression) != nil
        guard hasURL else { return nil }
        var out = [Signal(id: "link", label: "Contains a link", points: 2)]
        let isShort = shortHosts.contains(where: { text.contains($0) })
            || text.range(of: #"https?://[a-z0-9-]{1,6}\.[a-z]{2,4}/[a-z0-9]{3,}"#, options: [.regularExpression, .caseInsensitive]) != nil
        if isShort { out.append(Signal(id: "shortlink", label: "Uses a shortened link that hides where it goes", points: 1)) }
        return out
    }

    static func isOneTimeCode(_ lower: String) -> Bool {
        let hasCode = lower.range(of: #"\b\d{4,8}\b"#, options: .regularExpression) != nil
        let mentionsCode = ["otp", "code", "tac", "인증번호", "승인번호", "kod"].contains(where: lower.contains)
        let saysDontShare = ["do not share", "don't share", "never share", "jangan kongsi", "타인에게", "노출하지", "알려주지"].contains(where: lower.contains)
        let hasLink = lower.contains("http") || lower.contains("www.")
        return hasCode && mentionsCode && saysDontShare && !hasLink
    }

    static func isPhoneNumber(_ title: String) -> Bool {
        let digits = title.filter(\.isNumber)
        let allowed = CharacterSet(charactersIn: "+-() 0123456789")
        return digits.count >= 7 && title.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func senderKind(_ title: String) -> String {
        if title.isEmpty { return "unknown" }
        if isPhoneNumber(title) { return "number" }
        if title.contains("@") { return "email" }
        return "contact"
    }
}
