import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {graphResultDataPolicy} from '../../scripts/fixtures/graph-infer-effect-input.mjs';
import {acquisitionEndHandoff, acquisitionFailure} from
  '../host-common/acquisition-outcome.mjs';
import {openAcquiredEffectComputation} from './fixtures/acquired-effect-computation.fixture.mjs';
import {openAcquiredEffectComputation as openEffectComputation} from './acquired-effect-computation.mjs';


test('source-free composed Model admission retains custody without opening an installed Source', async () => {
  const prepared = {};
  const request = {}, managedRun = {}, operationPlan = {};
  const failure = new Error('ModelOwnerUnavailable');
  let custody;
  let sourceCalls = 0, planReads = 0;
  const resultPolicy = graphResultDataPolicy;
  const policyLimits = Object.freeze({maxWireBytes: 1024, maxNodes: 100, maxDepth: 8});
  // These nominal Plan/Request ports remain explicit. This failure fixture
  // stops before Common admission or a physical Model/Source constructor.
  const moon = {clientProgramInferPlanBoundary: () => ({_0: 0}),
    clientProgramEffectSerializationOccurrences: () => [], clientProgramEffectAcquisitionCount(actual) {
      assert.equal(actual, prepared);
      return 0;
    }, clientProgramInstalledEffectManagedOperationPlan(parent, actual, identity) {
      assert.equal(this, moon);
      assert.equal(parent, managedRun);
      assert.equal(actual, prepared);
      assert.equal(identity, request);
      assert.ok(custody, 'retain the same computation owner before reading its original Plan');
      planReads++;
      return {$tag: 1, _0: operationPlan};
    }, clientProgramInstalledEffectManagedHostOpen() {
      assert.fail('Model admission failure must not construct a Compute Host');
    }};
  await assert.rejects(openAcquiredEffectComputation({
    modelController: {discover: () => []},
    moon, managedRun,
    acquired: {prepared, requestIdentity: request,
      resultDataPolicy: resultPolicy, resultDataPolicyLimits: policyLimits,
      control: {runDefinitionRunId: () => 'fixture-run', adoptCheckedClientEffectInferRun(allowed, definition, policy, limits) {
        assert.equal(policy, resultPolicy);
        assert.equal(limits, policyLimits);
        assert.ok(custody);
        throw failure;
      }}},
    infer: {occurrence: {}}, now: () => '2026-10-04T00:00:00.000Z',
    retainComputationOwner(value) { custody = value; },
    sourceProfile: {sources: Array.from({length: 3}, () => ({
      admitsSource() { sourceCalls++; throw new Error('UnexpectedSourceSelection'); },
      prepare() { sourceCalls++; throw new Error('UnexpectedSourcePreparation'); },
      open() { sourceCalls++; throw new Error('UnexpectedSourceOpen'); },
    }))},
  }), error => error === failure);
  assert.equal(planReads, 1);
  assert.equal(sourceCalls, 0);
  assert.equal(await custody.cleanup(), false);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
});

test('rejected original preparation retain settles only the newly captured cleanup owner', async () => {
  const failure = new Error('ForeignInstalledModelPreparation');
  let custody, retains = 0, retirements = 0, prepares = 0, reads = 0, closes = 0;
  const preparation = Object.freeze({retain() {retains++; throw failure;},
    retire() {retirements++; assert.fail('A rejected borrow cannot retire another holder');}});
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared: {}}, originalPreparation: preparation,
    retainComputationOwner(owner) {custody = owner;},
    sourceProfile: {prepare() {prepares++;}, open() {reads++;}},
    sourceContinuation: {close() {closes++;}},
  }), error => error === failure);
  assert.equal(retains, 1);
  assert.equal(custody.cleanupPending(), true);
  assert.equal(await custody.cleanup(), false, 'settlement is not an original close');
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
  assert.equal(await custody.cleanup(), true);
  assert.deepEqual({retirements, prepares, reads, closes}, {retirements:0, prepares:0, reads:0, closes:1});
});

test('successful original preparation retain keeps its same retirement until acknowledgement', async () => {
  const failure = new Error('OriginalSourcePreparationUnavailable');
  let custody, retains = 0, retirements = 0, prepares = 0, reads = 0, closes = 0;
  const preparation = Object.freeze({retain() {assert.equal(this, preparation); retains++;},
    async retire() {assert.equal(this, preparation); return ++retirements > 1;}});
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared: {}}, originalPreparation: preparation,
    retainComputationOwner(owner) {custody = owner;},
    sourceProfile: {prepare() {prepares++; throw failure;}, open() {reads++;}},
    sourceContinuation: {accessFor: access => access, close() {closes++;}},
  }), error => error === failure);
  assert.equal(retains, 1);
  await custody.close();
  assert.equal(await custody.cleanup(), false);
  assert.equal(custody.cleanupPending(), true);
  assert.equal(closes, 0, 'the pending original retains the continuation');
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
  assert.equal(await custody.cleanup(), true);
  assert.deepEqual({retirements, prepares, reads, closes}, {retirements:2, prepares:1, reads:0, closes:1});
});

test('acquisition end handoff rejects an unissued or conflicting statement',
  () => {
    const handoff = acquisitionEndHandoff();
    assert.throws(() => handoff.retain(new Error('Unissued')),
      {message: 'InvalidAcquisitionEndHandoff'});
    assert.equal(handoff.outcome(new Error('Wrapped')).outcome, 'unknown');
    const first = acquisitionFailure(new Error('ReadLost'), 'stopped');
    assert.equal(handoff.retain(first), first);
    assert.equal(handoff.retain(first), first);
    assert.throws(() => handoff.retain(acquisitionFailure(
      new Error('OtherRead'), 'not_started')),
    {message: 'InvalidAcquisitionEndHandoff'});
    assert.equal(handoff.outcome(new Error('Wrapped')).outcome, 'stopped');
  });

