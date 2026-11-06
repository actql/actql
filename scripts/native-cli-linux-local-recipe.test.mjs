import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, symlinkSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {assembleNativeLinuxLocalRecipe} from './native-cli-linux-local-recipe.mjs';
import {prepareNativeLocalRuntime} from './native-cli-local-runtime.mjs';

const sourceSha = 'a'.repeat(40), target = 'x86_64-unknown-linux-gnu';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = bytes => ({bytes: bytes.length, sha256: hash(bytes)});
const wire = value => Buffer.from(JSON.stringify(value) + '\n');
const canonical = value => value && typeof value === 'object' && !Array.isArray(value)
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
// Synthetic receipts, headers and inspector responses test DATA assembly only.
// They are deliberately not compiled components or installed runtime evidence.
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-linux-recipe-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const sourceRoot = join(root, 'source'), sqliteDirectory = join(root, 'sqlite'), cryptoDirectory = join(root, 'crypto');
  const put = (path, bytes) => { mkdirSync(join(path, '..'), {recursive: true}); writeFileSync(path, bytes); return identity(bytes); };
  mkdirSync(sourceRoot); mkdirSync(sqliteDirectory); mkdirSync(cryptoDirectory);
  const notice = Buffer.from('Synthetic SQLite original notice\r\n');
  const cryptoNotice = Buffer.from('Synthetic Crypto original notice\r\n');
  const copyright = Buffer.from('Synthetic OpenSSL original copyright\n');
  const capacityPath = 'packages/python-local-runtime/native/pre-root/owned_capacity.h';
  const providerPath = 'src/platform_native/host_bootstrap/bootstrap_stub.c';
  const providerInputs = {
    [capacityPath]: put(join(sourceRoot, capacityPath), Buffer.from('synthetic capacity header\n')),
    [providerPath]: put(join(sourceRoot, providerPath), Buffer.from('synthetic bootstrap source\n')),
  };
  const sqliteRecipe = {provider_inputs: providerInputs, target: 'aarch64-apple-darwin', deployment_target: '11.0', local: {NOTICE: identity(notice)}};
  const cryptoRecipe = {local: {NOTICE: identity(cryptoNotice)}, source_targets: {[target]: {license: identity(copyright)}}};
  const sqlitePath = join(sourceRoot, 'packages/python-local-runtime/native/sqlite-component/source.json');
  const cryptoPath = join(sourceRoot, 'packages/python-local-runtime/native/crypto-component/source.json');
  const sr = put(sqlitePath, wire(sqliteRecipe)), cr = put(cryptoPath, wire(cryptoRecipe));
  put(join(sqlitePath, '../NOTICE'), notice); put(join(cryptoPath, '../NOTICE'), cryptoNotice);
  const selected = {...sqliteRecipe, target, deployment_target: null, original_recipe_sha256: sr.sha256,
    process_format: 'ELF64-little-x86-64-shared', provider_binding: 'same original process namespace',
    automatic_initializers: false, component_tls: false};
  const recipeHash = hash(wire(canonical(selected)));
  const library = Buffer.alloc(64); library.write('ELF', 1); library[0] = 0x7f; library[4] = 2; library[5] = 1;
  library.writeUInt16LE(3, 16); library.writeUInt16LE(62, 18);
  const sqlite = {source_sha: sourceSha, target, compiler_target: 'x86_64-linux-gnu', loaded: false, initialized: false,
    compile: 1, link: 1, elf_machine: 62, automatic_initializers: false, component_tls: false,
    recipe_sha256: recipeHash, stage: {outputs: {NOTICE: identity(notice)}, provider_inputs: providerInputs, selected_process_recipe: selected, original_recipe_sha256: sr.sha256, recipe_sha256: recipeHash, target},
    inputs: {[sqlitePath]: sr}, library: identity(library), notice: identity(notice), system_dependencies: ['libc.so.6']};
  const crypto = {source: sourceSha, target, compiler_target: 'x86_64-linux-gnu', loaded: false, initialized: false,
    providers: 0, inputs: {[cryptoPath]: cr}, recipe: cr, library: identity(library), dependencies: ['libc.so.6']};
  for (const [receipt, names] of [
    [sqlite, ['scripts/produce-python-sqlite-component.py', 'packages/python-local-runtime/native/sqlite-component/prepare.py']],
    [crypto, ['scripts/produce-native-crypto-component.py']],
  ]) {
    for (const name of [...names, 'scripts/linux_component_headers.py']) receipt.inputs[join(sourceRoot, name)] =
      put(join(sourceRoot, name), Buffer.from(`synthetic source: ${name}\n`));
    receipt.inputs[join(sourceRoot, capacityPath)] = providerInputs[capacityPath];
  }
  crypto.inputs[join(cryptoPath, '../NOTICE')] = identity(cryptoNotice);
  const sqliteReceipt = join(sqliteDirectory, 'process-producer.json'), cryptoReceipt = join(cryptoDirectory, 'producer.json');
  put(sqliteReceipt, wire(sqlite)); put(cryptoReceipt, wire(crypto));
  put(join(sqliteDirectory, 'libactql_sqlite_component.so'), library);
  put(join(cryptoDirectory, 'libactql_crypto_component.so'), library);
  put(join(sqliteDirectory, 'SQLITE-NOTICE'), notice);
  put(join(cryptoDirectory, 'CRYPTO-NOTICE'), cryptoNotice); put(join(cryptoDirectory, 'OPENSSL-COPYRIGHT'), copyright);
  put(join(sourceRoot, 'spec/contracts/actql-aoa.json'), wire({pipeline_registry_file: 'spec/registry.json',
    execution_contracts: {'REL.values': {}, 'ACTQL.expression_fragment/0.1': {}, 'REL.derive.ordered': {}}}));
  put(join(sourceRoot, 'spec/registry.json'), wire({})); put(join(sourceRoot, 'spec/local-check-environment.json'), wire({}));
  const execute = (tool, args) => {
    if (tool === 'git') return args[0] === 'rev-parse' ? sourceSha + '\n' : '';
    assert.equal(tool, 'readelf');
    return args[0] === '-d' ? '(NEEDED) Shared library: [libc.so.6]\n' : 'GLIBC_2.2.5 GLIBC_2.34';
  };
  return {root, options: {sourceSha, sourceRoot, sqliteDirectory, cryptoDirectory, outputDirectory: join(root, 'recipe')},
    execute, put, sqlite, crypto, sqliteReceipt, cryptoReceipt, sqlitePath, cryptoPath, notice, cryptoNotice, copyright};
}

