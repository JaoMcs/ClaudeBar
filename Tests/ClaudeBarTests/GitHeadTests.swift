import Foundation
import Testing

@testable import ClaudeBarCore

@Suite("Branch lida do .git/HEAD")
struct GitHeadTests {
    @Test func interpretaOConteudoDoHead() {
        #expect(GitHead.parse("ref: refs/heads/main\n") == "main")
        #expect(GitHead.parse("ref: refs/heads/feat/x") == "feat/x")
        // Stub do reftable: a branch real não está no arquivo.
        #expect(GitHead.parse("ref: refs/heads/.invalid\n") == nil)
        #expect(GitHead.parse(String(repeating: "a1", count: 20) + "\n") == "@a1a1a1a")
        #expect(GitHead.parse("lixo") == nil)
        #expect(GitHead.parse("") == nil)
    }

    /// Subpasta do repositório, worktree com `gitdir:` relativo e absoluto, e
    /// pasta fora de repositório.
    @Test func achaOHeadCertoNoDisco() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: base) }
        func put(_ path: String, _ text: String) throws {
            let url = base.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try put("main/.git/HEAD", "ref: refs/heads/main\n")
        try put("main/Sources/x/.keep", "")
        try put("main/.git/worktrees/wt/HEAD", "ref: refs/heads/feat/x\n")
        try put("wt/.git", "gitdir: ../main/.git/worktrees/wt\n")
        try put("abs/.git", "gitdir: \(base.path)/main/.git/worktrees/wt\n")
        try put("solto/.keep", "")

        #expect(GitHead.branch(at: base.appendingPathComponent("main/Sources/x").path) == "main")
        #expect(GitHead.branch(at: base.appendingPathComponent("wt").path) == "feat/x")
        #expect(GitHead.branch(at: base.appendingPathComponent("abs").path) == "feat/x")
        #expect(GitHead.branch(at: base.appendingPathComponent("solto").path) == nil)
        #expect(GitHead.branch(at: "relativo") == nil)
    }
}
