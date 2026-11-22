# G08 — Abrir pasta do projeto (F11) + nome da sessão e branch (F20)

Pesquisa de "como fazer". Não é o plano final. Legenda:
**[CONFIRMADO]** = lido em fonte oficial (Apple, git-scm, code.claude.com) ou no código/saída local nesta pesquisa.
**[SUPOSIÇÃO]** = conhecimento geral ou fonte secundária; precisa de teste antes de virar regra.

---

## 0. Ponto de partida no código (lido em 2026-11-15)

- `SessionRow.name` já existe e **já é exibido**: `SessionRow.init` faz `name ?? pastaDoCwd` e `MenuContent.label(for:)` monta `"\(row.name) — …"`. **[CONFIRMADO]** (`Sources/ClaudeBar/SessionRow.swift:46-47`, `MenuContent.swift:80`). O BACKLOG diz "já decodificado, não exibido": está desatualizado. O que falta de fato no F20 é a **branch** e, talvez, mostrar a pasta quando o nome não é a pasta.
- `claude agents --json` local traz `name` com o título gerado ("ClaudeBar evolução e brainstorm") e **não traz branch** nem campo de git. **[CONFIRMADO]** (saída local; campos vistos: `pid, cwd, kind, id, sessionId, name, status/state, startedAt`).
- O submenu da sessão mostra `Text(row.cwd)` e não tem ação de abrir pasta. **[CONFIRMADO]** (`MenuContent.swift:23`).
- `SessionStore` é `@MainActor @Observable`; `merge()` roda na main a cada evento do `DirectoryWatcher` e a cada poll de 5 s. `SessionMerge` se declara "funções puras: nada de disco". **[CONFIRMADO]**
- O hook (`claudebar-hook`) roda nos eventos `UserPromptSubmit`→working, `Stop`→idle, `Notification`→waiting e grava `SessionStatus` (`sessionId, state, cwd, pid, updatedAt, message`). **[CONFIRMADO]** (`scripts/install.sh:28-30`, `Sources/claudebar-hook/main.swift`).
- Info.plist gerado por `scripts/build-app.sh` não tem nenhuma chave `NS*UsageDescription`; assinatura `codesign --sign -` (ad-hoc). **[CONFIRMADO]**

---

## 1. F11 — Abrir pasta do projeto

### APIs (Apple)

| API | O que diz a doc | Fonte |
|---|---|---|
| `NSWorkspace.shared.open(_ url: URL) -> Bool` | "Opens the location at the specified URL." Retorna `true` se abriu. "You can call this method safely from any thread in macOS 10.6 and later." | [CONFIRMADO] https://developer.apple.com/documentation/appkit/nsworkspace/open(_:) |
| `open(_:configuration:completionHandler:)` + `NSWorkspace.OpenConfiguration.activates` | Versão assíncrona; `activates`: "whether the system activates the app and brings it to the foreground". | [CONFIRMADO] https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration |
| `activateFileViewerSelecting(_ fileURLs: [URL])` | "Activates the Finder, and opens one or more windows selecting the specified files." Seguro em qualquer thread. Mostra a pasta **selecionada no pai**, não o conteúdo dela. | [CONFIRMADO] https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:) |
| `FileManager.fileExists(atPath:isDirectory:)` | `isDirectory` = true se é diretório "or if the final path element is a symbolic link that points to a directory". Nota da Apple: prever comportamento pelo estado do FS "can cause odd behavior or race conditions… far better to attempt an operation… check for errors". Sugere `NSWorkspace.isFilePackage(atPath:)` para saber se é pacote. | [CONFIRMADO] https://developer.apple.com/documentation/foundation/filemanager/fileexists(atpath:isdirectory:) |

### Armadilhas

