# Spec G08 — Abrir pasta do projeto (F11) + nome da sessão e branch (F20)

Insumos: `04-como-fazer/G08-pasta-nome-branch.md`, `03-validacao/BACKLOG.md` (F11 e F20: P, sem dependência), `00-PLANO.md` (guard rails), código em `main` @ 3561ab8.
São duas entregas independentes, e cada uma vira um PR:

| Id | Entrega | Arquivos | Esforço |
|---|---|---|---|
| **F11** | Item "Abrir pasta do projeto" no submenu da sessão | `Sources/ClaudeBar/SessionStore.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/OpenFolderTests.swift` (novo), `README.md`, `README.pt-BR.md` | 1 h |
| **F20** | Branch ao lado do nome (o nome já está pronto) | `Sources/ClaudeBarCore/GitHead.swift` (novo), `Sources/ClaudeBarCore/SessionStatus.swift`, `Sources/claudebar-hook/main.swift`, `Sources/ClaudeBar/SessionRow.swift`, `Sources/ClaudeBar/SessionMerge.swift`, `Sources/ClaudeBar/MenuContent.swift`, `Tests/ClaudeBarTests/GitHeadTests.swift` (novo), `Tests/ClaudeBarTests/SessionMergeTests.swift`, `README.md`, `README.pt-BR.md`, `planning/03-validacao/BACKLOG.md` | 2,5 h |

Ordem e conflitos, para o gestor:
- F11 e F20 se tocam só em `MenuContent.swift`, em pontos diferentes (submenu e `label(for:)`). Rodam em qualquer ordem, mas não em paralelo no mesmo arquivo.
- **F20 conflita com F07.1 (spec G06)**: os dois mexem em `SessionStatus.swift`, `claudebar-hook/main.swift`, `SessionMerge.swift` e `MenuContent.swift`. Os conflitos são textuais e pequenos (um caso no enum contra um campo novo). Faça em sequência, qualquer um primeiro.
- **F09** deve chamar `SessionStore.openFolder(_:)` do F11 como reserva. Por isso F11 vem antes de F09, ou o F09 chama o F11 depois.
- **F42** (agrupar por branch) depende do campo `branch` do F20.

### Verificações feitas ao escrever esta spec (fecham itens "não confirmados" da pesquisa)
Testei localmente, com `swiftc -swift-version 6` e git 2.54, o parser exatamente como está abaixo:
- `gitdir:` relativo é resolvido a partir da pasta que contém o arquivo `.git`. Prova: `git worktree add --relative-paths ../wt` gravou `gitdir: ../main/.git/worktrees/wt`, e o parser devolveu a branch certa a partir de `wt/sub`. **Confirmado.**
- HEAD solto contém o SHA em hex puro (`79fc2088…`, 40 caracteres) e virou `@79fc208`. **Confirmado.**
- `git init --ref-format=reftable` grava `ref: refs/heads/.invalid`, e o parser devolve `nil`. **Confirmado.**
- Um FIFO no lugar de `HEAD` devolve `nil` sem travar, graças à checagem `isRegularFile`. **Confirmado.**
- `NSWorkspace.shared.isFilePackage(atPath:)` devolve `true` para `Foo.app` com `Contents/Info.plist`, **e também para um `Vazio.app` vazio**, e `false` para uma pasta comum. **Confirmado.**
- O código do parser compila em modo Swift 6 sem aviso de concorrência.

Continuam sem confirmação, com a proteção indicada em "Riscos": o prompt de TCC no app ao checar a pasta (F11), a atribuição do TCC ao terminal na leitura feita pelo hook (F20), o Finder vir para a frente e `open` num `.app` lançar o app. Este último fica irrelevante, porque o `.app` é barrado antes.

---

## F11 — Abrir pasta do projeto

### Objetivo
No submenu de cada sessão, o item **Abrir pasta do projeto** abre o `cwd` no gerenciador de arquivos padrão (o Finder). Se não der para abrir, aparece um alerta dizendo o motivo provável, sem falhar em silêncio.

