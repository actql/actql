import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, mkdir, readFile, readdir, rm, stat, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {localRuntimeHash} from '../packages/native-cli/lib/local-runtime.mjs';
import {relationFixtureDeclaration, relationFixtureRecords, relationFixtureOriginal,
  inspectRelationFixtureEnvironment, prepareNativeOriginalRelationFixture,
  relationFixtureAccount, prepareNativeRelationConfigurationInputs, relationFixtureRefusalAccounts,
  prepareNativeRelationRefusalInputs}
  from './native-original-relation-runtime-fixture.mjs';

async function scratch(t) {
  const path = await mkdtemp(join(tmpdir(), 'actql-relation-runtime-input-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  return path;
}

// These are data and refusal tests, never synthetic-library acceptance. The
// prepared positive diagnostic requires genuine selected producer receipts.
test('Source fixture independently declares exactly two primitive records', () => {
  assert.equal(Buffer.byteLength(relationFixtureRecords), 62);
  assert.deepEqual(JSON.parse(relationFixtureRecords), {items: [
    {id: 'first', value: 1}, {id: 'second', value: 2}]});
  assert.deepEqual(relationFixtureDeclaration, {connector_id: 'native-file-fixture',
    connector_registration: 'fixture', connector_version: 'fixture/0.1',
    views: [{resource: 'records', resource_kind: 'record', fields: [
      {name: 'id', type: 'string', nullable: false},
      {name: 'value', type: 'number', nullable: false}]}]});
});

test('selected original retains exact byte identity and does not rewrite the source', async t => {
  const root = await scratch(t), path = join(root, 'original.json');
  const body = Buffer.from('{"line":"e\\u0301"}\r\n');
  await writeFile(path, body, {mode: 0o600, flag: 'wx'});
  const selected = relationFixtureOriginal(path, body.length);
  assert.deepEqual(selected.body, body);
  assert.deepEqual(selected.original, {path, bytes: body.length, sha256: localRuntimeHash(body)});
  assert.deepEqual(relationFixtureOriginal(path, body.length, selected.original), selected);
  assert.deepEqual(await readFile(path), body);
});

test('selected original refuses relative paths, absent files, directories and symlinks', async t => {
  const root = await scratch(t), path = join(root, 'original');
  await writeFile(path, 'abc');
  await symlink(path, join(root, 'alias'));
  for (const selected of ['relative', join(root, 'absent'), root, join(root, 'alias')])
    assert.throws(() => relationFixtureOriginal(selected));
  assert.deepEqual(await readFile(path), Buffer.from('abc'));
});

test('finite original observation refuses empty oversized and changed receipt inputs', async t => {
  const root = await scratch(t), path = join(root, 'original');
  await writeFile(path, 'abc');
  const selected = relationFixtureOriginal(path, 3);
  assert.throws(() => relationFixtureOriginal(path, 2));
  for (const bound of [0, -1, Infinity, 1.5, 67108865])
    assert.throws(() => relationFixtureOriginal(path, bound));
  assert.throws(() => relationFixtureOriginal(path, 3, {...selected.original, bytes: 2}));
  await writeFile(path, 'xyz');
  assert.throws(() => relationFixtureOriginal(path, 3, selected.original), /digest differs/u);
  await writeFile(path, '');
  assert.throws(() => relationFixtureOriginal(path));
});

test('environment input rejects malformed noncanonical and foreign Source bodies', async () => {
  for (const bytes of [Buffer.from('{}'), Buffer.from('{ "version":0}'), Buffer.from([0xff]),
    Buffer.alloc(65537, 0x20)]) assert.throws(() => inspectRelationFixtureEnvironment(bytes));
  // A real previously authored Source environment still cannot substitute
  // its different connector/schema for this fixture's selected declaration.
  const source = await readFile(new URL('./fixtures/native-local-cli/source-environment.json', import.meta.url));
  assert.throws(() => inspectRelationFixtureEnvironment(source));
});

test('preparation never resets or adopts a previously existing namespace', async t => {
  const root = await scratch(t), directory = join(root, 'initialized');
  await mkdir(directory, {mode: 0o700});
  const original = Buffer.from('original initialized state');
  await writeFile(join(directory, 'state'), original, {mode: 0o600, flag: 'wx'});
  const missing = join(root, 'missing');
  await assert.rejects(prepareNativeOriginalRelationFixture({directory, recipePath: missing,
    sqliteReceiptPath: missing, cryptoReceiptPath: missing, originalCheckoutRoot: root,
    environmentPath: missing}), {code: 'EEXIST'});
  assert.deepEqual(await readdir(directory), ['state']);
  assert.deepEqual(await readFile(join(directory, 'state')), original);
});

test('failed preparation retains only its new private namespace without fallback', async t => {
  const root = await scratch(t), directory = join(root, 'fresh'), missing = join(root, 'missing');
  await assert.rejects(prepareNativeOriginalRelationFixture({directory, recipePath: missing,
    sqliteReceiptPath: missing, cryptoReceiptPath: missing, originalCheckoutRoot: root,
    environmentPath: missing}), {code: 'ENOENT'});
  assert.equal((await stat(directory)).mode & 0o777, 0o700);
  assert.deepEqual(await readdir(directory), []);
  await assert.rejects(prepareNativeOriginalRelationFixture({directory, recipePath: missing,
    sqliteReceiptPath: missing, cryptoReceiptPath: missing, originalCheckoutRoot: root,
    environmentPath: missing}), {code: 'EEXIST'});
});

test('preparation refuses a relabeled component before creating runtime members', async t => {
  const root = await scratch(t), directory = join(root, 'fresh');
  const recipePath = join(root, 'recipe.json'), receipt = join(root, 'receipt.json');
  await writeFile(recipePath, JSON.stringify({sourceSha: 'a'.repeat(40), platform: 'linux-x64-gnu',
    libraries: [{role: 'sqlite'}, {role: 'crypto'}], assets:
      ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy'].map(role => ({role}))}));
  await writeFile(receipt, JSON.stringify({source_sha: 'b'.repeat(40)}));
  await assert.rejects(prepareNativeOriginalRelationFixture({directory, recipePath,
    sqliteReceiptPath: receipt, cryptoReceiptPath: receipt, originalCheckoutRoot: root,
    environmentPath: join(root, 'not-read')}));
  assert.deepEqual(await readdir(directory), []);
});

test('fresh Common emitter and Native component declare the same exact setup inputs', async () => {
  const native = await readFile(new URL('../src/platform_native/row_source/capture_physical_scoped_wbtest.mbt', import.meta.url), 'utf8');
  const emitter = await readFile(new URL('../src/native_relation_fixture_inputs/environment_test.mbt', import.meta.url), 'utf8');
  const start = '///|\nfn capture_fixture_declaration';
  const expected = native.slice(native.indexOf(start), native.indexOf('///|\nfn capture_fixture_logical')).trim();
  assert(expected.length > 0);
  assert(emitter.includes(expected), 'Use current Common constructors and the same authored Host policy');
  assert(!emitter.includes('prepare_effect_free_client_program'), 'Emission constructs inputs, never query results');
});


test('fixture Account matches real Common admission and only separate Run and Source permissions', async () => {
  const account = relationFixtureAccount();
  assert.equal(account.account_id, 'operator');
  assert.equal(account.entries.length, 2);
  assert.deepEqual(account.entries.map(item => [item.principal.any_of, item.connection.any_of,
    item.resource.any_of, item.operation.any_of]), [
    [['machine-user'], ['native-file-fixture'], ['records'], ['read']],
    [['machine-user'], ['cli'], ['run'], ['cancel', 'read', 'submit']],
  ]);
  assert(account.entries.every(item => item.outcome === 'allow' && item.exclusions.length === 0));
  const regression = await readFile(new URL('../src/execution_authorization/native_relation_fixture_wbtest.mbt', import.meta.url), 'utf8');
  const canonical = regression.match(/let native_relation_account_canonical : String =\s*#\|([^\n]+)/u);
  assert(canonical, 'Keep the independently authored real Common admission regression');
  assert.deepEqual(account, JSON.parse(canonical[1]));
});

test('configuration setup refuses an initialized namespace before reading recipes', async t => {
  const root = await scratch(t), inputRoot = join(root, 'test-input');
  await mkdir(inputRoot, {mode: 0o700});
  await writeFile(join(root, 'preparation-receipt.json'), JSON.stringify({inputRoot,
    runtime: {root: join(root, 'runtime')}}));
  await writeFile(join(inputRoot, 'state'), 'original state');
  await assert.rejects(prepareNativeRelationConfigurationInputs(root), /untouched three-file/u);
  assert.deepEqual(await readdir(inputRoot), ['state']);
  assert.equal(await readFile(join(inputRoot, 'state'), 'utf8'), 'original state');
});


test('refusal Accounts change only the specific Source decision', () => {
  const accounts = relationFixtureRefusalAccounts(), baseline = relationFixtureAccount();
  for (const account of Object.values(accounts)) {
    assert.deepEqual(account.entries.find(entry => entry.entry_id === 'fixture-run-control'),
      baseline.entries.find(entry => entry.entry_id === 'fixture-run-control'));
    assert.equal(account.account_id, baseline.account_id);
    assert.equal(account.version, baseline.version);
  }
  assert.deepEqual(accounts['run-only'].entries, baseline.entries.filter(entry => entry.entry_id === 'fixture-run-control'));
  const connection = structuredClone(baseline); connection.entries.find(entry => entry.entry_id === 'fixture-records-read').connection.any_of = ['different'];
  assert.deepEqual(accounts['wrong-connection'], connection);
  const resource = structuredClone(baseline); resource.entries.find(entry => entry.entry_id === 'fixture-records-read').resource.any_of = ['different'];
  assert.deepEqual(accounts['wrong-resource'], resource);
});

test('refusal input preparation never copies an initialized or incomplete namespace', async t => {
  const root = await scratch(t), source = join(root, 'test-input');
  await mkdir(source, {mode: 0o700});
  await writeFile(join(source, 'state'), 'original state');
  await assert.rejects(prepareNativeRelationRefusalInputs(root), /fresh complete/u);
  assert.deepEqual(await readdir(root), ['test-input']);
  assert.equal(await readFile(join(source, 'state'), 'utf8'), 'original state');
});