for (const outcome of ['not_started', 'stopped', 'unknown']) {
  test(`acquired Effect opening keeps the adapter's ${outcome} observation`,
    async () => {
      let retained;
      let reads = 0;
      let prepares = 0;
      const failure = new Error('ReadUnavailable');
      const prepared = {};
      const selection = {status: 'selected', selectedCandidate: 'nativeQuery'};
      const preparedSource = {selection};
      const observations = [];
      await assert.rejects(openAcquiredEffectComputation({
        acquired: {prepared}, now: () => '2026-09-29T00:00:00.000Z',
        retainComputationOwner(owner) { retained = owner; },
        observe(name, detail) { observations.push({name, detail}); },
        sourceProfile: {
          async prepare({preparedEffect, preparedProgram}) {
            prepares++;
            assert.equal(retained.cleanupPending(), true);
            assert.equal(preparedEffect, prepared);
            assert.equal(preparedProgram, undefined);
            return preparedSource;
          },
          async open(options) {
            reads++;
            assert.equal(options.preparedSource, preparedSource);
            throw acquisitionFailure(failure, outcome);
          },
        },
      }), error => error.cause === failure);
      await retained.close();
      assert.equal(await retained.cleanup(), outcome !== 'unknown');
      assert.equal(retained.cleanupPending(), outcome === 'unknown');
      assert.equal(prepares, 1);
      assert.equal(reads, 1);
      assert.deepEqual(observations, [{name: 'acquisition_started', detail: {task: 0, selection}}],
        'a failed physical acquisition must not emit a completed selection');
    });
}

test('acquired Effect cleanup retries the recovery owner without another read',
  async () => {
    let retained;
    let reads = 0;
    let cleanups = 0;
    let pending = true;
    const failure = new Error('TransportStopUnconfirmed');
    const recovery = {
      async close() { throw new Error('FirstCloseFailed'); },
      async cleanup() {
        cleanups++;
        if (cleanups === 1) return false;
        pending = false;
        return true;
      },
      cleanupPending: () => pending,
    };
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { return {}; }, open() {
        reads++;
        throw acquisitionFailure(failure, 'unknown', recovery);
      }},
    }), error => error.cause === failure);
    await assert.rejects(retained.close(), {message: 'FirstCloseFailed'});
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 1);
  });

test('acquired Effect retains a reported recovery owner across error wrapping',
  async () => {
    let retained;
    let reads = 0;
    let pending = true;
    let closes = 0;
    const recovery = {async close() { closes++; },
      async cleanup() { return !pending; },
      cleanupPending: () => pending};
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { return {}; },
        open({reportAcquisitionFailure}) {
          reads++;
          const failure = acquisitionFailure(new Error('ReadLost'),
            'unknown', recovery);
          reportAcquisitionFailure(failure);
          throw new Error('AdapterBoundaryFailed', {cause: failure});
        }},
    }), {message: 'AdapterBoundaryFailed'});
    await retained.close();
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
    pending = false;
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 1);
    assert.equal(closes, 1);
  });

test('acquired Effect preparation failure is not an unobserved acquisition',
  async () => {
    let retained;
    let reads = 0;
    await assert.rejects(openAcquiredEffectComputation({acquired: {prepared: {}},
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { throw new Error('ForeignCheckedSource'); },
        open() { reads++; }},
    }), {message: 'ForeignCheckedSource'});
    await retained.close();
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 0);
  });

test('a stale Source admission is not an unknown provider acquisition', async () => {
  let retained;
  let reads = 0;
  let closes = 0;
  const observations = [];
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
    retainComputationOwner(owner) { retained = owner; },
    observe(name) { observations.push(name); },
    sourceProfile: {prepare: () => ({}), open() { reads++; }},
    sourceContinuation: {
      accessFor: access => access, prepared() {}, times: () => ({}),
      beforeRead: () => ({enter() { throw new Error('StaleResumeClaim'); }}),
      close() { closes++; },
    },
  }), {message: 'StaleResumeClaim'});
  await retained.close();
  assert.equal(await retained.cleanup(), true);
  assert.equal(retained.cleanupPending(), false);
  assert.equal(reads, 0);
  assert.equal(closes, 1);
  assert.deepEqual(observations, [], 'a refused original admission is not a Source attempt');
});

test('retained Source restoration is not a new adapter attempt even when it refuses', async () => {
  let retained;
  let reads = 0;
  let closes = 0;
  const observations = [];
  const refusal = new Error('RetainedOriginalUnavailable');
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
    retainComputationOwner(owner) {retained = owner;},
    observe(name) {observations.push(name);},
    sourceProfile: {prepare: () => ({}), open() {reads++;}},
    sourceContinuation: {
      accessFor: access => access, prepared() {}, times: () => ({}),
      beforeRead: () => ({retained: {}}),
      restore() {throw refusal;}, close() {closes++;},
    },
  }), error => error === refusal);
  await retained.close();
  assert.equal(await retained.cleanup(), true);
  assert.equal(retained.cleanupPending(), false);
  assert.equal(reads, 0);
  assert.equal(closes, 1);
  assert.deepEqual(observations, []);
});

test('source evidence failure retains capture cleanup until release succeeds',
  async () => {
    let retained;
    let reads = 0;
    let closes = 0;
    const selection = {status: 'selected', selectedCandidate: 'broadQuery'};
    const observations = [];
    const primary = new Error('SourceEvidenceUnavailable');
    const cleanupFailure = new Error('SourceReleaseUnavailable');
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}, authorityScopeCid: 'scope'},
      now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      observe(name, detail) { observations.push({name, detail}); },
      sourceProfile: {prepare() { return {selection}; }, open() {
        reads++;
        return {
          checkedSource: {sourceDataPolicyCid: 'policy'},
          acquisition: {selection},
          issueSourceEvidence() { throw primary; },
          close() {
            closes++;
            if (closes === 1) throw cleanupFailure;
          },
        };
      }},
    }), error => error === primary);
    await retained.close();
    await assert.rejects(retained.cleanup(), error => error === cleanupFailure);
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    await retained.close();
    assert.equal(await retained.cleanup(), true);
    assert.equal(reads, 1);
    assert.equal(closes, 2);
    assert.deepEqual(observations, [
      {name: 'acquisition_started', detail: {task: 0, selection}},
      {name: 'acquisition_completed', detail: {task: 0, acquisition: {selection}}},
    ], 'cleanup retries do not emit another physical acquisition');
  });