### Decisão técnica e por quê
- **`NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))`**. A API é nativa, devolve `Bool`, a doc da Apple a declara segura em qualquer thread e ela respeita o app de pastas que o usuário escolheu. A chamada nasce no `Button` do menu, que já está na main, então não há `Task` nem hop.
- **Validar antes: caminho absoluto, diretório existente e não pacote.** Um `.app` também é diretório, e `open` nele executaria o app. O `false` devolvido por `open` cobre a pasta que some entre a checagem e a abertura (TOCTOU).
- **Erro vai para o `report(title:message:)` que já existe** em `SessionStore`. Nada de UI nova.
- **O predicado vira `static func isOpenableFolder`** só para ter um teste. É a única parte com ramificação.
- Descartadas:
  - `Process("/usr/bin/open")`: fere o guard rail de não usar shell nem processo.
  - `activateFileViewerSelecting([url])`: mostra a pasta selecionada dentro do pai, não o conteúdo dela. É menos útil e serve de plano B (ver Riscos).
  - `open(_:configuration:completionHandler:)`: é assíncrona e não traz ganho enquanto o `open` simples trouxer o Finder para a frente.

### Arquivos e código

**`Sources/ClaudeBar/SessionStore.swift`**: um método e um predicado, logo depois de `terminate(_:)`.
```swift
    /// Abre a pasta do projeto no gerenciador de arquivos padrão (o Finder).
    /// Também serve de reserva para o "ir para a sessão" (F09).
    func openFolder(_ row: SessionRow) {
        guard Self.isOpenableFolder(row.cwd),
              NSWorkspace.shared.open(URL(fileURLWithPath: row.cwd, isDirectory: true))
        else {
            report(
                title: "Não foi possível abrir a pasta",
                message: "\(row.cwd)\n\nA pasta não existe mais ou o macOS negou o acesso."
            )
            return
        }
    }

    /// Só pasta de verdade: um `.app` também é diretório, e abri-lo executaria o
    /// app em vez de mostrar o conteúdo.
    static func isOpenableFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: path)
    }
```
`isOpenableFolder` herda o `@MainActor` da classe. O teste roda na main (ver abaixo), e assim não precisa de `nonisolated`.

**`Sources/ClaudeBar/MenuContent.swift`**: o item fica logo abaixo do caminho, que é o que ele abre.
```swift
                Menu(label(for: row)) {
                    Text(row.cwd)

                    Button("Abrir pasta do projeto") {
                        store.openFolder(row)
                    }

                    Divider()

                    Button("Marcar como visto") {
```

### Testes — `Tests/ClaudeBarTests/OpenFolderTests.swift` (novo)
```swift
import Foundation
import Testing

@testable import ClaudeBar

@Suite("Abrir pasta do projeto")
@MainActor
struct OpenFolderTests {
    /// Abrir um `.app` executaria o app: só pasta comum pode passar.
    @Test func soAbrePastaDeVerdade() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = base.appendingPathComponent("Foo.app", isDirectory: true)
        let file = base.appendingPathComponent("arquivo.txt")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? manager.removeItem(at: base) }

        #expect(SessionStore.isOpenableFolder(base.path))
        #expect(!SessionStore.isOpenableFolder(app.path))
        #expect(!SessionStore.isOpenableFolder(file.path))
        #expect(!SessionStore.isOpenableFolder(base.appendingPathComponent("sumiu").path))
        #expect(!SessionStore.isOpenableFolder("relativo/pasta"))
    }
}
```
`Foo.app` vazio basta, porque `isFilePackage` o reconhece pela extensão (confirmado acima). O `open` em si não é testado, já que abriria uma janela do Finder em CI.

### Scripts / README (`README.md` e `README.pt-BR.md`)
- Seção **The menu**: na lista do submenu, acrescentar "**Open project folder**: opens the `cwd` in Finder (only real folders; an `.app` is never launched)". Fazer o equivalente no pt-BR.
- Scripts: nada muda.

### Verificação manual
1. `swift test` passa.
2. `./scripts/install.sh`, abrir uma sessão em um projeto e clicar em **Abrir pasta do projeto**. O Finder deve abrir **o conteúdo** da pasta e vir para a frente.
3. Com uma sessão em `~/Documents/...`, rodar antes `tccutil reset SystemPolicyDocumentsFolder com.joaomarcos.claudebar` e repetir o clique. Anotar se aparece prompt de "Arquivos e Pastas" (ver Riscos).
4. Simular uma pasta que sumiu com `echo '{"session_id":"t","cwd":"/tmp/nao-existe"}' | ~/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook idle --pid $$`, depois abrir o menu e clicar. Deve aparecer o alerta com o caminho. Para limpar: `… claudebar-hook end`.
5. Simular um pacote com `cwd` igual a `/System/Applications/Calculator.app`. Deve aparecer o alerta, e a Calculadora **não** pode abrir.