test('Linux recipe preserves originals, both Crypto notices and current default assets', async t => {
  const f = fixture(t), {recipe, path} = assembleNativeLinuxLocalRecipe(f.options, f.execute);
  assert.deepEqual(JSON.parse(readFileSync(path)), recipe);
  assert.equal(recipe.platform, 'linux-x64-gnu'); assert.equal(recipe.sourceSha, sourceSha);
  assert.deepEqual(recipe.assets.map(item => item.role), ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy']);
  assert.deepEqual(readFileSync(recipe.licenses[0].original.path), f.notice);
  assert.deepEqual(readFileSync(recipe.licenses[1].original.path), Buffer.concat([f.copyright, Buffer.from('\n\n'), f.cryptoNotice]));
  assert.deepEqual(readFileSync(join(f.options.outputDirectory, 'sqlite-process-producer.json')), readFileSync(f.sqliteReceipt));
  assert.deepEqual(readFileSync(join(f.options.outputDirectory, 'crypto-producer.json')), readFileSync(f.cryptoReceipt));
  const output = join(f.root, 'runtime'); mkdirSync(output);
  const result = await prepareNativeLocalRuntime(output, recipe, f.execute);
  assert.equal(result.path, 'local-runtime.json');
  assert.deepEqual(JSON.parse(readFileSync(join(f.options.outputDirectory, 'originals.json'))).observations[0].abi, {minimumGlibc: '2.34'});
});

test('wrong source, target, dirty source and incomplete receipts are refused before output', t => {
  const mutations = [
    f => { f.sqlite.source_sha = 'b'.repeat(40); },
    f => { f.crypto.source = 'b'.repeat(40); },
    f => { f.sqlite.target = 'aarch64-unknown-linux-gnu'; },
    f => { f.crypto.target = 'aarch64-apple-darwin'; },
    f => { f.sqlite.link = 0; },
    f => { delete f.sqlite.stage; },
    f => { delete f.sqlite.notice; },
    f => { f.sqlite.notice.sha256 = 'b'.repeat(64); },
    f => { f.crypto.initialized = true; },
    f => { f.options.sourceSha = 'b'.repeat(40); },
  ];
  for (const mutate of mutations) {
    const f = fixture(t); mutate(f); f.put(f.sqliteReceipt, wire(f.sqlite)); f.put(f.cryptoReceipt, wire(f.crypto));
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute)); assert(!existsSync(f.options.outputDirectory));
  }
  const f = fixture(t);
  assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, (tool, args, options) =>
    tool === 'git' && args[0] === 'status' ? ' M dirty\n' : f.execute(tool, args, options)));
});

test('changed recipes, libraries, notices and missing outputs fail closed', t => {
  for (const filename of ['sqlite/libactql_sqlite_component.so', 'crypto/libactql_crypto_component.so',
    'sqlite/SQLITE-NOTICE', 'crypto/CRYPTO-NOTICE', 'crypto/OPENSSL-COPYRIGHT',
    'source/packages/python-local-runtime/native/sqlite-component/source.json',
    'source/packages/python-local-runtime/native/crypto-component/NOTICE']) {
    const f = fixture(t); f.put(join(f.root, filename), Buffer.from('changed'));
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute)); assert(!existsSync(f.options.outputDirectory));
  }
  for (const filename of ['sqlite/process-producer.json', 'crypto/producer.json', 'crypto/OPENSSL-COPYRIGHT']) {
    const f = fixture(t); rmSync(join(f.root, filename));
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute));
  }
});

