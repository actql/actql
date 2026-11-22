import assert from 'node:assert/strict';
import {access, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
// @ts-expect-error TS7016: the installed Row Effect facade still has an authored JavaScript entry.
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {createInstalledRowEffectPlanCapture} from './installed-row-effect-plan-capture.mjs';

const {captureManagedPlanDefinition: capture} = createInstalledRowEffectPlanCapture({
  fail(code) {throw Object.assign(new Error(code), {code});},
  text: (value): value is string => typeof value === 'string' && value.length > 0,
});
const slot = (role: string, operation: string) => Object.freeze({role, operation});
const definition = (kind: string) => Object.freeze({kind, memberOperations: Object.freeze([]),
  rowOperations: Object.freeze(kind === 'update'
    ? [slot('target-read', 'original-observe'), slot('write', 'original-write')]
    : [slot('write', 'original-write')])});
const driver = {kinds: ['update', 'command'], targetRead: {operation: 'original-observe'}};

test('definition DATA retains exact original frozen slots and leaves legacy omission unchanged', () => {
  assert.equal(capture(undefined, driver), undefined);
  for (const kind of ['update', 'command']) {
    const original = definition(kind);
    assert.strictEqual(capture(original, driver), original);
    assert.strictEqual(capture(original, driver)!.rowOperations, original.rowOperations);
    assert.equal(original.memberOperations.length, 0);
  }
});

test('definition grammar refuses proxies, accessors, iterators and wrong role order without callbacks', () => {
  let callbacks = 0;
  const original = definition('update');
  const proxy = new Proxy(original, {ownKeys() {callbacks++; throw new Error('proxy');}});
  const getter = Object.freeze({get kind() {callbacks++; return 'update';},
    memberOperations: Object.freeze([]), rowOperations: original.rowOperations});
  const rowGetter: (typeof original.rowOperations)[number][] = [];Object.defineProperty(rowGetter, '0', {get() {callbacks++; return original.rowOperations[0];},
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

test('the original Row constructor checks definition DATA before creating its Ledger directory', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-row-effect-definition-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const ledgerRoot = join(root, 'ledger');
  const original = definition('update');
  const cid = 'sha256:' + 'a'.repeat(64);
  const unused = () => assert.fail('Unexpected grant, request, or provider call');
  const installedDriver = {...driver, kinds: ['update'], prepareRequest: unused, requestFacts: unused,
    writeOperation: unused, send: unused, project: unused, footprint: unused, observeTargets: unused,
    recoveryEntry: unused, recoverRequests: unused, requestCid: unused};
  let closed = 0, evidenceKinds = 0;
  const options = {moon: {strategyRemoteManagedOutputEvidenceKind() {evidenceKinds++; return 'unused-kind';}},
    mappings: [{resource: 'records', mappingRef: 'mapping', mappingCid: cid,
    body: JSON.stringify({mapping_contract_cid: cid, minimum_approval: 'required',
      target_ref: 'target', permission_rules: []})}], environmentWire: '{}', connectorId: 'original',
    connectorRegistration: 'original', connectorRevision: 'original/0.1', connection: 'original',
    site: {issueEffectGrant: unused, issueReadGrant: unused, close() {closed++;}},
    authorization: {authorize: unused}, runtimeBundleCid: cid, bindingCid: 'original-binding',
    ledgerRoot, driver: installedDriver, managedPlanDefinition: original};
  await assert.rejects(createInstalledRowEffect({...options, managedPlanDefinition: {...original}}),
    {code: 'InvalidInstalledEffectPlanDefinition'});
  await assert.rejects(access(ledgerRoot), {code: 'ENOENT'});
  assert.equal(evidenceKinds, 0);
  const adapter = await createInstalledRowEffect(options);
  t.after(() => { if (!closed) return adapter.close(); });
  await access(ledgerRoot);
  assert.equal(evidenceKinds, 1);
  assert.deepEqual(adapter.mappings, [{resource: 'records', target: 'target', mappingRef: 'mapping', mappingCid: cid}]);
  await adapter.close();
  assert.equal(closed, 1);
});
