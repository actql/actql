// Actual recipe/parser and private caller functions, with explicit physical
// and grant doubles. This is not original Core/credential or TLS acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {captureInstalledEffectPlanRecipe, selectInstalledEffectCredentialOperation} from './installed-effect-plan.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const freeze = value => Object.freeze(value);
function recipeInput() {
  const operation = operation => freeze({operation, extent: freeze({testExtent: true})});
  const memberOperations = [operation('capture'), operation('recover')];
  const rowOperations = [operation('request'), operation('finalize')];
  const occurrences = [];
  for (const action of ['capture', 'apply', 'resume']) {
    for (const [slot, resource, operationName] of [['account', 'account', 'account-read'],
      ['schema', 'properties', 'properties-read']]) {
      const operationIndex = memberOperations.push(operation(operationName)) - 1;
      occurrences.push(freeze({phase: action + '-describe', slot, resource, perRow: false,
        operationIndex, maxRequestBytes: 32, maxResponseBytes: 64}));
    }
    for (const [slot, resource, operationName] of [['account', 'account', 'account-read'],
      ['schema-before', 'properties', 'properties-read'], ['target', undefined, 'target-read'],
      ['schema-after', 'properties', 'properties-read']]) {
      const operationIndex = rowOperations.push(operation(operationName)) - 1;
      occurrences.push(freeze({phase: action + '-target', slot, ...(resource === undefined ? {} : {resource}),
        operationIndex, maxRequestBytes: 32, maxResponseBytes: 64}));
    }
  }
  const operationIndex = rowOperations.push(operation('update')) - 1;
  occurrences.push(freeze({phase: 'write', operationIndex, maxRequestBytes: 32, maxResponseBytes: 64}));
  return freeze({memberOperations: freeze(memberOperations), rowOperations: freeze(rowOperations),
    captureConstruction: freeze({operationIndex: 0}), recoveryConstruction: freeze({operationIndex: 1}),
    requestConstruction: freeze({operationIndex: 0}), requestFinalization: freeze({operationIndex: 1}),
    credentialOperations: freeze(occurrences)});
}
const limitOf = value => value.memberOperations.length + value.rowOperations.length;
const capture = value => captureInstalledEffectPlanRecipe(value, limitOf(value));
function privateArrow(name, dependencies) {
  const source = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
  const pending = [parse(source, {ecmaVersion: 'latest', sourceType: 'module'})];
  let selected;
  while (pending.length) {
    const node = pending.pop();
    if (node.type === 'VariableDeclarator' && node.id.name === name) {
      assert.equal(selected, undefined, 'One actual private caller'); selected = node.init;
    }
    if (node.type === 'FunctionDeclaration' && node.id.name === name) {
      assert.equal(selected, undefined, 'One actual private caller'); selected = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) pending.push(...value.filter(item => item?.type));
      else if (value?.type) pending.push(value);
    }
  }
  assert(selected);
  return Function(...Object.keys(dependencies), `return (${source.slice(selected.start, selected.end)});`)(...Object.values(dependencies));
}

test('named credential read slots retain distinct original operation indexes within unchanged total bound', () => {
  const input = recipeInput(), selected = capture(input);
  assert.equal(selected.credentialOperations.length, 19);
  const before = selectInstalledEffectCredentialOperation(selected, 'capture-target', 'schema-before');
  const after = selectInstalledEffectCredentialOperation(selected, 'capture-target', 'schema-after');
  assert.notEqual(before.operationIndex, after.operationIndex);
  assert.equal(selected.rowOperations[before.operationIndex].operation, 'properties-read');
  assert.equal(selected.rowOperations[after.operationIndex].operation, 'properties-read');
  assert.equal(selectInstalledEffectCredentialOperation(selected, 'capture-target'), undefined);
  assert.equal(selectInstalledEffectCredentialOperation(selected, 'capture-target', 'missing'), undefined);
  assert.equal(selectInstalledEffectCredentialOperation(selected, 'write').slot, undefined);
  assert.throws(() => captureInstalledEffectPlanRecipe(input, limitOf(input) - 1), {code: 'InvalidInstalledEffectPlanRecipe'});
});

