import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {requestPreparationAvailable} from '../local-node/request-preparation-adapter.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

// These are the actual JS callers with explicit Core result/identity ports.
// No fixture here issues a Core preparation, resource admission or public Run.
const ports = () => ({
  clientProgramRequestPreparationControl() {return [1n, 0n];},
  clientLocalResourcePolicyOriginal() {return {};},
  clientLocalPreparationResourceLimits() {return [1n,1n,1n,1n,1n,1n];},
  clientProgramBeginRequestPreparation() {},
  clientProgramAbortRequestPreparation() {},
  clientProgramPrepareRequestNativeComputation() {},
  clientProgramPrepareRequestSourceComputation() {},
  clientProgramFinishRequestComputation() {},
  clientProgramPrepareRequestProgramNormalization() {},
  clientProgramPrepareRequestProgramAuthoringContext() {return {};},
  clientProgramPrepareRequestPolicySubjects() {},
  clientProgramReadRequestPolicySubject() {},
  clientProgramBindRequestPolicySubject() {},
  clientProgramFinishRequestPolicySubjects() {},
  clientProgramPrepareRequestProgramModuleBody() {},
  clientProgramRequestProgramModuleIssueCode() {},
  clientProgramBorrowRequestProgramPlanInput() {},
  clientProgramComposedInferOccurrences: () => [],
  clientProgramSerializationOccurrences: () => [],
  clientProgramAcquisitionCount() {return 0;},
  clientProgramAdoptRequestProgramPreparation() {},
  clientProgramReserveRequestSnapshot() {},
});
const context = (runtime, mode) => Object.freeze({runtime, preparedEnvironment: {},
  retainedRelationOutput: mode});

test('ModuleBody capability requires the new port and an own Boolean mode without accessor callbacks', () => {
  for (const mode of [false, true]) assert.equal(requestPreparationAvailable(context(ports(), mode)), true);
  const old = ports();
  old.clientProgramPrepareClosedValuesModuleBody = old.clientProgramPrepareRequestProgramModuleBody;
  delete old.clientProgramPrepareRequestProgramModuleBody;
  assert.equal(requestPreparationAvailable(context(old, false)), false);
  const unnormalized = ports();
  delete unnormalized.clientProgramPrepareRequestProgramNormalization;
  assert.equal(requestPreparationAvailable(context(unnormalized, false)), false);
  let normalizationReads = 0;
  Object.defineProperty(unnormalized, 'clientProgramPrepareRequestProgramNormalization', {
    get() {normalizationReads++; return () => {};},
  });
  assert.equal(requestPreparationAvailable(context(unnormalized, false)), false);
  assert.equal(normalizationReads, 0);
  for (const mode of [undefined, null, 0, 'false', {}]) {
    assert.equal(requestPreparationAvailable(context(ports(), mode)), false);
  }
  let callbacks = 0;
  const accessor = Object.freeze({runtime: ports(), preparedEnvironment: {},
    get retainedRelationOutput() {callbacks++; return false;}});
  assert.equal(requestPreparationAvailable(accessor), false);
  const proxy = new Proxy(context(ports(), false), {getOwnPropertyDescriptor() {callbacks++; return undefined;}});
  assert.equal(requestPreparationAvailable(proxy), false);
  const unauthored = ports();
  delete unauthored.clientProgramPrepareRequestProgramAuthoringContext;
  assert.equal(requestPreparationAvailable(context(unauthored, false)), false);
  Object.defineProperty(unauthored, 'clientProgramPrepareRequestProgramAuthoringContext', {
    get() {callbacks++; return () => ({});},
  });
  assert.equal(requestPreparationAvailable(context(unauthored, false)), false);
  assert.equal(callbacks, 0);
});

test('selected context failure cannot allocate producer slots or fall through to raw snapshot', async () => {
  const originalCause = new Error('original preparation context failure');
  for (const selected of [() => context({}, false), () => context(ports(), undefined),
    () => {throw originalCause;}]) {
    const view = await prepareOrdinarySourceManagedInstallation({}, {
      validator() {}, preparationContext: selected,
    }, false);
    for (let i = 0; i < 33; i++) {
      assert.throws(() => view.beforeSourceSnapshot('program', {}, undefined, {}), error =>
        selected === undefined ? false : error === originalCause || error.code === 'NodeLocalPreparationAdmissionUnavailable');
    }
    assert.deepEqual(await view.close(), {pending: false});
  }
  const view = await prepareOrdinarySourceManagedInstallation({}, {
    validator() {}, preparationContext: () => context(ports(), false),
  }, false);
  // The adapter declines this connection before any resource/Core call. A
  // selected funded path must not reinterpret that decline as raw preparation.
  assert.throws(() => view.beforeSourceSnapshot('program', {}, undefined, {}),
    {code: 'NodeLocalPreparationAdmissionUnavailable'});
  assert.deepEqual(await view.close(), {pending: false});
});

