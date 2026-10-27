import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
// A finite source-matched diagnostic can use its own build directory without
// overwriting a retained/borrowed default runtime. This is test plumbing only.
const moon = await import(process.env.ACTQL_TEST_FILE_LISTING_RUNTIME ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowSource} from './installed-row-source.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {fileListingDeclaration, token, item} from './fixtures/file-listing-source.fixture.mjs';
import {readGcsFileListing, GCS_FILE_LIST_OPERATION} from
  '../connectors/gcs/site/gcs-file-listing.mjs';

const read = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
async function fixture(selector, text, format = 'sql', listingLimits) {
  const {declaration, declared, environment: env, aliases, issuer} = fileListingDeclaration(
    moon, (await read('spec/local-check-environment.json')).trimEnd(), listingLimits);
  const environment = moon.clientProgramCheckEnvironment(env.wire, env.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(environment, 'the actual declared file-list profile is admitted');
  const document = JSON.stringify({version: 'actql/0.1', id: 'file-list-fixture',
    stages: [{id: 'scan', inputs: {remote: {connector: 'fixture', resource: 'files', request: selector}},
      steps: [{filter: 'true', as: 'listed'}, {select: ['name'], as: 'output'}],
      results: {r: {from: 'output', fields: ['name']}}}],
    results: {r: {from: {stage: 'scan', result: 'r'}}}});
  let prepared;
  if (text === undefined) {
    const preparation = moon.clientProgramPrepareEffectFreeWithParameters(document, 'json', environment, undefined);
    prepared = moon.clientProgramPreparationReady(preparation);
    assert.ok(prepared, inspect(moon.clientProgramPreparationIssue(preparation), {depth: 12}));
  } else {
    const publication = sourceAliasPublication(moon, environment, aliases);
    const prepare = installNodeClientProgramPreparation({moon, environment,
      sourcePublication: publication});
    // Use the actual public submit preparation. The caller does not add a
    // filter or replace the authored text with a hand-rendered JSON Program.
    try {
      prepared = await prepare({kind: 'aql', input: {text, format}, parameters: null});
    } catch (error) {
      assert.fail(inspect(error, {depth: 20}));
    }
    prepare.assertOwned(prepared);
  }
  const [registry, aoa, queryContract, evidenceContract] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json'),
  ]);
  const required = moon.clientProgramPrepareLocalQueryRequirement(prepared,
    0, 0, registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
  assert.equal(required.$tag, 1, inspect(required, {depth: 12}));
  const requirement = checked(required);
  const acquired = moon.clientProgramRowSourcePrepareAcquisition(
    declaration, requirement, queryContract, evidenceContract, undefined);
  assert.equal(acquired.$tag, 1, inspect(acquired, {depth: 12}));
  const acquisition = checked(acquired);
  const run = checked(moon.clientProgramRowSourceStart(acquisition, 'fixture', () => true));
  return {run, acquisition, issuer, declaration, declared, prepared,
    environmentWire: env.wire, registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
}

for (const empty of [true, false]) {
  test(`actual installed report supplier keeps ${empty ? 'empty' : 'duplicate and raw media'} correlation under the original Source owner`, async t => {
    const value = await fixture({paths: empty ? [] : ['a.csv'], glob: null});
    t.after(() => moon.clientProgramRowSourceClose(value.run));
    // Independent DATA units exercise the existing Ledger path, not an
    // adopted target allocation price or a normally installed public profile.
    const reportCapacity = moon.clientProgramRowSourceListingReportCapacity(7n, 9n);
    assert.notEqual(reportCapacity, undefined);
    const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1,
      32768n, 100000000n, 100000000n, 0));
    let reads = 0, grants = 0;
    const rawMedia = 'Text/Plain;Label="e\u0301"';
    const row = {...item('d', 'a.csv', '9007199254740993'), media_type: rawMedia};
    const adapter = await createInstalledRowSource({moon,
      declaration: value.declaration, declared: value.declared,
      environmentWire: value.environmentWire,
      connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
      referenceIssuer: value.issuer, bindingCid: token('c'), readOperation: 'read',
      listingReportCapacity: reportCapacity,
      site: {connection: 'fixture:files', issueReadGrant() { grants++; return {}; }, close() {}},
      authorization: {authorize: async () => ({action: 'dispatch'}),
        accountConfiguration: '{}', context: {contextCid: token('b')}},
      physicalTarget: (resource, fields) => ({resource, fields}),
      limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
      readPages: async ({listing, chargePage}) => {
        reads++;
        await listing.beginRequest(undefined);
        const body = Buffer.from(JSON.stringify({items: [row, row],
          request_token: null, next_token: null}));
        assert.equal(await listing.consumePage(body, {charge: chargePage(body)}), 1);
      }});
    const options = {preparedProgram: value.prepared, registry: value.registry,
      values: value.values, fragment: value.fragment, ordered: value.ordered};
    const preparedSource = await adapter.prepare(options);
    const capacity = adapter.ledgerCapacity(preparedSource);
    assert.notEqual(capacity.capacity, undefined);
    const shortLedger = checked(moon.clientProgramAcquisitionLedger(1, 1,
      32768n, 1n, 1n, 0));
    const before = moon.clientProgramMultiCapturedLedgerUsage(shortLedger);
    await assert.rejects(adapter.openCapture({...options, preparedSource, ledger: shortLedger}),
      error => error.cause?.code === 'MoonBitHostFailure');
    assert.equal(reads, 0);
    assert.equal(grants, 0);
    assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(shortLedger), before);
    const captured = await adapter.openCapture({...options, preparedSource, ledger});
    t.after(() => captured.close());
    assert.equal(reads, empty ? 0 : 1);
    assert.equal(grants, empty ? 0 : 1);
    assert.equal(moon.clientProgramCapturedSourceRowCount(captured.identity), empty ? 0 : 1);
    const evidence = JSON.parse(await captured.issueSourceEvidence({
      authorityScopeCid: token('b'),
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}));
    assert.deepEqual(evidence.file_listing_reports, {row_count: empty ? 0 : 1,
      rows: empty ? [] : [{row_ordinal: 0, resource_ref_cid: token('d'),
        version: '9007199254740993', reported_media_type: rawMedia,
        media_type: 'text/plain;label="e\u0301"'}]});
    const live = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    assert.equal(ledgerUsageSnapshot(live).attempts, 1n);
    assert.ok(ledgerUsageSnapshot(live).reservedRetentionBytes > 0n && ledgerUsageSnapshot(live).reservedExecutionBytes > 0n,
      'report reservation remains live after capture and evidence encoding');
    captured.close();
    const retired = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    assert.equal(ledgerUsageSnapshot(retired).heldBytes, 0n);
    assert.equal(ledgerUsageSnapshot(retired).reservedRetentionBytes, 0n);
    assert.equal(ledgerUsageSnapshot(retired).reservedExecutionBytes, 0n);
    await assert.rejects(captured.issueSourceEvidence({authorityScopeCid: token('b'),
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}),
    {code: 'MoonBitHostFailure'});
  });
}

