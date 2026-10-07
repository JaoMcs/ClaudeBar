import AppKit
import Observation
import OSLog
import UserNotifications

/// Os dois avisos que o app dá, cada um com som próprio.
///
/// A distinção importa: "terminou" é informativo, "esperando você" é
/// bloqueante — a sessão só anda depois que você responde.
enum Alert {
    /// A sessão passou de processando para pronto.
    case finished
    /// A sessão está travada esperando permissão ou escolha sua.
    case waiting

    var title: String {
        switch self {
        case .finished: "Claude terminou"
        case .waiting: "Claude está esperando você"
        }
    }

    /// Som do sistema, em `/System/Library/Sounds`.
    ///
    /// `Submarine` é um pulso grave, bem distinto do sino claro do `Glass`:
    /// dá para saber qual dos dois aconteceu sem olhar a tela.
    var soundName: String {
        switch self {
        case .finished: "Glass"
        case .waiting: "Submarine"
        }
    }

    /// Fração do volume principal. O aviso de "esperando" toca mais baixo por
    /// ser o que repete enquanto você não responde.
    var volume: Float {
        switch self {
        case .finished: 1
        case .waiting: 0.75
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
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "notifications")

    private static let enabledKey = "notificationsEnabled"

    /// Notificação nativa exige assinatura com Developer ID; ad-hoc é recusado
    /// com "Notifications are not allowed for this application".
    private var canUseSystemNotifications: Bool {
        isBundled && (authorization == .authorized || authorization == .provisional)
    }

    var state: NotificationState {
        guard isEnabled else { return .off }
        return canUseSystemNotifications ? .systemNotifications : .ownPopup
    }

    init() {
        // Padrão ligado: quem instalou um app de aviso quer ser avisado.
        defaults.register(defaults: [Self.enabledKey: true])
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

    /// Mostra um popup de exemplo, para conferir o canto da tela e o estilo.
    func showSample() {
        post(.waiting, body: "Exemplo: Claude needs your permission to use Bash")
    }

    func post(_ alert: Alert, body: String) {
        play(alert)

        guard isEnabled else { return }
        guard canUseSystemNotifications else {
            // Caminho normal com assinatura ad-hoc: popup desenhado pelo app.
            hud.show(alert, body: body)
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

    private func play(_ alert: Alert) {
        // O NSSound é reaproveitado por nome; tocar de novo enquanto ainda soa
        // não faz nada, então rebobina antes.
        let sound = sounds[alert.soundName] ?? NSSound(named: alert.soundName)
        guard let sound else { return }
        sounds[alert.soundName] = sound

        if sound.isPlaying {
            sound.stop()
        }
        sound.volume = alert.volume
        sound.play()
    }
}
