// Test-owned input assembly only. No query, Host initialization, Source grant,
// or new-source installed product claim is made by this helper.
import assert from 'node:assert/strict';
import {constants, closeSync, fstatSync, lstatSync, openSync, readSync} from 'node:fs';
import {chmod, mkdir, readdir, writeFile} from 'node:fs/promises';
import {isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {prepareNativeLocalRuntime} from './native-cli-local-runtime.mjs';
import {admitInstalledLocalRuntime, LOCAL_RUNTIME_MAX_BYTES, localRuntimeHash}
  from '../packages/native-cli/lib/local-runtime.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sourceRef = 'connector://native-file-fixture/records#records';
export const relationFixtureRecords = '{"items":[{"id":"first","value":1},{"id":"second","value":2}]}';
export const relationFixtureDeclaration = {connector_id: 'native-file-fixture',
  connector_registration: 'fixture', connector_version: 'fixture/0.1',
  views: [{resource: 'records', resource_kind: 'record', fields: [
    {name: 'id', type: 'string', nullable: false},
    {name: 'value', type: 'number', nullable: false},
  ]}]};

// Observe an explicitly selected original without following its final symlink.
export function relationFixtureOriginal(path, maximum = LOCAL_RUNTIME_MAX_BYTES, expected) {
  assert(isAbsolute(path), 'Select an absolute original path');
  assert(Number.isSafeInteger(maximum) && maximum > 0 && maximum <= LOCAL_RUNTIME_MAX_BYTES);
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink(), 'Original must be a regular non-symlink file');
  assert(before.size > 0 && before.size <= maximum, 'Original exceeds its finite byte bound');
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const opened = fstatSync(fd);
    assert(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino && opened.size === before.size);
    const bytes = Buffer.alloc(opened.size + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      if (count === 0) break;
      offset += count;
    }
    assert.equal(offset, opened.size, 'Original changed during read');
    const after = fstatSync(fd), named = lstatSync(path);
    assert(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === opened.dev && named.ino === opened.ino);
    const body = bytes.subarray(0, offset);
    const original = {path, bytes: offset, sha256: localRuntimeHash(body)};
    if (expected) {
      assert.equal(original.bytes, expected.bytes, 'Original size differs from producer receipt');
      assert.equal(original.sha256, expected.sha256, 'Original digest differs from producer receipt');
    }
    return {original, body};
  } finally { closeSync(fd); }
}

// Checking inputs only. Common regenerates the authored declaration and admits
// this exact environment later; this function does not replace that admission.
export function inspectRelationFixtureEnvironment(bytes) {
  assert(bytes.length > 0 && bytes.length <= 65536);
  const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
  const environment = JSON.parse(wire);
  assert.equal(canonicalText(environment), wire, 'Keep exact canonical environment bytes');
  const {evidence_bundle_cid: cid, ...body} = environment;
  verifyIdentity(body, cid);
  assert.equal(environment.version, 'actql-check-environment/0.1');
  assert.deepEqual(environment.connector_manifest, {version: 'actql-connectors/0.1',
    connectors: [{connector: 'fixture', connector_id: 'native-file-fixture', connector_version: 'fixture/0.1'}]});
  assert.equal(environment.connector_catalogs.length, 1);
  assert.equal(environment.source_views.length, 1);
  assert.equal(environment.schema_snapshots.length, 1);
  assert.equal(environment.connector_capabilities.length, 1);
  assert.deepEqual(environment.command_contracts, []);
  assert.deepEqual(environment.mapping_contracts, []);
  assert.deepEqual(environment.model_task_contracts, []);
  const snapshot = environment.schema_snapshots[0];
  assert.equal(snapshot.source_ref, sourceRef);
  const policy = environment.contract_registry.find(item => item.cid === snapshot.source_data_policy_cid);
  assert.deepEqual(policy?.body, {version: 'actql-source-data-policy/0.1', source_ref: sourceRef,
    classification: 'unknown'}, 'No fixture declassification or extra Source grant');
  const schema = environment.contract_registry.find(item => item.cid === snapshot.carrier_schema_contract_cid);
  assert.deepEqual(schema?.body, {type: 'object', nullable: false, additional_properties: false,
    fields: {id: {type: 'string', nullable: false}, value: {type: 'number', nullable: false}}});
  return {cid, sourceRef};
}

