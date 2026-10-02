import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { registry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { fixedCorpus } from '../../corpus.mjs';
import { program } from '../../engine.mjs';
import { replacements, generatedObservers, instrument } from '../instrument.mjs';
export const custodyDirectory = '.artifacts/relation-pipeline/capacity/custody';
export const custodyVariable = 'ACTQL_RELATION_PIPELINE_CUSTODY_PROGRAM';
export function custodyInput() {
  const case_ = fixedCorpus(registry, registrations).find(c => c.id === 'pair:distinct/filter');
  assert(case_ && case_.steps.length === 2);
  const pipeline = program(case_, registry);
  const input = {
    version: 'actql/0.1', id: 'p',
    stages: [{ id: 'compute', inputs: {},
      steps: [...JSON.parse(pipeline.source), ...JSON.parse(pipeline.steps).map((step, i) =>
        i === 0 ? { ...step, from: 'seed' } : step)],
      results: { r: { from: 's1', fields: pipeline.states.at(-1).fields } } }],
    results: { source: { from: { stage: 'compute', result: 'r' } } },
  };
  return { case: case_, program: input };
}
export function custodyOverlay(read, mode) {
  assert(['normal', 'pending'].includes(mode));
  const query = 'src/query_integration/query_checked_program_wbtest.mbt';
  const selected = 'src/connectors/local/selected_relation_provider.mbt';
  const fixture = 'src/query_integration/relation_pipeline_custody_wbtest.mbt';
  const originals = Object.fromEntries([...Object.keys(replacements), query, selected].map(p => [p, read(p)]));
  const overlay = Object.fromEntries(Object.entries(originals).map(([p, text]) =>
    [p, replacements[p] ? instrument(p, text.toString()) : text.toString()]));
  const anchor = '    Some(kind) => local_values_unary_program(kind)';
  assert.equal(overlay[query].split(anchor).length, 2);
  const variable = custodyVariable;
  overlay[query] = overlay[query].replace(anchor,
    `    Some(kind) => if kind == "capacity-custody-probe" { @env.get_env_var("${variable}").unwrap() } else { local_values_unary_program(kind) }`);
  overlay[fixture] = readFileSync(new URL('./custody-fixture.mbt', import.meta.url), 'utf8');
  const chainStart = '  let children : Ref[Array[ManagedProviderExecution]] = Ref([initial])';
  assert.equal(overlay[selected].split(chainStart).length, 2);
  overlay[selected] = overlay[selected].replace(chainStart,
    '  println("ACTQL_CUSTODY_CHAIN:started")\n  custody_started_children.val += 1\n' + chainStart);
  const childStart = '    children.val.push(next)';
  assert.equal(overlay[selected].split(childStart).length, 2);
  overlay[selected] = overlay[selected].replace(childStart,
    '    custody_started_children.val += 1\n' + childStart);
  overlay[selected] += `
///|
// Numeric observation only: no provider, payload or backing is retained.
let custody_started_children : Ref[Int] = Ref(0)
///|
pub fn custody_child_start_count() -> Int { custody_started_children.val }
`;
  if (mode === 'pending') {
    const work = '  let work = Ref(0L)';
    assert.equal(overlay[selected].split(work).length, 2);
    overlay[selected] = overlay[selected].replace(work, work + '\n  let custody_cleanup_calls = Ref(0)');
    const before = '        match @execution.cleanup_bounded_binding_rows(active) {';
    assert.equal(overlay[selected].split(before).length, 2);
    overlay[selected] = overlay[selected].replace(before, `        custody_cleanup_calls.val += 1
        if custody_cleanup_calls.val == 1 {
          println("ACTQL_CUSTODY_RETRY:false")
          return Ok(false)
        }
        if custody_cleanup_calls.val == 2 {
          println("ACTQL_CUSTODY_RETRY:error")
          return Err(@connector.InvalidLimits)
        }
${before}`);
  }
  return { originals, overlay, fixture, variable };
}

// The audit caller supplies the requested target and cleanup mode. A receipt
// cannot broaden its scope by changing both its own labels and observations.
export function auditCustody(receipt, target, mode, current, read) {
  assert(['js', 'wasm', 'native'].includes(target));
  assert(['normal', 'pending'].includes(mode));
  assert.equal(receipt.version, 'actql-relation-custody/0.1');
  assert.equal(receipt.target, target, 'Requested custody target differs from execution');
  assert.equal(receipt.mode, mode, 'Requested cleanup mode differs from execution');
  const pin = JSON.parse(read('toolchain.json'));
  assert.deepEqual(receipt.toolchain, pin);
  assert.deepEqual(receipt.source, current, 'Stale custody source');
  assert.equal(current.digest, hash(JSON.stringify(current.sources)));
  const { overlay, fixture, variable } = custodyOverlay(read, mode);
  const reviewed = { ...generatedObservers, ...overlay };
  const digests = Object.fromEntries(Object.entries(reviewed).map(([path, code]) => [path, hash(code)]));
  assert.deepEqual(receipt.overlays, digests, 'Unknown custody observation/injection source');
  const sources = { ...current.sources, ...digests };
  // snapshot orders full paths by JavaScript code units, not locale collation.
  const exact = Object.fromEntries(Object.keys(sources).sort().map(path => [path, sources[path]]));
  assert.deepEqual(receipt.executedSource.sources, exact, 'Detached custody executable source');
  assert.equal(receipt.executedSource.digest, hash(JSON.stringify(exact)));
  assert.deepEqual(receipt.command, ['moon', 'test', fixture, '--target', target, '--deny-warn']);
  assert.equal(receipt.exit, 0);
  assert.equal(receipt.inputVariable, variable);
  const input = custodyInput();
  assert.deepEqual(JSON.parse(read(receipt.inputPath)), input, 'Unreviewed custody execution domain');
  assert.equal(receipt.inputDigest, hash(JSON.stringify(input.program)));
  assert.equal(read(receipt.fixturePath).toString(), overlay[fixture], 'Detached custody regression fixture');
  assert.equal(receipt.physicalGcCompletion, false);
  assert.equal(receipt.completeAllocationUpper, false);
  assert.equal(receipt.prematureReleaseCandidate, false);
  const log = read(receipt.logPath).toString();
  assert.equal(hash(log), receipt.logDigest);
  assert(log.includes('Total tests: 1, passed: 1, failed: 0.'), 'Missing actual custody test success');
  assert.equal(log.split('ACTQL_CUSTODY_CHAIN:started').length, 2, 'Actual serial chain was not started exactly once');
  const rows = log.split('\n').filter(line => line.startsWith('ACTQL_CUSTODY:'))
    .map(line => JSON.parse(line.slice(14)));
  assert.equal(rows.length, 1); assert.deepEqual(rows[0], receipt.observation);
  const o = rows[0];
  for (const key of ['executionCapacity', 'before', 'after', 'workBefore', 'workAfter'])
    assert(Number.isSafeInteger(o[key]) && o[key] >= 0, 'Invalid custody observation');
  assert(o.executionCapacity > 0 && o.workBefore > 0);
  assert.equal(o.before, o.executionCapacity);
  assert.equal(o.workAfter, o.workBefore, 'Cleanup lost cumulative work');
  const after = log.indexOf('ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup');
  const cleanup = log.indexOf('"event":"before-cleanup"');
  const cleaned = log.indexOf('"event":"after-cleanup"');
  assert(after >= 0 && cleanup >= 0 && cleaned > cleanup);
  if (mode === 'normal') {
    assert.equal(o.after, 0); assert(cleaned < after, 'Capacity credited before synchronous cleanup');
    assert(!log.includes('ACTQL_CUSTODY_RETRY:'));
  } else {
    assert.equal(o.after, o.before, 'Pending cleanup lost reservation');
    assert(cleanup > after, 'Actual child cleanup did not remain pending');
    const no = log.indexOf('ACTQL_CUSTODY_RETRY:false');
    const error = log.indexOf('ACTQL_CUSTODY_RETRY:error');
    assert(no >= 0 && error > no && error < after, 'Missing actual false/error cleanup path');
  }
  assert(Object.keys(receipt.artifacts).length > 0);
  assert.deepEqual(Object.keys(receipt.archives).sort(), Object.keys(receipt.artifacts).sort());
  const base = `_build/${target}/debug/test/query_integration/`;
  const suffix = { js: 'js', wasm: 'wasm', native: 'exe' }[target];
  assert(Object.hasOwn(receipt.artifacts, `${base}query_integration.whitebox_test.${suffix}`), 'Missing executed target artifact');
  for (const [path, digest] of Object.entries(receipt.artifacts)) {
    assert(path.startsWith(base)); assert.match(digest, /^[a-f0-9]{64}$/);
    assert.equal(receipt.archives[path], `${custodyDirectory}/binaries/${digest}`);
    assert.equal(hash(read(receipt.archives[path])), digest, 'Custody executed artifact changed');
  }
  return { kind: 'finite actual chain custody correspondence', target, mode,
    physicalGcCompletion: false, completeAllocationUpper: false };
}
