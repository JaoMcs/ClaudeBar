export const meta = {
  name: 'impl-loop',
  description: 'Loop por task com modelo por complexidade: implementer → reviewer → fix (se BL/SG/CI) → merger. Contexto mínimo, protocolo wire.',
  whenToUse: 'Executar tasks do ClaudeBar. args: {"tasks":[{"id":"T19-ir-para-sessao","model":"opus"}], "root":"/caminho/do/clone"}',
  phases: [{ title: 'Implementar' }, { title: 'Revisar' }, { title: 'Corrigir' }, { title: 'Merge' }],
}

if (!args || !args.root || !args.tasks) throw new Error('args: {root, tasks}')
const ROOT = args.root
const TASKS = args.tasks
const UP = { haiku: 'sonnet', sonnet: 'opus', opus: 'opus' }
const IMPL = { type: 'object', properties: { ok: { type: 'integer' }, pr: { type: 'integer' }, b: { type: 'string' }, nv: { type: 'string' }, why: { type: 'string' } }, required: ['ok'] }
const REV = { type: 'object', properties: { ci: { type: 'integer' }, a: { type: 'array', items: { type: 'object', properties: { s: { type: 'string', enum: ['BL', 'SG', 'NIT'] }, f: { type: 'string' }, d: { type: 'string' } }, required: ['s', 'd'] } } }, required: ['ci', 'a'] }
const FIX = { type: 'object', properties: { ci: { type: 'integer' }, ok: { type: 'array', items: { type: 'string' } }, no: { type: 'array', items: { type: 'string' } } }, required: ['ci'] }
const MRG = { type: 'object', properties: { m: { type: 'integer' }, sha: { type: 'string' }, why: { type: 'string' } }, required: ['m'] }

const out = []
for (const t of TASKS) {
  const id = t.id, tid = id.split('-')[0]
  const src = `${ROOT}/.planning/06-tasks/${id}.md`
  let model = t.model || 'sonnet'

  phase('Implementar')
  let impl = null
  for (let tent = 1; tent <= 2 && !(impl && impl.ok && impl.pr); tent++) {
    if (tent === 2) { model = UP[model]; log(`${tid}: 2ª tentativa com ${model}`) }
    impl = await agent(`ROLE:impl T:${tid} SRC:${src} B:<campo Branch da task>\nRET:{"ok":1,"pr":0,"b":"","nv":""}`,
      { label: `impl:${tid}:${model}`, phase: 'Implementar', agentType: 'implementer', model, isolation: 'worktree', schema: IMPL })
  }
  if (!impl || !impl.ok || !impl.pr) { out.push({ t: tid, st: 'BLOQUEADA', why: impl ? impl.why : 'agente falhou' }); log(`${tid}: falhou`); break }

  phase('Revisar')
  const rev = await agent(`ROLE:rev PR:${impl.pr} SRC:${src}\nRET:{"ci":1,"a":[{"s":"","f":"","d":""}]}`,
    { label: `rev:${tid}:${model}`, phase: 'Revisar', agentType: 'reviewer', model, schema: REV })
  const acts = rev ? rev.a.filter(a => a.s !== 'NIT') : []
  let ci = rev ? rev.ci : 0, refusedBL = []
  if (!rev || !ci || acts.length) {
    for (let r = 1; r <= 2; r++) {
      phase('Corrigir')
      const fx = await agent(`ROLE:fix PR:${impl.pr} B:${impl.b} SRC:${src} CI:${ci}${r > 1 ? ' RODADA:2' : ''}\nA:${JSON.stringify(rev ? rev.a : [])}\nRET:{"ci":1,"ok":[],"no":[]}`,
        { label: `fix:${tid}:r${r}`, phase: 'Corrigir', agentType: 'implementer', model, isolation: 'worktree', schema: FIX })
      ci = fx ? fx.ci : 0
      refusedBL = (fx && fx.no ? fx.no : []).filter(x => /BL|bloqueante/i.test(x))
      if (ci) break
    }
  }
  if (!ci) { out.push({ t: tid, st: 'BLOQUEADA', pr: impl.pr, why: 'CI vermelho após 2 rodadas' }); break }
  if (refusedBL.length) { out.push({ t: tid, st: 'AGUARDA-USUARIO', pr: impl.pr, why: refusedBL, nv: impl.nv }); log(`${tid}: BL recusado, PR #${impl.pr} aberto`); break }

  phase('Merge')
  const m = await agent(`ROLE:merge PR:${impl.pr} T:${tid} CWD:${ROOT}\nRET:{"m":1,"sha":""}`,
    { label: `merge:${tid}`, phase: 'Merge', agentType: 'merger', effort: 'low', schema: MRG })
  if (!m || !m.m) { out.push({ t: tid, st: 'BLOQUEADA', pr: impl.pr, why: m ? m.why : 'merge falhou' }); break }
  out.push({ t: tid, st: 'FEITA', pr: impl.pr, sha: m.sha, model, nv: impl.nv, a: rev ? rev.a.length : 0 })
  log(`${tid}: mergeado #${impl.pr} (${model})`)
}
return out