function inspectComponentReceipt(path, role, recipe, originalCheckoutRoot, checkoutRoot) {
  // Match the existing component producer's finite receipt extent. Darwin's
  // current source-built OpenSSL proof includes its original source census.
  const selected = relationFixtureOriginal(path, 32 * 1024 * 1024);
  const receipt = JSON.parse(selected.body);
  assert.equal(role === 'sqlite' ? receipt.source_sha : receipt.source, recipe.sourceSha);
  const target = {'linux-x64-gnu': 'x86_64-unknown-linux-gnu', 'darwin-arm64': 'aarch64-apple-darwin'}[recipe.platform];
  assert(target, 'An explicit supported component platform is required');
  assert.equal(receipt.target, target);
  const library = recipe.libraries.find(item => item.role === role);
  assert(library, 'Missing owned component');
  assert.deepEqual(receipt.library, {bytes: library.original.bytes, sha256: library.original.sha256});
  relationFixtureOriginal(library.original.path, LOCAL_RUNTIME_MAX_BYTES, receipt.library);
  const inputs = Object.entries(receipt.compiled_inputs ?? {});
  assert(inputs.length > 0 && inputs.length <= 1024, 'A finite compiled-input receipt is required');
  const unchanged = [];
  for (const [input, extent] of inputs) {
    // The producer's resolved header path is an explicit original, not new
    // compiler/dependency discovery or permission to change its receipt.
    relationFixtureOriginal(extent.resolved_path ?? receipt.compiler_header_aliases?.[input] ?? input,
      LOCAL_RUNTIME_MAX_BYTES, extent);
    const local = relative(originalCheckoutRoot, input);
    if (local !== '..' && !local.startsWith(`..${sep}`) && !isAbsolute(local)) {
      relationFixtureOriginal(join(checkoutRoot, local), LOCAL_RUNTIME_MAX_BYTES, extent);
      unchanged.push(local);
    }
  }
  assert(unchanged.length > 0, 'Receipt must bind compiled checkout inputs');
  return {role, receipt: selected.original, sourceSha: recipe.sourceSha,
    compiledInputsVerified: inputs.length, unchangedCheckoutInputs: unchanged};
}

export function relationFixtureAccount() {
  const entry = (entry_id, connection, resource, operations) => ({entry_id,
    principal: {any_of: ['machine-user']}, connection: {any_of: [connection]},
    resource: {any_of: [resource]}, operation: {any_of: operations},
    outcome: 'allow', exclusions: []});
  return {version: 'actql-execution-account-config/0.1', account_id: 'operator',
    entries: [entry('fixture-records-read', 'native-file-fixture', 'records', ['read']),
      entry('fixture-run-control', 'cli', 'run', ['cancel', 'read', 'submit'])]};
}

