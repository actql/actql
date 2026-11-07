import assert from 'node:assert/strict';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nativeProcessRegionFixture} from './native-process-region-fixture.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-process-inputs-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const source = 'packages/python-local-runtime/native/pre-root';
  mkdirSync(join(root, source), {recursive: true});
  copyFileSync(new URL('../' + source + '/builder-toolchain.json', import.meta.url),
    join(root, source, 'builder-toolchain.json'));
  const pin = JSON.parse(readFileSync(join(root, source, 'builder-toolchain.json'), 'utf8'));
  const selected = pin.components.filter(value => ['rustc', 'rust-std', 'cargo'].includes(value.component));
  const tools = join(root, '.toolchains', 'native-core-handler-rust-' + pin.toolchain);
  mkdirSync(tools, {recursive: true});
  writeFileSync(join(tools, 'installed.json'), JSON.stringify({toolchain: pin.toolchain, components: selected}));
  const namespace = join(root, 'invocation'); mkdirSync(namespace);
  const calls = [];
  const execute = (command, args) => {
    calls.push([command, args]);
    if (command === '/usr/bin/getconf') return '16384\n';
    if (command === join(tools, 'bin/rustc')) {
      return `commit-hash: ${pin.rustc_commit}\nhost: ${pin.target}\n`;
    }
    if (command === join(tools, 'bin/cargo')) return 'cargo 1.90.0 (original fixture)\n';
    throw new Error('Unselected fixture command: ' + command);
  };
  return {root, namespace, tools, calls, execute};
}

test('process input preparation rejects another platform before acquiring inputs', () => {
  for (const [platform, arch] of [['linux', 'arm64'], ['darwin', 'x64']]) {
    assert.throws(() => nativeProcessRegionFixture('/unused', '/unused', {
      platform, arch, execute() {assert.fail('No command before platform admission');},
    }), /Darwin arm64/u);
  }
});

test('process input preparation refuses a different cached compiler selection', t => {
  const f = fixture(t);
  writeFileSync(join(f.tools, 'installed.json'), '{}');
  assert.throws(() => nativeProcessRegionFixture(f.root, f.namespace,
    {...f, platform: 'darwin', arch: 'arm64'}), /Expected values/u);
  assert.deepEqual(f.calls.map(([command]) => command), ['/usr/bin/getconf']);
});

test('process input preparation checks the actual cached Rust commit before compilation', t => {
  const f = fixture(t);
  assert.throws(() => nativeProcessRegionFixture(f.root, f.namespace, {
    platform: 'darwin', arch: 'arm64', execute(command, args) {
      if (command === join(f.tools, 'bin/rustc')) return 'commit-hash: foreign\nhost: aarch64-apple-darwin\n';
      return f.execute(command, args);
    },
  }), /Selected Rust commit/u);
});

test('process input preparation preserves fresh physical backing when a dependency digest refuses', t => {
  const f = fixture(t);
  const cache = join(f.root, '.toolchains/native-core-rust-archives');
  mkdirSync(cache);
  writeFileSync(join(cache,
    'c19937216e9d3aa9956d9bb8dfc0b0c8beb6058fc4f7a4dc4d850edf86a237d6.crate'),
  'foreign dependency');
  assert.throws(() => nativeProcessRegionFixture(f.root, f.namespace,
    {...f, platform: 'darwin', arch: 'arm64'}), /Expected values/u);
  const directory = join(f.namespace, 'process-region');
  const names = ['prepared', 'capture-refusal', 'startup', 'rust-handler', 'rust-aborted',
    'process-channel-foreign', 'process-channel-unstarted', 'process-channel-started',
    'process-channel-pending', 'process-channel-read-context'];
  assert.deepEqual(readdirSync(directory).sort(), names.map(name => name + '.backing').sort());
  for (const name of names) {
    const info = statSync(join(directory, name + '.backing'));
    assert.equal(info.mode & 0o777, 0o600);
    assert.equal(info.size, 64 * 16384);
    assert.equal(existsSync(join(directory, name + '.slot')), false);
  }
  assert(f.calls.every(([command]) => command === '/usr/bin/getconf' ||
    command === join(f.tools, 'bin/rustc') || command === join(f.tools, 'bin/cargo')));
  assert.throws(() => nativeProcessRegionFixture(f.root, f.namespace,
    {...f, platform: 'darwin', arch: 'arm64'}), {code: 'EEXIST'});
});