test('actual installed report cleanup keeps the original reservation until all three reports retire', async t => {
  const value = await fixture({paths: null, glob: '*.csv'});
  t.after(() => moon.clientProgramRowSourceClose(value.run));
  const reportCapacity = moon.clientProgramRowSourceListingReportCapacity(7n, 9n);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1,
    32768n, 100000000n, 100000000n, 0));
  let reads = 0;
  const rows = ['d', 'e', 'f'].map(ch => item(ch, `${ch}.csv`));
  const adapter = await createInstalledRowSource({moon,
    declaration: value.declaration, declared: value.declared,
    environmentWire: value.environmentWire,
    connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    referenceIssuer: value.issuer, bindingCid: token('c'), readOperation: 'read',
    listingReportCapacity: reportCapacity,
    site: {connection: 'fixture:files', issueReadGrant: () => ({}), close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: token('b')}},
    physicalTarget: (resource, fields) => ({resource, fields}),
    limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
    readPages: async ({listing, chargePage}) => {
      reads++;
      await listing.beginRequest(undefined);
      const body = Buffer.from(JSON.stringify({items: rows,
        request_token: null, next_token: null}));
      assert.equal(await listing.consumePage(body, {charge: chargePage(body)}), 3);
    }});
  const options = {preparedProgram: value.prepared, registry: value.registry,
    values: value.values, fragment: value.fragment, ordered: value.ordered};
  const captured = await adapter.openCapture({...options, ledger});
  // A later assertion failure must not leave this known finite Core cleanup
  // unfinished. Each invocation advances the same RowRun, never reacquires it.
  t.after(() => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try { captured.close(); return; }
      catch (error) { if (error.code !== 'MoonBitHostFailure') throw error; }
    }
    assert.fail('original report cleanup did not settle');
  });
  const evidence = JSON.parse(await captured.issueSourceEvidence({
    authorityScopeCid: token('b'),
    effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}));
  assert.deepEqual(evidence.file_listing_reports, {row_count: 3,
    rows: ['d', 'e', 'f'].map((ch, ordinal) => ({row_ordinal: ordinal,
      resource_ref_cid: token(ch), version: '1',
      reported_media_type: null, media_type: null}))});
  const live = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.ok(ledgerUsageSnapshot(live).reservedRetentionBytes > 0n && ledgerUsageSnapshot(live).reservedExecutionBytes > 0n);
  for (let attempt = 0; attempt < 2; attempt++) {
    assert.throws(() => captured.close(), {code: 'MoonBitHostFailure'});
    const pending = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    assert.equal(ledgerUsageSnapshot(pending).heldBytes, ledgerUsageSnapshot(live).heldBytes, 'original holding stays reserved');
    assert.equal(ledgerUsageSnapshot(pending).reservedRetentionBytes, ledgerUsageSnapshot(live).reservedRetentionBytes, 'retention is not refunded by partial reclaim');
    assert.equal(ledgerUsageSnapshot(pending).reservedExecutionBytes, ledgerUsageSnapshot(live).reservedExecutionBytes, 'encoding/cleanup workspace stays reserved');
    await assert.rejects(captured.issueSourceEvidence({authorityScopeCid: token('b'),
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}),
    {code: 'MoonBitHostFailure'});
  }
  captured.close();
  const retired = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.equal(ledgerUsageSnapshot(retired).heldBytes, 0n);
  assert.equal(ledgerUsageSnapshot(retired).reservedRetentionBytes, 0n);
  assert.equal(ledgerUsageSnapshot(retired).reservedExecutionBytes, 0n);
  captured.close();
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), retired);
  assert.equal(reads, 1, 'cleanup retries never reacquire the Source');
});