// Complete only this helper's uninitialized, exact three-file setup namespace.
// Never regenerate originals in a namespace that a Native Owner initialized.
export async function prepareNativeRelationConfigurationInputs(directory) {
  for (const root of [directory, join(directory, 'test-input')]) {
    const info = lstatSync(root);
    assert(info.isDirectory() && !info.isSymbolicLink() && (info.mode & 0o777) === 0o700);
  }
  const receipt = JSON.parse(relationFixtureOriginal(join(directory, 'preparation-receipt.json'), 65536).body);
  assert.equal(receipt.inputRoot, join(directory, 'test-input'));
  assert.equal(receipt.runtime.root, join(directory, 'runtime'));
  assert.deepEqual((await readdir(receipt.inputRoot)).sort(),
    ['environment.json', 'records.json', 'row-declaration.json'],
    'Configuration inputs require the untouched three-file setup namespace');
  const recipe = JSON.parse(relationFixtureOriginal(receipt.originalRecipe.path, 65536, receipt.originalRecipe).body);
  const manifest = admitInstalledLocalRuntime({root: receipt.runtime.root, metadata: receipt.runtime.metadata,
    expected: {sourceSha: receipt.sourceSha, platform: receipt.platform,
      localRuntimeSha256: receipt.runtime.metadata.sha256}});
  const observedEnvironment = manifest.assets.find(item => item.role === 'environment');
  relationFixtureOriginal(join(receipt.inputRoot, 'environment.json'), 65536, observedEnvironment);
  const selected = role => recipe.assets.find(asset => asset.role === role);
  const asset = role => {
    const original = selected(role).original;
    return new TextDecoder('utf-8', {fatal: true}).decode(relationFixtureOriginal(original.path, 65536, original).body);
  };
  // The baseline assembler retains its empty-environment guard. Only its run
  // packet is used; generic Native adoption separately selects the Source wire.
  const baseline = asset('environment');
  for (const key of ['source_views', 'connector_catalogs', 'contract_registry'])
    assert.deepEqual(JSON.parse(baseline)[key], []);
  const inputs = [receipt.inputRoot, receipt.libraries.sqlite, receipt.libraries.crypto,
    baseline, ...['registry', 'values', 'fragment', 'ordered', 'result-policy'].map(asset)];
  for (const role of ['registry', 'values', 'fragment', 'ordered', 'result-policy']) {
    const member = manifest.assets.find(item => item.role === role);
    relationFixtureOriginal(join(receipt.runtime.root, member.path), 65536, selected(role).original);
  }
  const write = (path, body) => writeFile(path, body, {flag: 'wx', mode: 0o600});
  await write(join(receipt.inputRoot, 'account.json'), canonicalText(relationFixtureAccount()));
  const runtime = relationFixtureOriginal(join(receipt.runtime.root, receipt.runtime.metadata.path),
    65536, receipt.runtime.metadata);
  await write(join(receipt.inputRoot, 'runtime.json'), runtime.body);
  const path = join(directory, 'configuration-inputs.json');
  await write(path, JSON.stringify(inputs));
  return path;
}

export function relationFixtureRefusalAccounts() {
  const baseline = relationFixtureAccount();
  const runOnly = structuredClone(baseline);
  runOnly.entries = runOnly.entries.filter(entry => entry.entry_id === 'fixture-run-control');
  const connection = structuredClone(baseline); connection.entries.find(entry => entry.entry_id === 'fixture-records-read').connection.any_of = ['different'];
  const resource = structuredClone(baseline); resource.entries.find(entry => entry.entry_id === 'fixture-records-read').resource.any_of = ['different'];
  return {'run-only': runOnly, 'wrong-connection': connection, 'wrong-resource': resource};
}

export async function prepareNativeRelationRefusalInputs(directory) {
  const source = join(directory, 'test-input');
  const info = lstatSync(source);
  assert(info.isDirectory() && !info.isSymbolicLink() && (info.mode & 0o777) === 0o700);
  const names = ['account.json', 'environment.json', 'records.json', 'row-declaration.json', 'run.json', 'runtime.json'];
  assert.deepEqual((await readdir(source)).sort(), names, 'Refusal inputs require the fresh complete configuration');
  const originals = new Map(names.map(name => [name, relationFixtureOriginal(join(source, name), 65536)]));
  assert.equal(originals.get('account.json').body.toString('utf8'), canonicalText(relationFixtureAccount()));
  assert.equal(originals.get('records.json').body.toString('utf8'), relationFixtureRecords);
  assert.equal(originals.get('row-declaration.json').body.toString('utf8'), canonicalText(relationFixtureDeclaration));
  inspectRelationFixtureEnvironment(originals.get('environment.json').body);
  const receipt = JSON.parse(relationFixtureOriginal(join(directory, 'preparation-receipt.json'), 65536).body);
  assert.equal(localRuntimeHash(originals.get('runtime.json').body), receipt.runtime.metadata.sha256);
  const result = {};
  for (const [name, account] of Object.entries(relationFixtureRefusalAccounts())) {
    const root = join(directory, `test-input-${name}`);
    await mkdir(root, {mode: 0o700});
    for (const file of names) await writeFile(join(root, file), file === 'account.json'
      ? canonicalText(account) : originals.get(file).body, {flag: 'wx', mode: 0o600});
    result[name] = root;
  }
  return result;
}