test('named credential read slots reject duplicate slots/indexes mixed legacy selection and unsupported phases', () => {
  const input = recipeInput();
  for (const mutate of [
    entries => {entries[1] = freeze({...entries[1], slot: entries[0].slot});},
    entries => {entries[1] = freeze({...entries[1], operationIndex: entries[0].operationIndex});},
    entries => {const {slot, resource, ...legacy} = entries[0]; entries[0] = freeze(legacy);},
    entries => {entries[0] = freeze({...entries[0], slot: ''});},
    entries => {entries[0] = freeze({...entries[0], slot: 'bad\0slot'});},
    entries => {entries[0] = freeze({...entries[0], resource: ''});},
    entries => {entries[0] = freeze({...entries[0], resource: '\ud800'});},
    entries => {entries[entries.length - 1] = freeze({...entries.at(-1), slot: 'write-slot'});},
  ]) {
    const entries = [...input.credentialOperations]; mutate(entries);
    assert.throws(() => capture(freeze({...input, credentialOperations: freeze(entries)})), {code: 'InvalidInstalledEffectPlanRecipe'});
  }
});

function readFixture() {
  const recipe = capture(recipeInput()), site = {}, calls = [], consumed = [];
  const member = {resource: 'companies'}, originalTarget = {grant: {}}, targetView = {grant: originalTarget.grant};
  const managedReadChild = privateArrow('managedReadChild', {recipeOf: () => recipe,
    ownerOf: () => ({site}), fail, selectInstalledEffectCredentialOperation, nodeTypes,
    requireSynchronousEffectResource: privateArrow('requireSynchronousEffectResource', {fail})});
  const read = managedReadChild({member, phase: 'capture-target',
    physicalOperations: options => {calls.push(options); return options;},
    runInvocationCid: 'original-run', dispatchRequestCid: 'original-dispatch', assertCurrent() {},
    originalTargetAuthorization(authorization, row) {
      assert.strictEqual(authorization, targetView); assert.equal(row, 3);
      consumed.push(authorization); return originalTarget;
    }});
  return {recipe, site, calls, consumed, read, originalTarget, targetView};
}

test('named credential read caller keeps metadata authorization separate from same-row target approval', () => {
  const f = readFixture(), metadata = {grant: {}};
  const before = f.read(metadata, {grant: metadata.grant, useId: 'schema-before', maxResponseBytes: 64}, 3, 'schema-before');
  const target = f.read(f.targetView, {grant: f.targetView.grant, useId: 'target', maxResponseBytes: 64}, 3, 'target');
  const after = f.read(metadata, {grant: metadata.grant, useId: 'schema-after', maxResponseBytes: 64}, 3, 'schema-after');
  assert.strictEqual(before.originalAuthorization, metadata); assert.strictEqual(after.originalAuthorization, metadata);
  assert.strictEqual(target.originalAuthorization, f.originalTarget);
  assert.deepEqual(f.consumed, [f.targetView]);
  assert.deepEqual(f.calls.map(value => [value.credentialSlot, value.resource, value.purpose]), [
    ['schema-before', 'properties', 'read'], ['target', 'companies', 'target-read'], ['schema-after', 'properties', 'read'],
  ]);
});

test('named credential read caller refuses missing slot foreign grant and oversize response before physical use', () => {
  for (const variant of ['missing', 'default', 'grant', 'bytes']) {
    const f = readFixture(), authorization = {grant: {}};
    const input = {grant: variant === 'grant' ? {} : authorization.grant, useId: 'original',
      maxResponseBytes: variant === 'bytes' ? 65 : 64};
    assert.throws(() => f.read(authorization, input, 3,
      variant === 'default' ? undefined : variant === 'missing' ? 'unknown' : 'account'),
    {code: 'ForeignInstalledEffectReadChild'});
    assert.deepEqual(f.calls, []); assert.deepEqual(f.consumed, []);
  }
});

test('named credential read caller preserves child binding and immutable request bound over caller input', async () => {
  const recipe = capture(recipeInput()), grant = {}, binding = {}, scope = {}, site = {};
  let received;
  const managedReadChild = privateArrow('managedReadChild', {recipeOf: () => recipe,
    ownerOf: () => ({site}), fail, selectInstalledEffectCredentialOperation, nodeTypes,
    requireSynchronousEffectResource: privateArrow('requireSynchronousEffectResource', {fail})});
  const read = managedReadChild({member: {resource: 'companies'}, phase: 'capture-target',
    physicalOperations: options => options.invoke({authorization: {grant, scope, useId: 'actual-use'},
      credential: {binding}, callResource: input => {received = input; return 'original-response';}}),
    assertCurrent() {}});
  assert.equal(await read({grant}, {grant, binding: {}, scope: {}, useId: 'requested-use',
    maxRequestBytes: 99999, maxResponseBytes: 64}, 0, 'account'), 'original-response');
  assert.strictEqual(received.binding, binding); assert.strictEqual(received.grant, grant);
  assert.strictEqual(received.scope, scope); assert.equal(received.useId, 'actual-use');
  assert.equal(received.maxRequestBytes, 32);
});