### Riscos e mitigação
- **Prompt de TCC ao checar pasta em `~/Documents`/`~/Desktop` (não confirmado).** O `fileExists` roda no app. Se o passo 3 mostrar um prompt, ele aparece só depois de um clique explícito do usuário naquela pasta, o que é aceitável. Se o usuário negar, `fileExists` devolve `false` e o alerta diz "o macOS negou o acesso". **Não** adicionar `NSDocumentsFolderUsageDescription` por antecipação. Se o prompt incomodar na prática, o plano B é trocar a validação e o `open` por `NSWorkspace.shared.activateFileViewerSelecting([url])`, que é o Finder fazendo o acesso, e registrar no PR.
- **Finder não vem para a frente (não confirmado)** quando o app é `LSUIElement`. Se o passo 2 falhar, trocar por `open(url, configuration: .init())`. `activates` é `true` por padrão e a assinatura é a confirmada na pesquisa. Não ativar o próprio ClaudeBar.
- **App de pastas trocado** (Path Finder etc.): o `open` respeita a escolha do usuário. É o comportamento desejado.

### Critérios de aceite
- O submenu de toda sessão, incluindo subagente, tem **Abrir pasta do projeto** logo abaixo do caminho.
- Clicar numa pasta existente abre o conteúdo dela no app de pastas padrão.
- Caminho inexistente, relativo, arquivo ou pacote `.app`: nenhum app é lançado e aparece o alerta "Não foi possível abrir a pasta" com o caminho.
- Nenhum `Process`/`Shell` novo. `rg 'usr/bin/open' Sources` volta vazio.
- `swift test` verde com o `OpenFolderTests` novo.

### O que NÃO fazer
- Não chamar `/usr/bin/open` nem `Shell`.
- Não pôr `Task`/`DispatchQueue` em volta do `open`, porque já estamos na main.
- Não adicionar chave `NS*UsageDescription` no `build-app.sh`.
- Não criar preferência de "abrir com…" nem item "Abrir no terminal/editor". Isso é YAGNI e fica para quando alguém pedir.

---

## F20 — Nome da sessão e branch

### Objetivo
Cada linha do menu mostra **nome · branch** (`ClaudeBar · feat/x — processando (há 10 s)`), para distinguir sessões do mesmo projeto em worktrees ou branches diferentes. O **nome já está pronto**: `SessionRow.name` vem do `name` de `claude agents --json`, com a pasta como reserva, e já aparece no label (`SessionRow.swift:47`, `MenuContent.swift:80`). O que falta é a branch.

### Decisão técnica e por quê
- **Branch lida pelo hook, não pelo app.** O `claudebar-hook` já roda a cada `UserPromptSubmit`, `Stop` e `Notification`, já recebe o `cwd` e roda como filho do Claude Code, dentro do terminal que já tem acesso à pasta do projeto. O app só exibe o que veio no arquivo. Assim, nenhuma leitura dentro do projeto parte do app, nenhum I/O novo acontece na main e o pedido de "Arquivos e Pastas" do macOS não aparece para o ClaudeBar em projetos de `~/Documents`.
- **Parser `GitHead` puro no ClaudeBarCore, com cerca de 40 linhas.** Ele sobe de `cwd` até `/` procurando `.git`. Com `.git` pasta, lê `HEAD`. Com `.git` arquivo (worktree ou submódulo), segue o `gitdir:`, absoluto ou relativo à pasta do `.git`. Retornos: `ref: refs/heads/x` → `x`. SHA → `@sha7`. Stub do reftable (`.invalid`) → `nil`. Qualquer outra coisa → `nil`.
- **Só lê arquivo comum** (`isRegularFileKey`). Um FIFO chamado `HEAD` travaria o hook, e com ele a sessão. É uma linha a mais e cumpre o guard rail de que o hook nunca quebra a sessão.
- **Limite de 80 caracteres e só a primeira linha.** O valor vai para texto de menu, e o padrão é o mesmo do `message` (200).
- **`branch: String?` opcional no `SessionStatus`.** O `Codable` sintetizado usa `decodeIfPresent`, então arquivos antigos sem o campo continuam válidos. App antigo lendo arquivo novo ignora a chave extra. Hook e app saem no mesmo bundle.
- **Atualiza a cada turno.** Uma troca de branch no meio da sessão aparece no próximo `Stop`/`UserPromptSubmit`. Sessão que só o CLI conhece fica sem branch até o primeiro prompt, o que é aceitável.
- Descartadas:
  - Ler `.git/HEAD` no app: traria o prompt de TCC em `~/Documents` (instável com assinatura ad-hoc) e I/O na main a cada `merge()`.
  - Rodar `git branch --show-current`: fere a regra do F20 de não rodar `git` e adiciona um processo por hook.
  - Statusline (`worktree.branch`): não há campo geral de branch, e usar isso exige tomar a statusline do usuário.
  - libgit2/SwiftGit2: dependência nova para ler uma linha.
  - `SessionStatus.projectName`/pasta no label quando o nome é um título gerado: fora do escopo. O submenu já mostra o `cwd`.

