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
    private let log = Logger(subsystem: "com.joaomarcos.claudebar", category: "hud")

    private static let visibleDuration: Duration = .seconds(4)
    private static let margin: CGFloat = 16
    private static let width: CGFloat = 320

    func show(_ alert: Alert, body: String) {
        let content = HUDView(alert: alert, body: body, width: Self.width) { [weak self] in
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

        // Aviso novo renova o tempo em vez de empilhar painéis.
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
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

    /// Canto superior direito da tela onde está o cursor — a mesma tela em que a
    /// barra de menu do ClaudeBar está sendo olhada.
    private func reposition(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let origin = CGPoint(
            x: frame.maxX - size.width - Self.margin,
            y: frame.maxY - size.height - Self.margin
        )
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
        .onTapGesture(perform: onDismiss)
    }

    private var symbolName: String {
        switch alert {
        case .finished: "checkmark.circle.fill"
        case .waiting: "exclamationmark.bubble.fill"
        }
    }

    private var tint: Color {
        switch alert {
        case .finished: .green
        case .waiting: .orange
        }
    }
}
