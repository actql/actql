import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {admitCompletedNativeLocalProvider} from './native-cli-completed-provider.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const source = 'a'.repeat(40);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-completed-provider-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const repository = join(root, 'source'), moon = join(root, 'moon'), artifact = join(root, 'artifact');
  const provider = join(artifact, 'native-producer');
  await mkdir(provider, {recursive: true});
  const json = async (path, value) => {
    await mkdir(dirname(path), {recursive: true});
    await writeFile(path, JSON.stringify(value));
  };
  const original = async (path, text) => {
    await mkdir(dirname(path), {recursive: true});
    const bytes = Buffer.from(text); await writeFile(path, bytes);
    return {path, bytes: bytes.length, sha256: sha(bytes)};
  };
  // Synthetic build metadata only. No compiler, binary, Host or component is
  // executed, and this fixture cannot establish ordinary package qualification.
  const recipe = {patch: {sha256: 'b'.repeat(64)}, required_defines: ['SELECTED'], outputs: {allocator: 'c'.repeat(64)}};
  const recipePath = join(repository, 'packages/python-local-runtime/native/pre-root/scoped-read-source.json');
  const inputs = [];
  for (const path of [join(repository, 'toolchain.json'), join(repository, 'moon.mod'),
    join(repository, 'scripts/produce-native-remote-scoped-runtime.py'),
    join(moon, 'bin/moon'), join(moon, 'bin/moonc'), join(moon, 'installed.json')]) {
    inputs.push(await original(path, 'synthetic-not-executable\n'));
  }
  inputs.push(await original(recipePath, JSON.stringify(recipe)));
  const build = join(provider, 'emission/native/release/build/cmd/native_client');
  const binary = await original(join(build, 'native_client.exe'), 'synthetic-not-a-binary');
  const generated = await original(join(build, 'native_client.c'), 'synthetic-generated-C');
  const command = ['selected-clang', '-o', binary.path, generated.path];
  const step = {original: command.slice(1), selected: command, receipt: join(provider, 'cc-0.json')};
  const receipt = {source, entry: 'src/cmd/native_client', target: 'darwin-arm64',
    plan_only: false, moon_build_exit: 0, providers: 1, core_modules: 1,
    commands_completed: 1, completed_c_steps: 1, executable: binary, generated_c: generated,
    allocator: {recipe_sha256: sha(Buffer.from(JSON.stringify(recipe))),
      patch_sha256: recipe.patch.sha256, required_defines: recipe.required_defines, outputs: recipe.outputs}};
  const generation = [join(moon, 'bin/moon'), 'build', '--target', 'native', '--release',
    '--target-dir', join(provider, 'emission'), '-j', '1', 'src/cmd/native_client', '--verbose'];
  await json(join(provider, 'build.json'), receipt);
  await json(join(provider, 'commands.json'), [command]);
  await json(join(provider, 'cc-plan.json'), {steps: [step]});
  await json(step.receipt, {...step, exit: 0, output: binary});
  await json(join(provider, 'inputs.json'), inputs);
  await json(join(provider, 'moon-build-command.json'), generation);
  return {root, repository, moon, artifact, provider, receipt, generated, binary, inputs, step, generation, json,
    admit: () => admitCompletedNativeLocalProvider(artifact, source, repository, moon)};
}

test('completed Local provider keeps exact source, bytes and actual generation without executing tools', async t => {
  const f = await fixture(t);
  const result = await f.admit();
  assert.deepEqual(result, {receipt: f.receipt, binary: f.binary.path,
    generatedC: f.generated.path, generation: f.generation});
  await assert.rejects(readFile(join(f.artifact, 'artifact.json')), {code: 'ENOENT'});
});

