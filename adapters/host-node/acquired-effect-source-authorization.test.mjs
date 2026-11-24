import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {createCheckpointComputationSource, createCheckpointSourceSelection}
  from './client-checkpoint-computation-source.mjs';

// Actual continuation caller and Checkpoint Source method, with explicit
// installed-reader/current/Account ports. This does not issue a Core original,
// open a provider, persist a Checkpoint or acknowledge physical cleanup.
const fail = code => {throw Object.assign(new Error(code), {code});};

function fixture(coordinates = [0, 1, 2].map(task => ({stage: task, input: 0, task}))) {
  const prepared = {}, definition = {identity: 'original-definition'}, held = new WeakSet();
  const accountConstruction = Object.freeze({original: 'account-construction'});
  const binding = Object.freeze({connectorId: 'original', connectorRegistration: 'original',
    connectorRevision: 'original/0.1', bindingCid: 'sha256:' + 'a'.repeat(64)});
  const configuration = {sourceRef: 'original-source', accountConfiguration: 'original-account',
    context: {contextCid: 'original-context'}};
  const events = [], gates = [];
  let current = true;
  const installedSource = createCheckpointSourceSelection({sources: [configuration],
    installedSources: [{configuration, gate: {configurationCid: 'original-config',
      contextCid: 'original-context'}}]});
  const {computationSourceAuthorization} = createCheckpointComputationSource({installedSource,
    accountConstruction, authorityScopeCid: 'original-authority', ownerPrincipal: 'original-principal',
    journal: {}, decisionOptions: {}, authorities: [], binding: {}, evidence: {},
    now: Date.now, maxReviewBytes: 65536, checkpointTtlMs: 60000,
    async createLocalAuthorizationGate(options) {
      assert.equal(options.accountConstruction, accountConstruction);
      assert.equal(options.accountConfiguration, configuration.accountConfiguration);
      assert.equal(options.context, configuration.context);
      const gate = {configurationCid: 'original-config', contextCid: 'original-context',
        assertConfigurationCurrent() {assert(current);},
        authorize(boundary, tuple, facts) {
          assert.equal(boundary, 'acquisition');
          assert.deepEqual(tuple, {connection: 'original', resource: 'records', operation: 'read'});
          events.push({boundary, tuple, subjectCid: facts.subjectCid});
          return {action: 'dispatch', admission: {enter() {events.push('enter');}}};
        }, close() {events.push('gate-close');}};
      gates.push(gate);
      return gate;
    }});
  const checkpoints = {journal: {}, computationSourceAuthorization,
    async retireComputationSources(runId) {assert.equal(runId, 'original-run');}};
  const continuation = acquiredEffectContinuation({moon: {}, checkpoints,
    acquired: {prepared, runDefinition: definition,
      control: {runDefinitionRunId(actual) {assert.equal(actual, definition);return 'original-run';}}},
    submission: {request: 'original-request'}, declaredResults: [],
    principalId: 'original-principal', unitId: 'original-unit', currentRun: () => current});
  const adapter = {ordinaryRecoveryBinding(value) {
    if (!held.has(value)) fail('InstalledSourcePreparationMismatch');
    return binding;
  }};
  const sources = coordinates.map(coordinate => {
    const occurrence = Object.freeze({...coordinate});
    const preparedSource = Object.freeze({occurrence,
      checkedSource: {sourceRef: 'original-source'},
      readTuple: {connection: 'original', resource: 'records', operation: 'read'},
      physicalBinding: {original: 'target'}});
    held.add(preparedSource);
    continuation.accessFor({authorization: {}}, occurrence);
    return {occurrence, preparedSource, adapter};
  });
  return {continuation, sources, events, gates, revoke() {current = false;}};
}

test('three original Source ports reach the same continuation authorization caller without a two-Source cap', async () => {
  const f = fixture();
  try {
    await f.continuation.prepared(f.sources);
    for (const source of f.sources) {
      const admitted = await f.continuation.beforeRead(source);
      admitted.enter(); admitted.enter();
    }
    const decisions = f.events.filter(value => value.boundary === 'acquisition');
    assert.equal(decisions.length, 3);
    assert.equal(new Set(decisions.map(value => value.subjectCid)).size, 3);
    assert.equal(f.events.filter(value => value === 'enter').length, 3);
  } finally {await f.continuation.close();}
});

