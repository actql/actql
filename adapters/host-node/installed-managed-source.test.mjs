import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {parse} from 'acorn';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';

// Execute the actual Host boundary with explicit nominal service ports. This
// does not supply a native database, Resource admission or physical close ACK.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
function visit(node, select) {
  if (node === null || typeof node !== 'object') return;
  select(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) for (const value of child) visit(value, select);
    else if (child && typeof child === 'object') visit(child, select);
  }
}
function admission(preparation, sourceProfile, prepared, request, count) {
  let declaration;
  visit(ast, node => {
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        node.declarations[0].id.name === 'admitPreparedSubmission') declaration = node;
  });
  assert(declaration);
  return new Function('preparation', 'sourceProfile', 'prepared', 'request', 'count', `
    const requestOf=()=>({requested:request,acquisitionCount:count,effectful:false});
    const moon={clientProgramSerializationOccurrences:()=>[]},inferSelections=new WeakMap();
    const admissionFailures=new WeakMap(),holderRefusal=undefined;
    const clientOperationError=code=>Object.assign(new Error(code),{code});
    ${source.slice(declaration.start, declaration.end)}
    return admitPreparedSubmission({preparedProgram:prepared});
  `)(preparation, sourceProfile, prepared, request, count);
}

test('ordinary installed Source admission uses the same generic Host Run service', () => {
  const prepared = {}, request = {}, profile = {sources: [{}, {}]}, calls = [];
  const preparation = {
    admitResultPublicationRun(value) {assert.strictEqual(value, prepared); calls.push('publication');},
    prepareManagedSourceRun(runtime, value, requested, selected) {
      assert.equal(typeof runtime.clientProgramSerializationOccurrences, 'function');
      assert.strictEqual(value, prepared); assert.strictEqual(requested, request);
      assert.strictEqual(selected, profile); calls.push('same-source-parent');
    },
  };
  admission(preparation, profile, prepared, request, 2);
  assert.deepEqual(calls, ['publication', 'same-source-parent']);
});

test('plural Source preparations forward one original parent and retain original methods', async () => {
  const checked = {}, parent = {}, quote = {}, log = [], prepared = [{}, {}];
  const originals = [0, 1].map(index => ({
    managedCaptureCapacity(requirement) {assert.strictEqual(this, originals[index]); return {requirement, capacity: quote};},
    async prepare(facts) {assert.strictEqual(this, originals[index]); assert.strictEqual(facts.preparedProgram, checked);
      log.push(index); return prepared[index];},
    ledgerCapacity(value) {assert.strictEqual(this, originals[index]); assert.strictEqual(value, prepared[index]);
      return {capacity: quote, transferBytes: 7n, executionBytes: 11n};},
  }));
  let current = true;
  const profile = bindInstalledManagedSources({sources: originals}, value => {
    assert.strictEqual(value, checked); if (!current) throw new Error('RetiredOriginal'); return parent;
  });
  originals[0].prepare = originals[0].ledgerCapacity = () => assert.fail('Replaced original method');
  for (let index = 0; index < 2; index++) {
    const result = await profile.sources[index].prepare({preparedProgram: checked});
    assert.strictEqual(result, prepared[index]);
    assert.deepEqual(profile.sources[index].ledgerCapacity(result),
      {capacity: quote, transferBytes: 7n, executionBytes: 11n, managedRun: parent});
  }
  assert.deepEqual(log, [0, 1]);
  assert.throws(() => profile.sources[1].ledgerCapacity(prepared[0]), /ForeignInstalledManagedSource/);
  assert.throws(() => profile.sources[0].ledgerCapacity({...prepared[0]}), /ForeignInstalledManagedSource/);
  current = false;
  assert.throws(() => profile.sources[0].ledgerCapacity(prepared[0]), /RetiredOriginal/);
});

test('Source preparation cannot install a parent association after cancellation during await', async () => {
  const checked = {}, parent = {}, prepared = {}; let current = true, capacities = 0;
  const profile = bindInstalledManagedSources({managedCaptureCapacity() {},
    async prepare() {await Promise.resolve(); current = false; return prepared;},
    ledgerCapacity() {capacities++; return {};},
  }, value => {assert.strictEqual(value, checked); if (!current) throw new Error('CancelledOriginal'); return parent;});
  await assert.rejects(profile.prepare({preparedProgram: checked}), /CancelledOriginal/);
  assert.throws(() => profile.ledgerCapacity(prepared), /ForeignInstalledManagedSource/);
  assert.equal(capacities, 0);
});

