// Complete the same Local artifact after its selected libraries have consumed
// the original completed provider. This reads build evidence; it never builds,
// executes a binary, changes a source identity or admits a runtime permission.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, open, readFile, readdir} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {releaseVersion} from './release-version.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
// Match the pinned compiler driver's checkout-source/runtime spelling adjustment.
// Include order/options, outputs and all other arguments remain unchanged.
const canonicalCArguments = (arguments_, repository) => arguments_.map(value =>
  value.startsWith('-I./.toolchains/') ? `-I${resolve(repository, value.slice(2))}`
    : ((value.startsWith('./src/') && value.endsWith('.c')) || value.startsWith('./.toolchains/'))
    ? resolve(repository, value) : value);

async function observedFile(path, expected, maximum = 512 * 1024 * 1024) {
  assert.equal(expected.path, path);
  assert(Number.isSafeInteger(expected.bytes) && expected.bytes >= 0 && expected.bytes <= maximum);
  assert.match(expected.sha256, /^[a-f0-9]{64}$/u);
  const fd = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await fd.stat();
    assert(before.isFile() && before.size === expected.bytes);
    const hash = createHash('sha256'), buffer = Buffer.alloc(1024 * 1024);
    let offset = 0;
    for (;;) {
      const {bytesRead} = await fd.read(buffer, 0, buffer.length, null);
      if (!bytesRead) break;
      offset += bytesRead;
      assert(offset <= expected.bytes);
      hash.update(buffer.subarray(0, bytesRead));
    }
    const after = await fd.stat(), named = await lstat(path);
    assert(offset === before.size && after.size === before.size &&
      after.dev === before.dev && after.ino === before.ino &&
      after.mtimeMs === before.mtimeMs && after.ctimeMs === before.ctimeMs);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === before.dev && named.ino === before.ino);
    assert.equal(hash.digest('hex'), expected.sha256, 'Completed provider member changed');
  } finally {await fd.close();}
}

async function jsonMember(path, maximum) {
  const fd = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await fd.stat();
    assert(before.isFile() && before.size > 0 && before.size <= maximum);
    const bytes = await fd.readFile(), after = await fd.stat(), named = await lstat(path);
    assert(bytes.length === before.size && after.size === before.size &&
      after.mtimeMs === before.mtimeMs && after.ctimeMs === before.ctimeMs);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === before.dev && named.ino === before.ino);
    return JSON.parse(bytes.toString('utf8'));
  } finally {await fd.close();}
}

