import assert from 'node:assert/strict';
import test from 'node:test';
import {runReleaseProjectNodeAction} from './release-project-node-action.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';

function ports({decisionFailure, closeFailure, closeObservationFailure, foreignCheckpoint = false,
  source = 'authored source', checkReply} = {}) {
  const ref = {namespaceId: 'original-namespace', authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  const original = {ref, runId: 'original-run', checkpointId: 'original-checkpoint', checkpointCid: 'sha256:' + 'c'.repeat(64)};
  const calls = [], closes = [], accepted = [];
  const checks = [], checkInputs = new WeakMap();
  let status = 'waiting_checkpoint';
  const state = () => ({version: 'actql-run-state/0.1', run_id: original.runId, status,
    checkpoint: {id: original.checkpointId, checkpoint_id: original.checkpointId, checkpoint_cid: original.checkpointCid}});
  const execution = {ref,
    async wait() {calls.push('wait'); return state();},
    async status() {calls.push('status'); return state();},
    async result(name) {assert.equal(name, 'updates'); calls.push('result'); return {
      async all() {calls.push('all'); return [{id: 'independent-result'}];},
      async describe() {calls.push('describe'); return {resultName: name, ref};},
    };},
  };
  const resolve = async decision => {
    calls.push(decision);
    if (decisionFailure) throw decisionFailure;
    status = decision === 'approved' ? 'succeeded' : 'cancelled';
    return {results: [{status: 'committed'}], signed: [{resolutionWire: JSON.stringify({decision,
      run_id: original.runId, run_definition_cid: ref.runDefinitionCid})}]};
  };
  const client = {
    async startSource(source, options) {assert.equal(source, 'authored source'); assert.equal(options.stopBefore, 'commit'); calls.push('start'); return execution;},
    async attach(value) {assert.deepEqual(value, ref); calls.push('attach'); return execution;},
    async checkpoints({checkpointId}) {assert.equal(checkpointId, original.checkpointId); calls.push('checkpoints'); return {items: [{
      checkpointId, checkpointCid: foreignCheckpoint ? 'sha256:' + 'd'.repeat(64) : original.checkpointCid,
      subject: {kind: 'run_unit', runId: original.runId, runDefinitionCid: ref.runDefinitionCid},
    }]};},
    async reviewCheckpoint() {calls.push('review'); return {bytes: new TextEncoder().encode('original sealed review')};},
    approve: () => resolve('approved'), reject: () => resolve('rejected'),
    async check(text, options) {
      calls.push('check'); checks.push({text, options});
      const unknown = text.includes('EFFECT UPDATE private.unknown');
      const invalid = text.includes('.outcome = 1');
      const value = {outcome: 'completed', report: {scope: {kind: 'bound_input'},
        verdict: unknown ? 'undetermined' : invalid ? 'invalid' : 'verified',
        reasons: invalid ? [{code: 'expression_domain_mismatch', facts: {domain: 'key_comparable_operands'}}] : [],
        requirements: [], coverage: unknown ? {limits: [{code: 'unresolved_protected'}]} : {limits: []}}};
      const result = checkReply ? checkReply(value, text) : value;
      checkInputs.set(result, {kind: 'text', text}); return result;
    },
    async plan() {calls.push('plan'); return {provider_io: 0};},
    async close() {calls.push('close'); if (closeFailure) throw closeFailure;},
  };
  return {original, calls, closes, accepted, checks, setStatus: value => {status = value;},
    config: {async connect(options) {assert.deepEqual(options, {mode: 'local', installation: {directory: '.actql-node'}, profile: 'mock'}); calls.push('connect'); return client;},
      async readProgram() {calls.push('read-source'); return source;},
      getCheckInput(value, id) {assert.equal(id, 'source'); return checkInputs.get(value);},
      async retainAccepted(value) {calls.push('retain-accepted'); accepted.push(value);},
      assertPendingTarget() {calls.push('pending-target');},
      retainClose(value) {closes.push(value); if (closeObservationFailure) throw closeObservationFailure;},
    }};
}

test('RC immediate approval uses the same Client directly after wait without another async read', async () => {
  const f = ports();
  const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'start', decision: 'approved'}});
  assert.equal(result.state.status, 'succeeded'); assert.deepEqual(result.original.ref, f.original.ref);
  assert(f.calls.indexOf('retain-accepted') < f.calls.indexOf('wait'));
  assert(!f.calls.includes('checkpoints') && !f.calls.includes('review'));
  for (const operation of ['start', 'approved', 'close']) assert.equal(f.calls.filter(value => value === operation).length, 1);
  assert.deepEqual(f.accepted, [{ref: f.original.ref}]);
  assert.deepEqual(result.firstClose, {attempted: true, returned: true});
  const asyncProbe = ports();
  await assert.rejects(runReleaseProjectNodeAction({...asyncProbe.config,
    assertPendingTarget: async () => {}, request: {kind: 'start', decision: 'approved'}}), /must be synchronous/u);
  assert(!asyncProbe.calls.includes('approved'));
});

