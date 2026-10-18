import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const connect = tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'connectEmbeddedLocal');
const control = connect.body.body.flatMap(node => node.declarations ?? [])
  .find(node => node.id.name === 'initialControl');
const close = control.init.arguments[0].properties.find(node => node.key.name === 'close').value;
const body = source.slice(close.body.start + 1, close.body.end - 1);
// Execute the actual final-duty statements with explicit Source/initial
// receivers. This does not issue either original or a physical cleanup ACK.
const make = compileFunction(`
  let {sourceManaged,sourceManagedClose,control,controlClose,originalInstallation,originals,duty}=state;
  let observedClose,adopted=false;
  return {async close(){${body}}, retained(){return {sourceManaged,originalInstallation,originals,duty};}};
`, ['state', 'retirePreparationReferences', 'profiles', 'host', 'clientOperationError']);

function fixture(sourceClose) {
  const host = {}, installation = {}, originals = {}, duty = {};
  const calls = [];
  const sourceManaged = {close() {assert.equal(this, sourceManaged); calls.push('source'); return sourceClose();}};
  const observation = Object.freeze({pending: false, originalParentObservation: true});
  const control = {close() {assert.equal(this, control); calls.push('parent'); return observation;}};
  const state = {sourceManaged, sourceManagedClose: sourceManaged.close,
    control, controlClose: control.close, originalInstallation: installation, originals, duty};
  const owner = make(state, () => calls.push('references'), {
    retirePreparation(h, i, generation) {
      assert.equal(h, host); assert.equal(i, installation); assert.equal(generation, host);
      calls.push('registry');
    },
  }, host, code => Object.assign(new Error(code), {code}));
  return {owner, calls, observation, sourceManaged, installation, originals, duty};
}

test('the actual Host final duty retains Mock/config originals until the same Source close confirms', async () => {
  let pending = true;
  const f = fixture(() => ({pending}));
  await assert.rejects(f.owner.close(), {code: 'InstalledSourcePreparationCleanupPending'});
  assert.deepEqual(f.calls, ['source']);
  assert.equal(f.owner.retained().sourceManaged, f.sourceManaged);
  assert.equal(f.owner.retained().originalInstallation, f.installation);
  assert.equal(f.owner.retained().originals, f.originals);
  assert.equal(f.owner.retained().duty, f.duty);
  pending = false;
  assert.equal(await f.owner.close(), f.observation);
  assert.deepEqual(f.calls, ['source', 'source', 'references', 'parent', 'registry']);
  assert.deepEqual(f.owner.retained(), {sourceManaged: undefined, originalInstallation: undefined,
    originals: undefined, duty: undefined});
  assert.equal(await f.owner.close(), f.observation);
  assert.equal(f.calls.length, 5);
});

test('a replaced Source close cannot acknowledge the captured original after a failed attempt', async () => {
  let pending = true;
  const failure = Object.freeze(new Error('OriginalSourceCloseUnknown'));
  const f = fixture(() => {if (pending) throw failure; return {pending: false};});
  f.sourceManaged.close = () => assert.fail('ReplacementSourceClose');
  await assert.rejects(f.owner.close(), error => error === failure);
  assert.deepEqual(f.calls, ['source']);
  pending = false;
  assert.equal(await f.owner.close(), f.observation);
  assert.deepEqual(f.calls, ['source', 'source', 'references', 'parent', 'registry']);
});

test('only an own DATA Source pending:false can release the final original parent', async () => {
  let observation, reads = 0;
  const f = fixture(() => observation);
  for (observation of [undefined, {}, Object.create({pending: false}),
    Object.defineProperty({}, 'pending', {get() {reads++; return false;}})]) {
    await assert.rejects(f.owner.close(), {code: 'InstalledSourcePreparationCleanupPending'});
    assert.equal(f.owner.retained().sourceManaged, f.sourceManaged);
  }
  assert.equal(reads, 0); assert.ok(f.calls.every(name => name === 'source'));
  observation = {pending: false};
  await f.owner.close();
  assert.deepEqual(f.calls.slice(-3), ['references', 'parent', 'registry']);
});