1. **Pacote (.app, .bundle) é diretório.** `open` num `.app` *lança o app* em vez de mostrar a pasta. Validar `isDirectory && !isFilePackage`. **[CONFIRMADO]** que `isFilePackage` existe e é a recomendação; **[SUPOSIÇÃO]** que `open` lança o pacote (comportamento padrão do LaunchServices, não li isso na página).
2. **TOCTOU**: a pasta pode sumir entre validar e abrir. Como `open` devolve `Bool`, tratar o `false` (mostrar alerta/linha "pasta não existe mais") cobre isso. **[CONFIRMADO]** (nota da Apple acima).
3. **Swift 6 / MainActor**: a ação nasce no `Button` do `MenuContent` (já MainActor); `open` é documentado como thread-safe, então não há hop nem `Task`. **[CONFIRMADO]** para thread-safety; **[SUPOSIÇÃO]** que o SDK atual não marca `open(_:)` como `@MainActor` (a página não mostra anotação; o compilador decide — se reclamar, já estamos na main).
4. **LSUIElement**: abrir pasta ativa o Finder (o app padrão de pasta); o ClaudeBar não precisa se ativar. **[SUPOSIÇÃO]** que o Finder vem para frente com `open(_:)` simples; se não vier, usar `open(_:configuration:)` com `activates = true` (propriedade confirmada).
5. **Handler de pasta trocado** (Path Finder, ForkLift): `open` respeita o app padrão; `activateFileViewerSelecting` sempre usa o Finder. **[SUPOSIÇÃO]**
6. **TCC**: `stat` de um caminho dentro de `~/Documents`/`~/Desktop` pode ou não disparar o prompt de "Arquivos e Pastas" (ver §3). Abrir via `NSWorkspace` delega ao Finder. **[SUPOSIÇÃO]** — testar com `tccutil reset SystemPolicyDocumentsFolder <bundleID>`.
7. Guard rail "nada via shell": não usar `Process("/usr/bin/open", …)`. `NSWorkspace` resolve sem processo. **[CONFIRMADO]** (00-PLANO.md).

### Alternativas

- (A) `open(URL(fileURLWithPath: cwd, isDirectory: true))` com validação `isDirectory && !isFilePackage`. Mostra o conteúdo da pasta. **Recomendado.**
- (B) `activateFileViewerSelecting([url])`: nunca lança app, mas abre o pai com a pasta selecionada (menos útil). Bom fallback se (A) devolver `false`? Não: se (A) falhou porque a pasta sumiu, (B) também não ajuda. Fica só como opção se o painel preferir "revelar".
- (C) `Process` + `/usr/bin/open`: descartado (guard rail).

### Esboço

```swift
// MenuContent, dentro do submenu da sessão
Button("Abrir pasta do projeto") { store.openFolder(row) }

// SessionStore (@MainActor)
func openFolder(_ row: SessionRow) {
    var isDir: ObjCBool = false
    let ws = NSWorkspace.shared
    guard row.cwd.hasPrefix("/"),
          FileManager.default.fileExists(atPath: row.cwd, isDirectory: &isDir), isDir.boolValue,
          !ws.isFilePackage(atPath: row.cwd),
          ws.open(URL(fileURLWithPath: row.cwd, isDirectory: true))
    else { return report(title: "Não foi possível abrir a pasta", message: row.cwd) }
}
```
`report(title:message:)` já existe em `SessionStore`. Reaproveitar; nada novo. F09 pode chamar `openFolder` como fallback.

Teste: a validação é 3 linhas de stdlib; o que vale testar é extrair o predicado `isOpenableFolder(path)` e checar dir temporário (true), arquivo (false), `Foo.app/` criado em tmp (false — **[SUPOSIÇÃO]** que `isFilePackage` reconhece pela extensão `.app` mesmo sem Info.plist).

---

## 2. F20 — Nome da sessão

### O que existe

- `claude agents --json` → `name`. Doc oficial: sessões sem nome recebem um "default display name" (pasta + sufixo de 2 chars, ex. `my-app-3f`) que "identifies the session in listings of running sessions, such as agent view and `claude agents --json` output". Há também o título gerado por modelo pequeno e o nome de `/rename` / `claude -n`. **[CONFIRMADO]** https://code.claude.com/docs/en/sessions.md (seção "Name your sessions").
- Hooks **não** recebem nome de sessão nem branch. Campos comuns: `session_id, prompt_id, transcript_path, cwd, scratchpad_dir, permission_mode, effort, hook_event_name` (+ `agent_id`, `agent_type` em subagente). **[CONFIRMADO]** https://code.claude.com/docs/en/hooks.md ("Common input fields").
- Statusline recebe `session_name` (só quando há nome custom ou título gerado; o `my-app-3f` não popula), `workspace.current_dir`, `workspace.project_dir`, `workspace.git_worktree` (nome do worktree linkado), `worktree.branch` (só em "worktree session" do Claude). **Nenhum campo de branch geral**; os exemplos oficiais rodam `git branch --show-current`. **[CONFIRMADO]** https://code.claude.com/docs/en/statusline.md ("Available data").

