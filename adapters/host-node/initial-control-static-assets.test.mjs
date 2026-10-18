import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import ownerModule from './initial-control-installation-owner.cjs';
import sourceModule from './initial-control-image-source.cjs';

const {createInitialControlInstallationOwner: createOwner} = ownerModule;
const changed = {code: 'NodeInitialControlOriginalChanged'};
const unavailable = {code: 'NodeInitialControlAssetUnavailable'};
const originals = () => ({host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}});

// The real byte primitive below supplies immutable Source only. These explicit
// operational controls test the existing private Owner, not the selected
// installation issuer, normal same-Host preparation or physical funding.
function fixture() {
  const original = originals(), expected = '{"original":"fixed-asset"}\n';
  let current = true, onRead, override = false, result;
  let reads = 0, closes = 0;
  const root = {assertCurrent(held) {
    assert.equal(this, root);
    for (const name of Object.keys(original)) assert.equal(held[name], original[name]);
    if (!current) throw refused;
  }, readAsset(held, path) {
    assert.equal(this, root); assert.equal(held.host, original.host); reads++;
    onRead?.();
    return override ? result : path === 'spec/control.json' ? expected : undefined;
  }, close() { assert.equal(this, root); closes++; return {pending: false}; }};
  const refused = new Error('OriginalOperationalCurrentRefused');
  const owner = createOwner(root), scope = owner.begin(original);
  return {root, owner, scope, original, expected, refused,
    setCurrent(value) { current = value; }, setOnRead(value) { onRead = value; },
    setResult(value) { override = true; result = value; },
    get reads() { return reads; }, get closes() { return closes; }};
}

test('an absent operational Owner refuses an asset before observing caller packets', () => {
  const owner = createOwner(undefined);
  let reads = 0;
  const packet = Object.defineProperty({}, 'host', {get() { reads++; }});
  assert.throws(() => owner.readAsset({}, packet, {}),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  assert.equal(reads, 0);
});

test('legacy operational controls without an asset original keep their existing cleanup', async () => {
  const root = {assertCurrent() {}, close() { return {pending: false}; }};
  const owner = createOwner(root), original = originals(), scope = owner.begin(original);
  assert.throws(() => owner.readAsset(scope, original, 'spec/control.json'), unavailable);
  assert.equal((await scope.close()).pending, false);
});

test('only the same nominal Scope and all five originals may borrow its fixed asset', () => {
  const f = fixture(), other = fixture();
  for (const value of [{}, {...f.scope}, other.scope, undefined]) {
    assert.throws(() => f.owner.readAsset(value, f.original, 'spec/control.json'), changed);
  }
  for (const name of Object.keys(f.original)) {
    assert.throws(() => f.owner.readAsset(f.scope, {...f.original, [name]: {}}, 'spec/control.json'), changed);
  }
  let reads = 0;
  const packet = Object.defineProperty({...f.original}, 'host', {get() { reads++; }});
  assert.throws(() => f.owner.readAsset(f.scope, packet, 'spec/control.json'), changed);
  assert.equal(f.reads, 0); assert.equal(reads, 0);
  assert.equal(f.owner.readAsset(f.scope, f.original, 'spec/control.json'), f.expected);
});

test('the asset projection retains the original callback receiver and has no path fallback', () => {
  const f = fixture();
  f.root.readAsset = () => { throw new Error('ReplacementAssetReader'); };
  assert.equal(f.owner.readAsset(f.scope, f.original, 'spec/control.json'), f.expected);
  assert.throws(() => f.owner.readAsset(f.scope, f.original, 'unselected.json'), unavailable);
  let coerced = 0;
  assert.throws(() => f.owner.readAsset(f.scope, f.original,
    {toString() { coerced++; return 'spec/control.json'; }}), unavailable);
  assert.equal(coerced, 0); assert.equal(f.reads, 2);
});

test('callback retirement refuses the String handoff while the same preparation stays pending', async () => {
  const f = fixture(), record = {}, duty = f.scope.retainPreparation(record);
  let closing;
  f.setOnRead(() => { closing = f.scope.close(); });
  assert.throws(() => f.owner.readAsset(f.scope, f.original, 'spec/control.json'), changed);
  assert.equal((await closing).pending, true);
  assert.equal(f.closes, 0);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(f.closes, 1);
  assert.equal(f.expected, '{"original":"fixed-asset"}\n');
});

test('after-callback operational current and original failure identity are preserved', async () => {
  const f = fixture();
  f.setOnRead(() => f.setCurrent(false));
  assert.throws(() => f.owner.readAsset(f.scope, f.original, 'spec/control.json'),
    error => error === f.refused);
  assert.equal((await f.scope.close()).pending, false);
  const other = fixture(), cleanupHandle = Object.freeze({status() { return {pending: true}; }, retry() {}});
  const cause = Object.freeze(Object.assign(new Error('OriginalAssetUnavailable'), {cleanupHandle}));
  other.setOnRead(() => { throw cause; });
  assert.throws(() => other.owner.readAsset(other.scope, other.original, 'spec/control.json'),
    error => error === cause && error.cleanupHandle === cleanupHandle);
  assert.equal(other.reads, 1);
});

test('malformed asset descriptors and non-String results cannot synthesize original Source', () => {
  let reads = 0;
  const base = {assertCurrent() {}, close() { return {pending: false}; }};
  const getter = Object.defineProperty({...base}, 'readAsset', {get() { reads++; }});
  assert.throws(() => createOwner(getter), changed);
  assert.equal(reads, 0);
  assert.throws(() => createOwner({...base, readAsset: false}),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  for (const value of [undefined, new String('copied'), Buffer.from('copied'), Promise.resolve('copied')]) {
    const f = fixture(); f.setResult(value);
    assert.throws(() => f.owner.readAsset(f.scope, f.original, 'spec/control.json'), unavailable);
    assert.equal(f.reads, 1);
  }
});

test('real same-FD captured asset stays original after pathname replacement and Scope close', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-initial-static-asset-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const file = join(directory, 'control.json'), bytes = Buffer.from('{"selected":"original"}\n');
  writeFileSync(file, bytes);
  const captured = sourceModule.captureInitialControlImageSource(file,
    {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')});
  const held = new Map([['spec/control.json', captured]]), original = originals();
  const root = {assertCurrent(value) { assert.equal(value.host, original.host); },
    readAsset(value, path) { assert.equal(this, root); assert.equal(value.host, original.host); return held.get(path)?.source; },
    close() { return {pending: false}; }};
  const owner = createOwner(root), scope = owner.begin(original);
  writeFileSync(file, '{"selected":"replacement"}');
  const escaped = owner.readAsset(scope, original, 'spec/control.json');
  assert.equal(escaped, bytes.toString('utf8'));
  assert.equal((await scope.close()).pending, false);
  assert.throws(() => owner.readAsset(scope, original, 'spec/control.json'), changed);
  // Scope retirement does not reclaim the original module holding or escaped
  // immutable String. Their lifetime remains separate, not a physical ACK.
  assert.equal(held.get('spec/control.json'), captured);
  assert.equal(escaped, captured.source);
});
