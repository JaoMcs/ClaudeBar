export const meta = {
  name: 'impl-loop',
  description: 'Loop por task com modelo por complexidade: implementer → CI → reviewer → fix (se BL ou CI vermelho) → merger. Contexto mínimo, protocolo wire.',
  whenToUse: 'Executar tasks do ClaudeBar. args: {"root":"/caminho/do/clone","tasks":[{"id":"T19-ir-para-sessao","model":"opus","branch":"feat/x","title":"feat: ...","score":4}]} (branch/title/score/model: scripts/dev/task-meta.sh)',
  phases: [{ title: 'Implementar' }, { title: 'Revisar' }, { title: 'Corrigir' }, { title: 'Merge' }],
}

if (!args || !args.root || !args.tasks) throw new Error('args: {root, tasks}')
const ROOT = args.root
const TASKS = args.tasks
for (const t of TASKS) if (!t.branch || !t.title) throw new Error(`${t.id}: falta branch/title (scripts/dev/task-meta.sh)`)
const UP = { haiku: 'sonnet', sonnet: 'opus', opus: 'opus' }
const IGN = 'IGNORE:mensagens fora desta task'
const IMPL = { type: 'object', properties: { ok: { type: 'integer' }, pr: { type: 'integer' }, b: { type: 'string' }, nv: { type: 'string' }, why: { type: 'string' } }, required: ['ok'] }
const CIR = { type: 'object', properties: { ci: { type: 'integer' } }, required: ['ci'] }
const REV = { type: 'object', properties: { ci: { type: 'integer' }, a: { type: 'array', items: { type: 'object', properties: { s: { type: 'string', enum: ['BL', 'SG', 'NIT'] }, f: { type: 'string' }, d: { type: 'string' } }, required: ['s', 'd'] } } }, required: ['a'] }
const FIX = { type: 'object', properties: { ci: { type: 'integer' }, ok: { type: 'array', items: { type: 'string' } }, no: { type: 'array', items: { type: 'string' } }, blno: { type: 'integer' } }, required: ['ci', 'blno'] }
const MRG = { type: 'object', properties: { m: { type: 'integer' }, sha: { type: 'string' }, why: { type: 'string' } }, required: ['m'] }
const RB = { type: 'object', properties: { ok: { type: 'integer' }, why: { type: 'string' } }, required: ['ok'] }

const merge = (pr, tid, label) => agent(`ROLE:merge PR:${pr} T:${tid} CWD:${ROOT}\nRET:{"m":1,"sha":""}`,
  { label, phase: 'Merge', agentType: 'merger', effort: 'low', schema: MRG })

