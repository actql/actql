// Matching-target inputs for the existing process/channel retirement cases.
// The Rust/C leaf is a test fixture, not an Engine, VM or installed supplier.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {closeSync, existsSync, ftruncateSync, mkdirSync, mkdtempSync, openSync,
  readFileSync, renameSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

const labels = ['prepared', 'capture-refusal', 'startup', 'rust-handler', 'rust-aborted',
  'process-channel-foreign', 'process-channel-unstarted', 'process-channel-started',
  'process-channel-pending', 'process-channel-read-context'];

// The existing workspace's pinned Cargo.lock selects this libc body.
// Cargo executes its original build script; no handwritten pthread ABI stands in.
const libc = {version: '0.2.171', sha256:
  'c19937216e9d3aa9956d9bb8dfc0b0c8beb6058fc4f7a4dc4d850edf86a237d6'};

function rustCompiler(repository, execute) {
  const pin = JSON.parse(readFileSync(join(repository,
    'packages/python-local-runtime/native/pre-root/builder-toolchain.json'), 'utf8'));
  const base = join(repository, '.toolchains');
  mkdirSync(base, {recursive: true});
  const destination = join(base, `native-core-handler-rust-${pin.toolchain}`);
  const selected = pin.components.filter(value => ['rustc', 'rust-std', 'cargo'].includes(value.component));
  assert.equal(selected.length, 3);
  const marker = JSON.stringify({toolchain: pin.toolchain, components: selected});
  const verify = directory => {
    const binary = join(directory, 'bin/rustc');
    const version = execute(binary, ['--version', '--verbose'],
      {encoding: 'utf8', timeout: 15000, maxBuffer: 65536});
    assert(version.includes(`commit-hash: ${pin.rustc_commit}\n`), 'Selected Rust commit required');
    assert(version.includes(`host: ${pin.target}\n`), 'Selected Rust target required');
    const cargo = join(directory, 'bin/cargo');
    assert(execute(cargo, ['--version'], {encoding: 'utf8', timeout: 15000, maxBuffer: 65536})
      .startsWith('cargo 1.90.0 '), 'Selected Cargo version required');
    return {rustc: binary, cargo};
  };
  if (existsSync(destination)) {
    assert.equal(readFileSync(join(destination, 'installed.json'), 'utf8'), marker);
    return verify(destination);
  }
  const stage = mkdtempSync(join(base, 'native-core-rust-install-'));
  const install = join(stage, 'toolchain');
  mkdirSync(install);
  const cache = join(base, 'native-core-rust-archives');
  mkdirSync(cache, {recursive: true});
  // Failed preparations remain owned here; never replace a selected toolchain.
  for (const entry of selected) {
    const archive = join(cache, entry.sha256 + '.tar.xz');
    if (!existsSync(archive)) execute('curl', ['--fail', '--location', '--silent', '--show-error',
      '--connect-timeout', '20', '--max-time', '180', entry.url, '--output', archive],
    {stdio: 'inherit', timeout: 185000});
    const bytes = readFileSync(archive);
    assert.equal(bytes.length, entry.bytes, 'Pinned Rust archive extent required');
    assert.equal(createHash('sha256').update(bytes).digest('hex'), entry.sha256,
      'Pinned Rust archive digest required');
    execute('tar', ['-xJf', archive, '-C', stage], {stdio: 'inherit', timeout: 60000});
    const name = new URL(entry.url).pathname.split('/').at(-1).replace(/\.tar\.xz$/u, '');
    execute('/bin/sh', [join(stage, name, 'install.sh'), '--prefix=' + install,
      '--disable-ldconfig'], {stdio: 'inherit', timeout: 60000});
  }
  verify(install);
  writeFileSync(join(install, 'installed.json'), marker, {flag: 'wx', mode: 0o600});
  renameSync(install, destination);
  return verify(destination);
}

export function nativeProcessRegionFixture(repository, namespace, {
  execute = execFileSync, platform = process.platform, arch = process.arch,
} = {}) {
  assert.equal(platform, 'darwin', 'Existing process fixture requires Darwin arm64');
  assert.equal(arch, 'arm64', 'Existing process fixture requires Darwin arm64');
  const page = Number(execute('/usr/bin/getconf', ['PAGESIZE'],
    {encoding: 'utf8', timeout: 5000, maxBuffer: 65536}).trim());
  assert(Number.isSafeInteger(page) && page > 0);
  const directory = join(namespace, 'process-region');
  mkdirSync(directory, {mode: 0o700});
  for (const label of labels) {
    const fd = openSync(join(directory, label + '.backing'), 'wx', 0o600);
    try { ftruncateSync(fd, 64 * page); } finally { closeSync(fd); }
  }
  const source = join(repository, 'packages/python-local-runtime/native/pre-root/fixtures');
  const library = join(directory, 'handler-thread.dylib');
  const child = join(directory, 'handler-process-child');
  const tools = rustCompiler(repository, execute);
  const archive = join(repository, '.toolchains/native-core-rust-archives', libc.sha256 + '.crate');
  if (!existsSync(archive)) execute('curl', ['--fail', '--location', '--silent', '--show-error',
    '--connect-timeout', '20', '--max-time', '90',
    `https://static.crates.io/crates/libc/libc-${libc.version}.crate`, '--output', archive],
  {stdio: 'inherit', timeout: 95000});
  assert.equal(createHash('sha256').update(readFileSync(archive)).digest('hex'), libc.sha256);
  execute('tar', ['-xzf', archive, '-C', directory], {stdio: 'inherit', timeout: 30000});
  const manifest = join(directory, 'Cargo.toml');
  writeFileSync(manifest, '[package]\nname="actql-native-handler-fixture"\nversion="0.0.0"\nedition="2021"\n' +
    '[lib]\ncrate-type=["cdylib"]\npath=' + JSON.stringify(join(source, 'handler_thread_rust.rs')) +
    '\n[dependencies]\nlibc={path=' + JSON.stringify(join(directory, `libc-${libc.version}`)) + '}\n',
  {flag: 'wx', mode: 0o600});
  // One C provider shared by the child and the Rust leaf, never a second copy.
  execute('cc', ['-std=c11', '-O1', '-D_DARWIN_C_SOURCE', '-pthread', '-dynamiclib',
    '-Wl,-install_name,@rpath/libactql_native_control.dylib',
    join(source, 'handler_thread_provider.c'), join(source, '../owned_image.c'),
    '-o', join(directory, 'libactql_native_control.dylib')],
  {stdio: 'inherit', timeout: 120000});
  execute(tools.cargo, ['build', '--offline', '--release', '--manifest-path', manifest],
    {stdio: 'inherit', timeout: 120000, env: {...process.env, RUSTC: tools.rustc,
      CARGO_TARGET_DIR: join(directory, 'rust-target'),
      CARGO_ENCODED_RUSTFLAGS: ['-L', 'native=' + directory, '-C',
        'link-arg=-Wl,-rpath,' + directory].join('\x1f')}});
  renameSync(join(directory, 'rust-target/release/libactql_native_handler_fixture.dylib'), library);
  execute('cc', ['-std=c11', '-O1', '-D_DARWIN_C_SOURCE', '-pthread',
    '-Wl,-rpath,@loader_path', join(source, 'handler_process_child.c'),
    '-L', directory, '-lactql_native_control', '-o', child],
  {stdio: 'inherit', timeout: 120000});
  return {ACTQL_TEST_NATIVE_PROCESS_REGION_ROOT: directory,
    ACTQL_TEST_NATIVE_HANDLER_PROCESS_CHILD: child,
    ACTQL_TEST_NATIVE_HANDLER_LIBRARY: library};
}