test('two-of-three Effect preparation retains custody before either selected read can start', async () => {
  const prepared = {};
  const failure = new Error('SecondSourcePreparationUnavailable');
  let custody;
  let reads = 0;
  const preparedTasks = [];
  const sources = [0, 1].map(task => {
    const access = {name: `source-${task}`};
    return {
      realizationKey: 'duckdb-acquired', sourceAccess: access,
      admitsSource: ref => ref === `source-${task}`,
      async prepare(options) {
        assert.equal(custody.cleanupPending(), true);
        assert.equal(options.preparedEffect, prepared);
        assert.equal(options.sourceAccess, access);
        assert.deepEqual(options.occurrence, {stage: task, input: 0, task});
        preparedTasks.push(task);
        if (task === 1) throw failure;
        return {};
      },
      async open() { reads++; throw new Error('UnexpectedRead'); },
    };
  });
  sources.splice(1, 0, {
    realizationKey: 'installed-row-source',
    admitsSource: ref => ref === 'unused',
    prepare() { assert.fail('UnusedSourcePreparation'); },
    open() { assert.fail('UnusedSourceRead'); },
    resolveSecret() { assert.fail('UnusedSourceSecret'); },
  });
  await assert.rejects(openAcquiredEffectComputation({
    moon: {
      clientProgramEffectAcquisitionCount: () => 2,
    },
    sourceRefs: ['source-0', 'source-1'],
    owner: {}, acquired: {prepared}, sourceProfile: {sources},
    retainComputationOwner(value) { custody = value; },
  }), error => error === failure);
  assert.deepEqual(preparedTasks, [0, 1]);
  assert.equal(reads, 0);
  assert.equal(await custody.cleanup(), false);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
});

test('one-of-three Effect opens only its checked Source and preserves its access and capture custody', async () => {
  const prepared = {};
  const access = {authorization: {authorize() { assert.fail('UnexpectedReadGate'); }}};
  const approvedAccess = {authorization: {authorize() { assert.fail('UnexpectedApprovalGate'); }}};
  const failure = new Error('EvidenceUnavailable');
  const operations = [];
  let custody;
  const untouched = ref => ({realizationKey: 'installed-row-source',
    admitsSource: value => value === ref,
    prepare() { operations.push(`${ref}:prepare`); assert.fail('UnusedPreparation'); },
    open() { operations.push(`${ref}:read`); assert.fail('UnusedRead'); },
    resolveSecret() { operations.push(`${ref}:secret`); assert.fail('UnusedSecret'); }});
  const source = {realizationKey: 'duckdb-acquired', sourceAccess: access,
    admitsSource: ref => ref === 'selected',
    prepare(options) {
      operations.push('prepare');
      assert.equal(options.preparedEffect, prepared);
      assert.equal(options.sourceAccess, approvedAccess);
      return {};
    },
    open(options) {
      operations.push('read');
      assert.equal(options.sourceAccess, approvedAccess);
      assert.equal(options.preparedEffect, prepared);
      return {checkedSource: {sourceDataPolicyCid: 'policy'},
        issueSourceEvidence() { throw failure; },
        close() { operations.push('release'); }};
    }};
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared, authorityScopeCid: 'scope'},
    sourceProfile: {realizationKey: 'installed-multi-acquired',
      sources: [untouched('unused-first'), source, untouched('unused-last')]},
    retainComputationOwner(value) { custody = value; },
    now: () => '2026-10-07T00:00:00.000Z',
    sourceContinuation: {
      accessFor(actual, occurrence) {
        assert.equal(actual, access);
        assert.deepEqual(occurrence, {stage: 0, input: 0, task: 0});
        return approvedAccess;
      },
      prepared(sources) { assert.deepEqual(sources.map(value => value.adapter), [source]); },
      times: () => ({}), beforeRead: () => ({enter() { operations.push('enter'); }}),
      close() { operations.push('continuation-release'); },
    },
  }), error => error === failure);
  assert.deepEqual(operations, ['prepare', 'enter', 'read']);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.deepEqual(operations, ['prepare', 'enter', 'read', 'release', 'continuation-release']);
});

for (const fault of ['duplicate-owner', 'unsupported-realization', 'ambiguous-owner', 'missing-owner']) {
  test(`selected Effect ${fault} rejects before any preparation or provider I/O`, async () => {
    let custody;
    const calls = [];
    const adapter = (name, refs, realizationKey = 'duckdb-acquired') => ({realizationKey,
      admitsSource: ref => refs.includes(ref),
      prepare() { calls.push(`${name}:prepare`); }, open() { calls.push(`${name}:open`); },
      resolveSecret() { calls.push(`${name}:secret`); }});
    const first = adapter('first', fault === 'duplicate-owner' ? ['first', 'second'] : ['first']);
    const second = adapter('second', fault === 'duplicate-owner' || fault === 'missing-owner'
      ? ['other'] : ['second'], fault === 'unsupported-realization' ? 'installed-row-source' : undefined);
    const unused = adapter('unused', fault === 'ambiguous-owner' ? ['second'] : ['unused']);
    await assert.rejects(openAcquiredEffectComputation({
      moon: {clientProgramEffectAcquisitionCount: () => 2},
      sourceRefs: ['first', 'second'],
      // This negative retains a valid typed Row capture but rejects its
      // unsupported Host realization before any adapter preparation or I/O.
      rowSourceTasks: fault === 'unsupported-realization' ? [1] : [],
      acquired: {prepared: {}}, sourceProfile: {sources: [first, unused, second]},
      retainComputationOwner(value) { custody = value; },
    }), {message: fault === 'duplicate-owner' ? 'DuplicateEffectSourceOwner'
      : fault === 'unsupported-realization' ? 'UnsupportedEffectSourceRealization'
        : 'InstalledSourceProgramMismatch'});
    assert.deepEqual(calls, []);
    await custody.close();
    assert.equal(await custody.cleanup(), true);
  });
}

