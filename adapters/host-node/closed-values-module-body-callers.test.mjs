import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {closedValuesPreparationAvailable} from '../local-node/closed-values-preparation-adapter.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

// These are the actual JS callers with explicit Core result/identity ports.
// No fixture here issues a Core preparation, resource admission or public Run.
const manager = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const start = manager.indexOf('    fundedPreparation(request, environment) {');
const end = manager.indexOf('    publicationPreparation(prepared) {', start);
assert.ok(start >= 0 && end > start);
const body = manager.slice(start, end).trim().replace(/,$/, '');
const fail = code => {throw Object.assign(new Error(code), {code});};
const ports = () => ({
  clientProgramPrepareClosedValuesModuleBody() {},
  clientProgramCompleteClosedValuesBody() {},
  clientProgramAdoptClosedValuesPreparation() {},
  clientProgramReserveClosedValuesSnapshot() {},
});
const context = (runtime, mode) => Object.freeze({runtime, preparedEnvironment: {},
  retainedRelationOutput: mode});

test('ModuleBody capability requires the new port and an own Boolean mode without accessor callbacks', () => {
  for (const mode of [false, true]) assert.equal(closedValuesPreparationAvailable(context(ports(), mode)), true);
  const old = ports();
  old.clientProgramPrepareClosedValuesBody = old.clientProgramPrepareClosedValuesModuleBody;
  delete old.clientProgramPrepareClosedValuesModuleBody;
  assert.equal(closedValuesPreparationAvailable(context(old, false)), false);
  for (const mode of [undefined, null, 0, 'false', {}]) {
    assert.equal(closedValuesPreparationAvailable(context(ports(), mode)), false);
  }
  let callbacks = 0;
  const accessor = Object.freeze({runtime: ports(), preparedEnvironment: {},
    get retainedRelationOutput() {callbacks++; return false;}});
  assert.equal(closedValuesPreparationAvailable(accessor), false);
  const proxy = new Proxy(context(ports(), false), {getOwnPropertyDescriptor() {callbacks++; return undefined;}});
  assert.equal(closedValuesPreparationAvailable(proxy), false);
  assert.equal(callbacks, 0);
});

test('funded caller passes the same installed mode to one ModuleBody then completes after return', () => {
  for (const mode of [false, true]) {
    const phase = {}, environment = {}, preparedEnvironment = {}, admission = {}, holder = {}, prepared = {};
    const calls = [];
    let constructing = false;
    const moon = {...ports(),
      clientProgramPrepareClosedValuesModuleBody(...args) {
        assert.strictEqual(this, moon);
        assert.deepEqual(args, [phase, environment, preparedEnvironment, admission, mode]);
        constructing = true; calls.push('body'); constructing = false;
      },
      clientProgramCompleteClosedValuesBody(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, phase);
        assert.equal(constructing, false); calls.push('complete'); return holder;
      },
      clientProgramPreparationBorrowRead(value) {assert.strictEqual(value, holder); return prepared;},
    };
    const state = {phase, context: Object.freeze({runtime: moon, environment,
      preparedEnvironment, retainedRelationOutput: mode})};
    const producer = {preparation: state};
    const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
    const read = Function('current', 'producerForRequest', 'fail', 'originals',
      'checkedPreparation', 'closedValuesPreparationAvailable',
      `return ({${body}}).fundedPreparation;`)(() => {}, () => producer, fail,
      originals, (_moon, value) => value, closedValuesPreparationAvailable);
    assert.strictEqual(read({}, environment), prepared);
    assert.strictEqual(read({}, environment), prepared);
    assert.deepEqual(calls, ['body', 'complete']);
    assert.strictEqual(state.prepared, prepared);
    state.context = context(moon, undefined);
    assert.throws(() => read({}, state.context.environment), {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.deepEqual(calls, ['body', 'complete']);
  }
});

test('selected context failure cannot allocate producer slots or fall through to raw snapshot', async () => {
  const originalCause = new Error('original preparation context failure');
  for (const selected of [() => context({}, false), () => context(ports(), undefined),
    () => {throw originalCause;}]) {
    const view = await prepareOrdinarySourceManagedInstallation({}, {
      validator() {}, preparationContext: selected,
      preparationRequirements() {assert.fail('No quote before capability/mode selection');},
    }, false);
    for (let i = 0; i < 33; i++) {
      assert.throws(() => view.beforeSourceSnapshot('program', {}, undefined, {}), error =>
        selected === undefined ? false : error === originalCause || error.code === 'NodeLocalPreparationAdmissionUnavailable');
    }
    assert.deepEqual(await view.close(), {pending: false});
  }
  const view = await prepareOrdinarySourceManagedInstallation({}, {
    validator() {}, preparationContext: () => context(ports(), false),
    preparationRequirements: () => ({}),
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
