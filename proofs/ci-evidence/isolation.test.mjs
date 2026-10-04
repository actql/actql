import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync, lstatSync, symlinkSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {mutationSourcePaths, stageMutationSource, copyRegular, stageDistribution, loaderPaths,
  isolatedRunArguments, scratchDockerfile, mutationSnapshotExtras, isolatedEnvironment, isolatedSourceFiles} from './isolation.mjs';

const temporary = t => {
  const path = mkdtempSync(join(tmpdir(), 'actql-isolated-input-test-'));
  t.after(() => rmSync(path, {recursive: true, force: true})); return path;
};
function sources() {
  const bodies = new Map([
    ['src/unused_kernel/fixture.mbt', 'also read by the restoration snapshot'],
    ['src/connectors/local/provider.mbt', 'production'],
    ['proofs/bounded-session/mutations.mjs', 'original mutation action'],
    ['proofs/bounded-session/evidence.mjs', 'original snapshot'],
    ...isolatedSourceFiles.map(path => [path, path]),
    ...mutationSnapshotExtras.map(path => [path, path]),
    ['unrelated/private.txt', 'must not enter the image'],
  ]);
  return {bodies, tree: {entries: new Map([...bodies.keys()].map(path => [path, {kind: 'blob', mode: '100644'}])),
    read: path => Buffer.from(bodies.get(path))}};
}

test('stage the actual snapshot input set, preserving independently obtained Git bytes/modes', t => {
  const {tree, bodies} = sources(), destination = temporary(t);
  tree.entries.get('src/connectors/local/provider.mbt').mode = '100755';
  const paths = mutationSourcePaths(tree);
  assert(paths.includes('src/unused_kernel/fixture.mbt')); assert(!paths.includes('unrelated/private.txt'));
  assert(mutationSnapshotExtras.every(path => paths.includes(path)));
  const staged = stageMutationSource({tree, destination});
  assert.equal(staged.files.length, paths.length);
  for (const path of paths) assert.equal(readFileSync(join(destination, 'source', path), 'utf8'), bodies.get(path));
  assert.equal(lstatSync(join(destination, 'source/src/connectors/local/provider.mbt')).mode & 0o777, 0o755);
  assert.throws(() => stageMutationSource({tree, destination}), /EEXIST/u);
});

test('missing, symlink, submodule and traversal source entries cannot be copied as normal source', () => {
  for (const change of [
    tree => tree.entries.delete(mutationSnapshotExtras[2]),
    tree => tree.entries.get('src/connectors/local/provider.mbt').mode = '120000',
    tree => tree.entries.get('src/connectors/local/provider.mbt').kind = 'commit',
    tree => tree.entries.set('src/../outside', {kind: 'blob', mode: '100644'}),
  ]) {
    const {tree} = sources(); change(tree); assert.throws(() => mutationSourcePaths(tree));
  }
});

test('regular runtime copying binds actual bytes/mode and refuses links or byte overflow', t => {
  const root = temporary(t), source = join(root, 'node'), target = join(root, 'copy/node');
  writeFileSync(source, 'executable'); chmodSync(source, 0o755);
  const budget = {remaining: 10};
  const recorded = copyRegular({source, target, budget});
  assert.equal(recorded.bytes, 10); assert.equal(recorded.mode, 0o755); assert.equal(budget.remaining, 0);
  assert.equal(readFileSync(target, 'utf8'), 'executable');
  assert.throws(() => copyRegular({source, target: join(root, 'oversized'), budget: {remaining: 9}}));
  symlinkSync('node', join(root, 'link'));
  assert.throws(() => copyRegular({source: join(root, 'link'), target: join(root, 'linked-copy'), budget: {remaining: 100}}));
});

test('an internal README link remains a link whose staged target bytes are bound', t => {
  const root = temporary(t), source = join(root, 'moon'), destination = join(root, 'staged');
  mkdirSync(join(source, 'core/lazy_list'), {recursive: true}); writeFileSync(join(source, 'core/README.md'), 'core documentation');
  symlinkSync('../README.md', join(source, 'core/lazy_list/README.md'));
  const budget = {remaining: 100};
  const observation = stageDistribution({source, destination, budget});
  assert(observation.records.some(entry => entry.path === 'core/README.md' && entry.digest));
  assert.deepEqual(observation.records.find(entry => entry.kind === 'symlink'),
    {path: 'core/lazy_list/README.md', kind: 'symlink', mode: lstatSync(join(source, 'core/lazy_list/README.md')).mode & 0o777, target: '../README.md'});
  assert(lstatSync(join(destination, 'core/lazy_list/README.md')).isSymbolicLink());
  assert.equal(readFileSync(join(destination, 'core/lazy_list/README.md'), 'utf8'), 'core documentation');
});

test('outside, absolute, dangling and cyclic distribution links are not cleared as harmless', t => {
  const root = temporary(t); writeFileSync(join(root, 'outside'), 'must not read');
  for (const [name, target] of [['escape', '../outside'], ['absolute', join(root, 'outside')], ['dangling', 'missing'], ['cycle', 'cycle']]) {
    const source = join(root, name); mkdirSync(source); symlinkSync(target, join(source, name === 'cycle' ? 'cycle' : 'link'));
    assert.throws(() => stageDistribution({source, destination: join(root, `stage-${name}`), budget: {remaining: 100}}));
  }
});

test('entry and byte limits stop distribution staging instead of emitting a complete runtime', t => {
  const root = temporary(t), source = join(root, 'moon'); mkdirSync(source); writeFileSync(join(source, 'binary'), '12345');
  assert.throws(() => stageDistribution({source, destination: join(root, 'entry-limit'), budget: {remaining: 10}, maxEntries: 1}), /bound/u);
  assert.throws(() => stageDistribution({source, destination: join(root, 'byte-limit'), budget: {remaining: 4}}), /oversized/u);
});

test('loader extraction retains actual standard paths and refuses unknown or missing dependencies', () => {
  const output = 'linux-vdso.so.1 (0x123)\nlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x456)\n/lib64/ld-linux-x86-64.so.2 (0x789)\n';
  assert.deepEqual(loaderPaths(output), ['/lib/x86_64-linux-gnu/libc.so.6', '/lib64/ld-linux-x86-64.so.2']);
  for (const value of ['', 'libc.so.6 => not found', '/private/libc (0x123)', '/lib/../outside (0x123)', 'statically linked'])
    assert.throws(() => loaderPaths(value));
});

test('the action uses an immutable image, no host mount/network/secret environment, and fresh tmpfs', () => {
  const args = isolatedRunArguments({imageId: `sha256:${'a'.repeat(64)}`, cidFile: '/owned/container.id', owner: '1:2:3'});
  for (const value of ['--read-only', '--network=none', '--cap-drop=ALL', '--security-opt=no-new-privileges', '--pull=never'])
    assert(args.includes(value));
  assert(!args.includes('--mount') && !args.includes('-v') && !args.includes('--env') && !args.includes('--env-file'));
  assert(args.includes('/workspace:rw,nosuid,nodev,mode=1777'));
  assert.throws(() => isolatedRunArguments({imageId: 'mutable:latest', cidFile: '/owned/container.id'}));
  const dockerfile = scratchDockerfile(); assert(dockerfile.startsWith('FROM scratch\n'));
  assert.equal(Object.keys(isolatedEnvironment).includes('GITHUB_TOKEN'), false);
  assert(!dockerfile.includes('RUN ') && !dockerfile.includes('apt') && !dockerfile.includes('Lean'));
});
