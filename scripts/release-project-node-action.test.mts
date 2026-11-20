import assert from 'node:assert/strict';
import test from 'node:test';
import {runReleaseProjectNodeAction} from './release-project-node-action.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';
import {connectInProcess} from '../packages/sdk/index.mjs';

type Action = Parameters<typeof runReleaseProjectNodeAction>[0];
type Close = Parameters<Action['retainClose']>[0];
type Accepted = Parameters<Action['retainAccepted']>[0];
type Completed = Extract<Parameters<Action['getCheckInput']>[0], {outcome: 'completed'}>;
type Check = {outcome: string; report: {scope: {kind: string}; verdict: string;
  runnable?: {verdict: string}; reasons: unknown[]; requirements: unknown[]; coverage: object}};
type Options = {decisionFailure?: unknown; closeFailure?: unknown; closeObservationFailure?: unknown;
  closeObservationFailureAfterClose?: unknown; foreignCheckpoint?: boolean; source?: string;
  checkReply?: (value: Check, text: string) => Check; resolutionFields?: Record<string, string>; readonly?: boolean};
type AssertionFailure = {code: string; actual: unknown; expected: unknown};
type TransportFailure = {code: string; cause: unknown};
type CheckRequest = {kind: string; scope: string; input: unknown; parameters: unknown};

function ports({decisionFailure, closeFailure, closeObservationFailure, closeObservationFailureAfterClose, foreignCheckpoint = false,
  source = 'authored source', checkReply, resolutionFields = {}, readonly = false}: Options = {}) {
  const ref = {namespaceId: 'original-namespace', authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  const original = {ref, runId: 'original-run', checkpointId: 'original-checkpoint', checkpointCid: 'sha256:' + 'c'.repeat(64)};
  const calls: string[] = [], closes: Close[] = [], accepted: Accepted[] = [];
  const checks: {text: string; options: unknown}[] = [], checkInputs = new WeakMap<object, {kind: string; text: string}>();
  let status = readonly ? 'succeeded' : 'waiting_checkpoint';
  const state = () => ({version: 'actql-run-state/0.1', run_id: original.runId, status,
    checkpoint: {id: original.checkpointId, checkpoint_id: original.checkpointId, checkpoint_cid: original.checkpointCid}});
  const execution = {ref,
    async wait() {calls.push('wait'); return state();},
    async status() {calls.push('status'); return state();},
    async result(name: string) {assert.equal(name, readonly ? 'main' : 'updates'); calls.push('result'); return {
      async all() {calls.push('all'); return [{id: 'independent-result'}];},
      async describe() {calls.push('describe'); return {resultName: name, ref};},
    };},
  };
  const resolve = async (decision: 'approved' | 'rejected', args: string[]) => {
    assert.deepEqual(args, [original.checkpointId], 'Decide exactly the original first-wait Checkpoint');
    calls.push(decision);
    if (decisionFailure) throw decisionFailure;
    status = decision === 'approved' ? 'succeeded' : 'cancelled';
    return {results: [{status: 'committed'}], signed: [{resolutionWire: JSON.stringify({decision,
      run_id: original.runId, run_definition_cid: ref.runDefinitionCid,
      checkpoint_id: original.checkpointId, checkpoint_cid: original.checkpointCid,
      ...resolutionFields})}]};
  };
  const client = {
    async startSource(source: string, options: unknown) {assert.equal(source, 'authored source');
      assert.deepEqual(options, readonly ? {format: 'aql'} : {format: 'aql', stopBefore: 'commit'});
      calls.push('start'); return execution;},
    async attach(value: unknown) {assert.deepEqual(value, ref); calls.push('attach'); return execution;},
    async checkpoints({checkpointId}: {checkpointId: string}) {assert.equal(checkpointId, original.checkpointId); calls.push('checkpoints'); return {items: [{
      checkpointId, checkpointCid: foreignCheckpoint ? 'sha256:' + 'd'.repeat(64) : original.checkpointCid,
      subject: {kind: 'run_unit', runId: original.runId, runDefinitionCid: ref.runDefinitionCid},
    }]};},
    async reviewCheckpoint() {calls.push('review'); return {bytes: new TextEncoder().encode('original sealed review')};},
    approve: (...args: string[]) => resolve('approved', args), reject: (...args: string[]) => resolve('rejected', args),
    async check(text: string, options: unknown) {
      calls.push('check'); checks.push({text, options});
      const unknown = text.includes('EFFECT UPDATE private.unknown');
      const invalid = text.includes('.outcome = 1');
      const value = {outcome: 'completed', report: {scope: {kind: 'bound_input'},
        verdict: unknown ? 'undetermined' : invalid ? 'invalid' : 'verified',
        ...(readonly ? {runnable: {verdict: 'yes'}} : {}),
        reasons: invalid ? [{code: 'expression_domain_mismatch', facts: {domain: 'key_comparable_operands'}}] : [],
        requirements: [], coverage: unknown ? {limits: [{code: 'unresolved_protected'}]} : {limits: []}}};
      const result = checkReply ? checkReply(value, text) : value;
      checkInputs.set(result, {kind: 'text', text}); return result;
    },
    async plan() {calls.push('plan'); return {provider_io: 0};},
    async close() {calls.push('close'); if (closeFailure) throw closeFailure;},
  };
  return {original, calls, closes, accepted, checks, setStatus: (value: string) => {status = value;},
    // The port fixture supplies only the exercised public methods and fields.
    config: {async connect(options: Parameters<Action['connect']>[0]) {assert.deepEqual(options, {mode: 'local', installation: {directory: '.actql-node'}, profile: 'mock'}); calls.push('connect'); return client;},
      async readProgram() {calls.push('read-source'); return source;},
      getCheckInput(value: object, id: string) {assert.equal(id, 'source'); return checkInputs.get(value);},
      async retainAccepted(value: Accepted) {calls.push('retain-accepted'); accepted.push(value);},
      assertPendingTarget() {calls.push('pending-target');},
      retainClose(value: Close) {closes.push(value); if (closeObservationFailure) throw closeObservationFailure;
        if (value.outcome !== undefined && closeObservationFailureAfterClose) throw closeObservationFailureAfterClose;},
    } as unknown as Omit<Action, 'request'>};
}

test('RC immediate approval uses the same Client directly after wait without another async read', async () => {
  for (const decision of ['approved', 'rejected'] as const) {
    const f = ports();
    const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'start', decision}});
    assert.equal(result.state!.status, decision === 'approved' ? 'succeeded' : 'cancelled');
    assert.deepEqual(result.original, f.original);
    assert(f.calls.indexOf('retain-accepted') < f.calls.indexOf('wait'));
    assert(!f.calls.includes('checkpoints') && !f.calls.includes('review'));
    assert.deepEqual(f.calls.slice(f.calls.indexOf('wait') + 1, f.calls.indexOf(decision)), ['pending-target']);
    for (const operation of ['start', decision, 'close']) assert.equal(f.calls.filter(value => value === operation).length, 1);
    assert.equal(f.calls.filter(value => value === 'wait').length, 2);
    assert.deepEqual(f.accepted, [{ref: f.original.ref}]);
    assert.deepEqual(result.firstClose, {attempted: true, returned: true});
  }
  const asyncProbe = ports();
  await assert.rejects(runReleaseProjectNodeAction({...asyncProbe.config,
    assertPendingTarget: async () => {}, request: {kind: 'start', decision: 'approved'}}), /must be synchronous/u);
  assert(!asyncProbe.calls.includes('approved'));
});

