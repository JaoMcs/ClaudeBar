import AppKit
import OSLog
import SwiftUI

/// Popup próprio, desenhado pelo app no canto da tela.
///
/// Existe porque a Central de Notificações do macOS recusa app assinado ad-hoc
/// ("Notifications are not allowed for this application"): sem Developer ID não
/// há notificação nativa. Este painel não depende de assinatura nem de
/// permissão, então funciona sempre.
@MainActor
final class StatusHUD {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    /// O que está na tela agora, e de qual sessão. `nil` com o painel fechado.
    private var shownAlert: Alert?
    private var shownSessionId: String?
    private let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "hud")

    private static let visibleDuration: Duration = .seconds(4)
    private static let margin: CGFloat = 16
    private static let width: CGFloat = 320

    // ponytail: um painel só, sem fila. Com duas sessões esperando aparece a
    // última; o ícone da barra segue avisando da outra. Fila se isso incomodar.
    /// - Parameter onOpen: chamado no clique, antes de fechar — leva à sessão.
    func show(_ alert: Alert, body: String, sessionId: String? = nil, onOpen: (@MainActor () -> Void)? = nil) {
        // Aviso informativo não tapa um de espera ainda aberto: fica só o som.
        if !alert.staysUntilAnswered, shownAlert?.staysUntilAnswered == true { return }

        let content = HUDView(alert: alert, body: body, width: Self.width) { [weak self] in
            onOpen?()
            self?.dismiss()
        }

        // A largura é fixa e a altura vem do layout — mas só depois de forçar o
        // layout: ler `fittingSize` antes disso devolve zero e o painel acaba
        // posicionado fora da tela.
        let hosting = NSHostingView(rootView: content)
        hosting.setFrameSize(NSSize(width: Self.width, height: 0))
        hosting.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: max(hosting.fittingSize.height, 1))

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(size)
        reposition(panel, size: size)
        panel.orderFrontRegardless()
        announce(alert, body: body)

        shownAlert = alert
        shownSessionId = sessionId

        // Aviso novo renova o tempo em vez de empilhar painéis. Aviso de espera
        // não tem tempo: fica até o clique ou até a sessão sair de "esperando".
        dismissTask?.cancel()
        dismissTask = nil
        guard !alert.staysUntilAnswered else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// O painel não toma foco, então o VoiceOver não passa por ele sozinho.
    private func announce(_ alert: Alert, body: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(alert.title). \(body)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        shownAlert = nil
        shownSessionId = nil
        panel?.orderOut(nil)
    }

    /// Fecha o aviso de espera se ele for desta sessão.
    func dismissWaiting(for sessionId: String) {
        guard shownAlert?.staysUntilAnswered == true, shownSessionId == sessionId else { return }
        dismiss()
    }

    /// Canto da tela para o popup: superior direito, a não ser que o cursor
    /// esteja lá — popup que fica na tela não pode nascer debaixo do clique.
    /// Ordem: superior direito, inferior direito, superior esquerdo.
    nonisolated static func origin(
        for size: NSSize, in frame: NSRect, avoiding mouse: NSPoint, margin: CGFloat
    ) -> NSPoint {
        let right = frame.maxX - size.width - margin
        let left = frame.minX + margin
        let top = frame.maxY - size.height - margin
        let bottom = frame.minY + margin
        let corners = [NSPoint(x: right, y: top), NSPoint(x: right, y: bottom), NSPoint(x: left, y: top)]
        // A margem entra na conta: cursor encostado na borda do popup também conta.
        return corners.first { corner in
            !NSRect(origin: corner, size: size).insetBy(dx: -margin, dy: -margin).contains(mouse)
        } ?? corners[0]
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Acima de janela normal, mas sem roubar foco de quem você está usando.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }

    /// Um canto da tela onde está o cursor — a mesma tela em que a barra de menu
    /// do ClaudeBar está sendo olhada — mas longe dele.
    private func reposition(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let origin = Self.origin(for: size, in: frame, avoiding: mouse, margin: Self.margin)
        panel.setFrameOrigin(origin)

        log.info("""
        hud size=\(size.width, privacy: .public)x\(size.height, privacy: .public) \
        origin=\(origin.x, privacy: .public),\(origin.y, privacy: .public) \
        tela=\(frame.debugDescription, privacy: .public) \
        painel=\(panel.frame.debugDescription, privacy: .public)
        """)
    }
}

/// Conteúdo do popup.
private struct HUDView: View {
    let alert: Alert
    let body_: String
    let width: CGFloat
    let onDismiss: () -> Void

    init(alert: Alert, body: String, width: CGFloat, onDismiss: @escaping () -> Void) {
        self.alert = alert
        self.body_ = body
        self.width = width
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 22))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(body_)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        // Título e corpo lidos juntos se o VoiceOver chegar ao painel.
        .accessibilityElement(children: .combine)
        .onTapGesture(perform: onDismiss)
    }

    private var symbolName: String {
        switch alert {
        case .finished: "checkmark.circle.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .permission: "hand.raised.fill"
        case .question: "questionmark.bubble.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch alert {
        case .finished: .green
        case .waiting, .permission, .question: .orange
        case .failed: .red
        }
    }
}