test('SQL and Pipe LIST_FILES use the installed capture boundary without a caller-authored filter', async t => {
  for (const [text, format] of [
    ["SELECT name FROM LIST_FILES(docs.invoices, glob => '**/*.csv')", 'sql'],
    ["FROM LIST_FILES(docs.invoices, glob => '**/*.csv') |> SELECT name", 'aql-text'],
  ]) {
    const fixtureValue = await fixture(undefined, text, format);
    const {run, declaration, declared, issuer, prepared, environmentWire,
      registry, values, fragment, ordered} = fixtureValue;
    t.after(() => moon.clientProgramRowSourceClose(run));
    const observed = [];
    const adapter = await createInstalledRowSource({moon, declaration, declared,
      environmentWire, connectorId: 'fixture', connectorRegistration: 'fixture',
      connectorRevision: 'fixture/0.1', referenceIssuer: issuer,
      bindingCid: token('c'), readOperation: 'read',
      site: {connection: 'fixture:files', issueReadGrant: () => ({}), close() {}},
      authorization: {authorize: async () => ({action: 'dispatch'}),
        accountConfiguration: '{}', context: {contextCid: token('b')}},
      physicalTarget: (resource, fields) => ({resource, fields}),
      limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
      readPages: async ({requestWire, listing, chargePage}) => {
        assert.deepEqual(JSON.parse(requestWire), {glob: '**/*.csv', paths: null});
        assert.ok(listing, 'the admitted Catalog profile selects the common listing protocol');
        for (const [requestToken, nextToken, items] of [
          [undefined, 'next', [item('f', 'ignored.txt')]],
          ['next', null, [item('d', 'a.csv'), item('e', 'b/z.csv')]],
        ]) {
          await listing.beginRequest(requestToken);
          const body = Buffer.from(JSON.stringify({items,
            request_token: requestToken ?? null, next_token: nextToken}));
          observed.push(await listing.consumePage(body, {charge: chargePage(body)}));
        }
      }});
    const captured = await adapter.open({preparedProgram: prepared, registry,
      values, fragment, ordered});
    t.after(() => captured.close());
    assert.deepEqual(observed, [0, 2]);
    assert.equal(moon.clientProgramCapturedSourceRowCount(captured.identity), 2);
    assert.equal(captured.checkedSource.sourceRef, declared.views[0].source_ref);
  }
});