### Arquivos e código

**`Sources/ClaudeBarCore/GitHead.swift`** (novo). Este é o código validado acima.
```swift
import Foundation

/// Branch do repositório git que contém uma pasta, lida direto do arquivo `HEAD`.
///
/// Sem rodar `git`: é só um arquivo de texto. Quem chama é o hook, que roda
/// dentro do terminal do Claude Code. O app nunca lê nada dentro do projeto,
/// para não disparar o pedido de acesso a Documentos/Mesa (TCC) do macOS.
public enum GitHead {
    /// `"main"`, `"@1a2b3c4"` com HEAD solto, ou `nil` quando a pasta não está
    /// num repositório ou o HEAD não diz a branch (repositório reftable).
    public static func branch(at cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        // O `cwd` pode ser subpasta do repositório: sobe até achar o `.git`.
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            if let head = headURL(dotGit: dotGit) {
                return readRegularFile(head).flatMap(parse)
            }
            if dir.path == "/" { return nil }
            dir.deleteLastPathComponent()
        }
    }

    /// `HEAD` dentro de `.git`, ou no destino do `gitdir:` quando `.git` é um
    /// arquivo (worktree linkado ou submódulo). O HEAD de um worktree é dele.
    static func headURL(dotGit: URL) -> URL? {
        if (try? dotGit.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return dotGit.appendingPathComponent("HEAD")
        }
        guard let text = readRegularFile(dotGit),
              let line = firstLine(text), line.hasPrefix("gitdir:")
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        // `gitdir:` relativo (`git worktree add --relative-paths`) parte da pasta do `.git`.
        return URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent())
            .appendingPathComponent("HEAD")
    }

    static func parse(_ text: String) -> String? {
        guard let head = firstLine(text) else { return nil }
        if head.hasPrefix("ref: ") {
            var ref = head.dropFirst("ref: ".count)
            if ref.hasPrefix("refs/heads/") { ref = ref.dropFirst("refs/heads/".count) }
            // Reftable (Git 2.45+): HEAD é um stub fixo e a branch real fica em
            // binário. Sem rodar git, o honesto é não mostrar branch.
            guard !ref.isEmpty, ref != ".invalid" else { return nil }
            // Vai para texto de menu: limitamos o tamanho, como a `message`.
            return String(ref.prefix(80))
        }
        // HEAD solto: o arquivo traz o SHA do commit (SHA-1 ou SHA-256).
        let isSHA = (head.count == 40 || head.count == 64) && head.allSatisfy(\.isHexDigit)
        return isSHA ? "@\(head.prefix(7))" : nil
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Só arquivo comum: um FIFO chamado `HEAD` travaria o hook, e com ele a sessão.
    private static func readRegularFile(_ url: URL) -> String? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```
Limites conhecidos, a documentar no código só se alguém reportar: `GIT_DIR` no ambiente, `core.worktree`, repositório bare, HEAD como symlink legado (vira `nil`) e não parar em fronteira de filesystem.

