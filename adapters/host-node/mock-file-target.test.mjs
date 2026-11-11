import assert from 'node:assert/strict';
import test from 'node:test';
import {open, lstat, unlink, rename, writeFile, readFile, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createMockFileTarget} from './mock-file-target.mjs';

// Actual filesystem/FD/rename/sync tests. The projection callbacks below are
// explicit test ports, not Common declaration admission, authority or a Run.
const original = '{"a":"old","b":"old","exact":9007199254740993}\n';
const io = {open, lstat, unlink, rename};
async function fixture(options = {}) {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-mock-file-target-', label: 'Mock physical target'});
  const dataPath = join(scratch.path, 'data.json');
  await writeFile(dataPath, original);
  let checks = 0;
  const target = createMockFileTarget({dataPath, maxBytes: 4096,
    assertCurrent() {checks++;}, ...options});
  return {scratch, dataPath, target, checks: () => checks,
    async finish() {
      assert.equal((await target.close()).pending, false);
      scratch.passed();
    }};
}
const update = (target, from, to, options = {}) => target.updateChild({
  authorize() {}, replace(bytes) {
    const text = bytes.toString('utf8');
    assert.equal(text.includes(from), true);
    return Buffer.from(text.replace(from, to));
  }, ...options,
});

test('Mock write observation counts only returned replacement before later fences and cannot alter the operation', async () => {
  for (const mode of ['success', 'rename-refused', 'current-after-write', 'observer-throws', 'observer-rejects']) {
    let observed = 0, renamed = 0, changed = false;
    const runOriginal = Object.freeze({original: mode});
    const failure = new Error(mode);
    const f = await fixture({
      assertCurrent() {if (changed && mode === 'current-after-write') throw failure;},
      io: {...io, async rename(...args) {
        if (mode === 'rename-refused') throw failure;
        await rename(...args); renamed++;
      }},
      observeWrite(original) {
        assert.strictEqual(original, runOriginal);
        observed++; changed = true;
        if (mode === 'observer-throws') throw failure;
        if (mode === 'observer-rejects') return Promise.reject(failure);
      },
    });
    const child = update(f.target, '"a":"old"', '"a":"new"', {runOriginal});
    if (mode === 'rename-refused' || mode === 'current-after-write') {
      await assert.rejects(child.prepare(), error => error === failure);
      await assert.rejects(child.prepare(), error => error === failure);
    } else {
      await child.prepare(); await child.prepare();
    }
    assert.equal(renamed, mode === 'rename-refused' ? 0 : 1);
    assert.equal(observed, renamed, 'No retry, directory sync or cleanup becomes another write');
    assert.equal(await readFile(f.dataPath, 'utf8'), mode === 'rename-refused'
      ? original : original.replace('"a":"old"', '"a":"new"'));
    assert.equal((await child.release()).pending, false);
    assert.equal(observed, renamed);
    await f.finish();
  }
});

test('Mock file read owns its actual FD and original close until release', async () => {
  const f = await fixture();
  let authorized = 0;
  const child = f.target.readChild({authorize() {authorized++;},
    consume: bytes => bytes.toString('utf8')});
  assert.equal(f.target.status().children, 1);
  assert.equal(await child.prepare(), original);
  assert.equal(await child.prepare(), original);
  assert.equal(authorized, 1);
  assert.equal(child.status().pending, true);
  assert.equal((await child.release()).pending, false);
  await assert.rejects(child.prepare(), {code: 'MockFileChildRetired'});
  assert.ok(f.checks() > 0);
  await f.finish();
});

test('Mock physical writer serializes same-target Hosts and preserves another completed row', async () => {
  const f = await fixture();
  const sibling = createMockFileTarget({dataPath: f.dataPath, maxBytes: 4096, assertCurrent() {}});
  const first = update(f.target, '"a":"old"', '"a":"first"');
  assert.deepEqual(await first.prepare(), {bytes: Buffer.byteLength(original) + 2});
  const blocked = update(sibling, '"b":"old"', '"b":"second"');
  await assert.rejects(blocked.prepare(), {code: 'EEXIST'});
  assert.equal((await blocked.release()).pending, false);
  // Another failed child did not remove the first writer's actual exclusion.
  assert.equal((await lstat(f.dataPath + '.actql-write.lock')).isFile(), true);
  assert.equal((await first.release()).pending, false);
  const second = update(sibling, '"b":"old"', '"b":"second"');
  await second.prepare();
  assert.equal((await second.release()).pending, false);
  assert.equal(await readFile(f.dataPath, 'utf8'),
    original.replace('"a":"old"', '"a":"first"').replace('"b":"old"', '"b":"second"'));
  await sibling.close();
  await f.finish();
});

