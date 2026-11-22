import Foundation

/// Uma janela de limite de uso (5 h ou semanal), como vem no stdin do statusline.
public struct RateWindow: Codable, Sendable, Equatable {
    /// De 0 a 100, decimal. Já veio acima de 100 em versões antigas do CLI.
    public let usedPercentage: Double
    public let resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// Percentual inteiro para exibir, preso entre 0 e 100.
    public var displayPercent: Int {
        Int(min(max(usedPercentage, 0), 100).rounded())
    }

    /// Aviso único por janela: passou de `percent`, a janela ainda vale e ainda
    /// não se avisou desta `resetsAt` (janela nova = `resetsAt` nova).
    public func crossedThreshold(_ percent: Double, alertedWindow: Date?, now: Date) -> Bool {
        usedPercentage >= percent && resetsAt > now && alertedWindow != resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

/// Limites da conta. Mesmo formato do `rate_limits` do statusline, mais a hora
/// em que o hook gravou — o app mostra a idade do dado.
public struct RateLimits: Codable, Sendable, Equatable {
    public var fiveHour: RateWindow?
    public var sevenDay: RateWindow?
    /// `nil` no payload do Claude Code; o hook preenche antes de gravar.
    public var updatedAt: Date?

    public init(fiveHour: RateWindow? = nil, sevenDay: RateWindow? = nil, updatedAt: Date? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case updatedAt = "updated_at"
    }

    /// Extrai os limites do JSON que o Claude Code manda ao statusline.
    ///
    /// `nil` quando o campo não vem (chave de API, sessão antes da 1ª resposta)
    /// ou vem sem nenhuma janela: nesses casos não se grava nada, para não
    /// apagar o dado bom que outra sessão gravou.
    public static func fromStatusLine(_ data: Data, now: Date = Date()) -> RateLimits? {
        struct Input: Decodable {
            let rateLimits: RateLimits?
            enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
        }
        guard var limits = (try? StatusDirectory.decoder.decode(Input.self, from: data))?.rateLimits,
              limits.fiveHour != nil || limits.sevenDay != nil
        else { return nil }
        limits.updatedAt = now
        return limits
    }

    /// Regravar acorda o app (watcher → consulta ao CLI). Só vale a pena se o
    /// número mudou ou se o dado salvo já tem um minuto.
    public func needsWrite(over saved: RateLimits?, now: Date = Date()) -> Bool {
        guard let saved else { return true }
        return saved.fiveHour != fiveHour || saved.sevenDay != sevenDay
            || now.timeIntervalSince(saved.updatedAt ?? .distantPast) >= 60
    }

    /// Linha curta impressa no rodapé do Claude Code quando não havia statusline
    /// antes. Janela ausente ou já renovada vira "–", nunca 0%.
    public func summary(now: Date = Date()) -> String {
        func text(_ window: RateWindow?) -> String {
            guard let window, window.resetsAt > now else { return "–" }
            return "\(window.displayPercent)%"
        }
        return "5h \(text(fiveHour)) · sem \(text(sevenDay))"
    }
}