**`Sources/ClaudeBarCore/SessionStatus.swift`**: um campo opcional e um parâmetro com default. Os chamadores atuais não mudam.
```swift
    public let message: String?
    /// Branch do repositório do `cwd` (`@sha7` com HEAD solto), lida pelo hook.
    /// Opcional: arquivos gravados antes deste campo continuam válidos.
    public let branch: String?
```
```swift
    public init(
        sessionId: String,
        state: SessionState,
        cwd: String,
        pid: Int32,
        updatedAt: Date = Date(),
        message: String? = nil,
        branch: String? = nil
    ) {
        …
        self.message = message
        self.branch = branch
    }
```

**`Sources/claudebar-hook/main.swift`**: calcular o `cwd` uma vez e passar a branch.
```swift
    let cwd = payload?.cwd ?? FileManager.default.currentDirectoryPath
    let status = SessionStatus(
        sessionId: sessionId,
        state: state,
        cwd: cwd,
        pid: parsePID(arguments),
        // A mensagem vem de fora e vai para uma notificação: limitamos o tamanho.
        message: payload?.message.map { String($0.prefix(200)) },
        // Lida aqui, e não no app: o hook roda no terminal, que já tem acesso à
        // pasta do projeto. Qualquer falha vira `nil`, nunca erro.
        branch: GitHead.branch(at: cwd)
    )
```

**`Sources/ClaudeBar/SessionRow.swift`**: um campo e um parâmetro com default no fim.
```swift
    /// Id curto do agente background, aceito por `claude stop`.
    let backgroundId: String?
    /// Branch gravada pelo hook. `nil` até o primeiro hook ou fora de repositório git.
    let branch: String?
```
```swift
        pid: Int32? = nil,
        backgroundId: String? = nil,
        branch: String? = nil
    ) {
        …
        self.backgroundId = backgroundId
        self.branch = branch
```

**`Sources/ClaudeBar/SessionMerge.swift`**: repassar o campo nos dois `SessionRow(...)`.
```swift
                pid: agent.pid ?? hook?.pid,
                backgroundId: agent.isSubagent ? agent.id : nil,
                branch: hook?.branch
```
```swift
                    pid: status.pid,
                    branch: status.branch
```

**`Sources/ClaudeBar/MenuContent.swift`**: `label(for:)`.
```swift
        text += row.name
        // A branch distingue duas sessões do mesmo projeto em worktrees diferentes.
        if let branch = row.branch {
            text += " · \(branch)"
        }
        text += " — \(description(for: row.state))"
```
Esse trecho substitui a linha `text += "\(row.name) — \(description(for: row.state))"`.

### Testes

**`Tests/ClaudeBarTests/GitHeadTests.swift`** (novo):
```swift
import ClaudeBarCore
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
```
`parse` é `internal`, por isso o `@testable import ClaudeBarCore`. O alvo de teste já depende de ClaudeBarCore. O `import ClaudeBarCore` simples ao lado é redundante e pode sair.

**`Tests/ClaudeBarTests/SessionMergeTests.swift`**: um teste que garante que o merge não perde o campo.
```swift
    @Test func branchDoHookChegaNaLinha() throws {
        let comBranch = SessionStatus(
            sessionId: "aaaaaaaa-0000-0000-0000-000000000000",
            state: .idle, cwd: "/Users/dev/my-app", pid: 1, branch: "feat/x"
        )
        let rows = SessionMerge.rows(agents: try decodeAgents(), statuses: [comBranch])
        #expect(rows.first { $0.sessionId == comBranch.sessionId }?.branch == "feat/x")
        #expect(SessionMerge.rows(agents: [], statuses: [comBranch]).first?.branch == "feat/x")
    }
```

### Scripts / README (`README.md` e `README.pt-BR.md`)
- `scripts/`: nada muda. Os hooks são os mesmos e o binário é substituído no lugar, então sessões já abertas passam a gravar a branch depois do reinstall.
- **The menu**: no exemplo, mostrar uma linha com branch (`⏳  ClaudeBar · feat/x — processando (há 10 s)`).
- **How it works**: no JSON de exemplo do arquivo de estado, acrescentar `"branch" : "main",` e uma frase dizendo que o hook lê a branch de `.git/HEAD` (seguindo `gitdir:` de worktree), mostra `@sha7` com HEAD solto e não mostra nada em repositório reftable.
- **Project structure**: acrescentar `GitHead.swift   branch read from .git/HEAD (by the hook, never runs git)`.
- **Security**: no primeiro bullet, acrescentar a branch à lista do que é lido. Novo bullet: "The only file read inside your project is `.git/HEAD` (or the `.git` gitfile of a worktree), by the hook, never by the app, and `git` is never run."
- **`planning/03-validacao/BACKLOG.md`**, linha F20: corrigir "já decodificado, não exibido" para "nome já exibido; falta a branch" e o risco para "ler no app traria prompt TCC em ~/Documents; lido no hook".