test('RC readonly original checks and starts once without approval, then cold reads main before status', async () => {
  const f = ports({readonly: true});
  const value = await runReleaseProjectNodeAction({...f.config, request: {kind: 'read', program: 'original.aql'}});
  assert.deepEqual(value.original, {ref: f.original.ref, runId: f.original.runId});
  assert.equal(value.state!.status, 'succeeded'); assert.equal(value.description!.resultName, 'main');
  assert.deepEqual(value.rows, [{id: 'independent-result'}]);
  assert(f.calls.indexOf('check') < f.calls.indexOf('start'));
  assert(f.calls.indexOf('retain-accepted') < f.calls.indexOf('wait'));
  for (const operation of ['start', 'wait', 'result', 'close'])
    assert.equal(f.calls.filter(value => value === operation).length, 1);
  assert(!f.calls.some(value => ['approved', 'rejected', 'checkpoints', 'review'].includes(value)));
  const cold = ports({readonly: true});
  await runReleaseProjectNodeAction({...cold.config, request: {kind: 'result', original: value.original, resultName: 'main'}});
  assert(cold.calls.indexOf('all') < cold.calls.indexOf('status'));
  assert(!cold.calls.includes('start')); assert.equal(cold.calls.at(-1), 'close');
});

test('RC static and readonly checks reach actual SDK bound-text admission and preserve the first Host failure', async () => {
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'rc-check-admission', capabilities: [],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
  for (const kind of ['static', 'read'] as const) {
    const source = 'SELECT 1 AS n |> RESULT main',
      calls: {operation: string; body?: unknown}[] = [],
      closes: Close[] = [];
    const primary = new Error('original Host check failure');
    // This fixture omits reinspection because the original check rejects.
    await assert.rejects(runReleaseProjectNodeAction({request: {kind, program: 'original.aql'},
      async connect(options: Parameters<Action['connect']>[0]) {
        assert.deepEqual(options, {mode: 'local', installation: {directory: '.actql-node'}, profile: 'mock'});
        return connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
          calls.push({operation, body});
          if (operation === 'connect') return profile;
          if (operation === 'check') throw primary;
          assert.fail('Failed check must not plan, submit, decide or read Results');
        }, async close() {calls.push({operation: 'close'});}});
      },
      async readProgram() {return source;},
      retainAccepted() {assert.fail('Failed check must not create an accepted Run');},
      assertPendingTarget() {assert.fail('Failed check must not reach approval');},
      retainClose(value: Close) {closes.push(value);},
    } as unknown as Action), cause => (cause as TransportFailure).code === 'ClientTransportUnknown' &&
      (cause as TransportFailure).cause === primary);
    assert.deepEqual(calls.map(value => value.operation), ['connect', 'check', 'close']);
    assert.equal((calls[1].body as CheckRequest).kind, 'text');
    assert.equal((calls[1].body as CheckRequest).scope, 'bound_input');
    assert.deepEqual((calls[1].body as CheckRequest).input, {text: source, format: 'aql'});
    assert.equal((calls[1].body as CheckRequest).parameters, null);
    assert.equal(closes.length, 2);
    assert.deepEqual(closes.map(({attempted, returned}) => ({attempted, returned})),
      [{attempted: true, returned: false}, {attempted: true, returned: true}]);
  }
});

