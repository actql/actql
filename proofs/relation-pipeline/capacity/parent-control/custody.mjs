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
// The checked Program includes Values at step 0. Cancellation stops the
// DISTINCT child; successful completion belongs to the final Filter child.
export function custodyCleanupStep(mode) {
  assert(['normal', 'pending', 'success'].includes(mode));
  const { case: case_, program: input } = custodyInput();
  assert.deepEqual(case_.steps.map(step => step.op), ['distinct', 'filter']);
  const stage = input.stages[0];
  assert.equal(stage.steps.length, 3);
  assert(stage.steps[0].values);
  const distinct = stage.steps.findIndex(step => step.distinct === true);
  const final = stage.steps.findIndex(step => step.as === stage.results.r.from);
  assert.equal(distinct, 1); assert.equal(final, 2);
  return mode === 'success' ? final : distinct;
}
export function custodyOverlay(read, mode) {
  assert(['normal', 'pending', 'success'].includes(mode));
  const query = 'src/query_integration/query_checked_program_wbtest.mbt';
  const selected = 'src/connectors/local/selected_relation_provider.mbt';
  const fixture = 'src/query_integration/relation_pipeline_custody_wbtest.mbt';
  const task = 'src/physical_strategy_host/task_execution.mbt';
  const dispatch = 'src/connectors/local/driver/managed_dispatch.mbt';
  const workspace = 'src/execution_relation/workspace_growth.mbt';
  const originals = Object.fromEntries([...Object.keys(replacements), query, selected, task, dispatch, workspace].map(p => [p, read(p)]));
  const overlay = Object.fromEntries(Object.entries(originals).map(([p, text]) =>
    [p, replacements[p] ? instrument(p, text.toString()) : text.toString()]));
  const anchor = '    Some(kind) => local_values_unary_program(kind)';
  assert.equal(overlay[query].split(anchor).length, 2);
  const variable = custodyVariable;
  overlay[query] = overlay[query].replace(anchor,
    `    Some(kind) => if kind == "capacity-custody-probe" { @env.get_env_var("${variable}").unwrap() } else { local_values_unary_program(kind) }`);
  overlay[fixture] = readFileSync(new URL('./custody-fixture.mbt', import.meta.url), 'utf8');
  const chainStart = '  state.children = [initial]';
  assert.equal(overlay[selected].split(chainStart).length, 2);
  overlay[selected] = overlay[selected].replace(chainStart,
    '  println("ACTQL_CUSTODY_CHAIN:started")\n  custody_started_children.val += 1\n' + chainStart);
  const childStart = '    state.children.push(next)';
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
  // Observe the actual same-Task resize and the constructor which requests
  // it. Neither observer changes an extent or releases/retains any resource.
  const taskGrow = '  execution.scratch = scratch';
  assert.equal(overlay[task].split(taskGrow).length, 2);
  overlay[task] = overlay[task].replace(taskGrow, taskGrow + String.raw`
  println("ACTQL_CUSTODY_TASK_GROWTH:{\"task\":" + execution.task.to_string() +
    ",\"before\":" + capacity.to_string() + ",\"after\":" + (capacity + extra).to_string() +
    ",\"extra\":" + extra.to_string() + ",\"scratchAfter\":" + scratch.to_string() + "}")`);
  const request = '    let result = reserve(preferred, preferred_retained)';
  assert.equal(overlay[workspace].split(request).length, 2);
  overlay[workspace] = overlay[workspace].replace(request, String.raw`    println("ACTQL_CUSTODY_WORKSPACE:{\"slotPeak\":" + slot_peak.to_string() +
      ",\"initialSlots\":" + growth.initial_slots.to_string() + ",\"logicalPeak\":" + logical_peak.to_string() +
      ",\"initialLive\":" + growth.initial_live.to_string() + ",\"textPeak\":" + text_peak.to_string() +
      ",\"retained\":" + retained.to_string() + ",\"extra\":" + extra.to_string() +
      ",\"funded\":" + growth.funded.to_string() + ",\"ceiling\":" + growth.live_ceiling.to_string() +
      ",\"metered\":" + (if growth.retained_outputs is Some(_) { 1 } else { 0 }).to_string() +
      ",\"preferred\":" + preferred.to_string() + "}")
` + request);
  const driver = '    match\n      @strategy.grow_task_execution_workspace(\n        setup.run,\n        execution,\n        scratch,';
  assert.equal(overlay[dispatch].split(driver).length, 2);
  overlay[dispatch] = overlay[dispatch].replace(driver, String.raw`    println("ACTQL_CUSTODY_DRIVER_GROWTH:{\"base\":" + setup.capacity.scratch_bytes.to_string() +
      ",\"workingBefore\":" + working_extra.val.to_string() + ",\"working\":" + extra.to_string() +
      ",\"metadata\":" + metadata_extra.val.to_string() + ",\"transport\":" + transport_extra.val.to_string() +
      ",\"imported\":" + imported.to_string() + ",\"scratch\":" + scratch.to_string() + "}")
` + driver);
  const cleanupStep = custodyCleanupStep(mode);
  const before = '        match @execution.cleanup_bounded_binding_rows(active) {';
  const after = '            Ok(reclaimed.val)';
  assert.equal(overlay[selected].split(before).length, 2);
  assert.equal(overlay[selected].split(after).length, 2);
  let retry = '';
  if (mode === 'pending' || mode === 'success') {
    const work = '  let work = Ref(0L)';
    assert.equal(overlay[selected].split(work).length, 2);
    overlay[selected] = overlay[selected].replace(work, work + '\n  let custody_cleanup_calls = Ref(0)');
    retry = `          custody_cleanup_calls.val += 1
          if custody_cleanup_calls.val == 1 {
            println("ACTQL_CUSTODY_RETRY:false")
            return Ok(false)
          }
          if custody_cleanup_calls.val == 2 {
            println("ACTQL_CUSTODY_RETRY:error")
            return Err(@connector.InvalidLimits)
          }
`;
  }
  // Observe the selected owner's real cleanup call. Do not retain the owner or
  // delay cleanup of an earlier child that has already handed off its output.
  overlay[selected] = overlay[selected].replace(before, `        if step == ${cleanupStep} {
${retry}          println("ACTQL_CUSTODY_CLEANUP:${cleanupStep}:before")
        }
${before}`);
  overlay[selected] = overlay[selected].replace(after, `            if step == ${cleanupStep} && reclaimed.val {
              println("ACTQL_CUSTODY_CLEANUP:${cleanupStep}:after")
            }
${after}`);
  return { originals, overlay, fixture, variable };
}