test('compiled listing owner admits exact selectors, nonmatching pages and distinct issued Resources', async t => {
  const {run, acquisition, issuer} = await fixture({paths: null, glob: '**/*.csv'});
  t.after(() => moon.clientProgramRowSourceClose(run));
  assert.equal(moon.clientProgramRowSourceIsListing(acquisition), true);
  checked(moon.clientProgramRowSourceBegin(run, 8192, 9, 3, issuer));
  const listing = rowListingCallbacks({moon, run, currentRead: async () => {}});
  const page = async (token, next, items) => {
    await listing.beginRequest(token);
    const body = Buffer.from(JSON.stringify({items, request_token: token ?? null, next_token: next}));
    const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
    return listing.consumePage(body, {charge});
  };
  assert.equal(await page(undefined, 'p1', [item('f', 'ignore.txt')]), 0);
  assert.equal(moon.clientProgramRowSourceListingComplete(run), false);
  assert.equal(await page('p1', 'p2', [item('d', 'a.csv'), item('d', 'a.csv'), item('e', 'b/z.csv')]), 2);
  assert.equal(moon.clientProgramRowSourceListingComplete(run), false);
  assert.equal(await page('p2', null, []), 0);
  assert.equal(moon.clientProgramRowSourceListingComplete(run), true);
  checked(moon.clientProgramRowSourceFinish(run));
  assert.ok(checked(moon.clientProgramRowSourceCapture(run)));
});

test('compiled listing owner rejects missing issuer before I/O and completes empty paths without requests', async t => {
  const {run, issuer} = await fixture({paths: [], glob: null});
  t.after(() => moon.clientProgramRowSourceClose(run));
  checked(moon.clientProgramRowSourceBegin(run, 8192, 9, 3, issuer));
  assert.equal(moon.clientProgramRowSourceListingComplete(run), true);
  checked(moon.clientProgramRowSourceFinish(run));
  assert.ok(checked(moon.clientProgramRowSourceCapture(run)));
  const missing = await fixture({paths: null, glob: '*'});
  t.after(() => moon.clientProgramRowSourceClose(missing.run));
  assert.throws(() => checked(moon.clientProgramRowSourceBegin(missing.run, 8192, 9, 3, undefined)),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramRowSourceFinish(missing.run)), {code: 'MoonBitHostFailure'});
});

test('compiled listing owner refuses incomplete or contradictory observations without capture', async t => {
  for (const conflict of [false, true]) {
    const {run, issuer} = await fixture({paths: ['a'], glob: null});
    t.after(() => moon.clientProgramRowSourceClose(run));
    checked(moon.clientProgramRowSourceBegin(run, 8192, 9, 3, issuer));
    const listing = rowListingCallbacks({moon, run, currentRead: async () => {}});
    await listing.beginRequest(undefined);
    await listing.consumePage(Buffer.from(JSON.stringify({items: [item('d', 'a')],
      request_token: null, next_token: 'more'})));
    if (conflict) {
      await listing.beginRequest('more');
      await assert.rejects(listing.consumePage(Buffer.from(JSON.stringify({items: [item('d', 'a', '2')],
        request_token: 'more', next_token: null}))), {code: 'MoonBitHostFailure'});
    }
    assert.throws(() => checked(moon.clientProgramRowSourceFinish(run)), {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)), {code: 'MoonBitHostFailure'});
  }
});