### Conclusão

O nome já chega pelo `claude agents --json` e já é exibido. Usar statusline para o nome seria pior: exige o usuário configurar statusline (só um comando por vez, conflitaria com o dele) e é rede de dados que o app não precisa. **Não fazer nada novo para o nome**, exceto, se o painel quiser, mostrar a pasta (`URL(fileURLWithPath: cwd).lastPathComponent`) na linha de detalhe do submenu quando `name != pasta`, porque títulos gerados ("ClaudeBar evolução e brainstorm") escondem o projeto.

Armadilha: sessão vista só pelo hook (CLI indisponível) cai no fallback "nome da pasta" — já tratado em `SessionRow.init`. **[CONFIRMADO]**

---

## 3. F20 — Branch lendo `.git/HEAD` sem rodar git

### Formato (oficial, git-scm)

- `HEAD` é symref: arquivo com `ref: refs/heads/<branch>`. "your `.git/HEAD` is a regular file whose content is `ref: refs/heads/master`". **[CONFIRMADO]** https://git-scm.com/docs/git-symbolic-ref
- Detached HEAD: "HEAD can also record a specific commit directly". **[CONFIRMADO]** https://git-scm.com/docs/gitrepository-layout . Que o conteúdo é o SHA hex puro (40 chars SHA-1 / 64 SHA-256) é **[SUPOSIÇÃO]** bem estabelecida (as páginas não mostram o literal).
- Legado: HEAD como **symlink** para `refs/heads/x` — "deprecated". **[CONFIRMADO]** (git-symbolic-ref). Ler via `String(contentsOf:)` segue o symlink e devolveria o SHA da branch, não o nome; tratar como detached é aceitável.
- Gitfile: "a plain text file `.git` at the root of your working tree, containing `gitdir: <path>`… usually managed via `git submodule` and `git worktree`". **[CONFIRMADO]** https://git-scm.com/docs/gitrepository-layout
- Worktree linkado: `$GIT_DIR` = `main/.git/worktrees/<id>`, e o HEAD do worktree é `…/worktrees/<id>/HEAD` (HEAD é por worktree; refs são compartilhadas). **[CONFIRMADO]** https://git-scm.com/docs/git-worktree (DETAILS). Ou seja: seguir o `gitdir:` e ler `HEAD` **lá** já dá a branch certa; não precisa de `commondir` (só seria preciso para resolver o SHA da branch, que não queremos).
- `gitdir:` pode ser **relativo**: `git worktree add --relative-paths` / `worktree.useRelativePaths=true`. **[CONFIRMADO]** (git-worktree, OPTIONS/CONFIGURATION). Que o relativo é resolvido a partir da pasta que contém o arquivo `.git` é **[SUPOSIÇÃO]** (comportamento do git; não achei a frase na doc).
- **Reftable**: em repositório com backend reftable (Git 2.45+), `HEAD` é um stub com conteúdo `ref: refs/heads/.invalid`; a branch real fica em `.git/reftable/` (binário). **[CONFIRMADO]** https://about.gitlab.com/blog/a-beginners-guide-to-the-git-reftable-format/ (fonte GitLab, que fez o upstream; não é git-scm). O próprio `git-prompt.sh` do git só lê `HEAD` direto quando `ref_format` é `files`; senão cai em `git symbolic-ref`. **[CONFIRMADO]** https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh (trecho `case "$ref_format" in files) … "ref: "*) head="${head#ref: }"`). Sem rodar git, a regra honesta é: `.invalid` → não mostrar branch.
- `cwd` pode ser **subpasta** do repo: o git sobe a árvore procurando `.git`. Precisamos subir também (parar em `/`). **[SUPOSIÇÃO]** sobre o limite exato (o git também para em fronteira de filesystem, `GIT_DISCOVERY_ACROSS_FILESYSTEM`; ignorar isso é aceitável aqui).
- `.git` dentro de submódulo também é gitfile (`gitdir: ../.git/modules/x`) — mesmo código cobre. **[CONFIRMADO]** (gitrepository-layout cita submodule).