test('continuation caller refuses another reader original before creating any Source gate', async () => {
  const f = fixture();
  try {
    const foreign = f.sources.map((source, index) => index === 2
      ? {...source, preparedSource: {...source.preparedSource}} : source);
    await assert.rejects(f.continuation.prepared(foreign), {code: 'InstalledSourcePreparationMismatch'});
    assert.equal(f.gates.length, 0);
  } finally {await f.continuation.close();}
});

test('continuation caller retains actual current refusal before the third Source gate', async () => {
  const f = fixture();
  try {
    await f.continuation.prepared(f.sources);
    f.revoke();
    await assert.rejects(f.continuation.beforeRead(f.sources[2]), {code: 'ClientRunCancellationRequested'});
    assert.equal(f.gates.length, 0);
  } finally {await f.continuation.close();}
});

// Actual two-Model normal416 handoff coordinates: two acquisitions in one
// stage have independent input/task ordinals, not a legacy pipeline diagonal.
test('same-stage original Source input one reaches its exact continuation without a diagonal coordinate restriction', async () => {
  const f = fixture([{stage: 0, input: 0, task: 0}, {stage: 0, input: 1, task: 1}]);
  try {
    await f.continuation.prepared(f.sources);
    for (const source of f.sources) (await f.continuation.beforeRead(source)).enter();
    const decisions = f.events.filter(value => value.boundary === 'acquisition');
    assert.equal(decisions.length, 2);
    assert.equal(new Set(decisions.map(value => value.subjectCid)).size, 2);
    assert.equal(f.events.filter(value => value === 'enter').length, 2);
  } finally {await f.continuation.close();}
});

test('original Source coordinates retain nonnegative integer refusal before any gate', async () => {
  for (const key of ['stage', 'input', 'task']) {
    const f = fixture([{stage: 0, input: 1, task: 1, [key]: -1}]);
    try {
      await f.continuation.prepared(f.sources);
      await assert.rejects(f.continuation.beforeRead(f.sources[0]), {code: 'InvalidComputationSourceContinuation'});
      assert.equal(f.gates.length, 0);
    } finally {await f.continuation.close();}
  }
});


test('continuation refuses substituted or incomplete registered Source coordinates before any gate', async () => {
  for (const mutate of [
    sources => [{...sources[0], occurrence: {...sources[0].occurrence, input: 1}}, sources[1]],
    sources => [{...sources[0], preparedSource: sources[1].preparedSource}, sources[1]],
    sources => [sources[0], sources[0]],
    sources => [sources[0]],
    sources => [{...sources[0], occurrence: {...sources[0].occurrence, computeTask: 1}}, sources[1]],
  ]) {
    const f = fixture([{stage: 0, input: 0, task: 0, computeTask: 0},
      {stage: 0, input: 1, task: 1, computeTask: 0}]);
    try {
      await assert.rejects(f.continuation.prepared(mutate(f.sources)), {code: 'HeldAcquisitionChanged'});
      assert.equal(f.gates.length, 0);
    } finally {await f.continuation.close();}
  }
});


test('prepared Source cannot substitute its registered reader or coordinates before entry', async () => {
  for (const change of [
    source => {source.occurrence = {...source.occurrence, input: 1};},
    source => {source.preparedSource = {...source.preparedSource};},
    source => {source.adapter = {...source.adapter};},
  ]) {
    const f = fixture([{stage: 0, input: 0, task: 0, computeTask: 0}]);
    try {
      await f.continuation.prepared(f.sources);
      change(f.sources[0]);
      await assert.rejects(f.continuation.beforeRead(f.sources[0]), {code: 'HeldAcquisitionChanged'});
      assert.equal(f.gates.length, 0);
    } finally {await f.continuation.close();}
  }
});
