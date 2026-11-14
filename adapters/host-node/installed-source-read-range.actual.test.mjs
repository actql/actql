import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {beginInstalledSourceInitialization, finishInstalledSourceInitialization,
  retainInstalledHostServiceInstallation} from './installed-host-services.mjs';
import {createInstalledRowSource} from './installed-row-source.mjs';
import {installedSourceReadAccesses, installedSourceReadBindings} from './installed-source.mjs';
import {createInstalledConnectorTable, installedConnectorForTable} from './installed-connectors.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';

const runtimeUrl = process.env.ACTQL_TEST_BOUND_CONSTRUCTION_RUNTIME === undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)
  : pathToFileURL(process.env.ACTQL_TEST_BOUND_CONSTRUCTION_RUNTIME);
const runtimeCid = `sha256:${createHash('sha256').update(await readFile(runtimeUrl)).digest('hex')}`;

// Actual initial Resource, Source construction, checked acquisition and RowRun.
// The page/authorization ports are component fixtures, not an installed remote
// provider or ordinary SDK/Host acceptance. All nominal values use f.moon.
async function fixture(t, {denied = false} = {}) {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const selected = await f.profile();
  const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors),
    'source', selected.value);
  // The component uses this actual selected installation and its same parent.
  // Pin the actual imported runtime, not a claimed publication/provider result.
  retainInstalledHostServiceInstallation(f.services, entry, runtimeCid);
  const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  const context = beginInstalledSourceInitialization(f.services, entry, 'fixture', baseWire);
  const views = Array.from({length: 65}, (_, index) => ({resource: `records-${index}`,
    resource_kind: 'record', fields: [{name: 'id', type: 'number', nullable: false}]}));
  let reads = 0, grants = 0, adapter, original;
  const decisions = [];
  const authorization = {authorize: async value => {
    decisions.push(value.resource);
    return {action: denied ? 'deny' : 'dispatch'};
  }, accountConfiguration: '{}', context: {contextCid: 'fixture-context'}};
  try {
    original = context.prepareAuthoredDeclaration(JSON.stringify({views}));
    adapter = await createInstalledRowSource({moon: f.moon, ...original,
      environmentWire: original.environment.wire, sourceInitialization: context,
      connectorId: 'fixture', connectorRegistration: entry.registration, connectorRevision: entry.revision,
      site: {connection: 'fixture:read-range', issueReadGrant() {grants++; return {};}, close() {}},
      authorization, readOperation: 'read', physicalTarget: (resource, fields) => ({resource, fields}),
      async readPages({resource, verifyRead, chargePage, consumePage}) {
        assert.equal(resource, 'records-64');
        await verifyRead(); reads++;
        const rows = [{id: 65}], bytes = Buffer.from(JSON.stringify(rows));
        assert.equal(consumePage(rows, {charge: chargePage(bytes)}), 1);
      }, bindingCid: `sha256:${'b'.repeat(64)}`,
      limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 2, maxCaptureRows: 2}});
    finishInstalledSourceInitialization(context, adapter);
    f.sources.push(adapter);
  } catch (cause) {
    finishInstalledSourceInitialization(context, adapter, cause, true);
    throw cause;
  }
  const accesses = installedSourceReadAccesses(adapter), access = accesses[64];
  assert.equal(accesses.length, 65);
  assert.equal(installedSourceReadBindings(adapter)[64], access.sourceRef);
  assert.equal(access.resource, 'records-64');
  assert.ok(events.some(event => event.accepted && event.operation ===
    'clientProgramReserveInstalledSourceConstruction'));
  const checkedEnvironment = f.moon.clientProgramCheckEnvironment(original.environment.wire,
    original.environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const program = {version: 'actql/0.1', id: 'source-read-range', stages: [{id: 'scan',
    inputs: {remote: {connector: 'fixture', resource: 'records-64'}},
    steps: [{select: ['id'], as: 'out'}], results: {r: {from: 'out', fields: ['id']}}},
  {id: 'compute', inputs: {x: {result: {stage: 'scan', result: 'r'}}},
    steps: [{filter: 'id > 0'}, {select: ['id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}}}],
  results: {r: {from: {stage: 'compute', result: 'r'}}}};
  const outcome = f.moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),
    'json', checkedEnvironment, undefined);
  const preparedProgram = f.moon.clientProgramPreparationReady(outcome);
  assert.ok(preparedProgram);
  const [registry, aoa] = await Promise.all([
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8').then(JSON.parse)]);
  const inputs = {preparedProgram, registry, sourceAccess: access,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  return {...f, adapter, inputs, access, authorization, decisions, events,
    counts: () => ({reads, grants})};
}

test('same initial Source owner admits and captures the sixty-fifth declared read binding', async t => {
  const f = await fixture(t);
  const preparedSource = await f.adapter.prepare(f.inputs);
  const planned = f.adapter.ledgerCapacity(preparedSource);
  const ledger = f.moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(f.inputs.preparedProgram,
    planned.capacity, planned.transferBytes, planned.executionBytes,
    f.inputs.registry, f.inputs.values, f.inputs.fragment, f.inputs.ordered);
  assert.ok(ledger);
  const capture = await f.adapter.openCapture({...f.inputs, preparedSource, ledger});
  try {
    assert.equal(f.moon.clientProgramCapturedSourceRowCount(capture.identity), 1);
    assert.deepEqual(f.counts(), {reads: 1, grants: 1});
    assert.ok(f.decisions.length > 0 && f.decisions.every(resource => resource === 'records-64'));
  } finally {await capture.close();}
  await f.close();
  assert.equal(f.retire(), true);
});

test('larger Source range retains exact identity and current-read refusal controls', async t => {
  const f = await fixture(t, {denied: true});
  const original = installedSourceReadAccesses(f.adapter);
  for (const last of [original[0], {...f.access, authorization: {...f.authorization}},
    {...f.access, connection: 'foreign'}]) {
    assert.throws(() => installedSourceReadBindings({...f.adapter,
      sourceReadAccesses: [...original.slice(0, 64), last]}),
    {message: 'InvalidInstalledSourceReadAccesses'});
  }
  await assert.rejects(f.adapter.prepare(f.inputs), {code: 'ACTQL_E_ACCOUNT_DENIED'});
  assert.deepEqual(f.counts(), {reads: 0, grants: 0});
  assert.ok(f.decisions.length > 0);
  await f.close();
  assert.equal(f.retire(), true);
});
