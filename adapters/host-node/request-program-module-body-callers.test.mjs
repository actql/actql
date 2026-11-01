import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {requestPreparationAvailable} from '../local-node/request-preparation-adapter.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

// These are the actual JS callers with explicit Core result/identity ports.
// No fixture here issues a Core preparation, resource admission or public Run.
const manager = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const start = manager.indexOf('    async fundedPreparation(');
const end = manager.indexOf('    publicationPreparation(prepared) {', start);
assert.ok(start >= 0 && end > start);
const body = manager.slice(start, end).trim().replace(/,$/, '');
const fail = code => {throw Object.assign(new Error(code), {code});};
const ports = () => ({
  clientProgramRequestPreparationControl() {return [1n, 0n];},
  clientLocalResourcePolicyOriginal() {return {};},
  clientLocalPreparationResourceLimits() {return [1n,1n,1n,1n,1n,1n];},
  clientProgramBeginRequestPreparation() {},
  clientProgramAbortRequestPreparation() {},
  clientProgramPrepareRequestNativeComputation() {},
  clientProgramPrepareRequestSourceComputation() {},
  clientProgramFinishRequestComputation() {},
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
  for (const mode of [undefined, null, 0, 'false', {}]) {
    assert.equal(requestPreparationAvailable(context(ports(), mode)), false);
  }
  let callbacks = 0;
  const accessor = Object.freeze({runtime: ports(), preparedEnvironment: {},
    get retainedRelationOutput() {callbacks++; return false;}});
  assert.equal(requestPreparationAvailable(accessor), false);
  const proxy = new Proxy(context(ports(), false), {getOwnPropertyDescriptor() {callbacks++; return undefined;}});
  assert.equal(requestPreparationAvailable(proxy), false);
  assert.equal(callbacks, 0);
});

test('funded caller passes the same installed mode to one original Request compiler and ModuleBody', async () => {
  for (const mode of [false, true]) for (const valuesMaxRows of [undefined, 2]) {
    const parent = {}, receipt = {}, environment = {}, preparedEnvironment = {}, admission = {}, holder = {}, prepared = {};
    const captured = {input: {}, parameters: {text: '日本語😀'}}, parametersCursor = {}, calls = [];
    let constructing = false;
    const moon = {...ports(),
      clientProgramPrepareRequestNativeComputation(...args) {
        assert.strictEqual(this, moon);
        assert.deepEqual(args, [parent, receipt, captured.input, captured.parameters, environment, preparedEnvironment, valuesMaxRows]);
        calls.push('check');
      },
      clientProgramFinishRequestComputation(...args) {
        assert.strictEqual(this, moon);
        assert.deepEqual(args, [parent, receipt, environment, preparedEnvironment]);
        calls.push('compiler'); return 'effect_free';
      },
      clientProgramPrepareRequestProgramModuleBody(...args) {
        assert.strictEqual(this, moon);
        assert.deepEqual(args, [parent, receipt, admission, mode]);
        constructing = true; calls.push('body'); constructing = false;
      },
      clientProgramBorrowRequestProgramPlanInput(value, original) {
        assert.strictEqual(this, moon); assert.strictEqual(value, parent); assert.strictEqual(original, receipt);
        assert.equal(constructing, false); calls.push('borrow'); return holder;
      },
      clientProgramPreparationBorrowRead(value) {assert.strictEqual(value, holder); return prepared;},
      clientProgramRequestParametersOriginal(...args) {
        assert.deepEqual(args, [parent, receipt]); calls.push('parameters'); return parametersCursor;
      },
    };
    const state = {parent, snapshot: captured, context: Object.freeze({runtime: moon, environment,
      preparedEnvironment, retainedRelationOutput: mode, valuesMaxRows})};
    const request = {};
    const producer = {receipt, request, kind: 'program', body: captured, preparation: state};
    const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
    const read = Function('current', 'producerForRequest', 'fail', 'originals', 'checked',
      'checkedRequestProgramPreparation', 'requestPreparationAvailable', 'reportCapacityRefusal',
      `const closing=false,closed=false;return ({${body}}).fundedPreparation;`)(() => {}, () => producer, fail,
      originals, value => value, (_moon, value) => value, requestPreparationAvailable, () => {});
    for(let i=0;i<2;i++){
      const original=await read(request, environment);
      assert.strictEqual(original.prepared, prepared);
      assert.equal(original.kind,'effect_free');
      assert.deepEqual(original.originalInputs,{environment,parameters:undefined,parametersCursor});
      assert.equal(Object.isFrozen(original),true);
      assert.equal(Object.isFrozen(original.originalInputs),true);
    }
    assert.deepEqual(calls, ['check', 'compiler', 'borrow', 'body', 'parameters']);
    assert.strictEqual(state.prepared, prepared);
    state.context = context(moon, undefined);
    await assert.rejects(read(request, state.context.environment), {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.deepEqual(calls, ['check', 'compiler', 'borrow', 'body', 'parameters']);
  }
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
      retainedRelationOutput: mode, sequenceContractOriginal: {}};
    const original = create(moon, installation, environment, {preparedEnvironment}, mode);
    assert.equal(Object.isFrozen(original), true);
    assert.strictEqual(original.retainedRelationOutput, mode);
    installation.closedValuesPreparationContext = original;
    assert.strictEqual(read({installation}), original);
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