test('three Effect acquisitions remain unsupported with three installed Sources', async () => {
  await assert.rejects(openEffectComputation({
    moon: {clientProgramEffectAcquisitionCount: () => 3}, acquired: {prepared: {}},
    sourceProfile: {sources: [{}, {}, {}]},
    retainComputationOwner() { assert.fail('UnsupportedAcquisitionCount'); },
  }), {message: 'InvalidAcquiredEffectComputationPort'});
});


// Execute the actual retained custody declaration with explicit original Core
// ports. No callbacks, Program, Ledger or physical stop are manufactured here;
// the fixed fixtures represent an already closed/settled child at this seam.
function acquiredCleanupFixture({dagRetired = true, physicalReady = true, keyedReady} = {}) {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = ast.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openAcquiredEffectComputation');
  const custody = declaration.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(item => item.id.name === 'custody'));
  assert.ok(custody);
  const events = [], checkedHost = {};
  const moon = {clientProgramRefreshAcquiredEffectCleanup(value) {
    assert.strictEqual(value, checkedHost); events.push('dag-retirement'); return dagRetired;
  }};
  const physical = {async cleanup() {events.push('physical'); return physicalReady;},
    cleanupPending() {events.push('physical-pending'); return !physicalReady;}};
  const keyed = keyedReady === undefined ? undefined : {
    async cleanup() {events.push('keyed'); return keyedReady;}, cleanupPending:() => !keyedReady};
  const value = new Function('moon', 'checkedHost', 'execution', 'keyedCleanup', `
    let pending=true,closed=true,settled=true,unresolved=false;
    let recovery,contentFamily,contentFamilyCleanup,contentRecovery,sourceContinuation,modelToken,restoredModelOutput;
    const restoredModelHostAttempted=false;
    const captures=[]; let originalPreparationRetained=false;
    const cleanupInfer=async()=>true; const observeUsage=()=>{};
    ${source.slice(custody.start, custody.end)}
    return custody;
  `)(moon, checkedHost, physical, keyed);
  return {value, events};
}

test('acquired Effect cleanup uses original DAG retirement after physical cleanup', async () => {
  const fixture = acquiredCleanupFixture();
  assert.equal(await fixture.value.cleanup(), true);
  assert.equal(fixture.value.cleanupPending(), false);
  assert.deepEqual(fixture.events, ['physical', 'physical-pending', 'dag-retirement']);
  assert.equal(await fixture.value.cleanup(), true);
  assert.equal(fixture.events.length, 3, 'Settled custody repeats no cleanup or aggregate accounting');
});

test('acquired Effect cleanup waits for the same keyed owner before DAG retirement', async () => {
  const pending = acquiredCleanupFixture({keyedReady:false});
  assert.equal(await pending.value.cleanup(), false);
  assert.deepEqual(pending.events, ['physical', 'physical-pending', 'keyed']);
  const complete = acquiredCleanupFixture({keyedReady:true});
  assert.equal(await complete.value.cleanup(), true);
  assert.deepEqual(complete.events, ['physical', 'physical-pending', 'keyed', 'dag-retirement']);
});

test('original composed Model binds only after the same completed keyed Source closure is admitted', () => {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const declaration = tree.body.map(node => node.declaration ?? node).find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === 'openAcquiredEffectComputation');
  const original = declaration.body.body.find(node => node.type === 'TryStatement').block.body;
  const prepare = original.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'prepareInferComponent'));
  assert(prepare);
  const occurrence = {}, captures = [{}, {}], sourceEvidence = [{}, {}], observation = {}, closure = {};
  const compiled = {}, runDefinition = {}, scope = {}, selected = {}, capturedInput = {}, result = {};
  const evidence = sourceEvidence.map(value => ({sourceEvidence:value}));
  const infer = {occurrence}, keyedFamily = {observation, capturedInput};
  const modelPlan = {compiled, runDefinition}, originalPreparation = {scope};
  let binds = 0, admissions = 0, refuse = false;
  const primary = new Error('OriginalSourceClosureRefused');
  const acquired = {authorityScopeCid:'authority', control:{admitComposedInferSources(...args) {
    admissions++;
    assert.deepEqual(args, [occurrence, captures, sourceEvidence, 'authority', 'start', 'complete', observation]);
    if (refuse) throw primary;
    return closure;
  }}};
  const originalModelComponent = {bindOriginal(context) {
    binds++; assert.equal(context.sources, closure); assert.equal(context.selected, selected);
    assert.equal(context.originalPreparation, originalPreparation); assert.equal(context.plan, modelPlan);
    assert.equal(context.capturedInput, capturedInput); return result;
  }};
  const run = new Function('p', `const {infer,captures,evidence,keyedFamily,
    originalPreparation,originalModelComponent,acquired,originalModelSelection}=p;
    let modelPlan=p.modelPlan;
    const current=()=>{},sourceFree=false,multiple=true,contentFamily=undefined;
    const restoredModelInput=undefined,modelToken=undefined,modelController=undefined;
    const principalId='fixture',signal=undefined,now=()=>{},moon={};
    const captureStartedAt='start',captureCompletedAt='complete';
    let inferOperation,inferCapture;
    ${source.slice(prepare.start, prepare.end)}
    return prepareInferComponent();`);
  const inputs = {infer,captures,evidence,keyedFamily,modelPlan,originalPreparation,
    originalModelComponent,acquired,originalModelSelection:selected};
  assert.equal(run(inputs), result); assert.deepEqual({admissions,binds}, {admissions:1,binds:1});
  refuse = true;
  assert.throws(() => run(inputs), error => error === primary);
  assert.deepEqual({admissions,binds}, {admissions:2,binds:1});
});