### Verificação manual
1. `swift test` passa.
2. `./scripts/install.sh`. Numa sessão em repositório na `main`, mandar um prompt. O menu deve mostrar `nome · main`.
3. `git worktree add ../x-wt -b feat/x` e abrir uma sessão em `../x-wt`. Depois do primeiro prompt, aparece `· feat/x`, e a sessão original continua `· main`.
4. `git checkout --detach` numa sessão e mandar um prompt. Aparece `· @abc1234`.
5. Sessão numa pasta fora de git (`/tmp`): sem `·`.
6. **TCC**: com um projeto em `~/Documents`, rodar `tccutil reset SystemPolicyDocumentsFolder com.joaomarcos.claudebar`, reiniciar o app, abrir sessão e mandar um prompt. **Nenhum** prompt de "Arquivos e Pastas" pode aparecer para o ClaudeBar, e a branch tem de aparecer.
7. `cat ~/.claude/claudebar/*.json` mostra `"branch"` e mantém o `0600`.

### Riscos e mitigação
- **TCC atribuir a leitura do hook ao ClaudeBar em vez do terminal (não confirmado).** O hook mora dentro de `ClaudeBar.app/Contents/MacOS/`, mas é lançado por `posix_spawn` pelo Claude Code, e o "processo responsável" deveria ser o terminal ou o Claude.app, que já leem o projeto. O passo 6 decide. Se aparecer prompt, **não** adicionar chave de uso. Pare e registre no PR: a alternativa é mover a leitura para trás de um opt-in (fora do escopo). Fail-open está garantido de qualquer jeito: acesso negado → `readRegularFile` devolve `nil` → sem branch, e o hook segue.
- **Leitura bloqueante travar o hook.** FIFO coberto pela checagem de arquivo comum. Volume de rede lento afeta o próprio Claude Code do mesmo jeito. O Claude Code mata hooks pelo timeout padrão. Não adicionar `timeout` no `install.sh` agora.
- **Branch atrasada em um turno** depois de `git checkout` fora do Claude. Isso é aceito e fica documentado no README.
- **Conflito de formato com F07.1**: os dois são aditivos (um caso no enum e um campo opcional). Resolver o merge à mão, sem reescrever.

### Critérios de aceite
- O label mostra `nome · branch` quando o hook gravou branch e mostra só `nome` quando não gravou. O resto do label não muda.
- Worktree linkado com `gitdir:` absoluto ou relativo mostra a branch do worktree, não a do repositório principal.
- HEAD solto mostra `@` mais 7 caracteres hex. Reftable, pasta fora de git e `cwd` relativo não mostram nada.
- Arquivo de estado sem `branch` (formato antigo) continua decodificando: o teste `sessaoConhecidaSoPelosHooksNaoEhPerdida` segue verde sem mudança.
- Nenhum `Process`/`git` novo (`rg '"git"' Sources` vazio) e nenhuma leitura no `cwd` a partir do alvo `ClaudeBar` (`rg GitHead Sources/ClaudeBar` vazio).
- O hook nunca sai com erro por causa da branch: `GitHead` não lança e só devolve `String?`.
- `swift test` verde com `GitHeadTests` e o teste novo do merge.

### O que NÃO fazer
- Não ler `.git/HEAD` no app, nem como reserva para sessão sem hook.
- Não rodar `git`, nem via `Shell`, nem via `zsh -lc`.
- Não ler `refs/`, `packed-refs`, `commondir` ou `reftable/`, porque só o nome interessa.
- Não mexer no nome da sessão: ele já vem do CLI. Não configurar a statusline do usuário.
- Não adicionar `NSDocumentsFolderUsageDescription` nem outra chave de uso no `build-app.sh`.
- Não criar toggle "mostrar branch" (YAGNI).
