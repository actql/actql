import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

const source = readFileSync(new URL('../local-node/installed-project-mock-answers.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const load = ast.body.map(node => node.declaration ?? node).find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'loadInstalledProjectMockAnswers');
const start = load.body.body.findIndex(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(item => item.id.name === 'retired'));
assert.ok(start >= 0);
const tail = load.body.body.slice(start).map(node => source.slice(node.start, node.end)).join('\n');
const install = compileFunction(`let retained=entries;
  let original,selection,project,profile,profilePorts,assertCurrent,openFile;
  const deferAnswers=false;
  const taskBounds=[10,20,3,4,5,6,7,80];
  let ports={retire:retireAnswers};
  const call=(name,...args)=>ports[name](...args);
  const fail=code=>{throw Object.assign(new Error(code),{code});};
  ${tail}`, ['moon', 'entries', 'check', 'checked', 'runtimeField', 'retireAnswers']);

// Execute the existing answer owner's actual binding/retirement methods.
// Model/Task/current ports are explicit identity doubles; checked is a
// stopping-port identity here, not a substitute for actual compiler/Owner tests.
function fixture() {
  const task = {}, answers = {}, profile = {}, now = () => 'original clock';
  const entry = Object.freeze({task, answers, name: 'original Task'});
  let installs = 0, normalizes = 0, retiredAnswers = 0;
  let busy = false, current = true, providerFailure, substitutedProvider;
  const provider = {}, installation = {};
  const moon = {
    clientProgramNormalizeMockTask(actualTask, actualProfile, ...limits) {
      normalizes++;
      assert.strictEqual(actualTask, task); assert.strictEqual(actualProfile, profile);
      assert.deepEqual(limits, [10,20,3,4,5,6,7,80]);
      return normalized;
    },
    clientProgramNormalizedPublicModelTaskMaterials(value) {
      assert.strictEqual(value, normalized);
      return runtimeTupleFromFields(['original Task wire', 'original Task CID',
        'original prompt wire', 'original prompt CID']);
    },
    clientProgramMockExecutionMaterials(actualProfile,value,...limits) {
      assert.strictEqual(actualProfile,profile);assert.strictEqual(value,normalized);
      assert.deepEqual(limits,[10,20,3,4,5,6,7,80]);
      return runtimeTupleFromFields(['original execution wire','original execution CID',
        'original retry wire','original retry CID','original backoff wire','original backoff CID']);
    },
    clientProgramInstallOriginalMock(actualProfile, actualTask, value, actualAnswers, clock) {
      installs++;
      assert.strictEqual(actualProfile, profile); assert.strictEqual(actualTask, task);
      assert.strictEqual(value, normalized); assert.strictEqual(actualAnswers, answers);
      assert.strictEqual(clock, now);
      return installation;
    },
    clientProgramOriginalMockProvider(value) {
      assert.strictEqual(value, installation);
      if (providerFailure) throw providerFailure;
      return substitutedProvider ?? provider;
    },
    clientProgramRetireOriginalMock(value) {
      assert.strictEqual(value, installation);
      return !busy;
    },
    clientProgramProjectPublicModelTaskEnvironment(wire,cid,tasks,...limits) {
      assert.equal(wire,'original environment wire');assert.equal(cid,'original environment CID');
      assert.deepEqual(tasks,[normalized]);assert.deepEqual(limits,[10,20,3,4,5,6,7,80]);
      return runtimeTupleFromFields(['original projected environment','original projected CID',42]);
    },
  };
  const normalized = {};
  const view = install(moon, Object.freeze([entry]), () => {
    if (!current) throw new Error('OriginalCurrentRefused');
  }, value => value, runtimeField, (actualAnswers, actualTask) => {
    assert.strictEqual(actualAnswers, answers); assert.strictEqual(actualTask, task);
    retiredAnswers++;
  });
  return {view, moon, profile, now, entry, installation, provider,
    bind: () => view.bindModelsForRuntime(moon, profile, now),
    counts: () => ({installs, normalizes, retiredAnswers}),
    busy: value => {busy = value;},
    failProvider: value => {providerFailure = value;},
    replaceProvider: () => {substitutedProvider = {};},
  };
}

test('same answer owner installs its original Task/answers once and rejects replacement binding', () => {
  const f = fixture();
  const bound = f.bind();
  assert.strictEqual(f.bind(), bound);
  const entries = bound.originalsForRuntime(f.moon);
  assert.equal(entries.length, 1);
  assert.strictEqual(entries[0].task, f.entry.task);
  assert.strictEqual(entries[0].answers, f.entry.answers);
  assert.strictEqual(entries[0].installation, f.installation);
  assert.strictEqual(bound.forTaskCid(f.moon, 'original Task CID'), entries[0]);
  assert.equal(bound.forTaskCid(f.moon, 'foreign Task CID'), undefined);
  assert.throws(() => f.view.bindModelsForRuntime(f.moon, {}, f.now),
    {code: 'ForeignInstalledMockModelOriginal'});
  assert.throws(() => ({...bound}).originalsForRuntime(f.moon),
    {code: 'ForeignInstalledMockModelOriginal'});
  assert.deepEqual(f.counts(), {installs: 1, normalizes: 1, retiredAnswers: 0});
  f.view.retire(f.moon);
});

test('partial Model provider failure stays sticky and cleanup retains its original installation', () => {
  const f = fixture(), marker = new Error('OriginalProviderRefusal');
  f.failProvider(marker);
  assert.throws(f.bind, error => error === marker);
  f.failProvider(undefined);
  assert.throws(f.bind, error => error === marker);
  assert.deepEqual(f.counts(), {installs: 1, normalizes: 1, retiredAnswers: 0});
  f.view.retire(f.moon);
  assert.equal(f.counts().retiredAnswers, 1);
});

test('busy Model installation retains answers until the same installation acknowledges retirement', () => {
  const f = fixture(), bound = f.bind();
  f.busy(true);
  assert.throws(() => f.view.retire(f.moon), {code: 'InstalledMockModelsCleanupPending'});
  assert.equal(f.counts().retiredAnswers, 0);
  f.busy(false);
  f.view.retire(f.moon);
  f.view.retire(f.moon);
  assert.equal(f.counts().retiredAnswers, 1);
  assert.throws(() => bound.originalsForRuntime(f.moon), {code: 'InstalledMockModelsRetired'});
});

test('changed opaque Model provider refuses without a new normalization or installation', () => {
  const f = fixture(), bound = f.bind();
  f.replaceProvider();
  assert.throws(() => bound.originalsForRuntime(f.moon), {code: 'ForeignInstalledMockModelOriginal'});
  assert.throws(f.bind, {code: 'ForeignInstalledMockModelOriginal'});
  assert.deepEqual(f.counts(), {installs: 1, normalizes: 1, retiredAnswers: 0});
  f.view.retire(f.moon);
});

test('Mock Host material envelope retains exact Common execution and dependency bodies', () => {
  const f=fixture(),bound=f.bind();
  const installation=bound.modelInstallationForRuntime(f.moon,
    'original environment wire','original environment CID');
  assert.deepEqual(installation,{environmentWire:'original projected environment',
    executionContracts:[{modelTaskCid:'original Task CID',bodyWire:'original execution wire',
      cid:'original execution CID'}],
    dependencyBodies:[{bodyWire:'original prompt wire',cid:'original prompt CID'},
      {bodyWire:'original retry wire',cid:'original retry CID'},
      {bodyWire:'original backoff wire',cid:'original backoff CID'}]});
  assert.ok(Object.isFrozen(installation)&&Object.isFrozen(installation.executionContracts)&&
    Object.isFrozen(installation.dependencyBodies));
  assert.throws(()=>({...bound}).modelInstallationForRuntime(f.moon,
    'original environment wire','original environment CID'),{code:'ForeignInstalledMockModelOriginal'});
  f.view.retire(f.moon);
});