for (const [name, options] of [
  ['original DAG still retiring', {dagRetired: false}],
  ['physical child still pending', {physicalReady: false}],
]) test(`acquired Effect task retirement keeps ${name} pending`, async () => {
  const fixture = acquiredCleanupFixture(options);
  assert.equal(await fixture.value.cleanup(), false);
  assert.equal(fixture.value.cleanupPending(), true);
  if (options.physicalReady === false) assert.deepEqual(fixture.events, ['physical']);
});


// Actual cleanup and successful publication block, extracted unchanged. The
// Core/Store/Task owner ports are explicit; this is not ordinary funding proof.
function persistedModelScratchFixture({retire = true, releaseFailure, heldOutput = false} = {}) {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = ast.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openAcquiredEffectComputation');
  const cleanup = declaration.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'cleanupInfer'));
  const main = declaration.body.body.find(node => node.type === 'TryStatement');
  const persisted = main.block.body.find(node => node.type === 'IfStatement' &&
    source.slice(node.start, node.end).includes('(await inferCapture.persist()).plan'));
  assert.ok(cleanup && persisted);
  const events = [], plan = {}, content = {live: true};
  let modelClosed = false;
  const inferCapture = {persist: async () => {events.push('persist'); return {plan};},
    custody: {retirePublication: async () => {events.push('retire-publication'); return retire;},
      close: async () => {events.push('close-model'); modelClosed = true;},
      cleanupPending: () => !modelClosed}};
  const inferOperation = {publicationCapacityPending: () => true,
    releaseOriginalPublicationCapacity() {
      events.push('release-capacity');
      if (releaseFailure !== undefined) releaseFailure();
      return true;
    }};
  const execution = {async refreshCompletedScratch() {
    assert.strictEqual(this, execution); assert.equal(modelClosed, true);
    events.push('refresh-original-scratch'); assert.equal(content.live, true);
  }};
  const run = new Function('inferCapture', 'inferOperation', 'execution', 'events', `
    let inferReleased=false,inferCloseAttempted=false,modelReleased=false,modelCloseAttempted=false;
    const modelContinuation={close(){throw Error('same journal continuation must remain');}};
    const originalPreparation={},component={},restoredModelOutput=${heldOutput ? '{}' : 'undefined'};
    let publicationPlan;
    const current=()=>{};
    const faultInjection=async()=>{events.push('capture-committed');};
    ${source.slice(cleanup.start, cleanup.end)}
    return async()=>{${source.slice(persisted.start, persisted.end)} return publicationPlan;};
  `)(inferCapture, inferOperation, execution, events);
  return {run, events, plan, content, inferCapture};
}

test('persisted original Model retires its aliases before scratch refresh while Content and journal remain', async () => {
  const f = persistedModelScratchFixture();
  assert.strictEqual(await f.run(), f.plan);
  assert.deepEqual(f.events, ['persist', 'retire-publication', 'release-capacity',
    'close-model', 'refresh-original-scratch', 'capture-committed']);
  assert.equal(f.content.live, true);
});

test('pending original Model publication keeps aliases and forbids scratch refresh', async () => {
  const f = persistedModelScratchFixture({retire: false});
  await assert.rejects(f.run(), {code: 'ClientDispatchCleanupPending'});
  assert.deepEqual(f.events, ['persist', 'retire-publication']);
  assert.equal(f.inferCapture.custody.cleanupPending(), true);
  assert.equal(f.content.live, true);
});

test('original Model alias retirement preserves thrown undefined null and Error before refresh', async () => {
  for (const original of [undefined, null, new Error('original Model retirement')]) {
    const f = persistedModelScratchFixture({releaseFailure() {throw original;}});
    let rejected = false;
    try {await f.run();} catch (error) {rejected = true; assert.strictEqual(error, original);}
    assert.equal(rejected, true);
    assert.deepEqual(f.events, ['persist', 'retire-publication', 'release-capacity']);
    assert.equal(f.content.live, true);
  }
});


// Actual source/evidence and Model component caller fragments. Core funding,
// admitted evidence and physical Source ports remain explicit here.
const inferSourceText = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
const inferSourceNodes = [];
(function walk(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type) inferSourceNodes.push(node);
  for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(walk);
  else if (value && typeof value === 'object') walk(value);
})(parse(inferSourceText, {ecmaVersion: 'latest', sourceType: 'module'}));
const declares = (node, name) => node.type === 'VariableDeclaration' &&
  node.declarations.some(value => value.id.name === name);
const sourceEvidenceBlock = inferSourceNodes.filter(node => node.type === 'BlockStatement' &&
  node.body.some(value => declares(value, 'sourceEvidenceOptions')));
assert.equal(sourceEvidenceBlock.length, 1);
const sourceEvidenceStatements = sourceEvidenceBlock[0].body;
const evidenceFirst = sourceEvidenceStatements.findIndex(node => declares(node, 'sourceEvidenceOptions'));
const evidenceLast = sourceEvidenceStatements.findIndex(node => node.type === 'ExpressionStatement' &&
  inferSourceText.slice(node.start, node.end).startsWith('await sourceContinuation?.captured('));
assert(evidenceLast > evidenceFirst);
const evidenceSource = inferSourceText.slice(sourceEvidenceStatements[evidenceFirst].start,
  sourceEvidenceStatements[evidenceLast].end);
const inferComponentNode = inferSourceNodes.filter(node => node.type === 'VariableDeclarator' &&
  node.id.name === 'prepareInferComponent');
assert.equal(inferComponentNode.length, 1);