test('RC readonly refusal stops before submission and still closes its own Client', async () => {
  const f = ports({readonly: true, checkReply(value) {value.report.runnable!.verdict = 'no'; return value;}});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'read'}}));
  assert(!f.calls.includes('start')); assert(!f.calls.includes('wait')); assert.equal(f.accepted.length, 0);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
});

test('RC first close failure remains primary over a later failed close observation', async () => {
  const cleanup = new Error('original Client cleanup pending'), later = new Error('later observation failure');
  const f = ports({readonly: true, closeFailure: cleanup, closeObservationFailureAfterClose: later});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'read'}}), cause => cause === cleanup);
  assert.equal(f.calls.filter(value => value === 'start').length, 1);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert.deepEqual(f.closes.at(-1), {attempted: true, returned: false, outcome: 'threw'});
});

test('RC successful first close does not hide a failed later close observation', async () => {
  const later = new Error('original post-close observation failure');
  const f = ports({readonly: true, closeObservationFailureAfterClose: later});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'read'}}), cause => cause === later);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert.deepEqual(f.closes.at(-1), {attempted: true, returned: true, outcome: 'returned'});
});

for (const decision of ['approved', 'rejected'] as const) for (const field of ['checkpoint_id', 'checkpoint_cid'])
test(`RC immediate decision refuses foreign ${field} for ${decision}`, async () => {
  const foreign = field === 'checkpoint_id' ? 'foreign-checkpoint' : 'sha256:' + 'd'.repeat(64);
  const f = ports({resolutionFields: {[field]: foreign},
    closeFailure: new Error('later close failure'), closeObservationFailure: new Error('later observation failure')});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'start', decision}}), error => {
    assert.equal((error as AssertionFailure).code, 'ERR_ASSERTION');
    assert.equal((error as AssertionFailure).actual, foreign);
    assert.equal((error as AssertionFailure).expected, field === 'checkpoint_id' ? f.original.checkpointId : f.original.checkpointCid);
    return true;
  });
  for (const operation of ['start', decision, 'close', 'wait'])
    assert.equal(f.calls.filter(value => value === operation).length, 1);
  assert(!f.calls.includes('checkpoints') && !f.calls.includes('review'));
  assert.deepEqual(f.accepted, [{ref: f.original.ref}]);
  assert.equal(f.closes.at(-1)!.returned, false); assert.equal(f.closes.at(-1)!.outcome, 'threw');
});

test('RC original resolution failure remains primary across failed close and observation', async () => {
  const primary = new Error('original uncertain resolution'), cleanup = new Error('original close pending');
  const f = ports({decisionFailure: primary, closeFailure: cleanup, closeObservationFailure: new Error('observation failure')});
  await assert.rejects(runReleaseProjectNodeAction({...f.config, request: {kind: 'start', decision: 'approved'}}), value => value === primary);
  assert.equal(f.calls.filter(value => value === 'approved').length, 1);
  assert.equal(f.calls.filter(value => value === 'start').length, 1);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert.equal(f.closes.at(-1)!.returned, false); assert.equal(f.closes.at(-1)!.outcome, 'threw');
  assert.equal(f.accepted.length, 1);
});

test('RC cold resolution selects only the original public checkpoint without reprepare', async () => {
  const f = ports();
  const result = await runReleaseProjectNodeAction({...f.config, request: {kind: 'resolve', original: f.original, decision: 'rejected'}});
  assert.equal(result.state!.status, 'cancelled'); assert(!f.calls.includes('start'));
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
  for (const call of f.checks) assert.deepEqual(call.options, {kind: 'text', format: 'aql', scope: 'bound_input'});
  assert.deepEqual(result.staticChecks!.map(value => (value.check as Completed).report.verdict), ['invalid', 'undetermined']);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert(!f.calls.includes('start') && !f.calls.includes('approved'));
  assert.deepEqual(result.firstClose, {attempted: true, returned: true});
});

test('RC static refuses wrong causes, fabricated Requirements and changed original text while retaining first close', async () => {
  const program = 'churn-risk.aql', source = projectTemplateFiles('churn-risk-mock')[program];
  const changes: ((value: Check) => void)[] = [
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
    getCheckInput: () => ({kind: 'text', text: source}) as ReturnType<Action['getCheckInput']>,
    request: {kind: 'static', program}}), /original public check text/u);
  assert.equal(f.calls.filter(value => value === 'close').length, 1);
  assert(!f.calls.includes('start'));
});
