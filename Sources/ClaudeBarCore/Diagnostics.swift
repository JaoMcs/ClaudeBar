import Foundation

/// Texto para colar numa issue. Só versões, estados, contagens e caminhos
/// anonimizados: nunca `cwd`, projeto, branch ou mensagem.
public enum Diagnostics {
    /// Troca o prefixo `home` por `~` só em fronteira de pasta.
    public static func anonymize(_ path: String, home: String) -> String {
        let home = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// `paths`: `(rótulo, caminho)` na ordem em que saem.
    public static func text(
        appVersion: String, osVersion: String, integration: IntegrationState,
        counts: [SessionState: Int], paths: [(String, String)], home: String
    ) -> String {
        var lines = [
            "Awaitbar: \(appVersion)",
            "macOS: \(osVersion)",
            "Integration: \(String(describing: integration))",
            "Sessions:",
        ]
        for state in SessionState.allCases {
            lines.append("  \(state.rawValue): \(counts[state] ?? 0)")
        }
        lines.append("Paths:")
        for (label, path) in paths {
            lines.append("  \(label): \(anonymize(path, home: home))")
        }
        return lines.joined(separator: "\n")
    }
}
