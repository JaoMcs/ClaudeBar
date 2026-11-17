import Foundation

/// Troca o `statusLine` do `settings.json` pelo do ClaudeBar e desfaz a troca.
/// Funções puras sobre o dicionário do `JSONSerialization`; ler, fazer backup
/// e gravar o arquivo é do `HookInstaller`.
public enum StatusLineInstall {
    /// O que fazer com `statusline-original.json` depois da troca.
    /// `@unchecked`: só guarda o objeto imutável que o `JSONSerialization` devolveu.
    public enum Original: @unchecked Sendable {
        /// Já estava instalado: o arquivo guarda o original de verdade.
        case keep
        /// Gravar este objeto (0600).
        case save([String: Any])
        /// Não havia statusline: apagar um arquivo velho, se existir.
        case remove
    }

    /// `true` quando o `statusLine` é o nosso.
    public static func isOurs(_ statusLine: Any?) -> Bool {
        guard let command = (statusLine as? [String: Any])?["command"] as? String else { return false }
        return command.contains("claudebar-hook")
    }

    /// `hookCommand` já vem pronto para shell, com ` statusline` no fim.
    public static func install(
        _ settings: [String: Any],
        hookCommand: String
    ) -> (settings: [String: Any], original: Original) {
        let current = settings["statusLine"] as? [String: Any]
        // Reinstalar não pode salvar o nosso como "original": o hook chamaria
        // a si mesmo.
        if isOurs(current) { return (settings, .keep) }

        // Mantém `padding`, `refreshInterval` e o que mais o usuário tinha.
        var ours = current ?? [:]
        ours["type"] = "command"
        ours["command"] = hookCommand
        var result = settings
        result["statusLine"] = ours
        return (result, current.map { .save($0) } ?? .remove)
    }

    /// Só desfaz se o `statusLine` ainda é o nosso: se o usuário trocou depois,
    /// a escolha dele fica. O instalador apaga `statusline-original.json` depois.
    public static func uninstall(_ settings: [String: Any], original: [String: Any]?) -> [String: Any] {
        guard isOurs(settings["statusLine"]) else { return settings }
        var result = settings
        result["statusLine"] = original
        return result
    }
}
