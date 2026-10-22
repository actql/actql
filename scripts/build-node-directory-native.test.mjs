import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';
import {buildNodeDirectoryNative, directoryNativeDescriptor} from './build-node-directory-native.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
test('normal private directory artifact binds actual source, used headers, ABI and executable bytes', async () => {
  assert.equal(process.platform, 'darwin'); assert.equal(process.versions.node, '22.22.0');
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'directory-package-native-', label: 'selected normal directory artifact',
    digests: () => ['_build/native/directory-darwin-' + process.arch + '.node', directoryNativeDescriptor]});
  const outputs = buildNodeDirectoryNative({root, destination: scratch.path});
  const original = JSON.parse(outputs.get(directoryNativeDescriptor));
  assert.equal(original.platform, process.platform); assert.equal(original.arch, process.arch);
  assert.equal(original.node, process.versions.node); assert.equal(original.moduleAbi, process.versions.modules);
  assert.equal(original.napi, 8);
  assert.equal(original.source.sha256, sha(readFileSync(join(root, original.source.path))));
  assert.ok(original.headers.length > 5);
  assert.ok(original.headers.some(value => value.path === 'node/node_api.h'));
  assert.ok(original.headers.some(value => value.path.startsWith('sdk/')));
  assert.equal(JSON.stringify(original).includes(root), false);
  const binary = readFileSync(join(scratch.path, original.binary.path));
  assert.equal(binary.length, original.binary.bytes); assert.equal(sha(binary), original.binary.sha256);
  const require = createRequire(import.meta.url), native = require(join(scratch.path, original.binary.path));
  const directory = join(scratch.path, 'empty'); mkdirSync(directory);
  const handle = native.open(directory, 1, 1024, 1024);
  assert.equal(native.current(handle), undefined); assert.equal(native.next(handle), null);
  assert.deepEqual(native.close(handle), {outcome: 'closed', errno: 0});
  // Read-only freshness rebuilds the selected output; it never loads another
  // native instance or issues operational facility coverage.
  buildNodeDirectoryNative({root, destination: scratch.path, check: true});
  writeFileSync(join(scratch.path, '_build/native/unselected.node'), 'not an admitted artifact');
  assert.throws(() => buildNodeDirectoryNative({root, destination: scratch.path}),
    /StaleDirectoryNativeOutput/);
  scratch.passed();
});

test('native package generation refuses aliased parents before any compiler/output use', async () => {
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'directory-package-alias-', label: 'directory artifact alias refusal'});
  const destination = join(scratch.path, 'package'), outside = join(scratch.path, 'original');
  mkdirSync(destination); mkdirSync(outside); symlinkSync(outside, join(destination, '_build'));
  assert.throws(() => buildNodeDirectoryNative({root, destination}), /AliasedDirectoryNativeOutput/);
  assert.equal(existsSync(join(outside, 'native')), false);
  const dangling = join(scratch.path, 'dangling'); mkdirSync(dangling);
  symlinkSync(join(scratch.path, 'missing-target'), join(dangling, '_build'));
  assert.throws(() => buildNodeDirectoryNative({root, destination: dangling}), /AliasedDirectoryNativeOutput/);
  scratch.passed();
});
