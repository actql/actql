import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import test from 'node:test';
import {parse} from 'acorn';

// Actual private constructor/validator with explicit Row/current/resource and
// I/O entry ports. This admits definition DATA only, never an opaque plan.
const source = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => {
  const matches = tree.body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(matches.length, 1, name); return source.slice(matches[0].start, matches[0].end);
};
const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0;
const capture = new Function('nodeTypes', 'fail', 'text',
  declaration('captureManagedPlanDefinition') + ';return captureManagedPlanDefinition;')(nodeTypes, fail, text);
const slot = (role, operation) => Object.freeze({role, operation});
const definition = kind => Object.freeze({kind, memberOperations: Object.freeze([]),
  rowOperations: Object.freeze(kind === 'update'
    ? [slot('target-read', 'original-observe'), slot('write', 'original-write')]
    : [slot('write', 'original-write')])});
const driver = {kinds: ['update', 'command'], targetRead: {operation: 'original-observe'}};

test('definition DATA retains exact original frozen slots and leaves legacy omission unchanged', () => {
  assert.equal(capture(undefined, driver), undefined);
  for (const kind of ['update', 'command']) {
    const original = definition(kind);
    assert.strictEqual(capture(original, driver), original);
    assert.strictEqual(capture(original, driver).rowOperations, original.rowOperations);
    assert.equal(original.memberOperations.length, 0);
  }
});

test('definition grammar refuses proxies, accessors, iterators and wrong role order without callbacks', () => {
  let callbacks = 0;
  const original = definition('update');
  const proxy = new Proxy(original, {ownKeys() {callbacks++; throw new Error('proxy');}});
  const getter = Object.freeze({get kind() {callbacks++; return 'update';},
    memberOperations: Object.freeze([]), rowOperations: original.rowOperations});
  const rowGetter = [];Object.defineProperty(rowGetter, '0', {get() {callbacks++; return original.rowOperations[0];},
    enumerable: true});Object.freeze(rowGetter);
  const iterator = [...original.rowOperations];iterator[Symbol.iterator] = () => {callbacks++; throw new Error('iterator');};
  Object.freeze(iterator);
  const supplied = [proxy, getter,
    Object.freeze({...original, rowOperations: rowGetter}),
    Object.freeze({...original, rowOperations: iterator}),
    Object.freeze({...original, rowOperations: Object.freeze([...original.rowOperations].reverse())}),
    Object.freeze({...original, extra: true}), {...original},
    Object.freeze({...original, rowOperations: Object.freeze([slot('target-read', 'foreign'), original.rowOperations[1]])})];
  for (const value of supplied) assert.throws(() => capture(value, driver),
    {code: 'InvalidInstalledEffectPlanDefinition'});
  assert.equal(callbacks, 0);
});

test('existing Row constructor retains the same definition before its first I/O await and refuses bad DATA first', async () => {
  const original = definition('update');
  const cid = 'sha256:' + 'a'.repeat(64);
  let io = 0, owner;
  const create = new Function('ports', `
    const {captureEffectResources,defaultLimits,checkDriver,profileOf,cidPattern,mkdir,createRowEffectStage}=ports;
    const captureManagedPlanDefinition=ports.capture,fail=ports.fail,text=ports.text;
    const optionalFunction=value=>value===undefined||typeof value==='function';
    ${declaration('createInstalledRowEffect')}
    return createInstalledRowEffect;
  `)({captureEffectResources: () => undefined, defaultLimits: {}, checkDriver: () => driver,
    profileOf: () => undefined, cidPattern: /^sha256:[0-9a-f]{64}$/u,
    async mkdir() {io++;}, createRowEffectStage(owners) {assert.equal(owners.length, 1);owner = owners[0];return owner;},
    capture, fail, text});
  const options = {moon: {}, mappings: [{resource: 'records', mappingRef: 'mapping', mappingCid: cid,
    body: JSON.stringify({mapping_contract_cid: cid, minimum_approval: 'required',
      target_ref: 'target', permission_rules: []})}], environmentWire: '{}', connectorId: 'original',
    connectorRegistration: 'original', connectorRevision: 'original/0.1', connection: 'original',
    site: {issueEffectGrant() {}, issueReadGrant() {}}, authorization: {authorize() {}},
    runtimeBundleCid: cid, bindingCid: 'original-binding', ledgerRoot: 'explicit-no-native-path', driver,
    managedPlanDefinition: original};
  assert.strictEqual(await create(options), owner);
  assert.strictEqual(owner.managedPlanDefinition, original);assert.equal(io, 1);
  await assert.rejects(create({...options, managedPlanDefinition: {...original}}),
    {code: 'InvalidInstalledEffectPlanDefinition'});
  assert.equal(io, 1);
});