test('Host retains the actual output mode in its original preparation context and checks correspondence', () => {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let initializer;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'AssignmentExpression' && node.left.object?.name === 'originalInstallation' &&
        node.left.property?.name === 'closedValuesPreparationContext') {
      assert.equal(initializer, undefined); initializer = node.right;
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    }
  };
  visit(ast);
  assert.ok(initializer);
  const create = Function('moon', 'originalInstallation', 'environment', 'sourceEnvironmentOriginal',
    'retainedRelationOutput', `return ${source.slice(initializer.start, initializer.end)};`);
  const declaration = ast.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'readLocalPreparationContext');
  const read = Function('assertSourceManagedHostPreparation', 'clientOperationError',
    source.slice(declaration.start, declaration.end) + ';return readLocalPreparationContext;')(
    () => {}, code => Object.assign(new Error(code), {code}));
  for (const mode of [false, true]) {
    const moon = {}, control = {}, environment = {}, preparedEnvironment = {};
    const installation = {initialControl: control, projectRuntime: moon,
      retainedRelationOutput: mode, sourceFreeMaxWork: 30000000, sequenceContractOriginal: {}};
    const original = create(moon, installation, environment, {preparedEnvironment}, mode);
    assert.equal(Object.isFrozen(original), true);
    assert.strictEqual(original.retainedRelationOutput, mode);
    installation.closedValuesPreparationContext = original;
    assert.strictEqual(read({installation}), original);
    installation.closedValuesPreparationContext = Object.freeze({...original, sourceFreeMaxWork: 40000000});
    assert.throws(() => read({installation}), {code: 'NodeLocalPreparationAdmissionUnavailable'});
    installation.closedValuesPreparationContext = original;
    for (const invalid of [undefined, null, 0, 'false', !mode]) {
      installation.closedValuesPreparationContext = Object.freeze({...original, retainedRelationOutput: invalid});
      assert.throws(() => read({installation}), {code: 'NodeLocalPreparationAdmissionUnavailable'});
    }
  }
});


test('selected row context requires finite own DATA without observing accessors', () => {
  for (const valuesMaxRows of [undefined, 1, 10000, 10001, 100000, 2147483647]) {
    assert.equal(requestPreparationAvailable(Object.freeze({
      ...context(ports(), false), valuesMaxRows})), true);
  }
  for (const valuesMaxRows of [null, 0, -1, 1.5, 2147483648, Number.MAX_SAFE_INTEGER, Infinity, '2']) {
    assert.equal(requestPreparationAvailable(Object.freeze({
      ...context(ports(), false), valuesMaxRows})), false);
  }
  let getters = 0;
  const selected = Object.freeze({...context(ports(), false),
    get valuesMaxRows() {getters++; return 2;}});
  assert.equal(requestPreparationAvailable(selected), false);
  assert.equal(getters, 0);
  const missing = ports(); delete missing.clientProgramRequestProgramModuleIssueCode;
  assert.equal(requestPreparationAvailable(context(missing, false)), false);
});

test('selected source-free work context accepts finite own DATA and refuses accessors', () => {
  for (const sourceFreeMaxWork of [undefined, 1, 30000000, 2147483647]) {
    assert.equal(requestPreparationAvailable(Object.freeze({
      ...context(ports(), false), sourceFreeMaxWork})), true);
  }
  for (const sourceFreeMaxWork of [null, 0, -1, 1.5, 2147483648, Infinity, '30000000']) {
    assert.equal(requestPreparationAvailable(Object.freeze({
      ...context(ports(), false), sourceFreeMaxWork})), false);
  }
  let getters = 0;
  assert.equal(requestPreparationAvailable(Object.freeze({...context(ports(), false),
    get sourceFreeMaxWork() {getters++; return 30000000;}})), false);
  assert.equal(getters, 0);
});