test('completed versioned Local provider retains the actual original version C step and cannot relabel an old provider', async t => {
  const f = await fixture(t), version = '0.0.7-rc.1';
  const admit = () => admitCompletedNativeLocalProvider(f.artifact, source, f.repository, f.moon, {packageVersion: version});
  await assert.rejects(admit(), /another or no explicit package version/u);
  f.receipt.package_version = version;
  await f.json(join(f.provider, 'build.json'), f.receipt);
  await assert.rejects(admit());
  const object = {path: join(f.provider, 'emission/version.o'), bytes: 1, sha256: sha(Buffer.from('v'))};
  await writeFile(object.path, 'v');
  const original = ['-c', './src/cmd/native_client/version_stub.c', '-o', object.path];
  const selected = ['selected-clang', ...original, `-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION=${JSON.stringify(version)}`];
  const step = {original, selected, receipt: join(f.provider, 'cc-version.json')};
  await f.json(step.receipt, {...step, exit: 0, output: object});
  const commands = [f.step.selected, selected];
  await f.json(join(f.provider, 'commands.json'), commands);
  await f.json(join(f.provider, 'cc-plan.json'), {steps: [f.step, step]});
  Object.assign(f.receipt, {commands_completed: 2, completed_c_steps: 2});
  await f.json(join(f.provider, 'build.json'), f.receipt);
  for (const name of ['scripts/release-version.mjs', 'scripts/python_release_cohort.py', 'src/cmd/native_client/version_stub.c']) {
    const path = join(f.repository, name); await mkdir(dirname(path), {recursive: true}); await writeFile(path, 'inert original version helper');
    f.inputs.push({path, bytes: 29, sha256: sha(Buffer.from('inert original version helper'))});
  }
  await f.json(join(f.provider, 'inputs.json'), f.inputs);
  assert.equal((await admit()).receipt.package_version, version);
  selected[selected.length - 1] = '-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="0.0.7"';
  await f.json(join(f.provider, 'cc-plan.json'), {steps: [f.step, {...step, selected}]});
  await assert.rejects(admit());
});

test('foreign, planned, incomplete and wrong-entry providers cannot become fresh artifacts', async t => {
  const f = await fixture(t);
  for (const delta of [{source: 'd'.repeat(40)}, {plan_only: true}, {moon_build_exit: 1},
    {entry: 'src/cmd/native_remote'}, {providers: 2}, {commands_completed: 0}, {completed_c_steps: 0}]) {
    await f.json(join(f.provider, 'build.json'), {...f.receipt, ...delta});
    await assert.rejects(f.admit());
  }
});

test('changed input, executable and generated C each refuse completion', async t => {
  const f = await fixture(t);
  for (const item of [f.inputs[0], f.binary, f.generated]) {
    const bytes = await readFile(item.path);
    await writeFile(item.path, Buffer.alloc(bytes.length, 88));
    await assert.rejects(f.admit());
    await writeFile(item.path, bytes);
  }
  assert.equal((await f.admit()).binary, f.binary.path);
});

test('missing or replaced compiler results never trigger a replacement compilation', async t => {
  const f = await fixture(t);
  const actual = {...f.step, exit: 1, output: f.binary};
  await f.json(f.step.receipt, actual);
  await assert.rejects(f.admit());
  await f.json(f.step.receipt, {...actual, exit: 0, selected: ['other-clang']});
  await assert.rejects(f.admit());
  await rm(f.step.receipt);
  await assert.rejects(f.admit(), {code: 'ENOENT'});
});

test('a replaced input symlink and a different allocator recipe refuse', async t => {
  const f = await fixture(t), item = f.inputs[0];
  await writeFile(item.path + '.copy', await readFile(item.path));
  await rm(item.path); await symlink(item.path + '.copy', item.path);
  await assert.rejects(f.admit());
  await rm(item.path); await writeFile(item.path, await readFile(item.path + '.copy'));
  await f.json(join(f.provider, 'build.json'), {...f.receipt,
    allocator: {...f.receipt.allocator, recipe_sha256: '0'.repeat(64)}});
  await assert.rejects(f.admit());
});

test('completion refuses an already assembled or partially staged artifact without removing it', async t => {
  const f = await fixture(t);
  const marker = join(f.artifact, 'artifact.json');
  await writeFile(marker, 'retained original');
  await assert.rejects(f.admit());
  assert.equal(await readFile(marker, 'utf8'), 'retained original');
});

test('actual Moon source spelling matches only the same original C input, never different flags or outputs', async t => {
  const f = await fixture(t);
  const planned = {...f.step, original: ['-o', f.binary.path, '-O2', './src/platform_native/sqlite/sqlite_stub.c']};
  const original = ['-o', f.binary.path, '-O2', join(f.repository, 'src/platform_native/sqlite/sqlite_stub.c')];
  await f.json(join(f.provider, 'cc-plan.json'), {steps: [planned]});
  const actual = {...planned, original, exit: 0, output: f.binary};
  await f.json(f.step.receipt, actual);
  assert.equal((await f.admit()).binary, f.binary.path);
  for (const changed of [
    ['-o', f.binary.path, '-O0', original[3]],
    ['-o', f.binary.path + '.other', '-O2', original[3]],
    ['-o', f.binary.path, '-O2', join(f.root, 'foreign/src/platform_native/sqlite/sqlite_stub.c')],
  ]) {
    await f.json(f.step.receipt, {...actual, original: changed});
    await assert.rejects(f.admit());
  }
});