function sourceOriginalFixture({changedDuringPreparation = false} = {}) {
  const capture = {}, original = Object.freeze({wire: 'original-source-evidence'}), evidence = [];
  const calls = [], stale = new Error('original-Source-no-longer-current');
  let current = true;
  const ports = {infer: {}, captured: {capture, checkedSource: {sourceDataPolicyCid: 'original-policy'},
    async prepareSourceEvidenceOriginal(options) {
      assert.deepEqual(options, {authorityScopeCid: 'original-scope', effectiveDataPolicyCid: 'original-policy'});
      calls.push('prepare'); if (changedDuringPreparation) current = false;
    }, issueSourceEvidence() {assert.fail('do not reissue the same original evidence through its wire port');}},
    acquired: {authorityScopeCid: 'original-scope', control: {takeSourceEvidenceOriginal(value) {
      assert.strictEqual(value, capture); assert(current); calls.push('take'); return original;
    }}},
    current() {if (!current) throw stale;}, evidence,
    source: {}, captureStartedAt: 'start', now: () => 'end', sourceContinuation: {captured(source, captured, wire, start, end) {
      assert.strictEqual(source, ports.source); assert.strictEqual(captured, ports.captured);
      assert.equal(wire, original.wire); assert.deepEqual([start, end], ['start', 'end']); calls.push('continuation');
    }}};
  const invoke = new Function(...Object.keys(ports), 'return (async()=>{' + evidenceSource + '})();');
  return {invoke: () => invoke(...Object.values(ports)), evidence, original, calls, stale};
}

test('acquired Model Source transfers its one original evidence and derives only the continuation wire', async () => {
  const f = sourceOriginalFixture(); await f.invoke();
  assert.deepEqual(f.calls, ['prepare', 'take', 'continuation']);
  assert.equal(f.evidence.length, 1);
  assert.strictEqual(f.evidence[0].sourceEvidence, f.original);
  assert.equal(f.evidence[0].sourceEvidenceWire, f.original.wire);
});

test('acquired Model Source rechecks current after evidence preparation before transferring the original', async () => {
  const f = sourceOriginalFixture({changedDuringPreparation: true});
  await assert.rejects(f.invoke, error => error === f.stale);
  assert.deepEqual(f.calls, ['prepare']); assert.deepEqual(f.evidence, []);
});

function inferOriginalComponentFixture({refusal} = {}) {
  const captures = [{logicalInput: {}}, {logicalInput: {}}], originals = [{}, {}];
  const evidence = originals.map(sourceEvidence => ({sourceEvidence}));
  const occurrence = {}, admitted = {}, compiled = {}, operation = {}, custody = {};
  const calls = [];
  const control = {admitComposedInferSources(actual, sources, values, scope, start, end) {
    assert.strictEqual(actual, occurrence); assert.strictEqual(sources, captures);
    assert.strictEqual(values[0], originals[0]); assert.strictEqual(values[1], originals[1]);
    assert.deepEqual([scope, start, end], ['scope', 'start', 'end']); calls.push('admit');
    if (refusal !== undefined) throw refusal; return admitted;
  }, adoptCheckedClientEffectInferRun() {calls.push('compiled'); return compiled;},
  admitRunEvidence() {assert.fail('the same transferred evidence is not reparsed');}};
  const acquired = {control, prepared: {}, allowed: {}, runDefinition: {}, authorityScopeCid: 'scope'};
  const ports = {current() {}, infer: {occurrence}, multiple: true, sourceFree: false,
    contentFamily: undefined, evidence, captures, acquired, captureStartedAt: 'start', captureCompletedAt: 'end',
    moon: {clientProgramAdmitComposedInferSources() {assert.fail('the facade must unwrap actual evidence tokens');},
      strategyRunEvidenceJson() {assert.fail('an original logical input is not a String argument');}},
    modelToken: undefined, restoredModelInput: undefined, originalModelSelection: undefined,
    originalPreparation: undefined, principalId: 'principal', signal: undefined, now: () => 'now', store: {},
    modelController: undefined, modelRecord: undefined, faultInjection: undefined,
    openNodeInferCaptureCustody(facts) {
      assert.strictEqual(facts.operation, operation); assert.strictEqual(facts.sourceEvidence[0], originals[0]);
      assert.strictEqual(facts.sourceEvidence[1], originals[1]); calls.push('retain'); return custody;
    }, openNodeComposedInferProvider(context) {
      assert.strictEqual(context.sources, admitted); assert.strictEqual(context.plan.compiled, compiled);
      assert.strictEqual(context.control, control); calls.push('provider'); context.retainOperation(operation); return operation;
    }, originalModelComponent: undefined, keyedFamily: undefined};
  const actual = inferSourceText.slice(inferComponentNode[0].init.start, inferComponentNode[0].init.end);
  const invoke = new Function(...Object.keys(ports), 'let modelPlan,inferOperation,inferCapture,restoredKeyedSource;return (' + actual + ')();');
  return {invoke: () => invoke(...Object.values(ports)), operation, calls};
}

test('acquired Model joins and publishes the same transferred evidence through the existing typed facade', () => {
  const f = inferOriginalComponentFixture(); assert.strictEqual(f.invoke(), f.operation);
  assert.deepEqual(f.calls, ['admit', 'compiled', 'provider', 'retain']);
});

test('acquired Model preserves its original typed Source refusal without provider or wire fallback', () => {
  const refusal = new Error('original-Source-tuple-refused'), f = inferOriginalComponentFixture({refusal});
  assert.throws(f.invoke, error => error === refusal); assert.deepEqual(f.calls, ['admit']);
});

test('acquired Effect publication reuses transferred Source evidence and admits only legacy wire inputs', () => {
  const text = readFileSync(new URL('./local-values-plan.mjs', import.meta.url), 'utf8');
  const declaration = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.declaration?.id?.name === 'acquiredMultiEffectPublicationPlan').declaration;
  const node = declaration.body.body.find(node => declares(node, 'sourceEvidence')).declarations[0].init;
  const original = {}, legacy = {}, limits = {}, calls = [];
  const sources = [{sourceEvidence: original, sourceEvidenceWire: 'not-reparsed'}, {sourceEvidenceWire: 'legacy-wire'}];
  const control = {admitRunEvidence(name, wire, actualLimits) {
    assert.equal(name, 'source_evidence'); assert.equal(wire, 'legacy-wire');
    assert.strictEqual(actualLimits, limits); calls.push('legacy'); return legacy;
  }};
  const values = new Function('sources', 'control', 'limits', 'return (' + text.slice(node.start, node.end) + ');')(sources, control, limits);
  assert.strictEqual(values[0], original); assert.strictEqual(values[1], legacy); assert.deepEqual(calls, ['legacy']);
});