test('read projection completes inside the original physical child before its completion', async () => {
  const f = readFixture(), authorization = {grant: {}}, events = [], response = {}, decoded = {};
  const operation = f.read(authorization, {grant: authorization.grant, useId: 'account', maxResponseBytes: 64},
    0, 'account', original => {
      assert.strictEqual(original, response); events.push('project'); return decoded;
    });
  const result = await operation.invoke({authorization, credential: {}, async callResource() {
    events.push('send'); await Promise.resolve(); events.push('receive'); return response;
  }});
  events.push('child-complete');
  assert.strictEqual(result, decoded);
  assert.deepEqual(events, ['send', 'receive', 'project', 'child-complete']);
});

test('read projection failure or pending result cannot complete a physical child projection', async () => {
  const primary = new Error('Native projection refused');
  for (const [project, expected] of [
    [() => {throw primary;}, primary],
    [() => Promise.reject(new Error('Pending projection')), {code: 'InstalledEffectResourcesUnavailable'}],
    [() => ({then(resolve) {resolve('late');}}), {code: 'InstalledEffectResourcesUnavailable'}],
  ]) {
    const f = readFixture(), authorization = {grant: {}};
    const operation = f.read(authorization, {grant: authorization.grant, useId: 'account', maxResponseBytes: 64},
      0, 'account', project);
    await assert.rejects(operation.invoke({authorization, credential: {}, callResource: async () => ({})}), expected);
    assert.equal(f.calls.length, 1);
  }
});

test('read projection rejects async proxy and non-callable callbacks before authorization consumption or IO', () => {
  for (const project of [async () => ({}), new Proxy(() => ({}), {}), {}]) {
    const f = readFixture();
    assert.throws(() => f.read(f.targetView, {grant: f.targetView.grant, useId: 'target', maxResponseBytes: 64},
      3, 'target', project), {code: 'ForeignInstalledEffectReadChild'});
    assert.deepEqual(f.calls, []); assert.deepEqual(f.consumed, []);
  }
});

test('named physical credential caller selects same-endpoint occurrences by exact slot and refuses resource substitution', async () => {
  const recipe = capture(recipeInput()), calls = [], moon = {
    clientProgramInstalledEffectManagedPlanCaptureChildren: () => 100,
  };
  const originalSite = {}, member = {resource: 'companies', memberIndex: 0};
  const prepare = privateArrow('prepareCredentialOperation', {recipeOf: () => recipe, moon,
    fail, selectInstalledEffectCredentialOperation,
    installedRowCredentialOperationSite: () => originalSite,
    prepareInstalledRowCaptureChild: ({create}) => create(),
    prepareInstalledEffectCredentialChild: options => {calls.push(options); return 'selected-child';},
  });
  const facts = {member, rowIndex: 3, phase: 'capture-target', operation: 'properties-read',
    site: {credential: {}}, originalAuthorization: {}, useId: 'original', resource: 'properties', purpose: 'read',
    managedEffect: {runtime: moon, operationPlan: {}}, requestChildren: [], retireRequestAliases() {}, assertCurrent() {}};
  assert.equal(await prepare({...facts, credentialSlot: 'schema-before'}), 'selected-child');
  assert.equal(await prepare({...facts, credentialSlot: 'schema-after'}), 'selected-child');
  assert.notEqual(calls[0].operationIndex, calls[1].operationIndex);
  for (const changed of [{credentialSlot: 'missing'}, {resource: 'foreign'}, {purpose: 'effect'}, {maxResponseBytes: 65}]) {
    await assert.rejects(prepare({...facts, credentialSlot: 'schema-before', ...changed}),
      {code: 'InstalledEffectPhysicalPlanUnavailable'});
  }
  assert.equal(calls.length, 2);
});