### Open source que faz igual

- `git/contrib/completion/git-prompt.sh` (oficial do git): lê `$g/HEAD`, aceita prefixo `ref: `, senão marca `detached=yes`; trata symlink com `git symbolic-ref`. Link acima. **[CONFIRMADO]**
- Exemplos da doc oficial de statusline do Claude Code: rodam `git branch --show-current` (o que **não** queremos). **[CONFIRMADO]**
- Não achei app Swift/macOS de barra de menu que faça o parse em Swift. Código próprio, ~25 linhas.

### A armadilha grande: TCC (Arquivos e Pastas)

Doc Apple de `NSDocumentsFolderUsageDescription`: "The first time your app tries to access a file in the user's Documents folder without implied user consent, the system prompts the user for permission…" e o reset é `tccutil reset SystemPolicyDocumentsFolder <bundleID>`. **[CONFIRMADO]** https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription . Vale igual para Desktop/Downloads (chaves irmãs) **[SUPOSIÇÃO: não abri as páginas irmãs]**.

Consequências para o ClaudeBar:
- Hoje o app **não lê nada** dentro do `cwd`. Ler `.git/HEAD` de projetos em `~/Documents/...` (caso real: `~/Documents/code/esport project`, `~/Documents/pessoal`) passa a disparar o prompt de privacidade **no app da barra**, sem `NS*UsageDescription` no Info.plist.
- Com assinatura ad-hoc, a concessão tende a ser esquecida a cada build (o BACKLOG já registra isso para Automação no F30). **[SUPOSIÇÃO]** para a pasta Documentos especificamente; fontes só secundárias (ex.: https://docs.openclaw.ai/platforms/mac/permissions.md diz que build ad-hoc ganha identidade nova e o macOS esquece concessões).
- Isso contradiz o risco "baixo, sem permissão" do BACKLOG para F20.

**Saída sem TCC: ler a branch no hook, não no app.** O `claudebar-hook` roda como filho do Claude Code dentro do terminal, que já tem acesso à pasta do projeto (o TCC atribui o acesso ao "processo responsável", o terminal). **[SUPOSIÇÃO]** sobre a atribuição — é o comportamento conhecido do TCC, mas não achei página Apple que diga isso; testar: projeto em `~/Documents`, `tccutil reset SystemPolicyDocumentsFolder <bundleID do ClaudeBar>`, abrir sessão, ver se algum prompt aparece.
- O hook já recebe `cwd` e já roda a cada `UserPromptSubmit` e `Stop` → a branch é atualizada a cada turno, o que cobre trocas de branch no meio da sessão com atraso de um turno.
- `SessionStatus` ganha `branch: String?` opcional (decode tolerante; arquivos antigos sem o campo continuam válidos). O app só exibe. Zero I/O novo na main, zero mudança em `SessionMerge` além de repassar o campo.
- Limite: sessão que o hook ainda não viu (só `claude agents`) fica sem branch até o primeiro prompt. Aceitável; não ler no app como fallback (traria o TCC de volta).

### Alternativas

| Opção | Prós | Contras | Veredito |
|---|---|---|---|
| (A) Parse de `.git/HEAD` **no hook**, campo `branch` no `SessionStatus` | Sem TCC no app, sem processo, sem I/O na main, atualiza por turno | Atraso de um turno; mexe no formato do arquivo (aditivo) | **Recomendado** |
| (B) Parse de `.git/HEAD` no app (em `merge()` ou ao abrir o menu) | Sempre fresco | Prompt TCC em `~/Documents`/`~/Desktop`, instável com ad-hoc; I/O na main a cada evento; volume de rede pode travar | Não |
| (C) Rodar `git symbolic-ref --short HEAD` / `git branch --show-current` | Cobre reftable e symlink | Viola "sem rodar git" (F20) e adiciona processo; no app, ainda tem TCC | Não |
| (D) Statusline do Claude Code (`worktree.branch`, `workspace.git_worktree`) | Oficial | Não tem branch geral; exige configurar statusline do usuário (conflito) | Não |
| (E) Biblioteca (libgit2/SwiftGit2) | Completa | Dependência nova para ler uma linha | Não |

### Esboço do parser (ClaudeBarCore, puro, testável)

```swift
public enum GitHead {
    /// Branch do repositório que contém `cwd`, "@abc1234" se detached, nil se não é repo
    /// ou se o HEAD é o stub do reftable.
    public static func branch(at cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            if let head = headFile(dotGit), let text = try? String(contentsOf: head, encoding: .utf8) {
                return parse(text)
            }
            if dir.path == "/" { return nil }
            dir.deleteLastPathComponent()
        }
    }

    static func headFile(_ dotGit: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit.appendingPathComponent("HEAD") }
        // gitfile: worktree linkado ou submódulo
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent())
        return gitDir.appendingPathComponent("HEAD")
    }

    static func parse(_ text: String) -> String? {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: ") {
            let ref = head.dropFirst(5)
            let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : String(ref)
            return name == ".invalid" ? nil : String(name.prefix(80))   // reftable stub
        }
        let hex = head.allSatisfy(\.isHexDigit) && (head.count == 40 || head.count == 64)
        return hex ? "@" + head.prefix(7) : nil
    }
}
```

Notas:
- `URL(fileURLWithPath:relativeTo:)` cobre `gitdir:` absoluto e relativo. **[SUPOSIÇÃO]** de que a base relativa correta é a pasta do arquivo `.git` (ver acima).
- `prefix(80)`: o valor vai para texto de menu; sem shell, sem caminho. Não há injeção, só limitar tamanho (mesmo padrão do `message` no hook).
- `fileExists` + `String(contentsOf:)` num FIFO chamado `HEAD` bloquearia; no hook isso trava um hook, não o app. Paranoia opcional: checar `.isRegularFileKey`. **[SUPOSIÇÃO]** que vale a pena; YAGNI até alguém reportar.
- Sendable/Swift 6: enum sem estado, funções `static` puras → nenhum problema de isolamento. **[CONFIRMADO]** pela forma do código (sem estado compartilhado).
- Repo bare / `GIT_DIR` em env / `core.worktree`: ignorados. Ceiling conhecido.

Teste único (XCTest já existe em `Tests/ClaudeBarTests`): tabela de `parse` (`"ref: refs/heads/main\n"`→`main`, `"ref: refs/heads/feat/x"`→`feat/x`, SHA 40→`@xxxxxxx`, `"ref: refs/heads/.invalid"`→nil, lixo→nil) + um repo falso em tmp com `.git` gitfile apontando para `wt/HEAD` e `cwd` numa subpasta.

### Exibição

- Label: `"\(row.name) · \(branch)"` só quando houver branch; detalhe do submenu: pasta + branch. Decisão de UI fica para o design.
- F42 (agrupar por worktree/branch) depende deste campo. **[CONFIRMADO]** (BACKLOG).

---

## 4. Recomendação

1. **F11**: `NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))` validando diretório existente e não-pacote, tratando `false` com o `report` existente. Sem `Process`.
2. **F20 nome**: já está feito (`row.name`). Corrigir o BACKLOG; opcionalmente mostrar a pasta no detalhe.
3. **F20 branch**: parser `GitHead` no ClaudeBarCore, chamado **pelo hook**; `SessionStatus.branch: String?`; app só exibe. Tolera `gitdir:` (absoluto/relativo), subpasta, detached (`@sha7`), reftable (sem branch), symlink legado (vira detached/nil).
4. Atualizar o risco do F20 no BACKLOG: ler no app traria prompt TCC em `~/Documents` com assinatura ad-hoc.

## 5. Não confirmado (testar antes de fechar)

- `open(_:)` num `.app` lança o app (motivo do `!isFilePackage`).
- `isFilePackage` reconhece `.app` vazio criado em teste.
- Finder vem para frente com `open(_:)` simples a partir de app `LSUIElement`.
- `stat`/`fileExists` em `~/Documents/...` dispara (ou não) o prompt TCC no app.
- TCC atribui a leitura do hook ao terminal (processo responsável), sem prompt para o ClaudeBar.
- Concessão de Documentos perdida a cada build ad-hoc (só fonte secundária).
- Conteúdo literal do HEAD detached = SHA hex; base de resolução do `gitdir:` relativo.
- SDK atual não anota `NSWorkspace.open(_:)` com `@MainActor` (irrelevante: chamado da main).