export async function prepareNativeOriginalRelationFixture({directory, recipePath,
  sqliteReceiptPath, cryptoReceiptPath, originalCheckoutRoot, environmentPath,
  checkoutRoot = repository}) {
  for (const path of [directory, recipePath, sqliteReceiptPath, cryptoReceiptPath,
    originalCheckoutRoot, environmentPath, checkoutRoot]) assert(isAbsolute(path));
  // Exclusive creation refuses initialized and previously attempted fixtures.
  // Failed preparation is preserved for diagnosis, never reset or adopted.
  await mkdir(directory, {mode: 0o700});
  assert.equal(lstatSync(directory).mode & 0o777, 0o700);
  const selectedRecipe = relationFixtureOriginal(recipePath, 65536);
  const recipe = JSON.parse(selectedRecipe.body);
  assert.deepEqual(recipe.libraries.map(item => item.role).sort(), ['crypto', 'sqlite']);
  assert.deepEqual(recipe.assets.map(item => item.role).sort(),
    ['environment', 'fragment', 'ordered', 'registry', 'result-policy', 'values']);
  const producers = [inspectComponentReceipt(sqliteReceiptPath, 'sqlite', recipe, originalCheckoutRoot, checkoutRoot),
    inspectComponentReceipt(cryptoReceiptPath, 'crypto', recipe, originalCheckoutRoot, checkoutRoot)];
  const selectedEnvironment = relationFixtureOriginal(environmentPath, 65536);
  const environment = inspectRelationFixtureEnvironment(selectedEnvironment.body);
  const input = join(directory, 'test-input'), runtime = join(directory, 'runtime');
  await mkdir(input, {mode: 0o700});
  await mkdir(runtime, {mode: 0o700});
  const write = (path, bytes) => writeFile(path, bytes, {flag: 'wx', mode: 0o600});
  await write(join(input, 'environment.json'), selectedEnvironment.body);
  await write(join(input, 'row-declaration.json'), canonicalText(relationFixtureDeclaration));
  await write(join(input, 'records.json'), relationFixtureRecords);
  const options = structuredClone(recipe);
  options.assets.find(item => item.role === 'environment').original = {
    ...selectedEnvironment.original, path: join(input, 'environment.json')};
  const metadata = await prepareNativeLocalRuntime(runtime, options);
  const manifest = admitInstalledLocalRuntime({root: runtime, metadata,
    expected: {sourceSha: recipe.sourceSha, platform: recipe.platform, localRuntimeSha256: metadata.sha256}});
  // Producer copies are exclusive writes inside our 0700 root. Tighten only
  // these new copies, never retained originals or another initialized state.
  for (const child of ['lib', 'data', 'licenses']) await chmod(join(runtime, child), 0o700);
  for (const item of [...manifest.libraries, ...manifest.assets, ...manifest.licenses, metadata])
    await chmod(join(runtime, item.path), 0o600);
  const receipt = {scope: 'test-owned Source-capable inputs; retained components, no installed product or execution claim',
    sourceSha: recipe.sourceSha, platform: recipe.platform, originalRecipe: selectedRecipe.original,
    producers, originalEnvironment: selectedEnvironment.original, environment,
    runtime: {root: runtime, metadata}, inputRoot: input,
    libraries: Object.fromEntries(manifest.libraries.map(item => [item.role, join(runtime, item.path)]))};
  await write(join(directory, 'preparation-receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
  await prepareNativeRelationConfigurationInputs(directory);
  return receipt;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === '--prepare-refusals') {
    assert.equal(process.argv.length, 4);
    console.log(JSON.stringify(await prepareNativeRelationRefusalInputs(process.argv[3]), null, 2));
  } else {
    assert.equal(process.argv.length, 8,
      'Usage: node scripts/native-original-relation-runtime-fixture.mjs DIRECTORY RECIPE SQLITE_RECEIPT CRYPTO_RECEIPT ORIGINAL_CHECKOUT ENVIRONMENT');
    const [directory, recipePath, sqliteReceiptPath, cryptoReceiptPath, originalCheckoutRoot, environmentPath] = process.argv.slice(2);
    const receipt = await prepareNativeOriginalRelationFixture({directory, recipePath, sqliteReceiptPath,
      cryptoReceiptPath, originalCheckoutRoot, environmentPath});
    console.log(JSON.stringify(receipt, null, 2));
  }
}