function restoredModelSourceEvidenceFixture({infer = {}, refusal} = {}) {
  const node = inferSourceNodes.find(value => value.type === 'IfStatement' &&
    inferSourceText.slice(value.test.start, value.test.end) === 'admission?.retained !== undefined');
  assert(node);
  // Read the current branch, including its original continue, in one loop.
  const currentText = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const tree = parse(currentText, {ecmaVersion: 'latest', sourceType: 'module'});
  let currentBranch;
  (function visit(value) {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'IfStatement' && currentText.slice(value.test.start, value.test.end) ===
        'admission?.retained !== undefined') currentBranch = value;
    for (const child of Object.values(value)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(tree);
  assert(currentBranch);
  const original = {}, captured = {}, record = {}, source = {};
  const restored = {captured, sourceEvidenceWire: 'same-authenticated-source-evidence'};
  const calls = [], captures = [], evidence = [], limits = Object.freeze({maxWireBytes: 1000000});
  const ports = {infer, admission: {retained: record}, source, ledger: {}, captures, evidence,
    localContractLimits: limits, current() {calls.push('current');},
    sourceContinuation: {restore(actual, retained) {
      assert.strictEqual(actual, source); assert.strictEqual(retained, record);
      calls.push('restore'); return restored;
    }}, acquired: {control: {admitRunEvidence(name, wire, bound) {
      assert.equal(name, 'source_evidence'); assert.equal(wire, restored.sourceEvidenceWire);
      assert.strictEqual(bound, limits); assert.strictEqual(captures[0], captured);
      calls.push('admit-original'); if (refusal) throw refusal; return original;
    }}}};
  const invoke = Function(...Object.keys(ports), 'for (const once of [0]) ' +
    currentText.slice(currentBranch.start, currentBranch.end));
  return {invoke: () => invoke(...Object.values(ports)), captures, captured, evidence, original, restored, calls};
}

test('restored Model Source admits its same sealed wire into the current nominal evidence owner', () => {
  const f = restoredModelSourceEvidenceFixture(); f.invoke();
  assert.strictEqual(f.evidence[0].sourceEvidence, f.original);
  assert.strictEqual(f.evidence[0].captured, f.captured);
  assert.equal(f.evidence[0].sourceEvidenceWire, f.restored.sourceEvidenceWire);
  assert.deepEqual(f.calls, ['restore', 'current', 'admit-original', 'current']);
});

test('restored Model Source evidence refusal retains the original capture for cleanup', () => {
  const refusal = Object.freeze(new Error('original sealed evidence refused'));
  const f = restoredModelSourceEvidenceFixture({refusal});
  assert.throws(f.invoke, error => error === refusal);
  assert.deepEqual(f.captures, [f.captured]); assert.deepEqual(f.evidence, []);
  assert.deepEqual(f.calls, ['restore', 'current', 'admit-original']);
});

// Execute the actual cold branch and existing custody, with explicit Core and
// physical ports. No Common ABI, Store, ordinary funding or Source IO claim.
function restoredHostCallerFixture({hostFailure, waiting = false} = {}) {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const main = tree.body.find(node => node.declaration?.id?.name === 'openAcquiredEffectComputation').declaration;
  const body = main.body.body.find(node => node.type === 'TryStatement').block.body;
  const cold = body.find(node => node.type === 'IfStatement' && source.slice(node.test.start, node.test.end) === 'restoredModel');
  const custody = main.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'custody'));
  assert.ok(cold && custody);
  const pin = {}, compiled = {}, definition = {}, managedRun = {}, owner = {}, graph = {}, host = {};
  const capture = {}, settlement = {}, events = [];
  let complete = false, started = 0, retired = false, constructorCalls = 0;
  let retirementFailure;
  const operation = {async run() {
    events.push('run');
    if (waiting) return {status: 'waiting'};
    if (!complete) {complete = true; return {status: 'settling', settlement};}
    return {actualOutput: true};
  }, settlementSlot(value) {assert.strictEqual(value, settlement); return 4;},
  acquireOutput() {events.push('pin'); return pin;}};
  const context = {component: {startRestored() {started++; return operation;}},
    current() {}, inferCapture: {retainCompleted() {events.push('capture'); return true;}},
    async handleModelPause(boundary) {
      events.push(boundary.status);
      if (waiting) return {action: 'waiting_checkpoint', checkpoint: 'same checkpoint'};
      assert.equal(boundary.slot, 4); assert.strictEqual(boundary.settlement, settlement);
      return {action: 'resume'};
    }, modelPlan: {compiled, runDefinition: definition}, managedRun, owner,
    captures: [{capture: {source: () => capture}, async close() {events.push('source-close');}}],
    originalModelSelection: {graph}, infer: {graph},
    acquired: {control: {openCheckedClientInstalledRestoredModelEffectHost(...args) {
      constructorCalls++;
      assert.deepEqual(args, [compiled, definition, managedRun, owner, [capture], pin, graph]);
      assert.equal(events.at(-1), 'pin'); events.push('host');
      if (hostFailure) hostFailure(); return host;
    }}},
    moon: {clientProgramRetireInstalledEffectCapturedConsumers(actual) {
      assert.strictEqual(actual, managedRun); events.push('retire-consumers');
      if (retirementFailure) retirementFailure(); return {$tag: 1, _0: retired};
    }, clientProgramReleaseInferOutput(actual) {
      assert.strictEqual(actual, pin); assert(retired); events.push('unpin'); return true;
    }, clientProgramRefreshAcquiredEffectCleanup(actual) {
      assert.strictEqual(actual, host); events.push('refresh-host'); return retired;
    }}, checked(value) {assert.equal(value.$tag, 1); return value._0;},
    cleanupInfer: async () => {events.push('cleanup-model'); return true;},
    observeUsage() {}, execution: undefined};
  const invoke = new Function(...Object.keys(context), `
    const restoredModel=true;
    let restoredModelOutput,restoredModelHostAttempted=false,checkedHost;
    let closed=false,settled=false,unresolved=false,pending=true;
    let recovery,contentFamily,contentFamilyCleanup,contentRecovery,keyedCleanup,sourceContinuation,modelToken;
    let originalPreparationRetained=false;
    ${source.slice(custody.start, custody.end)}
    return {custody, async run() {try {${source.slice(cold.start, cold.end)}
      return checkedHost;} finally {settled=true;}}};
  `)(...Object.values(context));
  return {...invoke, events, host, counts: () => ({started, constructorCalls}),
    retire(value) {retired = value;}, retirementThrows(callback) {retirementFailure = callback;},
    };
}