export async function admitCompletedNativeLocalProvider(destination, source, repository, moonHome, {packageVersion} = {}) {
  const selectedVersion = packageVersion === undefined ? undefined : releaseVersion(packageVersion).version;
  assert.match(source, /^[a-f0-9]{40}$/u);
  destination = resolve(destination);
  const directory = await lstat(destination);
  assert(directory.isDirectory() && !directory.isSymbolicLink());
  // A completed artifact or partially assembled sidecar is not another fresh
  // finalization attempt. Preserve it for its own original failure handling.
  assert.deepEqual(await readdir(destination), ['native-producer']);
  const provider = join(destination, 'native-producer');
  const original = await lstat(provider);
  assert(original.isDirectory() && !original.isSymbolicLink());
  const receipt = await jsonMember(join(provider, 'build.json'), 65536);
  assert.equal(receipt.source, source, 'Completed provider must have the exact current source');
  assert.equal(receipt.entry, 'src/cmd/native_client');
  assert.equal(receipt.target, 'darwin-arm64');
  assert.equal(receipt.plan_only, false);
  assert.equal(receipt.moon_build_exit, 0);
  assert.equal(receipt.providers, 1);
  assert.equal(receipt.core_modules, 1);
  const commands = await jsonMember(join(provider, 'commands.json'), 16 * 1024 * 1024);
  assert(Array.isArray(commands) && commands.length > 0 && commands.length <= 10000);
  assert(commands.every(command => Array.isArray(command) && command.every(part => typeof part === 'string')));
  const commandSignatures = new Set(commands.map(command => JSON.stringify(command)));
  assert.equal(receipt.commands_completed, commands.length);
  const plan = await jsonMember(join(provider, 'cc-plan.json'), 4 * 1024 * 1024);
  assert(Array.isArray(plan.steps) && plan.steps.length > 0 && plan.steps.length <= 256);
  assert.equal(receipt.completed_c_steps, plan.steps.length);
  if (selectedVersion !== undefined) {
    assert.equal(receipt.package_version, selectedVersion, 'Completed provider has another or no explicit package version');
    const steps = plan.steps.filter(step => step.original.some(value =>
      value.endsWith('src/cmd/native_client/version_stub.c')));
    assert.equal(steps.length, 1);
    assert.deepEqual(steps[0].selected.filter(value => value.startsWith('-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION')),
      [`-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION=${JSON.stringify(selectedVersion)}`]);
  }
  const executed = new Set();
  for (const step of plan.steps) {
    assert(Array.isArray(step.selected) && commandSignatures.has(JSON.stringify(step.selected)));
    assert(isAbsolute(step.receipt) && resolve(step.receipt).startsWith(provider + '/'));
    assert(!executed.has(step.receipt)); executed.add(step.receipt);
    const actual = await jsonMember(step.receipt, 1024 * 1024);
    assert.equal(actual.exit, 0);
    assert.deepEqual(canonicalCArguments(actual.original, repository),
      canonicalCArguments(step.original, repository));
    assert.deepEqual(actual.selected, step.selected);
    assert(actual.output && isAbsolute(actual.output.path));
    assert(resolve(actual.output.path).startsWith(join(provider, 'emission') + '/'));
    const output = step.selected.indexOf('-o');
    assert(output >= 0 && actual.output.path === step.selected[output + 1]);
    await observedFile(actual.output.path, actual.output);
  }
  const inputs = await jsonMember(join(provider, 'inputs.json'), 16 * 1024 * 1024);
  assert(Array.isArray(inputs) && inputs.length > 0 && inputs.length <= 20000);
  const paths = new Set();
  for (const input of inputs) {
    assert(isAbsolute(input.path) && !paths.has(input.path)); paths.add(input.path);
    await observedFile(input.path, input);
  }
  for (const path of [join(repository, 'toolchain.json'), join(repository, 'moon.mod'),
    join(repository, 'scripts/produce-native-remote-scoped-runtime.py'),
    join(repository, 'packages/python-local-runtime/native/pre-root/scoped-read-source.json'),
    join(moonHome, 'bin/moon'), join(moonHome, 'bin/moonc'), join(moonHome, 'installed.json')]) {
    assert(paths.has(path), 'Completed provider is missing a required original input');
  }
  if (selectedVersion !== undefined) for (const path of ['scripts/release-version.mjs', 'scripts/python_release_cohort.py',
    'src/cmd/native_client/version_stub.c'])
    assert(paths.has(join(repository, path)), 'Completed versioned provider lacks its original version projection');
  const recipe = await readFile(join(repository, 'packages/python-local-runtime/native/pre-root/scoped-read-source.json'));
  assert.equal(receipt.allocator.recipe_sha256, digest(recipe));
  const parsed = JSON.parse(recipe.toString('utf8'));
  assert.equal(receipt.allocator.patch_sha256, parsed.patch.sha256);
  assert.deepEqual(receipt.allocator.required_defines, parsed.required_defines);
  assert.deepEqual(receipt.allocator.outputs, parsed.outputs);
  const build = join(provider, 'emission/native/release/build/cmd/native_client');
  const binary = join(build, 'native_client.exe'), generatedC = join(build, 'native_client.c');
  await observedFile(binary, receipt.executable, 64 * 1024 * 1024);
  await observedFile(generatedC, receipt.generated_c);
  const generation = await jsonMember(join(provider, 'moon-build-command.json'), 65536);
  assert.deepEqual(generation, [join(moonHome, 'bin/moon'), 'build', '--target', 'native', '--release',
    '--target-dir', join(provider, 'emission'), '-j', '1', 'src/cmd/native_client', '--verbose']);
  return {receipt, binary, generatedC, generation};
}