test('Source preparation requires the same captured own checked Program across its original await', async () => {
  const original = {}, foreign = {}, parent = {}, prepared = {}; let calls = 0, reads = 0;
  const profile = bindInstalledManagedSources({managedCaptureCapacity() {},
    async prepare(facts) {calls++; await Promise.resolve(); facts.preparedProgram = foreign; return prepared;},
    ledgerCapacity() {assert.fail('No association may be installed');},
  }, checked => {assert.strictEqual(checked, original); return parent;});
  await assert.rejects(profile.prepare({preparedProgram: original}), /ForeignInstalledManagedSource/);
  await assert.rejects(profile.prepare(Object.create({preparedProgram: original})), /ForeignInstalledManagedSource/);
  await assert.rejects(profile.prepare({get preparedProgram() {reads++; return original;}}), /ForeignInstalledManagedSource/);
  assert.equal(calls, 1); assert.equal(reads, 0);
  assert.throws(() => profile.ledgerCapacity(prepared), /ForeignInstalledManagedSource/);
});

test('unmigrated and already managed Sources retain their selected preparation path', () => {
  const legacy = {prepareManagedRun() {}}, missing = {sources: [{managedCaptureCapacity() {}}, {}]};
  const forbidden = () => assert.fail('No alternate parent may be issued');
  assert.strictEqual(bindInstalledManagedSources(legacy, forbidden), legacy);
  assert.strictEqual(bindInstalledManagedSources(missing, forbidden), missing);
  assert.strictEqual(bindInstalledManagedSources(undefined, forbidden), undefined);
});

test('managed Source view preserves original physical and plural method receivers without changing their returns', () => {
  const child = {}, close = Promise.resolve({pending: true}), capture = {}, source = {
    managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    open(value) {assert.strictEqual(this, source); assert.strictEqual(value, child); return child;},
    close() {assert.strictEqual(this, source); return close;},
    retainedCapture(value) {assert.strictEqual(this, source); assert.strictEqual(value, child); return capture;},
    admitsSource(value) {assert.strictEqual(this, source); return value === 'original';},
  };
  const profile = {sources: [source], close() {assert.strictEqual(this, profile); return close;},
    admitsSource(value) {assert.strictEqual(this, profile); return value === 'plural';}};
  const view = bindInstalledManagedSources(profile, () => assert.fail('Method forwarding does not issue a parent'));
  for (const name of ['open', 'close', 'retainedCapture', 'admitsSource']) source[name] = () => assert.fail('Replaced child method');
  profile.close = profile.admitsSource = () => assert.fail('Replaced plural method');
  assert.strictEqual(view.sources[0].open(child), child);
  assert.strictEqual(view.sources[0].close(), close);
  assert.strictEqual(view.sources[0].retainedCapture(child), capture);
  assert.equal(view.sources[0].admitsSource('original'), true);
  assert.strictEqual(view.close(), close);
  assert.equal(view.admitsSource('plural'), true);
});

test('DuckDB quotes its actual pending capture and physical transport without selecting or reading it', async () => {
  const text = readFileSync(new URL('./installed-source.mjs', import.meta.url), 'utf8');
  const syntax = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const node = syntax.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'duckdbAdapter');
  assert(node);
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const requirement = {}, pending = {}, capacity = {}, calls = [];
  const profile = {database: '/never-opened.duckdb', schema: 'main', table: 'four_rows', sourceRef: 'source:rows',
    environmentWire: '{"connector_catalogs":[]}', transportLimits: {maxRows: 4, maxCells: 4,
      maxTransportBytes: 1024, maxSqlBytes: 4096, maxParameters: 0, maxColumns: 1, memoryBytes: 1048576, threads: 1}};
  const moon = {
    clientProgramQueryRequirementSourceRef(value) {return value === requirement ? profile.sourceRef : 'source:foreign';},
    clientProgramPrepareDuckDBCaptureCapacity(value, schema, table, ...contracts) {
      assert.strictEqual(value, requirement); assert.equal(schema, 'main'); assert.equal(table, 'four_rows');
      assert.deepEqual(contracts.map(body => JSON.parse(body).version),
        ['actql-query-acquisition-contract/0.1', 'actql-query-process-evidence-contract/0.1', 'actql-query-two-receipt-contract/0.1']);
      calls.push('pending'); return pending;
    },
    clientProgramInstalledPendingDuckDBCaptureCapacity(value) {assert.strictEqual(value, pending); calls.push('typed-capacity'); return capacity;},
  };
  const create = await new AsyncFunction('loadDuckDBNativeRuntime', 'readFile', 'checked',
    'computePhysicalCapacity', 'importMetaUrl',
    text.slice(node.start, node.end).replaceAll('import.meta.url', 'importMetaUrl') + ';return duckdbAdapter;')(
    async () => {}, readFile, value => value, computePhysicalCapacity, new URL('./installed-source.mjs', import.meta.url).href);
  const adapter = await create(profile, moon, {root: '/unused', principalId: 'original'});
  const result = adapter.managedCaptureCapacity(requirement), physical = computePhysicalCapacity(profile.transportLimits);
  assert.deepEqual(result, {capacity, transferBytes: physical.transferBytes, executionBytes: physical.executionBytes});
  assert.deepEqual(calls, ['pending', 'typed-capacity']);
  assert.throws(() => adapter.managedCaptureCapacity({}), /InstalledSourceProgramMismatch/);
  assert.deepEqual(calls, ['pending', 'typed-capacity']);
});