test('Mock target authorization refusal opens no FD and never changes the file', async () => {
  let opens = 0;
  const f = await fixture({io: {...io, open(...args) {opens++; return open(...args);}}});
  const denied = new Error('OriginalAccountDenied');
  for (const child of [f.target.readChild({authorize() {throw denied;}, consume() {assert.fail();}}),
    update(f.target, 'old', 'new', {authorize() {throw denied;}})]) {
    await assert.rejects(child.prepare(), error => error === denied);
    assert.equal((await child.release()).pending, false);
  }
  assert.equal(opens, 0);
  assert.equal(await readFile(f.dataPath, 'utf8'), original);
  await f.finish();
});

test('Mock physical target refuses an original changed during replacement preparation', async () => {
  let changed;
  const f = await fixture({io: {...io, async open(path, ...args) {
    if (path.endsWith('.tmp')) await changed;
    return open(path, ...args);
  }}});
  const other = Buffer.from(original.replace('"b":"old"', '"b":"external"'));
  // The physical current check must not trust the projection's earlier bytes.
  // Use a real separate write before its next awaited file-current boundary.
  const child = f.target.updateChild({authorize() {}, replace(bytes) {
    changed = writeFile(f.dataPath, other);
    return Buffer.from(bytes.toString('utf8').replace('"a":"old"', '"a":"new"'));
  }});
  await assert.rejects(child.prepare(), {code: 'MockFileTargetChanged'});
  await changed;
  assert.equal((await child.release()).pending, false);
  assert.equal(await readFile(f.dataPath, 'utf8'), other.toString('utf8'));
  await f.finish();
});

test('Mock write reply loss keeps the same failure and never repeats replacement', async () => {
  let replacements = 0;
  const lost = new Error('OriginalRenameReplyLost');
  const f = await fixture({io: {...io, async rename(...args) {
    replacements++; await rename(...args); throw lost;
  }}});
  const child = update(f.target, '"a":"old"', '"a":"new"');
  const first = child.prepare(), second = child.prepare();
  assert.equal(first, second);
  await assert.rejects(first, error => error === lost);
  await assert.rejects(child.prepare(), error => error === lost);
  assert.equal(replacements, 1);
  assert.equal((await child.release()).pending, false);
  assert.equal(await readFile(f.dataPath, 'utf8'), original.replace('"a":"old"', '"a":"new"'));
  assert.equal(replacements, 1);
  await f.finish();
});

test('Mock cleanup keeps writer exclusion and calls only the captured original close', async () => {
  let held, closes = 0, replacements = 0;
  const f = await fixture({io: {...io, async open(path, ...args) {
    const file = await open(path, ...args);
    if (path.endsWith('/data.json')) {
      held = file;
      const close = file.close;
      file.close = async function () {
        closes++;
        if (closes === 1) return false;
        return Reflect.apply(close, this, []);
      };
    }
    return file;
  }}});
  const child = update(f.target, '"a":"old"', '"a":"new"');
  await child.prepare();
  held.close = () => {replacements++; assert.fail('ReplacementMustNotAcknowledgeOriginalFD');};
  assert.equal((await child.release()).pending, true);
  assert.equal((await lstat(f.dataPath + '.actql-write.lock')).isFile(), true);
  assert.equal((await child.retry()).pending, false);
  assert.equal(closes, 2);
  assert.equal(replacements, 0);
  await f.finish();
});