test('RC original resolution failure remains primary across failed close and observation', async () => {
  const primary = new Error('original uncertain resolution'), cleanup = new Error('original close pending');
  const f = ports({decisionFailure: primary, closeFailure: cleanup, closeObservationFailure: new Error('observation failure')});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'start', decision: 'approved'}}), value => value === primary);
  assert.equal(f.calls.filter(value => value === 'approved').length, 1);
  assert.equal(f.calls.filter(value => value === 'start').length, 1);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert.equal(f.closes.at(-1).returned, false); assert.equal(f.closes.at(-1).outcome, 'threw');
  assert.equal(f.accepted.length, 1);
});

test('RC cold resolution selects only the original public checkpoint without reprepare', async () => {
  const f = ports();
  const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'resolve', original: f.original, decision: 'rejected'}});
  assert.equal(result.state.status, 'cancelled'); assert(!f.calls.includes('start'));
  assert.equal(f.calls.filter(value => value === 'rejected').length, 1);
  const foreign = ports({foreignCheckpoint: true});
  await assert.rejects(runReleaseProjectNodeAction({...foreign.config,
    request: {kind: 'resolve', original: foreign.original, decision: 'approved'}}));
  assert(!foreign.calls.includes('approved')); assert.equal(foreign.calls.at(-1), 'close');
});

test('RC Saved reads the original Named Result before status and static never starts a Run', async () => {
  const f = ports(); f.setStatus('succeeded');
  const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'result', original: f.original}});
  assert.deepEqual(result.rows, [{id: 'independent-result'}]);
  assert(f.calls.indexOf('all') < f.calls.indexOf('status')); assert(!f.calls.includes('start'));
  const staticPorts = ports({source: projectTemplateFiles('churn-risk-mock')['churn-risk.aql']});
  await runReleaseProjectNodeAction({...staticPorts.config, request: {kind: 'static', program: 'churn-risk.aql'}});
  assert(staticPorts.calls.includes('check') && staticPorts.calls.includes('plan'));
  assert(!staticPorts.calls.includes('start') && !staticPorts.calls.includes('approved'));
  assert.equal(staticPorts.calls.at(-1), 'close');
});

for (const template of ['churn-risk-mock', 'deal-review-mock']) test(`RC static ${template} keeps known invalid and protected unknown distinct before any Run`, async () => {
  const program = template.slice(0, -5) + '.aql', source = projectTemplateFiles(template)[program];
  const f = ports({source});
  const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'static', program}});
  assert.equal(f.checks.length, 3); assert.equal(f.checks[0].text, source);
  const variable = template === 'churn-risk-mock' ? 'risk' : 'review';
  assert.equal(f.checks[1].text, source.replace(variable + ".outcome = 'ok'", variable + '.outcome = 1'));
  assert.equal(f.checks[2].text, 'SELECT 1 AS id |> RESULT out |> EFFECT UPDATE private.unknown FROM RESULT out ID id SET (Name = 1)');
  for (const call of f.checks.slice(1)) assert.deepEqual(call.options, {kind: 'text', format: 'aql', scope: 'bound_input'});
  assert.deepEqual(result.staticChecks.map(value => value.check.report.verdict), ['invalid', 'undetermined']);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert(!f.calls.includes('start') && !f.calls.includes('approved'));
  assert.deepEqual(result.firstClose, {attempted: true, returned: true});
});

test('RC static refuses wrong causes, fabricated Requirements and changed original text while retaining first close', async () => {
  const program = 'churn-risk.aql', source = projectTemplateFiles('churn-risk-mock')[program];
  const changes = [
    value => {if (value.report.verdict === 'invalid') value.report.verdict = 'undetermined';},
    value => {if (value.report.verdict === 'undetermined') value.report.verdict = 'invalid';},
    value => {if (value.report.verdict === 'invalid') value.report.reasons = [];},
    value => {if (value.report.verdict === 'invalid') value.report.requirements = [{code: 'fabricated'}];},
    value => {if (value.report.verdict === 'undetermined') value.report.coverage = {};},
  ];
  for (const change of changes) {
    const f = ports({source, checkReply(value) {change(value); return value;}});
    await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'static', program}}));
    assert.equal(f.calls.filter(value => value === 'close').length, 1);
    assert(!f.calls.includes('start') && !f.calls.includes('approved'));
  }
  const f = ports({source});
  await assert.rejects(runReleaseProjectNodeAction({...f.config,
    getCheckInput: () => ({kind: 'text', text: source}), request: {kind: 'static', program}}), /original public check text/u);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert(!f.calls.includes('start'));
});