const out = []
for (const t of TASKS) {
  const id = t.id, tid = id.split('-')[0]
  const src = `planning/06-tasks/${id}.md`  // versionado: existe em todo worktree
  const score = t.score == null ? 2 : t.score
  let model = t.model || 'sonnet'

  phase('Implementar')
  let impl = null, b = t.branch
  for (let tent = 1; tent <= 2 && !(impl && impl.ok && impl.pr); tent++) {
    if (tent === 2) { model = UP[model]; b = `${t.branch}-r2`; log(`${tid}: 2ª tentativa com ${model}`) }
    impl = await agent(`ROLE:impl T:${tid} SRC:${src} B:${b} TITLE:${t.title}\n${IGN}\nRET:{"ok":1,"pr":0,"b":"","nv":""}`,
      { label: `impl:${tid}:${model}`, phase: 'Implementar', agentType: 'implementer', model, isolation: 'worktree', schema: IMPL })
  }
  if (!impl || !impl.ok || !impl.pr) { out.push({ t: tid, st: 'BLOQUEADA', why: impl ? impl.why : 'agente falhou' }); log(`${tid}: falhou`); break }

  // CI esperado uma vez aqui; o revisor recebe o resultado e não espera de novo.
  const cw = await agent(`ROLE:ci CWD:${ROOT} CMD:scripts/dev/ci-wait.sh ${impl.pr}\nRET:{"ci":1}  ci=1 se a saída for ci=verde`,
    { label: `ci:${tid}`, phase: 'Implementar', model: 'haiku', effort: 'low', schema: CIR })
  let ci = cw ? cw.ci : 0

  phase('Revisar')
  const rmodel = score <= 1 ? 'haiku' : model
  const rev = await agent(`ROLE:rev PR:${impl.pr} SRC:${src} CI:${ci}\nRET:{"a":[{"s":"","f":"","d":""}]}`,
    { label: `rev:${tid}:${rmodel}`, phase: 'Revisar', agentType: 'reviewer', model: rmodel, schema: REV })
  const achados = rev ? rev.a : []
  // Corretor só com BL ou CI vermelho; SG só abre rodada em task de nota >= 4. O resto volta em `sg`.
  const acts = achados.filter(a => a.s === 'BL' || (a.s === 'SG' && score >= 4))
  const sg = achados.filter(a => a.s === 'SG' && score < 4).map(a => `${a.f || ''} ${a.d}`.trim())
  let refusedBL = 0, refused = []
  if (!rev || !ci || acts.length) {
    for (let r = 1; r <= 2; r++) {
      phase('Corrigir')
      const fx = await agent(`ROLE:fix PR:${impl.pr} B:${impl.b} SRC:${src} CI:${ci}${r > 1 ? ' RODADA:2' : ''}\n${IGN}\nA:${JSON.stringify(acts)}\nRET:{"ci":1,"ok":[],"no":[],"blno":0}  blno=quantos achados BL você NÃO aplicou`,
        { label: `fix:${tid}:r${r}`, phase: 'Corrigir', agentType: 'implementer', model, isolation: 'worktree', schema: FIX })
      ci = fx ? fx.ci : 0
      refusedBL = fx ? (fx.blno || 0) : 0; refused = fx && fx.no ? fx.no : []
      if (ci) break
    }
  }
  if (!ci) { out.push({ t: tid, st: 'BLOQUEADA', pr: impl.pr, why: 'CI vermelho após 2 rodadas', sg }); break }
  if (refusedBL > 0) { out.push({ t: tid, st: 'AGUARDA-USUARIO', pr: impl.pr, why: refused, nv: impl.nv, sg }); log(`${tid}: BL recusado, PR #${impl.pr} aberto`); break }

  phase('Merge')
  let m = await merge(impl.pr, tid, `merge:${tid}`)
  // Trilhas paralelas: outro PR pode ter entrado antes. Primeiro o script (barato); agente de rebase só se sobrar conflito em código.
  if (m && !m.m && /CONFLICT|DIRTY|BEHIND/i.test(m.why || '')) {
    log(`${tid}: atrás da main, rebase-auto`)
    const ra = await agent(`ROLE:rebase PR:${impl.pr} CWD:${ROOT} CMD:scripts/dev/rebase-auto.sh ${impl.pr}\nRET:{"ok":1,"why":""}  ok=1 se a saída for rebase=ok`,
      { label: `rebase-auto:${tid}`, phase: 'Merge', agentType: 'merger', effort: 'low', schema: RB })
    let ok = ra && ra.ok
    if (!ok) {
      log(`${tid}: conflito em código, agente de rebase`)
      const rb = await agent(`ROLE:fix PR:${impl.pr} B:${impl.b} SRC:${src} CONFLITO:1\n${IGN}\nDO:git fetch origin;rebase em origin/main;resolver mantendo as duas mudanças;gates;push --force-with-lease;ci-wait\nRET:{"ci":1,"ok":[],"no":[],"blno":0}`,
        { label: `rebase:${tid}`, phase: 'Merge', agentType: 'implementer', model, isolation: 'worktree', schema: FIX })
      ok = rb && rb.ci
    }
    if (ok) m = await merge(impl.pr, tid, `merge2:${tid}`)
  }
  if (!m || !m.m) { out.push({ t: tid, st: 'BLOQUEADA', pr: impl.pr, why: m ? m.why : 'merge falhou', sg }); break }
  out.push({ t: tid, st: 'FEITA', pr: impl.pr, sha: m.sha, model, nv: impl.nv, a: achados.length, sg })
  log(`${tid}: mergeado #${impl.pr} (${model})`)
}
return out