test('Mock pending temporary cleanup cannot release its parent writer exclusion', async () => {
  let blocked = true, removes = 0;
  const failed = new Error('OriginalPrepareReplaceFailure');
  const f = await fixture({io: {...io, rename() {throw failed;},
    async unlink(path) {
      if (path.endsWith('.tmp')) {
        removes++;
        if (blocked) throw new Error('OriginalTemporaryStillOwned');
      }
      return unlink(path);
    }}});
  const child = update(f.target, '"a":"old"', '"a":"new"');
  await assert.rejects(child.prepare(), error => error === failed);
  assert.equal((await child.release()).pending, true);
  assert.equal((await lstat(f.dataPath + '.actql-write.lock')).isFile(), true);
  blocked = false;
  assert.equal((await child.retry()).pending, false);
  assert.equal(removes, 2);
  assert.equal(await readFile(f.dataPath, 'utf8'), original);
  await f.finish();
});

test('Mock file bounds and symlinks refuse without touching another physical target', async () => {
  const f = await fixture({maxBytes: 1});
  const tooLarge = f.target.readChild({authorize() {}, consume() {assert.fail();}});
  await assert.rejects(tooLarge.prepare(), {code: 'InvalidMockTargetFile'});
  assert.equal((await tooLarge.release()).pending, false);
  const link = join(f.scratch.path, 'linked.json');
  await symlink(f.dataPath, link);
  const target = createMockFileTarget({dataPath: link, maxBytes: 4096, assertCurrent() {}});
  const child = update(target, 'old', 'new');
  await assert.rejects(child.prepare(), {code: 'ELOOP'});
  assert.equal((await child.release()).pending, false);
  assert.equal((await lstat(link)).isSymbolicLink(), true);
  assert.equal(await readFile(f.dataPath, 'utf8'), original);
  await target.close();
  await f.finish();
});

test('Mock failed initial close getter retains the same FD until close-only retry', async () => {
  let opens = 0, getters = 0, closes = 0;
  const failure = new Error('OriginalCloseGetterUnavailable');
  const f = await fixture({io: {...io, async open(...args) {
    opens++;
    const file = await open(...args), close = file.close;
    Object.defineProperty(file, 'close', {configurable: true, get() {
      if (++getters === 1) throw failure;
      return function () {closes++; return Reflect.apply(close, this, []);};
    }});
    return file;
  }}});
  const child = f.target.readChild({authorize() {}, consume() {assert.fail('NoReadAfterFailedSetup');}});
  await assert.rejects(child.prepare(), error => error === failure);
  assert.equal(child.status().pending, true);
  assert.equal((await child.retry()).pending, false);
  assert.equal(opens, 1);
  assert.equal(getters, 2);
  assert.equal(closes, 1);
  await f.finish();
});

test('Mock lock-path replacement stays pending and never unlinks a foreign inode', async () => {
  const f = await fixture();
  const child = update(f.target, '"a":"old"', '"a":"new"');
  await child.prepare();
  const lock = f.dataPath + '.actql-write.lock', displaced = join(f.scratch.path, 'displaced-original-lock');
  await rename(lock, displaced);
  await writeFile(lock, 'foreign', {flag: 'wx'});
  assert.equal((await child.release()).pending, true);
  assert.equal(await readFile(lock, 'utf8'), 'foreign');
  assert.equal(child.status().errors[0].code, 'MockFileTargetPathChanged');
  // Restore only this fixture's exact original inode for its close-only retry.
  // Production never deletes/replaces another writer or repairs an old lock.
  await unlink(lock);
  await rename(displaced, lock);
  assert.equal((await child.retry()).pending, false);
  await f.finish();
});

test('Mock per-operation current fence is rechecked after the actual file await', async () => {
  let active = true;
  const revoked = new Error('OriginalAccountNoLongerCurrent');
  const f = await fixture({io: {...io, async open(path, ...args) {
    const file = await open(path, ...args);
    if (path.endsWith('/data.json')) active = false;
    return file;
  }}});
  const child = update(f.target, 'old', 'new', {assertCurrent() {if (!active) throw revoked;}});
  await assert.rejects(child.prepare(), error => error === revoked);
  assert.equal((await child.release()).pending, false);
  assert.equal(await readFile(f.dataPath, 'utf8'), original);
  await f.finish();
});

test('Mock current fences cannot be replaced by Boolean or asynchronous success', async () => {
  let opens = 0;
  const f = await fixture({io: {...io, open(...args) {opens++; return open(...args);}}});
  for (const assertCurrent of [() => true, async () => {}]) {
    const child = f.target.readChild({authorize() {}, consume() {assert.fail();}, assertCurrent});
    await assert.rejects(child.prepare(), {code: 'InvalidMockFileCurrentFence'});
    assert.equal((await child.release()).pending, false);
  }
  assert.equal(opens, 0);
  await f.finish();
});

