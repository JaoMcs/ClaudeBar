import AppKit
import Darwin

/// Leva você até a sessão: sobe a árvore de processos do `claude` até o app que
/// a hospeda (terminal, editor, Claude.app) e traz esse app para a frente.
///
/// Nada aqui pede permissão: `sysctl`, `NSRunningApplication` e `NSWorkspace`
/// funcionam com assinatura ad-hoc. Trazer a **aba** exata exigiria Apple Events
/// (Automação), que fica para depois.
public enum SessionNavigator {
    /// App que hospeda a sessão do `pid` (o processo do `claude`).
    ///
    /// Dentro do tmux a subida termina no servidor (filho do `launchd`), então o
    /// caminho é outro: achar o pane pelo TTY, trocar o cliente para ele e subir
    /// a partir do cliente. `followTmux: false` pula essa parte — ela troca o
    /// pane de verdade, então só deve rodar quando você pediu para ir.
    ///
    /// Síncrono e pode rodar `tmux`: chame fora da main actor.
    public static func app(for pid: Int32, followTmux: Bool = true) -> NSRunningApplication? {
        if let found = ancestor(of: pid, parent: parentPID, isApp: isRegularApp) {
            return NSRunningApplication(processIdentifier: found)
        }
        guard followTmux,
              let client = switchTmuxClient(toSessionOf: pid),
              let found = ancestor(of: client, parent: parentPID, isApp: isRegularApp)
        else { return nil }
        return NSRunningApplication(processIdentifier: found)
    }

    /// Traz o app para a frente. No macOS 14 a ativação é cooperativa: o
    /// `activate` pode ser recusado quando quem pede não é o app ativo (um app
    /// de barra de menu, uma CLI). O `NSWorkspace` faz a cessão por nós.
    @MainActor
    public static func bringToFront(_ app: NSRunningApplication) async -> Bool {
        if app.activate(options: []) { return true }
        guard let url = app.bundleURL else { return false }
        // `activates` já é `true` por padrão; app em execução é reaproveitado.
        let opened = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return opened != nil
    }

    // MARK: - Árvore de processos

    /// Primeiro ancestral (incluindo o próprio `pid`) que é um app com janela.
    ///
    /// Função pura, para os testes descreverem árvores falsas. O limite evita
    /// laço infinito numa árvore inesperada.
    static func ancestor(of pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
        var current = pid
        for _ in 0..<64 where current > 1 {
            if isApp(current) { return current }
            guard let next = parent(current), next != current else { return nil }
            current = next
        }
        return nil
    }

    /// `.regular` pula helpers (Electron, `LSUIElement`), que também aparecem
    /// como `NSRunningApplication` mas não têm a janela da sessão.
    private static func isRegularApp(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    /// `sysctl`, não `proc_pidinfo`: este falha em processo de root, e o
    /// Terminal.app põe um `/usr/bin/login` (setuid root) entre ele e o shell.
    static func parentPID(_ pid: Int32) -> Int32? {
        kinfo(pid).map { $0.kp_eproc.e_ppid }
    }

    /// Terminal de controle do processo (ex. `/dev/ttys003`), ou `nil` sem TTY.
    static func ttyPath(of pid: Int32) -> String? {
        // `-1` é o `NODEV` do C (não importado pelo Swift): processo sem terminal.
        guard let device = kinfo(pid)?.kp_eproc.e_tdev, device != -1 else { return nil }
        var buffer = [CChar](repeating: 0, count: 64)
        // `devname_r`, não `devname`: este devolve um buffer estático.
        let name = buffer.withUnsafeMutableBufferPointer { pointer in
            devname_r(device, S_IFCHR, pointer.baseAddress, Int32(pointer.count)).map { String(cString: $0) }
        }
        guard let name, name != "??" else { return nil }
        return "/dev/\(name)"
    }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // PID inexistente devolve sucesso com `size == 0`.
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    // MARK: - tmux

    /// Um app de barra de menu não herda o `PATH` do shell. Sem `zsh -lc` de
    /// reserva: se o tmux não está num caminho conhecido, não há tmux.
    private static let tmuxURL: URL? = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    .first { FileManager.default.isExecutableFile(atPath: $0) }
    .map { URL(fileURLWithPath: $0) }

    /// Troca o cliente tmux mais recente para o pane da sessão e devolve o PID
    /// dele — é o cliente que roda dentro do terminal. Só o socket padrão.
    ///
    /// `select-window` + `select-pane` + `switch-client` para a sessão existem em
    /// qualquer tmux; `switch-client -t %pane` só nas versões novas.
    private static func switchTmuxClient(toSessionOf pid: Int32) -> Int32? {
        guard let tmux = tmuxURL,
              let tty = ttyPath(of: pid),
              let panes = Shell.output(of: tmux, arguments: ["list-panes", "-a", "-F", "#{pane_tty}\t#{pane_id}\t#{session_id}"]),
              let target = pane(forTTY: tty, in: panes),
              let clients = Shell.output(of: tmux, arguments: ["list-clients", "-t", target.session, "-F", "#{client_activity}\t#{client_tty}\t#{client_pid}"]),
              let client = mostRecentClient(in: clients)
        else { return nil }

        // Argumentos separados, nunca interpolados: id e tty vêm do tmux, mas
        // continuam não passando por shell.
        _ = Shell.output(of: tmux, arguments: ["select-window", "-t", target.pane])
        _ = Shell.output(of: tmux, arguments: ["select-pane", "-t", target.pane])
        _ = Shell.output(of: tmux, arguments: ["switch-client", "-c", client.tty, "-t", target.session])
        return client.pid
    }

    /// Linha de `list-panes -a -F '#{pane_tty}\t#{pane_id}\t#{session_id}'`
    /// cujo TTY é o do `claude`. Linha fora do formato é ignorada.
    static func pane(forTTY tty: String, in listPanes: String) -> (pane: String, session: String)? {
        for line in listPanes.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 3, fields[0] == tty {
                return (String(fields[1]), String(fields[2]))
            }
        }
        return nil
    }

    /// Com vários terminais anexados à mesma sessão, o que você usou por último.
    static func mostRecentClient(in listClients: String) -> (tty: String, pid: Int32)? {
        listClients.split(separator: "\n")
            .compactMap { line -> (activity: Int, tty: String, pid: Int32)? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count == 3, let activity = Int(fields[0]), let pid = Int32(fields[2]) else { return nil }
                return (activity, String(fields[1]), pid)
            }
            .max { $0.activity < $1.activity }
            .map { ($0.tty, $0.pid) }
    }
}
