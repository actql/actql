import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import * as host from './index.mjs';

const limits = {maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64};
const cid = digit => `sha256:${digit.repeat(64)}`;
const read = name => readFileSync(new URL(`../sdk/fixtures/${name}`, import.meta.url), 'utf8');
const wire = read('values.environment.json').trimEnd();
const environment = host.admitEnvironment(wire, JSON.parse(wire).evidence_bundle_cid, {rela: true});
const document = read('values.json');
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value && typeof value === 'object' ? `{${Object.keys(value).sort()
    .map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const digest = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

function fixture(task = false, runId = 'original-plan-run') {
  const prepared = host.prepare(document, 'json', environment);
  const compilation = (task ? host.compileTasks : host.compileValues)(prepared);
  const issued = (task ? host.issueAllowedTaskRun : host.issueAllowedRun)(prepared, compilation,
    {executionContextCid: cid('b'), hostPolicyCid: cid('c'), expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = (task ? host.issueTaskRunDefinition : host.issueSourceFreeRunDefinition)(
    prepared, compilation, issued.admission, 'original-plan-scope', runId,
    '2026-10-15T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const planWire = (task ? host.privateTaskCompilationWires : host.privateCompilationWires)(compilation).compiledPlan;
  const programCid = JSON.parse(planWire).program_definition_cid;
  const selection = host.captureOriginalRunPlan(prepared, compilation, issued.admission, definition, limits);
  const evidence = {prepared: issued.preparedInvocationWire, authorization: issued.authorizationWire};
  const original = host.originalRunPlanAdmissionEvidence(selection, definition, programCid, evidence);
  return {prepared, compilation, issued, definition, selection, evidence, original, programCid, planWire};
}

for (const task of [false, true]) {
  test(`portable original ${task ? 'Tasks' : 'Values'} Plan uses the exact checked compilation`, () => {
    const f = fixture(task);
    assert.equal(f.original.compiledPlanWire, f.planWire);
    assert.equal(host.readStoredRunPlanOriginal(f.original, f.definition, f.programCid, limits),
      f.original.planViewWire);
    const view = JSON.parse(f.original.planViewWire);
    assert.equal(view.version, 'actql-plan-view/0.1');
    assert.equal(view.observation, 'static');
    assert.equal(view.provider_io, 0);
    assert.equal(view.capabilities.static_plan, true);
    assert.equal(view.capabilities.durable_control, false);
    assert.deepEqual(view.capabilities.sample_capture, []);
    assert.equal(view.compiled_plan_cid, JSON.parse(f.planWire).compiled_plan_cid);
    const {self_cid: mapCid, ...mapBody} = view.logical_map;
    assert.equal(mapCid, digest(mapBody));
    assert.equal(mapBody.program_definition_cid, f.programCid);
    assert(Object.isFrozen(f.selection));
    assert(Object.isFrozen(f.original));
  });
}

test('first capture refuses copied holders and a different physical checked preparation', () => {
  const f = fixture(), other = fixture(false, 'other-run');
  for (const fields of [
    [{...f.prepared}, f.compilation, f.issued.admission, f.definition],
    [f.prepared, {...f.compilation}, f.issued.admission, f.definition],
    [f.prepared, f.compilation, {...f.issued.admission}, f.definition],
    [f.prepared, f.compilation, f.issued.admission, {...f.definition}],
    [other.prepared, f.compilation, f.issued.admission, f.definition],
    [f.prepared, other.compilation, f.issued.admission, f.definition],
    [f.prepared, f.compilation, other.issued.admission, f.definition],
  ]) assert.throws(() => host.captureOriginalRunPlan(...fields, limits), /ForeignRunHost/u);
});

test('admission evidence remains joined to the original Run, Program and exact original authorization', () => {
  const f = fixture(), other = fixture(false, 'other-run');
  for (const fields of [
    [f.selection, other.definition, f.programCid, f.evidence],
    [f.selection, f.definition, cid('f'), f.evidence],
    [f.selection, f.definition, f.programCid, {...f.evidence, prepared: '{}'}],
    [f.selection, f.definition, f.programCid, {...f.evidence, authorization: '{}'}],
    [{...f.selection}, f.definition, f.programCid, f.evidence],
    [f.original, f.definition, f.programCid, f.evidence],
  ]) assert.throws(() => host.originalRunPlanAdmissionEvidence(...fields), /ForeignRunHost/u);
});

test('authenticated saved metadata restores in a fresh process without capture or preparation', () => {
  const f = fixture();
  const moduleUrl = new URL('./index.mjs', import.meta.url).href;
  const script = `import {admitRunDefinition,readStoredRunPlanOriginal,
    originalRunPlanAdmissionEvidence} from ${JSON.stringify(moduleUrl)};
    const p=JSON.parse(process.argv[1]),definition=admitRunDefinition(p.definition);
    const wire=readStoredRunPlanOriginal(p.original,definition,p.programCid,p.limits);
    let refused=false;try{originalRunPlanAdmissionEvidence(p.original,definition,p.programCid,p.evidence);}
    catch(e){refused=e.message==='ForeignRunHostHandle';}
    console.log(JSON.stringify({wire,refused}));`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', script,
    JSON.stringify({definition: host.privateRunDefinition(f.definition).wire,
      original: f.original, programCid: f.programCid, limits, evidence: f.evidence})],
  {encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {wire: f.original.planViewWire, refused: true});
});

test('missing legacy original is unavailable and malformed/changed saved bytes are refused', () => {
  const f = fixture();
  assert.throws(() => host.readStoredRunPlanOriginal(undefined, f.definition, f.programCid, limits),
    {code: 'RunHostOriginalPlanUnavailable'});
  for (const original of [null, {}, {...f.original, extra: true},
    {...f.original, compiledPlanWire: '{'}, {...f.original, planViewWire: '{'},
    {...f.original, planViewWire: f.original.planViewWire + ' '},
    {...f.original, compiledPlanWire: f.original.compiledPlanWire + ' '},
    {get compiledPlanWire() { throw new Error('accessor executed'); }, planViewWire: f.original.planViewWire},
  ]) assert.throws(() => host.readStoredRunPlanOriginal(original, f.definition, f.programCid, limits),
    error => error.message !== 'accessor executed');
  assert.throws(() => host.readStoredRunPlanOriginal(f.original, f.definition, cid('e'), limits),
    /ForeignRunHostOriginalPlan/u);
});

test('closed Plan shape, sidecar CID and producer coordinates are independently validated', () => {
  const f = fixture();
  const reject = view => assert.throws(() => host.readStoredRunPlanOriginal(
    {...f.original, planViewWire: canonical(view)}, f.definition, f.programCid, limits));
  const view = () => JSON.parse(f.original.planViewWire);
  reject({...view(), provider_io: 1});
  reject({...view(), extra: true});
  reject({...view(), compiled_plan_cid: cid('f')});
  const invalidCid = view();
  invalidCid.logical_map.self_cid = cid('d');
  reject(invalidCid);
  const foreignPort = view();
  foreignPort.logical_map.steps[0].ports[0].port_id = cid('e');
  const {self_cid: unused, ...body} = foreignPort.logical_map;
  foreignPort.logical_map.self_cid = digest(body);
  reject(foreignPort);
});

test('saved original cannot be rebound to a different compiled Plan or a foreign definition', () => {
  const f = fixture();
  const changed = JSON.parse(document);
  changed.stages[0].steps[0].values.rows[0].id = 77;
  const prepared = host.prepare(JSON.stringify(changed), 'json', environment);
  const compilation = host.compileValues(prepared);
  const issued = host.issueAllowedRun(prepared, compilation,
    {executionContextCid: cid('b'), hostPolicyCid: cid('c'), expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = host.issueSourceFreeRunDefinition(prepared, compilation, issued.admission,
    'original-plan-scope', 'different-plan', '2026-10-15T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  assert.throws(() => host.readStoredRunPlanOriginal(f.original, definition, f.programCid, limits),
    /ForeignRunHostOriginalPlan/u);
  assert.throws(() => host.captureOriginalRunPlan(f.prepared, f.compilation,
    f.issued.admission, definition, limits), {code: 'RunHostOriginalPlanRejected'});
});

test('capture and restore preserve caller byte/node/depth bounds without coercion', () => {
  const f = fixture();
  for (const bounds of [{...limits, maxWireBytes: 1}, {...limits, maxNodes: 1},
    {...limits, maxDepth: 1}, {...limits, maxWireBytes: '65536'},
    {...limits, maxNodes: 2147483648}, {...limits, maxDepth: NaN}]) {
    assert.throws(() => host.readStoredRunPlanOriginal(f.original, f.definition, f.programCid, bounds));
    assert.throws(() => host.captureOriginalRunPlan(f.prepared, f.compilation,
      f.issued.admission, f.definition, bounds));
  }
});