test('GCS physical pages reach actual installed listing capture without provider glob translation', async t => {
  const value = await fixture(undefined,
    "FROM LIST_FILES(docs.invoices, glob => '**/*.csv') |> SELECT name", 'aql-text');
  const {run, declaration, declared, issuer, prepared, environmentWire,
    registry, values, fragment, ordered} = value;
  t.after(() => moon.clientProgramRowSourceClose(run));
  const observed = [], raw = [], sends = [];
  const scope = {operation: GCS_FILE_LIST_OPERATION,
    resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1'};
  const pages = [
    {kind: 'storage#objects', nextPageToken: 'nonmatching', items: [
      {bucket: 'actql-fixture', name: 'ignored.txt', generation: '1', size: '3'}]},
    {kind: 'storage#objects', nextPageToken: 'empty', items: [
      {bucket: 'actql-fixture', name: 'b/z.csv', generation: '9007199254740993', size: '3'},
      {bucket: 'actql-fixture', name: 'a.csv', generation: '1', size: '3'}]},
    {kind: 'storage#objects'},
  ];
  const resources = new Map([['a.csv', item('d', 'a.csv').resource],
    ['b/z.csv', item('e', 'b/z.csv').resource],
    ['ignored.txt', item('f', 'ignored.txt').resource]]);
  const adapter = await createInstalledRowSource({moon, declaration, declared,
    environmentWire, connectorId: 'fixture', connectorRegistration: 'fixture',
    connectorRevision: 'fixture/0.1', referenceIssuer: issuer,
    bindingCid: token('c'), readOperation: GCS_FILE_LIST_OPERATION,
    site: {connection: 'fixture:gcs', issueReadGrant: () => ({grant: {}, scope}), close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: token('b')}},
    physicalTarget: (resource, fields) => ({resource, fields}),
    limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
    async readPages({listing, authorizationFor, chargePage}) {
      await readGcsFileListing({target: {bucket: 'actql-fixture', prefix: ''},
        limits: {maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxTimeMs: 10000},
        credential: {journal: {fixture: true}}, authorizationFor,
        resourceFor: target => resources.get(target.objectName),
        chargePage: body => { raw.push(Buffer.from(body)); return chargePage(body); },
        listing: {beginRequest: listing.beginRequest,
          consumePage: async (body, admission) => {
            observed.push(await listing.consumePage(body, admission));
          }},
        callResource: async call => {
          sends.push(call.operations.get(GCS_FILE_LIST_OPERATION).path);
          return {accepted: true, statusCode: 200, headers: [],
            body: Buffer.from(JSON.stringify(pages[sends.length - 1]))};
        }});
    }});
  const captured = await adapter.open({preparedProgram: prepared, registry,
    values, fragment, ordered});
  t.after(() => captured.close());
  assert.deepEqual(observed, [0, 2, 0]);
  assert.equal(raw.length, 3);
  assert.equal(moon.clientProgramCapturedSourceRowCount(captured.identity), 2);
  assert.ok(sends.every(path => !path.includes('matchGlob') && !path.includes('delimiter')));
  assert.ok(sends[1].includes('pageToken=nonmatching'));
  assert.ok(sends[2].includes('pageToken=empty'));
});

test('GCS charged physical bytes enforce exact listing ceiling, not normalized envelope length', async t => {
  // Independently fixed 200-byte provider response, projecting to the common
  // 51-byte empty terminal envelope. The ticket, not the projected body, is
  // the authority for physical listing bytes.
  const wire = '{"kind":"storage#objects"}';
  const raw = Buffer.from(wire + ' '.repeat(200 - Buffer.byteLength(wire)));
  assert.equal(raw.length, 200);
  for (const maximum of [200, 199]) {
    const value = await fixture({paths: null, glob: '*'}, undefined, 'sql',
      {maxListingBytes: maximum});
    t.after(() => moon.clientProgramRowSourceClose(value.run));
    const scope = {operation: GCS_FILE_LIST_OPERATION,
      resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1};
    let calls = 0;
    const adapter = await createInstalledRowSource({moon, declaration: value.declaration,
      declared: value.declared, environmentWire: value.environmentWire,
      connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
      referenceIssuer: value.issuer, bindingCid: token('c'),
      readOperation: GCS_FILE_LIST_OPERATION, physicalTarget: (resource, fields) => ({resource, fields}),
      site: {connection: 'fixture:gcs', issueReadGrant: () => ({grant: {}, scope}), close() {}},
      authorization: {authorize: async () => ({action: 'dispatch'}),
        accountConfiguration: '{}', context: {contextCid: token('b')}},
      limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
      readPages: ({listing, authorizationFor, chargePage}) => readGcsFileListing({
        target: {bucket: 'actql-fixture', prefix: ''},
        limits: {maxPageBytes: 4096, maxPageItems: 9, maxRequestBytes: 4096, maxTimeMs: 10000},
        listing, authorizationFor, chargePage, credential: {journal: {fixture: true}},
        resourceFor: () => assert.fail('An empty page cannot issue a Resource'),
        callResource: async () => {
          calls++;
          return {accepted: true, statusCode: 200, headers: [], body: raw};
        },
      }),
    });
    const open = () => adapter.open({preparedProgram: value.prepared, registry: value.registry,
      values: value.values, fragment: value.fragment, ordered: value.ordered});
    if (maximum === 200) {
      const capture = await open(); t.after(() => capture.close());
      assert.equal(moon.clientProgramCapturedSourceRowCount(capture.identity), 0);
    } else {
      await assert.rejects(open(), error => {
        assert.equal(error.code, 'MoonBitHostFailure');
        assert.match(inspect(error, {depth: 20}), /max_listing_bytes/u);
        return true;
      });
    }
    assert.equal(calls, 1);
  }
});