test('Mock file Run close retires only its original children and keeps a sibling usable', async () => {
  const f = await fixture();
  // These are explicit scope identities for this physical-owner test, not
  // admitted Common Run handles, an Account decision or resource issuers.
  const firstRun = Object.freeze({}), secondRun = Object.freeze({});
  const makeRead = runOriginal => f.target.readChild({runOriginal,
    authorize() {}, consume: bytes => bytes.toString('utf8')});
  const first = makeRead(firstRun), second = makeRead(secondRun);
  assert.equal(await first.prepare(), original);
  assert.equal(await second.prepare(), original);
  assert.equal(f.target.status().children, 2);
  assert.equal((await f.target.closeFor(firstRun)).pending, false);
  assert.equal(first.status().pending, false);
  assert.equal(second.status().pending, true);
  assert.equal(f.target.statusFor(firstRun).children, 0);
  assert.equal(f.target.statusFor(secondRun).children, 1);
  assert.equal(f.target.status().closing, false);
  assert.throws(() => makeRead(firstRun), {code: 'MockFileRunClosing'});
  const later = makeRead(secondRun);
  assert.equal(await later.prepare(), original);
  assert.equal((await later.release()).pending, false);
  assert.equal((await f.target.closeFor(secondRun)).pending, false);
  await f.finish();
});

test('Mock per-Run pending original close is independent and survives current loss', async () => {
  let held, closes = 0, replacements = 0, current = true;
  const f = await fixture({assertCurrent() {
    if (!current) throw new Error('OriginalHostNoLongerCurrent');
  }, io: {...io, async open(...args) {
    const file = await open(...args);
    if (held === undefined) {
      held = file;
      const close = file.close;
      file.close = async function () {
        if (++closes === 1) return false;
        return Reflect.apply(close, this, []);
      };
    }
    return file;
  }}});
  const firstRun = Object.freeze({}), secondRun = Object.freeze({});
  const makeRead = runOriginal => f.target.readChild({runOriginal,
    authorize() {}, consume: bytes => bytes.toString('utf8')});
  const first = makeRead(firstRun), second = makeRead(secondRun);
  await first.prepare(); await second.prepare();
  held.close = () => {replacements++; assert.fail('ReplacementIsNotOriginalAck');};
  current = false;
  await assert.rejects(f.target.closeFor(firstRun), {code: 'MockFileCleanupPending'});
  assert.equal(f.target.statusFor(firstRun).pending, true);
  assert.equal(f.target.statusFor(secondRun).pending, true);
  assert.equal((await f.target.closeFor(secondRun)).pending, false);
  assert.equal(first.status().pending, true);
  assert.equal((await f.target.closeFor(firstRun)).pending, false);
  assert.equal(closes, 2); assert.equal(replacements, 0);
  await f.finish();
});

test('Mock Run close waits for the original late FD acquisition before its physical ACK', async () => {
  let start, release, closes = 0;
  const started = new Promise(resolve => {start = resolve;});
  const paused = new Promise(resolve => {release = resolve;});
  const f = await fixture({io: {...io, async open(...args) {
    const file = await open(...args), close = file.close;
    file.close = function () {closes++; return Reflect.apply(close, this, []);};
    start(); await paused;
    return file;
  }}});
  const runOriginal = Object.freeze({});
  const child = f.target.readChild({runOriginal, authorize() {},
    consume() {assert.fail('NoReadAfterRunClose');}});
  const prepared = child.prepare();
  // Observe the original rejection before allowing close to finish.
  const refused = assert.rejects(prepared, {code: 'MockFileRunClosing'});
  await started;
  const closing = f.target.closeFor(runOriginal);
  assert.equal(f.target.closeFor(runOriginal), closing);
  await Promise.resolve();
  assert.equal(f.target.statusFor(runOriginal).pending, true);
  assert.equal(closes, 0);
  release();
  await refused;
  assert.equal((await closing).pending, false);
  assert.equal(child.status().pending, false);
  assert.equal(closes, 1);
  await f.finish();
});
