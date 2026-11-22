import Carbon.HIToolbox
import Foundation

/// Atalho global ⌃⌥⌘N pela API de hot keys do Carbon. Diferente de um monitor
/// de teclado (`NSEvent.addGlobalMonitorForEvents`), não pede Acessibilidade
/// nem Monitoramento de Entrada: o sistema só avisa quando *esta* combinação é
/// pressionada. Opt-in: a combinação fica tomada no sistema inteiro.
@MainActor
enum GlobalHotKey {
    /// Chave do `UserDefaults`. Padrão `false`.
    nonisolated static let enabledKey = "globalHotKeyEnabled"
    /// Mostrado nos Ajustes e no README. Tecla física: em layout não QWERTY é
    /// a tecla que fica onde o N fica no QWERTY.
    nonisolated static let display = "⌃⌥⌘N"

    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            status == eventHotKeyExistsErr
                ? String(localized: "Another app already uses \(GlobalHotKey.display).")
                : String(localized: "macOS refused the shortcut (error \(String(status))).")
        }
    }

    /// Idempotente: chamar de novo só troca a ação.
    static func register(_ action: @escaping @MainActor () -> Void) throws {
        self.action = action
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // Ponteiro de função C: não captura nada, lê a ação estática. O alvo
            // é o do app, então o evento chega na main thread.
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { GlobalHotKey.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
            guard status == noErr else { throw Failure(status: status) }
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4157_4254, id: 1) // "AWBT"
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { throw Failure(status: status) }
        hotKey = ref
    }

    /// Idempotente: libera a combinação para outros apps.
    static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
