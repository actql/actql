// Reviewed input assembly only. This does not compile, load, install, admit
// state, or establish runtime acceptance for either process-bound component.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {constants, closeSync, fstatSync, lstatSync, openSync, readSync, mkdirSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve, parse} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeLocalDefaultAssets} from './native-cli-default-assets.mjs';
import {inspectLocalLibrary} from './native-cli-local-runtime.mjs';
import {LOCAL_RUNTIME_MAX_BYTES, localRuntimeHash, admitLocalLibraryBytes, validateLocalRuntimeManifest} from '../packages/native-cli/lib/local-runtime.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const platform = 'linux-x64-gnu', target = 'x86_64-unknown-linux-gnu';
const componentRoot = 'packages/python-local-runtime/native';
const identity = bytes => ({bytes: bytes.length, sha256: localRuntimeHash(bytes)});
function directories(path) {
  const absolute = resolve(path);
  let current = parse(absolute).root;
  for (const part of absolute.slice(current.length).split('/').filter(Boolean)) {
    current = join(current, part);
    const stat = lstatSync(current);
    assert(stat.isDirectory() && !stat.isSymbolicLink(), `Non-original directory: ${current}`);
  }
}
function read(path, maximum, expected) {
  path = resolve(path); directories(dirname(path));
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.size > 0 && before.size <= maximum, `Invalid original: ${path}`);
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const opened = fstatSync(fd);
    assert(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino && opened.size === before.size);
    const buffer = Buffer.alloc(opened.size + 1);
    let size = 0, count;
    while ((count = readSync(fd, buffer, size, buffer.length - size, null)) > 0) size += count;
    assert.equal(size, opened.size);
    const after = fstatSync(fd), named = lstatSync(path);
    for (const field of ['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs']) assert.equal(after[field], opened[field]);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === opened.dev && named.ino === opened.ino);
    const bytes = buffer.subarray(0, size);
    if (expected) assert.deepEqual(identity(bytes), {bytes: expected.bytes, sha256: expected.sha256}, `Changed original: ${path}`);
    return bytes;
  } finally { closeSync(fd); }
}
const json = bytes => JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const pythonWire = value => Buffer.from(JSON.stringify(sorted(value)).replace(/[\u0080-\uffff]/gu,
  char => `\\u${char.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n');

export function assembleNativeLinuxLocalRecipe({sourceSha, sqliteDirectory, cryptoDirectory, outputDirectory,
  sourceRoot = root}, execute = execFileSync) {
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  sourceRoot = resolve(sourceRoot); sqliteDirectory = resolve(sqliteDirectory);
  cryptoDirectory = resolve(cryptoDirectory); outputDirectory = resolve(outputDirectory);
  const clean = () => {
    const git = args => execute('git', args, {cwd: sourceRoot, encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024}).trim();
    assert.equal(git(['rev-parse', 'HEAD']), sourceSha, 'Exact current source required');
    assert.equal(git(['status', '--porcelain', '--untracked-files=all']), '', 'Clean committed source required');
  };
  clean();
  // Reject the output inside the checkout: writing recipe data must not dirty
  // the source whose exact identity the completed components claim.
  assert(outputDirectory !== sourceRoot && !outputDirectory.startsWith(sourceRoot + '/'));
  directories(dirname(outputDirectory));
  const originals = [];
  const capture = (path, maximum, expected) => {
    const bytes = read(path, maximum, expected);
    originals.push({path: resolve(path), maximum, ...identity(bytes)});
    return bytes;
  };
  const sqliteReceipt = capture(join(sqliteDirectory, 'process-producer.json'), 8 * 1024 * 1024);
  const cryptoReceipt = capture(join(cryptoDirectory, 'producer.json'), 8 * 1024 * 1024);
  const sqlite = json(sqliteReceipt), crypto = json(cryptoReceipt);
  assert.equal(sqlite.source_sha, sourceSha); assert.equal(crypto.source, sourceSha);
  for (const receipt of [sqlite, crypto]) {
    assert.equal(receipt.target, target);
    assert.match(receipt.compiler_target, /^x86_64-(?:[A-Za-z0-9_.]+-)?linux-gnu$/u);
    assert.equal(receipt.loaded, false); assert.equal(receipt.initialized, false);
    assert(receipt.library && receipt.inputs);
  }
  assert.equal(sqlite.compile, 1); assert.equal(sqlite.link, 1);
  assert.equal(sqlite.elf_machine, 62); assert.equal(sqlite.automatic_initializers, false); assert.equal(sqlite.component_tls, false);
  assert.equal(crypto.providers, 0);
  const sourcePath = relative => {
    assert(typeof relative === 'string' && !relative.startsWith('/') &&
      !relative.split('/').some(part => !part || part === '..' || part === '.'));
    return join(sourceRoot, relative);
  };
  const recordedInput = (receipt, relative, expected) => {
    const recorded = Object.entries(receipt.inputs).filter(([path]) =>
      path.startsWith('/') && path.endsWith('/' + relative));
    assert.equal(recorded.length, 1, `One original source input required: ${relative}`);
    assert.deepEqual(recorded[0][1], expected, `Contradictory source input: ${relative}`);
  };
  const recipes = {};
  for (const [role, receipt] of [['sqlite', sqlite], ['crypto', crypto]]) {
    const relative = `${componentRoot}/${role}-component/source.json`;
    const raw = capture(join(sourceRoot, relative), 65536);
    const recipe = recipes[role] = json(raw);
    recordedInput(receipt, relative, identity(raw));
    const producerInputs = role === 'sqlite' ? [
      'scripts/produce-python-sqlite-component.py', `${componentRoot}/sqlite-component/prepare.py`,
    ] : ['scripts/produce-native-crypto-component.py'];
    for (const input of [...producerInputs, `${componentRoot}/pre-root/owned_capacity.h`]) {
      recordedInput(receipt, input, identity(capture(sourcePath(input), 1024 * 1024)));
    }
    for (const [name, expected] of Object.entries(recipe.local)) {
      assert(!name.split('/').some(part => part === '..' || !part) && !name.startsWith('/'));
      const input = `${componentRoot}/${role}-component/${name}`;
      const bytes = capture(sourcePath(input), 16 * 1024 * 1024, expected);
      if (role === 'crypto') recordedInput(receipt, input, identity(bytes));
      else assert.deepEqual(receipt.stage?.outputs?.[name], identity(bytes), `Contradictory staged SQLite input: ${name}`);
    }
    if (role === 'sqlite') {
      assert(recipe.provider_inputs && typeof recipe.provider_inputs === 'object');
      assert.deepEqual(receipt.stage?.provider_inputs, recipe.provider_inputs);
      // These pins are recorded by SQLite's source stage, not generally by
      // the outer producer inputs map. Do not invent extra receipt fields.
      for (const [input, expected] of Object.entries(recipe.provider_inputs)) {
        capture(sourcePath(input), 16 * 1024 * 1024, expected);
      }
      const selected = {...recipe, target, deployment_target: null, original_recipe_sha256: localRuntimeHash(raw),
        process_format: 'ELF64-little-x86-64-shared', provider_binding: 'same original process namespace',
        automatic_initializers: false, component_tls: false};
      assert.deepEqual(receipt.stage?.selected_process_recipe, selected);
      assert.equal(receipt.stage.original_recipe_sha256, localRuntimeHash(raw));
      assert.equal(receipt.recipe_sha256, localRuntimeHash(pythonWire(selected)));
      assert.equal(receipt.stage.recipe_sha256, receipt.recipe_sha256);
      assert.equal(receipt.stage.target, target);
    } else assert.deepEqual(receipt.recipe, identity(raw));
  }
  assert(sqlite.notice && typeof sqlite.notice === 'object', 'Original SQLite notice identity required');
  const sqliteNotice = capture(join(sqliteDirectory, 'SQLITE-NOTICE'), 1024 * 1024, sqlite.notice);
  assert.deepEqual(identity(sqliteNotice), recipes.sqlite.local.NOTICE);
  const cryptoNotice = capture(join(cryptoDirectory, 'CRYPTO-NOTICE'), 1024 * 1024, recipes.crypto.local.NOTICE);
  const copyright = capture(join(cryptoDirectory, 'OPENSSL-COPYRIGHT'), 1024 * 1024,
    recipes.crypto.source_targets[target].license);
  const combined = Buffer.concat([copyright, Buffer.from('\n\n'), cryptoNotice]);
  assert(combined.length <= 1024 * 1024);
  const names = new Set(['libactql_sqlite_component.so', 'libactql_crypto_component.so']);
  const observations = [];
  const libraries = [['sqlite', sqlite, sqliteDirectory], ['crypto', crypto, cryptoDirectory]].map(([role, receipt, directory]) => {
    const name = `libactql_${role}_component.so`, path = join(directory, name);
    const bytes = capture(path, LOCAL_RUNTIME_MAX_BYTES, receipt.library);
    admitLocalLibraryBytes(bytes, platform);
    const observed = inspectLocalLibrary(path, platform, names, execute); observations.push(observed);
    assert.deepEqual([...observed.dependencies].sort(), [...(role === 'sqlite' ? receipt.system_dependencies : receipt.dependencies)].sort());
    return {role, name, original: {path, ...identity(bytes)}, license: `${role}.txt`, dependencies: observed.dependencies};
  });
  // Default generation reads only these checked source inputs. Capture them
  // before invoking it, and recheck every original after all observations.
  const aoa = json(capture(join(sourceRoot, 'spec/contracts/actql-aoa.json'), 1024 * 1024));
  assert(typeof aoa.pipeline_registry_file === 'string' && !aoa.pipeline_registry_file.startsWith('/') &&
    !aoa.pipeline_registry_file.split('/').includes('..'));
  capture(join(sourceRoot, aoa.pipeline_registry_file), 1024 * 1024);
  capture(join(sourceRoot, 'spec/local-check-environment.json'), 65536);
  const defaults = nativeLocalDefaultAssets(sourceRoot);
  const contents = new Map([...defaults].map(([role, bytes]) => [`${role}.json`, bytes]));
  contents.set('sqlite.txt', sqliteNotice); contents.set('crypto.txt', combined);
  contents.set('sqlite-process-producer.json', sqliteReceipt); contents.set('crypto-producer.json', cryptoReceipt);
  const assets = [...defaults].map(([role, bytes]) => ({role,
    original: {path: join(outputDirectory, `${role}.json`), ...identity(bytes)}}));
  const licenses = ['sqlite', 'crypto'].map(role => ({name: `${role}.txt`,
    original: {path: join(outputDirectory, `${role}.txt`), ...identity(contents.get(`${role}.txt`))}}));
  const recipe = {sourceSha, platform, libraries, assets, licenses};
  validateLocalRuntimeManifest({sourceSha, platform,
    libraries: libraries.map((item, index) => ({role: item.role, path: `lib/${item.name}`, ...identity(read(item.original.path, LOCAL_RUNTIME_MAX_BYTES, item.original)),
      license: `licenses/${item.license}`, dependencies: item.dependencies, abi: observations[index].abi})),
    assets: assets.map(item => ({role: item.role, path: `data/${item.role}.json`, bytes: item.original.bytes, sha256: item.original.sha256})),
    licenses: licenses.map(item => ({path: `licenses/${item.name}`, bytes: item.original.bytes, sha256: item.original.sha256})),
  }, {sourceSha, platform});
  for (const item of originals) read(item.path, item.maximum, item);
  clean();
  contents.set('originals.json', Buffer.from(JSON.stringify({sourceSha, platform, originals, observations}, null, 2) + '\n'));
  contents.set('local-runtime-recipe.json', Buffer.from(JSON.stringify(recipe, null, 2) + '\n'));
  mkdirSync(outputDirectory); // Exclusive creation; never overwrite reviewed data.
  for (const [name, bytes] of contents) {
    const path = join(outputDirectory, name);
    writeFileSync(path, bytes, {flag: 'wx', mode: 0o644}); read(path, Math.max(bytes.length, 1), identity(bytes));
  }
  return {path: join(outputDirectory, 'local-runtime-recipe.json'), recipe};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2), options = {};
    const flags = {'--source': 'sourceSha', '--sqlite-component': 'sqliteDirectory',
      '--crypto-component': 'cryptoDirectory', '--output': 'outputDirectory'};
    assert.equal(args.length, 8, 'Required: --source SHA --sqlite-component DIR --crypto-component DIR --output NEW_DIR');
    for (let i = 0; i < args.length; i += 2) {
      const key = flags[args[i]]; assert(key && !options[key] && args[i + 1]); options[key] = args[i + 1];
    }
    console.log(assembleNativeLinuxLocalRecipe(options).path);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