test('file, component directory and parent directory symlinks are refused', t => {
  for (const filename of ['sqlite/process-producer.json', 'sqlite/libactql_sqlite_component.so', 'crypto/CRYPTO-NOTICE']) {
    const f = fixture(t), path = join(f.root, filename), saved = join(f.root, 'saved');
    f.put(saved, readFileSync(path)); rmSync(path); symlinkSync(saved, path);
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute));
  }
  const f = fixture(t), alias = join(f.root, 'alias'); symlinkSync(f.options.sqliteDirectory, alias);
  assert.throws(() => assembleNativeLinuxLocalRecipe({...f.options, sqliteDirectory: alias}, f.execute));
  const parent = join(f.root, 'parent'); symlinkSync(f.root, parent);
  assert.throws(() => assembleNativeLinuxLocalRecipe({...f.options, cryptoDirectory: join(parent, 'crypto')}, f.execute));
});

test('actual inspector dependency or ABI disagreement and mutation during observation are refused', t => {
  for (const dynamic of ['(NEEDED) Shared library: [libother.so]\n', '(RUNPATH) Library runpath: [/tmp]\n']) {
    const f = fixture(t);
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, (tool, args, options) =>
      tool === 'readelf' && args[0] === '-d' ? dynamic : f.execute(tool, args, options)));
  }
  const f = fixture(t);
  assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, (tool, args, options) => {
    if (tool === 'readelf') f.put(f.cryptoReceipt, Buffer.from('{}'));
    return f.execute(tool, args, options);
  }));
  assert(!existsSync(f.options.outputDirectory));
});

test('existing output, checkout output and oversized receipt are refused', t => {
  const f = fixture(t); mkdirSync(f.options.outputDirectory);
  assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute));
  assert.throws(() => assembleNativeLinuxLocalRecipe({...f.options, outputDirectory: join(f.options.sourceRoot, 'new')}, f.execute));
  const g = fixture(t); g.put(g.sqliteReceipt, Buffer.alloc(8 * 1024 * 1024 + 1));
  assert.throws(() => assembleNativeLinuxLocalRecipe(g.options, g.execute));
});


test('missing and contradictory guaranteed producer source inputs are refused', t => {
  for (const [role, relative] of [
    ['sqlite', 'packages/python-local-runtime/native/sqlite-component/source.json'],
    ['sqlite', 'scripts/produce-python-sqlite-component.py'],
    ['sqlite', 'packages/python-local-runtime/native/sqlite-component/prepare.py'],
    ['sqlite', 'packages/python-local-runtime/native/pre-root/owned_capacity.h'],
    ['crypto', 'packages/python-local-runtime/native/crypto-component/source.json'],
    ['crypto', 'scripts/produce-native-crypto-component.py'],
    ['crypto', 'packages/python-local-runtime/native/pre-root/owned_capacity.h'],
    ['crypto', 'packages/python-local-runtime/native/crypto-component/NOTICE'],
  ]) for (const missing of [true, false]) {
    const f = fixture(t), path = join(f.options.sourceRoot, relative);
    if (missing) delete f[role].inputs[path];
    else f[role].inputs[path] = {...f[role].inputs[path], sha256: 'b'.repeat(64)};
    f.put(f[`${role}Receipt`], wire(f[role]));
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute));
    assert(!existsSync(f.options.outputDirectory));
  }
});

test('SQLite staged source and provider pins must match current original inputs', t => {
  for (const mutate of [
    f => { delete f.sqlite.stage.outputs.NOTICE; },
    f => { f.sqlite.stage.outputs.NOTICE.sha256 = 'b'.repeat(64); },
    f => { delete f.sqlite.stage.provider_inputs; },
    f => { delete f.sqlite.stage.provider_inputs['src/platform_native/host_bootstrap/bootstrap_stub.c']; },
    f => { f.sqlite.stage.provider_inputs['src/platform_native/host_bootstrap/bootstrap_stub.c'].sha256 = 'b'.repeat(64); },
    f => { f.put(join(f.options.sourceRoot, 'src/platform_native/host_bootstrap/bootstrap_stub.c'), Buffer.from('changed provider source')); },
    f => { f.sqlite.recipe_sha256 = 'b'.repeat(64); },
    f => { f.sqlite.stage.original_recipe_sha256 = 'b'.repeat(64); },
  ]) {
    const f = fixture(t); mutate(f); f.put(f.sqliteReceipt, wire(f.sqlite));
    assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, f.execute));
    assert(!existsSync(f.options.outputDirectory));
  }
});


test('missing physical glibc ABI and wrong ELF architecture are refused', t => {
  const f = fixture(t);
  assert.throws(() => assembleNativeLinuxLocalRecipe(f.options, (tool, args, options) =>
    tool === 'readelf' && args[0] === '--version-info' ? 'No version information' : f.execute(tool, args, options)));
  const g = fixture(t), path = join(g.options.sqliteDirectory, 'libactql_sqlite_component.so');
  const bytes = readFileSync(path); bytes.writeUInt16LE(183, 18);
  g.sqlite.library = g.put(path, bytes); g.put(g.sqliteReceipt, wire(g.sqlite));
  assert.throws(() => assembleNativeLinuxLocalRecipe(g.options, g.execute));
  assert(!existsSync(g.options.outputDirectory));
});
