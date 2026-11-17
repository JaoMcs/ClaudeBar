import AppKit
import SwiftUI

/// Janela de Ajustes, aberta pelo item "Ajustes…" do menu.
///
/// `NSWindow` próprio em vez da cena `Settings`: num app accessory, o
/// `SettingsLink`/`openSettings` dentro de um `MenuBarExtra` `.menu` abre a
/// janela atrás do app da frente, e a correção conhecida depende de
/// identificador privado e de delays. Aqui a janela está na mão, e
/// `orderFrontRegardless` traz para a frente mesmo com o app inativo.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(notifier: Notifier) {
        // Fechada = janela nova, com estado relido. Aberta = só traz para a frente.
        if window?.isVisible != true {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(notifier: notifier)
            ))
            window.title = "Ajustes do ClaudeBar"
            window.styleMask = [.titled, .closable]
            // Quem mantém a janela viva é a referência acima; sem isso o
            // `close()` a liberaria por conta própria.
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        // `activate()` não garante ativação (é cooperativa no macOS 14+);
        // `orderFrontRegardless` garante a janela visível na frente.
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Conteúdo da janela de Ajustes. Tudo fica em `UserDefaults`; o `Notifier` lê
/// cada valor na hora do aviso, então não há cópia para sincronizar. O
/// interruptor geral "Notificações" fica só no menu.
private struct SettingsView: View {
    let notifier: Notifier

    @AppStorage(Alert.finished.enabledKey) private var notifyFinished = true
    @AppStorage(Alert.waiting.enabledKey) private var notifyWaiting = true
    @AppStorage(Alert.failed.enabledKey) private var notifyFailed = true
    @AppStorage(Notifier.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Alert.finished.soundKey) private var soundFinished = Alert.finished.soundName
    @AppStorage(Alert.waiting.soundKey) private var soundWaiting = Alert.waiting.soundName
    @AppStorage(Alert.question.soundKey) private var soundQuestion = Alert.question.soundName
    @AppStorage(Alert.failed.soundKey) private var soundFailed = Alert.failed.soundName

    var body: some View {
        Form {
            Section("Avisos") {
                Toggle("Avisar quando o Claude terminar", isOn: $notifyFinished)
                Toggle("Avisar quando o Claude esperar você", isOn: $notifyWaiting)
                Toggle("Avisar quando a resposta falhar", isOn: $notifyFailed)
            }

            Section("Som") {
                Toggle("Tocar som", isOn: $soundEnabled)
                soundPicker("Terminou", selection: $soundFinished, alert: .finished)
                // Permissão e "esperando" dividem o mesmo som.
                soundPicker("Pede permissão / esperando", selection: $soundWaiting, alert: .waiting)
                soundPicker("Pergunta", selection: $soundQuestion, alert: .question)
                soundPicker("Falhou", selection: $soundFailed, alert: .failed)
            }

            Section("Sistema") {
                Button("Sobre o ClaudeBar") {
                    // O clique veio desta janela, então o app já está ativo e o
                    // painel nasce na frente. Nome e versão passados à mão: sem
                    // bundle (`swift run`) não há Info.plist.
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "ClaudeBar",
                        .applicationVersion: Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "dev",
                        .credits: NSAttributedString(
                            string: "Sem rede, sem login. Não lê suas conversas."
                        ),
                    ])
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func soundPicker(_ title: String, selection: Binding<String>, alert: Alert) -> some View {
        Picker(title, selection: selection) {
            ForEach(Notifier.systemSounds, id: \.self) { Text($0) }
        }
        .disabled(!soundEnabled)
        // O valor novo vem no closure: não depende da ordem entre a escrita do
        // `@AppStorage` e o `onChange`.
        .onChange(of: selection.wrappedValue) { _, name in
            notifier.preview(name, for: alert)
        }
    }
}
