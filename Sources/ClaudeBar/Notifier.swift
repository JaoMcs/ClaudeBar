import AppKit
import ClaudeBarCore
import Observation
import OSLog
import UserNotifications

/// Os avisos que o app dá, cada um com som próprio.
///
/// A distinção importa: "terminou" é informativo, "esperando você" é
/// bloqueante — a sessão só anda depois que você responde.
enum Alert {
    /// A sessão passou de processando para pronto.
    case finished
    /// A sessão está travada esperando você, sem tipo conhecido.
    case waiting
    /// O Claude quer aprovar uma ferramenta.
    case permission
    /// O Claude fez uma pergunta e espera a resposta.
    case question
    /// A resposta falhou por erro de API (limite, sobrecarga…): o turno acabou
    /// sem o "terminou" que você esperava.
    case failed
    /// O uso da janela de 5 h passou do percentual escolhido nos Ajustes.
    case limit

    init(waiting kind: WaitKind?) {
        self = switch kind {
        case .permission: .permission
        case .question: .question
        case nil: .waiting
        }
    }

    var title: String {
        switch self {
        case .finished: String(localized: "Claude finished")
        case .waiting: String(localized: "Claude is waiting for you")
        case .permission: String(localized: "Claude asks for permission")
        case .question: String(localized: "Claude asked a question")
        case .failed: String(localized: "Claude's reply failed")
        case .limit: String(localized: "5 h limit is running out")
        }
    }

    /// Avisos que pedem ação sua: ficam na tela até você agir.
    var staysUntilAnswered: Bool {
        switch self {
        case .waiting, .permission, .question: true
        case .finished, .failed, .limit: false
        }
    }

    /// Som do sistema, em `/System/Library/Sounds`.
    ///
    /// `Submarine` é um pulso grave, bem distinto do sino claro do `Glass`:
    /// dá para saber qual dos dois aconteceu sem olhar a tela. `Basso` é o
    /// som de erro do macOS. `Purr` é mais suave que o `Submarine`: pergunta
    /// não trava uma ferramenta no meio, permissão trava.
    var soundName: String {
        switch self {
        case .finished: "Glass"
        case .waiting, .permission: "Submarine"
        case .question: "Purr"
        case .failed: "Basso"
        case .limit: "Funk"
        }
    }

    /// Chave em `UserDefaults` do "avisar" deste tipo (Ajustes). Permissão e
    /// pergunta são espera: dividem o toggle com "esperando você".
    var enabledKey: String {
        switch self {
        case .finished: "notifyFinished"
        case .waiting, .permission, .question: "notifyWaiting"
        case .failed: "notifyFailed"
        case .limit: "notifyLimit"
        }
    }

    /// Chave em `UserDefaults` do som escolhido para este tipo (Ajustes).
    /// Permissão usa o mesmo som de "esperando", como no padrão.
    var soundKey: String {
        switch self {
        case .finished: "soundFinished"
        case .waiting, .permission: "soundWaiting"
        case .question: "soundQuestion"
        case .failed: "soundFailed"
        case .limit: "soundLimit"
        }
    }

    /// Fração do volume principal. O aviso de "esperando" toca mais baixo por
    /// ser o que repete enquanto você não responde.
    var volume: Float {
        switch self {
        case .finished, .failed, .limit: 1
        case .waiting, .permission, .question: 0.75
        }
    }
}

/// O que oferecer no menu a respeito das notificações.
enum NotificationState: Equatable {
    /// Desligadas por você, no menu.
    case off
    /// Ligadas, saindo pela Central de Notificações do macOS.
    case systemNotifications
    /// Ligadas, saindo pelo popup próprio do app — o macOS recusa a API para
    /// app sem Developer ID, então esse é o caminho normal aqui.
    case ownPopup
}

