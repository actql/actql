import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {contentCid} from './local-account-config.mjs';

// Actual continuation caller and Checkpoint Source method, with explicit
// installed-reader/current/Account ports. This does not issue a Core original,
// open a provider, persist a Checkpoint or acknowledge physical cleanup.
const source = readFileSync(new URL('./client-checkpoints.mjs', import.meta.url), 'utf8');
const nodes = [];
function collect(node) {
  if (!node || typeof node !== 'object') return;
  if (typeof node.type === 'string') nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value && typeof value === 'object') collect(value);
  }
}
collect(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
const select = (type, name) => {
  const found = nodes.filter(node => node.type === type && (node.id?.name ?? node.key?.name) === name);
  assert.equal(found.length, 1);
  return source.slice(found[0].start, found[0].end);
};
const makeAuthorization = compileFunction(`
  const {installedSources, sources, createLocalAuthorizationGate} = ports;
  const authorityScopeCid = 'original-authority', ownerPrincipal = 'original-principal';
  const journal = {}, decisionOptions = {}, authorities = [], binding = {};
  const decide = undefined, answeringAuthorities = undefined;
  const evidence = {}, now = Date.now, maxReviewBytes = 65536, checkpointTtlMs = 60000;
  ${select('VariableDeclarator', 'IDENTIFIER').replace(/^IDENTIFIER/, 'const IDENTIFIER')};
  ${select('FunctionDeclaration', 'installedSource')}
  return ({${select('Property', 'computationSourceAuthorization')}}).computationSourceAuthorization;
`, ['ports', 'contentCid', 'fail']);
const fail = code => {throw Object.assign(new Error(code), {code});};

function fixture(coordinates = [0, 1, 2].map(task => ({stage: task, input: 0, task}))) {
  const prepared = {}, definition = {identity: 'original-definition'}, held = new WeakSet();
  const binding = Object.freeze({connectorId: 'original', connectorRegistration: 'original',
    connectorRevision: 'original/0.1', bindingCid: 'sha256:' + 'a'.repeat(64)});
  const configuration = {sourceRef: 'original-source', accountConfiguration: 'original-account',
    context: {contextCid: 'original-context'}};
  const events = [], gates = [];
  let current = true;
  const authorization = makeAuthorization({sources: [configuration],
    installedSources: [{configuration, gate: {configurationCid: 'original-config',
      contextCid: 'original-context'}}],
    async createLocalAuthorizationGate(options) {
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
    }}, contentCid, fail);
  const checkpoints = {journal: {}, computationSourceAuthorization: authorization,
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