test('restored Model caller settles the same operation and retains its output before original Host construction', async () => {
  const f = restoredHostCallerFixture(); assert.strictEqual(await f.run(), f.host);
  assert.deepEqual(f.events, ['run', 'settling', 'run', 'capture', 'pin', 'host']);
  assert.deepEqual(f.counts(), {started: 1, constructorCalls: 1});
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.events.includes('unpin'), false);
  assert.equal(f.events.includes('cleanup-model'), false);
  f.retire(true); assert.equal(await f.custody.cleanup(), true);
  assert(f.events.indexOf('retire-consumers') < f.events.indexOf('unpin'));
  assert(f.events.indexOf('unpin') < f.events.indexOf('cleanup-model'));
  const count = f.events.length; assert.equal(await f.custody.cleanup(), true); assert.equal(f.events.length, count);
});

test('failed restored Host constructor keeps the original pin across false throw and same cleanup retry', async () => {
  for (const original of [undefined, new Error('original Host constructor')]) {
    const f = restoredHostCallerFixture({hostFailure() {throw original;}});
    let failed = false;
    try {await f.run();} catch (error) {failed = true; assert.strictEqual(error, original);}
    assert(failed); await f.custody.close(); assert.equal(await f.custody.cleanup(), false);
    assert.equal(f.events.includes('unpin'), false);
    const cleanupFailure = new Error('actual retained child close');
    f.retirementThrows(() => {throw cleanupFailure;});
    await assert.rejects(f.custody.cleanup(), error => error === cleanupFailure);
    assert.equal(f.custody.cleanupPending(), true); assert.equal(f.events.includes('unpin'), false);
    f.retirementThrows(undefined); f.retire(true);
    assert.equal(await f.custody.cleanup(), true); assert.equal(f.custody.cleanupPending(), false);
    assert.deepEqual(f.counts(), {started: 1, constructorCalls: 1});
    assert.equal(f.events.filter(value => value === 'unpin').length, 1);
  }
});

test('restored Model waiting keeps its same custody without pinning or constructing a Host', async () => {
  const f = restoredHostCallerFixture({waiting: true});
  const result = await f.run();
  assert.strictEqual(result.cleanupOwner, f.custody); assert.equal(result.status, 'waiting_checkpoint');
  assert.deepEqual(f.events, ['run', 'waiting']); assert.deepEqual(f.counts(), {started: 1, constructorCalls: 0});
});

test('restored keyed publication uses the actual saved Source leaves and refuses changed direct evidence', () => {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const fn = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'selectRestoredKeyedSource');
  const select = new Function('return (' + source.slice(fn.start, fn.end) + ');')();
  const left = {source: {identity: 'left-evidence'}, logicalRelationCid: 'left'},
    right = {source: {identity: 'right-evidence'}, logicalRelationCid: 'right'},
    keyed = {source: {identity: 'keyed-evidence'}, logicalRelationCid: 'keyed'};
  const moon = {clientProgramCapturedSourceLogicalCid: value => value};
  const direct = [left, right].map(value => ({captured: {identity: value.logicalRelationCid}, sourceEvidence: value.source}));
  assert.strictEqual(select(moon, [keyed, right, left], direct), keyed);
  assert.throws(() => select(moon, [keyed, right, left], [{...direct[0], sourceEvidence: right.source}, direct[1]]),
    {message: 'RestoredModelSourceOriginalsUnavailable'});
  assert.throws(() => select(moon, [keyed, keyed, left], direct), {message: 'RestoredModelSourceOriginalsUnavailable'});
});


test('persisted restored Host output keeps its Model aliases until the actual Host consumer retirement', async () => {
  const f = persistedModelScratchFixture({heldOutput: true});
  assert.strictEqual(await f.run(), f.plan);
  assert.deepEqual(f.events, ['persist', 'capture-committed']);
});

test('saved non-keyed Model preserves the ordinary Host route without projecting a keyed Source', () => {
  const source = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
  const nodes = [];
  (function walk(node) {if (!node || typeof node !== 'object') return; if (node.type) nodes.push(node);
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(walk);
    else if (value && typeof value === 'object') walk(value);
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  const branch = nodes.find(node => node.type === 'IfStatement' &&
    source.slice(node.test.start, node.test.end).startsWith('savedOriginal && multiple &&'));
  assert.ok(branch);
  let selections = 0, projections = 0;
  const moon = {clientProgramEffectComposedModelKeyedAcquisition() {selections++; return {$tag: 1, _0: undefined};}};
  const checked = value => value._0;
  const acquired = {prepared: {}, control: {restoredInferSourceOriginals() {projections++; assert.fail('not a keyed Plan');}}};
  new Function('moon', 'checked', 'acquired', `const savedOriginal=true,multiple=true,infer={graph:{}};
    ${source.slice(branch.start, branch.end)}`)(moon, checked, acquired);
  assert.deepEqual({selections, projections}, {selections: 1, projections: 0});
});