/// Notificação do sistema + som.
@MainActor
@Observable
final class Notifier {
    /// Ligado/desligado por você, no menu. Persiste entre execuções.
    private(set) var isEnabled: Bool
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private var sounds: [String: NSSound] = [:]
    private let hud = StatusHUD()
    private let isBundled = Bundle.main.bundleIdentifier != nil
    private let defaults: UserDefaults
    /// Só para teste: observa o som em vez de tocar. `nil` toca de verdade.
    private let soundOverride: (@MainActor (Alert) -> Void)?
    private let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "notifications")

    private static let enabledKey = "notificationsEnabled"
    static let soundEnabledKey = "soundEnabled"
    static let reminderEnabledKey = "waitingReminderEnabled"
    static let reminderMinutesKey = "waitingReminderMinutes"
    static let hideContentKey = "hideContent"
    static let limitThresholdKey = "limitAlertThreshold"
    private static let limitAlertedWindowKey = "limitAlertedWindow"

    /// Sons do sistema, sem extensão — é como o `NSSound(named:)` prefere o nome.
    /// Lidos do disco para acompanhar o que o macOS instalado tiver.
    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    /// Notificação nativa exige assinatura com Developer ID; ad-hoc é recusado
    /// com "Notifications are not allowed for this application".
    private var canUseSystemNotifications: Bool {
        isBundled && (authorization == .authorized || authorization == .provisional)
    }

    var state: NotificationState {
        guard isEnabled else { return .off }
        return canUseSystemNotifications ? .systemNotifications : .ownPopup
    }

    init(defaults: UserDefaults = .standard, playSound: (@MainActor (Alert) -> Void)? = nil) {
        self.defaults = defaults
        soundOverride = playSound
        // Padrão ligado: quem instalou um app de aviso quer ser avisado.
        var padroes: [String: Any] = [
            Self.enabledKey: true, Self.soundEnabledKey: true,
            Self.reminderEnabledKey: true, Self.reminderMinutesKey: 5,
        ]
        for alert in [Alert.finished, .waiting, .permission, .question, .failed, .limit] {
            padroes[alert.enabledKey] = true
            padroes[alert.soundKey] = alert.soundName
        }
        // Aviso de limite é opt-in: o único que nasce desligado.
        padroes[Alert.limit.enabledKey] = false
        padroes[Self.limitThresholdKey] = 80
        defaults.register(defaults: padroes)
        isEnabled = defaults.bool(forKey: Self.enabledKey)

        if isEnabled {
            requestAuthorization()
        } else {
            refreshAuthorization()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        log.info("notificações \(enabled ? "ligadas" : "desligadas") pelo menu")

        if enabled {
            requestAuthorization()
        } else {
            hud.dismiss()
        }
    }

    /// Lembrete único de espera ligado nos Ajustes. Lido na hora, sem cópia.
    var isReminderEnabled: Bool { defaults.bool(forKey: Self.reminderEnabledKey) }

    /// "Nunca mostrar o conteúdo da mensagem". Lido na hora, sem cópia, para
    /// valer no próximo aviso sem reiniciar.
    var hidesContent: Bool { defaults.bool(forKey: Self.hideContentKey) }

    /// Aviso do limite de 5 h ligado nos Ajustes (e notificações ligadas no menu).
    var isLimitAlertEnabled: Bool { isEnabled && defaults.bool(forKey: Alert.limit.enabledKey) }

    /// Percentual dos Ajustes a partir do qual avisar.
    var limitThreshold: Double { Double(defaults.integer(forKey: Self.limitThresholdKey)) }

    /// `resetsAt` da janela de 5 h que já avisou. Persiste: reabrir o app na
    /// mesma janela não repete o aviso.
    var limitAlertedWindow: Date? {
        get { defaults.object(forKey: Self.limitAlertedWindowKey) as? Date }
        set { defaults.set(newValue, forKey: Self.limitAlertedWindowKey) }
    }

    /// Minutos até o lembrete, nunca menos de 1.
    var reminderMinutes: Int { max(defaults.integer(forKey: Self.reminderMinutesKey), 1) }

    /// Som a tocar para o aviso, ou `nil` com o som desligado nos Ajustes.
    func soundName(for alert: Alert) -> String? {
        guard defaults.bool(forKey: Self.soundEnabledKey) else { return nil }
        return defaults.string(forKey: alert.soundKey) ?? alert.soundName
    }

    /// Toca o som escolhido nos Ajustes, para você ouvir antes de decidir.
    func preview(_ soundName: String, for alert: Alert) {
        play(soundName, volume: alert.volume)
    }

    /// Mostra um popup de exemplo, para conferir o canto da tela e o estilo.
    /// Sem `onOpen`: o clique só fecha. Ignora o liga/desliga por tipo dos
    /// Ajustes: o exemplo é pedido na hora, não é um aviso de sessão.
    func showSample() {
        post(.permission, body: hidesContent
            ? String(localized: "Example: my-project needs you")
            : String(localized: "Example: Claude needs your permission to use Bash"), sample: true)
    }

    /// Fecha o popup de espera desta sessão, se for ele que está na tela.
    func dismissWaiting(for sessionId: String) {
        hud.dismissWaiting(for: sessionId)
    }

    /// - Parameters:
    ///   - playSound: `false` mostra o aviso mudo — você já está olhando o app
    ///     da sessão (F14).
    ///   - onOpen: o que o clique no popup faz antes de fechar. A notificação
    ///     nativa ignora: não há delegate de clique ainda.
    ///   - sample: `true` passa mesmo com este tipo desligado nos Ajustes.
    func post(
        _ alert: Alert,
        body: String,
        sessionId: String? = nil,
        playSound: Bool = true,
        sample: Bool = false,
        onOpen: (@MainActor () -> Void)? = nil
    ) {
        // Desligado no menu, ou este tipo desligado nos Ajustes = silêncio total.
        guard isEnabled, sample || defaults.bool(forKey: alert.enabledKey) else { return }

        if playSound, let soundName = soundName(for: alert) {
            if let soundOverride { soundOverride(alert) } else { play(soundName, volume: alert.volume) }
        }

        guard canUseSystemNotifications else {
            // Caminho normal com assinatura ad-hoc: popup desenhado pelo app.
            hud.show(alert, body: body, sessionId: sessionId, onOpen: onOpen)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = body
        // Sem som na notificação: quem toca é o `NSSound` acima, que é o único
        // jeito de controlar volume e escolher som por tipo de aviso.

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [log] error in
            if let error {
                log.error("falha ao entregar notificação: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func requestAuthorization() {
        guard isBundled else {
            log.warning("sem bundle: API de notificação indisponível")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [log] granted, error in
            if let error {
                log.error("requestAuthorization falhou: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("requestAuthorization: \(granted ? "concedida" : "negada", privacy: .public)")
            }
            Task { @MainActor in self.refreshAuthorization() }
        }
    }

    private func refreshAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [log] settings in
            let status = settings.authorizationStatus
            log.info("status de autorização: \(status.rawValue, privacy: .public)")
            Task { @MainActor in self.authorization = status }
        }
    }

    private func play(_ name: String, volume: Float) {
        // O NSSound é reaproveitado por nome; tocar de novo enquanto ainda soa
        // não faz nada, então rebobina antes. Nome que sumiu do sistema dá
        // `nil` e o aviso sai calado, sem quebrar.
        let sound = sounds[name] ?? NSSound(named: name)
        guard let sound else { return }
        sounds[name] = sound

        if sound.isPlaying {
            sound.stop()
        }
        sound.volume = volume
        sound.play()
    }
}
