// Contract-pin migration of authored preimages; never reads runtime output.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => JSON.stringify((function order(v) {
  if (Array.isArray(v)) return v.map(order);
  if (v !== null && typeof v === 'object') return Object.fromEntries(
    Object.keys(v).sort().map(key => [key, order(v[key])]));
  return v;
})(value));
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const files = ['stage-semantics', 'stage-definition', 'program-semantics',
  'program-definition', 'local-unit-stage-body'];
const paths = Object.fromEntries(files.map(name => [name, `portability/corpus/${name}.json`]));
const history = 'portability/corpus/historical/pre-typed-json-identities.json';
const write = process.argv.includes('--write');
if (write && !existsSync(history)) {
  const previous = Object.fromEntries(files.map(name => [name, read(paths[name])]));
  assert.equal(previous['stage-semantics'].cases[0].envelope.expression_contract_cid,
    'sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb');
  mkdirSync('portability/corpus/historical', {recursive: true});
  writeFileSync(history, JSON.stringify(previous, null, 2) + '\n');
}
const previous = read(history);
const bodies = structuredClone(previous);
const root = cid(read('spec/contracts/actql-expressions.json'));
assert.equal(root, read('spec/contracts/actql-aoa.json').expression_contract_cid);
const stages = bodies['stage-semantics'];
for (const c of [...stages.cases, ...bodies['local-unit-stage-body'].cases]) {
  c.envelope.expression_contract_cid = root;
  c.expected_cid = cid(c.envelope);
}
for (const c of bodies['stage-definition'].cases) {
  c.expected_cid = cid({version: 'actql-stage-definition/0.1', id: c.id,
    stage_semantics_cid: stages.cases.find(s => s.name === c.stage_case).expected_cid});
}
for (const c of bodies['program-semantics'].cases) {
  const [a, b] = stages.cases.slice(0, 2).map(s => structuredClone(s.envelope));
  const port = c.import_mode === 1 ? {result: {stage: 'a', result: 'r'}} :
    c.import_mode === 2 ? {receipt: {stage: 'a', effect: 'd'}} : null;
  if (port) b.local_body.inputs.rows = port;
  const envelope = {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
    expression_contract_cid: root, parameters: a.parameters, bindings: a.bindings,
    parameter_references: [a, b].flatMap((s, i) => s.parameter_references.map(r =>
      ({...r, path: `/stages/${i}${r.path}`}))),
    binding_references: a.binding_references.map(r => ({...r, path: `/stages/0${r.path}`})),
    program_template: {stages: [
      {id: 'a', after: 'initial', imports: {}, stage_semantics_cid: cid(a)},
      {id: 'b', after: c.accepted ? 'accepted' : 'completed', imports: port ? {rows: port} : {},
        stage_semantics_cid: cid(b)}], exports: {out: {from: {stage: 'b', result: 'r'}}}}};
  c.expected_cid = cid(envelope);
}
for (const c of bodies['program-definition'].cases) {
  const semantics = bodies['program-semantics'].cases.find(p =>
    p.import_mode === c.import_mode && p.accepted === c.accepted).expected_cid;
  c.expected_cid = cid({version: 'actql-program-definition/0.1', id: c.id,
    program_semantics_cid: semantics});
}
for (const name of files) {
  if (write) writeFileSync(paths[name], JSON.stringify(bodies[name], null, 2) + '\n');
  else assert.deepEqual(read(paths[name]), bodies[name], `stale typed JSON stage pin: ${name}`);
}
console.log('Authored Stage/Program preimages and retained predecessor identities verified.');