// The audit caller supplies the requested target and cleanup mode. A receipt
// cannot broaden its scope by changing both its own labels and observations.
export function auditCustody(receipt, target, mode, current, read) {
  assert(['js', 'wasm', 'native'].includes(target));
  assert(['normal', 'pending', 'success'].includes(mode));
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
  if (mode === 'success') auditFinalizationGrowth(log, o, read);
  else assert.equal(o.before, o.executionCapacity);
  assert.equal(o.workAfter, o.workBefore, 'Cleanup lost cumulative work');
  const after = log.indexOf(mode === 'success' ?
    'ACTQL_CUSTODY_STAGE:after-completion-before-cleanup' :
    'ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup');
  const cleanupStep = custodyCleanupStep(mode);
  const beforeMarker = `ACTQL_CUSTODY_CLEANUP:${cleanupStep}:before`;
  const afterMarker = `ACTQL_CUSTODY_CLEANUP:${cleanupStep}:after`;
  assert.equal(log.split(beforeMarker).length, 2, 'Missing or repeated actual child cleanup');
  assert.equal(log.split(afterMarker).length, 2, 'Missing or repeated confirmed child cleanup');
  const cleanup = log.indexOf(beforeMarker);
  const cleaned = log.indexOf(afterMarker);
  assert(after >= 0 && cleanup >= 0 && cleaned > cleanup);
  assert.equal(o.after, o.before, 'Settlement lost scratch before explicit cleanup');
  assert(cleanup > after, 'Successful child cleanup preceded pending-scratch observation');
  if (mode === 'normal') {
    assert(!log.includes('ACTQL_CUSTODY_RETRY:'));
  } else {
    const no = log.indexOf('ACTQL_CUSTODY_RETRY:false');
    const error = log.indexOf('ACTQL_CUSTODY_RETRY:error');
    if (mode === 'success') {
      const settlement = log.indexOf('ACTQL_CUSTODY_STAGE:before-success-settlement');
      assert(settlement >= 0 && no > settlement && no < after && error > after && cleanup > error,
        'Missing success-time pending observation and explicit error/retry cleanup path');
    } else {
      assert(no > after && error > no && cleanup > error, 'Missing explicit false/error/retry cleanup path');
    }
    if (mode === 'success') {
      assert(Number.isSafeInteger(o.heldAtCompletion) && o.heldAtCompletion > 0,
        'Missing accepted output holding at completion');
      assert.equal(o.unusedRetentionAtCompletion, 0, 'Unused output retention remains reserved');
    }
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

// Bind the completed-output constructor's existing common workspace quote to
// the driver's SAME original Task resize. No prior quote is cleanup credit.
function auditFinalizationGrowth(log, o, read) {
  for (const key of ['beforeFinalization', 'afterFinalization'])
    assert(Number.isSafeInteger(o[key]) && o[key] >= 0, 'Missing finalization capacity boundary');
  assert.equal(o.beforeFinalization, o.executionCapacity, 'Unexpected growth before finalization');
  assert.equal(o.afterFinalization, o.before, 'Finalization debit differs from settlement custody');
  const begin = 'ACTQL_CUSTODY_FINALIZATION:before', end = 'ACTQL_CUSTODY_FINALIZATION:after';
  assert.equal(log.split(begin).length, 2, 'Missing exact finalization entry');
  assert.equal(log.split(end).length, 2, 'Missing exact finalization exit');
  const first = log.indexOf(begin), last = log.indexOf(end);
  assert(first >= 0 && last > first && last < log.indexOf('ACTQL_CUSTODY_STAGE:before-success-settlement'),
    'Finalization boundaries moved across settlement');
  // Read the original common Owner's units and page from the source already
  // pinned by this receipt. The proof does not supply another product tariff.
  const recipe = read('src/execution_relation/capacity_inventory.mbt').toString();
  const literal = (source, pattern) => {
    const matches = [...source.matchAll(pattern)];
    assert.equal(matches.length, 1, 'Unknown common workspace capacity recipe');
    const value = Number(matches[0][1]);
    assert(Number.isSafeInteger(value) && value > 0);
    return value;
  };
  assert(recipe.includes('CursorRootSlots => execution_capacity_node_bytes()'));
  assert(recipe.includes('ValueNodeSlots => execution_capacity_node_bytes()'));
  const node = literal(read('src/execution_relation/execution_capacity.mbt').toString(),
    /pub fn execution_capacity_node_bytes\(\) -> Int64 \{\s*([0-9]+)L\s*\}/g);
  const wire = literal(recipe, /CanonicalWireBytes => ([0-9]+)L/g);
  const quoted = literal(recipe, /QuotedBytes => ([0-9]+)L/g);
  const page = literal(read('src/execution_relation/workspace_growth.mbt').toString(),
    /let remainder = extra % ([0-9]+)L/g);
  const prefixes = ['ACTQL_CUSTODY_WORKSPACE:', 'ACTQL_CUSTODY_DRIVER_GROWTH:', 'ACTQL_CUSTODY_TASK_GROWTH:'];
  let position = 0, phase = 0, requested = 0, scratch = 0;
  for (const line of log.split('\n')) {
    const at = position; position += line.length + 1;
    const kind = prefixes.findIndex(prefix => line.startsWith(prefix));
    if (kind < 0) continue;
    assert(at > first && at < last, 'Task growth occurred outside original finalization');
    assert.equal(kind, phase, 'Detached or repeated finalization growth constructor');
    const value = JSON.parse(line.slice(prefixes[kind].length));
    for (const number of Object.values(value))
      assert(Number.isSafeInteger(number) && number >= 0, 'Invalid actual growth observation');
    if (kind === 0) {
      const required = Math.max(0, value.slotPeak - value.initialSlots) * node +
        Math.max(0, value.logicalPeak - value.initialLive) * (node + wire) +
        (value.textPeak + value.retained) * quoted;
      assert(Number.isSafeInteger(required));
      assert.equal(value.extra, required, 'Workspace changed the common tariff');
      assert.equal(value.funded, 0, 'Unexpected earlier workspace funding');
      assert([0, 1].includes(value.metered));
      const remainder = required % page;
      const spare = value.metered && remainder && required < value.ceiling ?
        Math.min(page - remainder, value.ceiling - required) : 0;
      requested = Math.max(required + spare, value.funded);
      assert(Number.isSafeInteger(requested) && requested > 0);
      assert.equal(value.preferred, requested, 'Workspace changed the common page quote');
    } else if (kind === 1) {
      assert.equal(value.workingBefore, 0, 'Unexpected earlier driver workspace growth');
      assert.equal(value.working, requested, 'Driver detached from original workspace request');
      // This finite source-free constructor has no imported/Result/frame debt.
      for (const key of ['metadata', 'transport', 'imported']) assert.equal(value[key], 0);
      scratch = value.base + value.working;
      assert(Number.isSafeInteger(scratch));
      assert.equal(value.scratch, scratch, 'Driver replaced the original workspace quote');
    } else {
      assert.equal(value.task, 0, 'Capacity grew on another Task');
      assert.equal(value.before, o.executionCapacity, 'Detached Task reservation growth');
      assert.equal(value.extra, requested, 'Task growth differs from the actual constructor');
      assert.equal(value.scratchAfter, scratch, 'Task resized a different workspace');
      assert.equal(value.after, value.before + requested);
      assert.equal(value.after, o.afterFinalization, 'Unexplained finalization capacity change');
    }
    phase++;
  }
  assert.equal(phase, 3, 'Missing actual finalization growth');
}

// Reconstruct the reviewed product mutation independently of the report labels.
export function auditCustodyMutations(records, current, read) {
  const site = 'src/physical_strategy_host/task_execution.mbt';
  const code = read(site).toString();
  const variants = [
    { name: 'drop-installed-scratch-release-condition', mode: 'normal',
      before: '(execution.hooks.unwrap().scratch_released)()',
      after: 'physical_equal(execution, execution)' },
    { name: 'settle-success-before-scratch-release', mode: 'success',
      before: 'if task_execution_scratch_released(execution) {', after: 'if true {' },
  ];
  assert.deepEqual(records.map(({ name, mode }) => ({ name, mode })),
    variants.map(({ name, mode }) => ({ name, mode })), 'Incomplete custody mutations');
  for (const [index, record] of records.entries()) {
    const variant = variants[index];
    assert.equal(record.target, 'js');
    assert.equal(record.site, site);
    assert.equal(record.beforeDigest, hash(code));
    assert.equal(code.split(variant.before).length, 2, 'Ambiguous custody mutation source');
    const sources = { ...current.sources, [site]: hash(code.replace(variant.before, variant.after)) };
    assert.deepEqual(record.source.sources, sources);
    assert.equal(record.source.digest, hash(JSON.stringify(sources)));
    assert(Number.isInteger(record.exit) && record.exit > 0, 'Mutation did not exit with a detected failure');
    const log = read(record.logPath).toString();
    assert.equal(hash(log), record.logDigest);
    assert(log.includes('Scratch credited before child cleanup'), 'Mutation failed for a different reason');
  }
}
