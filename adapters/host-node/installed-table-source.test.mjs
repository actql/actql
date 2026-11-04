import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from './fixtures/ledger-usage.mjs';
// Real Iceberg generations -> installed row Source -> common capture. This is
// not packed/public Effect approval acceptance: fixture publication is direct.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {checked as checkedRuntime} from '../host-common/runtime-result.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {installRowSourceAuthorization} from './installed-row-source.mjs';
import {createInstalledTableSource} from './installed-table-source.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
const connection = 'local-table';
const limits = {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16};

async function sourceFixture(t, rows, runtime = moon) {
  const f = await tablePhysicalFixture(t);
  const operation = f.operation();
  const material = f.prepare(operation, rows);
  const committed = await f.bridge.execute(material, {useCid: cid('7')});
  const receipt = JSON.parse(committed.observation.body).result;
  assert.equal(receipt.row_count, rows.length);
  const selector = {catalog_identity_cid: f.catalog.catalogCid, namespace: ['test'],
    table_name: 'rows', table_uuid: receipt.table_uuid, schema_cid: f.mapping.schema_cid};
  const allow = await installRowSourceAuthorization({accountConfiguration:
    sourceReadAccountConfiguration({connection, resource: 'rows'}), principalId: 'table-reader',
  root: f.root, connectorRegistration: 'local'});
  const deny = await installRowSourceAuthorization({accountConfiguration:
    sourceReadAccountConfiguration({connection, resource: 'rows', outcome: 'deny'}),
  principalId: 'table-reader', root: f.root, connectorRegistration: 'local'});
  let current = allow, checks = 0, stopAt = Infinity;
  const authorization = {...allow, authorize: async (...args) => {
    checks++;
    if (checks >= stopAt) current = deny;
    return current.authorize(...args);
  }};
  // The installed local filesystem transport needs no external secret. Its
  // dispatch gate is genuine; this fixture's Site only verifies the gate's
  // opaque fact rather than manufacturing an approval/credential observation.
  const site = {connection, close() {},
    issueReadGrant({decision, resource}) {
      assert.equal(resource, 'rows');
      const facts = authorizationDispatchFacts(decision);
      assert.ok(facts);
      assert.equal(facts.configurationCid, allow.configurationCid);
      assert.equal(decision.action, 'dispatch');
      return Object.freeze({decision});
    },
  };
  const install = async (bridge, sourceLimits = limits) => createInstalledTableSource({moon: runtime,
    baseEnvironmentWire: (await read('spec/local-check-environment.json')).trimEnd(),
    connectorId: 'table-local', connectorRegistration: 'local', connectorRevision: 'local/0.1',
    site, authorization, bridge, limits: sourceLimits,
    targets: [{resource: 'rows', selector, schemaWire: f.schemaWire}]});
  const prepare = async source => {
    const environment = JSON.parse(source.environmentWire);
    const checked = moon.clientProgramCheckEnvironment(source.environmentWire,
      environment.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(checked);
    // Use the existing two-capture Run ledger, without creating a new budget
    // owner. These tests acquire its first occurrence and inspect its custody;
    // they do not claim execution of the joined Program or public results.
    const inputStage = id => ({id, inputs: {input: {connector: 'table-local', resource: 'rows'}},
        steps: [{filter: 'id >= 0', as: 'kept'}, {select: ['id'], as: 'output'}],
        results: {rows: {from: 'output', fields: ['id']}}});
    const document = JSON.stringify({version: 'actql/0.1', id: 'independent-table-reader',
      stages: [inputStage('read'), inputStage('second'),
        {id: 'join', inputs: {left: {result: {stage: 'read', result: 'rows'}},
          right: {result: {stage: 'second', result: 'rows'}}},
        steps: [{from: 'left', join: {with: 'right', kind: 'inner',
          on: [{left: 'id', right: 'id'}], max_output_rows: 100,
          select: {id: 'left.id'}}, as: 'output'}],
        results: {rows: {from: 'output', fields: ['id']}}}],
      results: {rows: {from: {stage: 'join', result: 'rows'}}}});
    const preparedProgram = moon.clientProgramPrepareEffectFree(document, 'json', checked);
    assert.ok(preparedProgram);
    const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
    const inputs = {preparedProgram, registry: await read('spec/dependencies/aoa-pipeline-registry.json'),
      values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
    // Admit the same installed contract tuple once, as the normal Host does;
    // query preparation and its two-capture Ledger share this nominal original.
    inputs.registry = checkedRuntime(moon.clientPrepareInstalledSequenceContracts(
      inputs.registry, inputs.values, inputs.fragment, inputs.ordered));
    const preparedSources = await Promise.all([0, 1].map(stage => source.prepare(
      {...inputs, occurrence: {stage, input: 0, task: stage}})));
    const capacities = preparedSources.map(value => source.ledgerCapacity(value));
    const ledger = moon.clientProgramPrepareMultiCapturedLocalInstalledLedger(
      preparedProgram, capacities.map(value => value.capacity),
      capacities.map(value => value.transferBytes),
      capacities.map(value => value.executionBytes), inputs.registry, inputs.values,
      inputs.fragment, inputs.ordered);
    assert.ok(ledger);
    return {...inputs, preparedSource: preparedSources[0], ledger};
  };
  return {...f, material, receipt, selector, install, prepare,
    revokeAt(check) { stopAt = check; }, checks: () => checks};
}

for (const empty of [false, true]) {
  test(`installed Table Source freezes a real ${empty ? 'empty' : 'sparse'} generation through later replace`, async t => {
    const expected = empty ? [] : [{id: 1, p: 'e\u0301\r\n'}, {id: 2, p: null}, {id: 3}, {id: 3}];
    let captureResumes = 0;
    const runtime = Object.freeze({...moon,
      clientProgramRowSourceCaptureAdvance(...args) {
        captureResumes++;
        return Reflect.apply(moon.clientProgramRowSourceCaptureAdvance, moon, args);
      }});
    const f = await sourceFixture(t, expected, runtime);
    let received, generation, replaced = false;
    const bridge = {...f.bridge,
      async resolveGeneration(selector, signal) {
        const frozen = await f.bridge.resolveGeneration(selector, signal);
        generation = frozen.result.receipt.generation_cid;
        if (!replaced) {
          // This is a separate fixture publication, not replay of the old
          // operation. The acquired reader must retain the earlier generation.
          const material = f.bridge.prepareWrite({operation: f.operation('replace', {
            table_uuid: f.receipt.table_uuid, generation_cid: f.receipt.generation_cid}),
          mapping: f.mapping, rows: [{id: 9}], schemaWire: f.schemaWire,
          reservation: {bytes: 1048576, files: 16}});
          const next = JSON.parse((await f.bridge.execute(material, {useCid: cid('7')})).observation.body);
          assert.equal(next.ok, true);
          replaced = true;
        }
        return frozen;
      },
      async read(receipt, mapping, signal) {
        assert.equal(receipt.generation_cid, generation);
        const response = await f.bridge.read(receipt, mapping, signal);
        received = plain(response.result);
        return response;
      },
    };
    const source = await f.install(bridge), prepared = await f.prepare(source);
    const preparationChecks = f.checks();
    assert.equal(preparationChecks, 2); // Both original Source occurrences prepare.
    const acquired = await source.open({...prepared, retainedRelationOutput: true});
    try {
      assert.deepEqual(received, expected);
      assert.equal(moon.clientProgramCapturedSourceRowCount(acquired.identity), expected.length);
      assert.equal(moon.clientProgramCapturedSourceSchemaCid(acquired.identity),
        'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513');
      // Five fixed original read boundaries plus current authority at every
      // actual bounded capture resume; the batching work is not a fixed count.
      assert.ok(captureResumes > 0);
      assert.equal(f.checks(), preparationChecks + 5 + captureResumes);
      assert.equal(acquired.setup, undefined);
      assert.ok(acquired.capture.source());
      assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger)).heldBytes > 0n);
    } finally { acquired.close(); }
    assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
      .every(value => value === 0n));
    assert.throws(() => acquired.capture.source(), {code: 'MoonBitHostFailure'});
    // Releasing the temporary acquisition never releases the durable Table.
    assert.deepEqual(plain((await f.bridge.read(f.receipt, f.mapping)).result), expected);
    const later = await source.open(await f.prepare(source));
    try { assert.equal(moon.clientProgramCapturedSourceRowCount(later.identity), 1); }
    finally { later.close(); await source.close(); }
  });
}

test('installed Table Source rechecks genuine read authority after each physical await', async t => {
  for (const stopAt of [3, 4, 5]) {
    await t.test(`deny at acquisition check ${stopAt}`, async t => {
      const f = await sourceFixture(t, [{id: 1}]);
      let metadata = 0, reads = 0;
      const bridge = {...f.bridge,
        async resolveGeneration(...args) { metadata++; return f.bridge.resolveGeneration(...args); },
        async read(...args) { reads++; return f.bridge.read(...args); }};
      const source = await f.install(bridge), prepared = await f.prepare(source);
      f.revokeAt(stopAt);
      await assert.rejects(source.open(prepared), {code: 'ExecutionAuthorizationDenied'});
      assert.equal(metadata, stopAt > 3 ? 1 : 0);
      assert.equal(reads, stopAt > 4 ? 1 : 0);
      assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
        .every(value => value === 0n));
      await source.close();
      assert.deepEqual(plain((await f.bridge.read(f.receipt, f.mapping)).result), [{id: 1}]);
    });
  }
});

test('installed Table Source cancellation after data I/O releases only its acquisition', async t => {
  const expected = [{id: 1, p: null}, {id: 2}];
  const f = await sourceFixture(t, expected);
  const abort = new AbortController();
  let reads = 0;
  const bridge = {...f.bridge, async read(...args) {
    const response = await f.bridge.read(...args);
    reads++;
    abort.abort(new Error('CancelledAfterTableRead'));
    return response;
  }};
  const source = await f.install(bridge), prepared = await f.prepare(source);
  await assert.rejects(source.open({...prepared, signal: abort.signal}),
    {message: 'CancelledAfterTableRead'});
  assert.equal(reads, 1);
  assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
    .every(value => value === 0n));
  await source.close();
  assert.deepEqual(plain((await f.bridge.read(f.receipt, f.mapping)).result), expected);
});

test('installed Table Source keeps the same accounted cleanup after a read failure', async t => {
  let permitClose = false, closes = 0, released = 0, heldRun;
  const closeFailure = new Error('InjectedTableCaptureCloseFailure');
  const runtime = {...moon, clientProgramRowSourceCloseAccounted(run) {
    closes++;
    if (heldRun === undefined) heldRun = run;
    assert.equal(run, heldRun);
    if (!permitClose) return {$tag: 0, _0: closeFailure};
    const result = moon.clientProgramRowSourceCloseAccounted(run);
    if (result.$tag === 1) released++;
    return result;
  }};
  const f = await sourceFixture(t, [{id: 1}], runtime);
  let reads = 0, failure;
  const source = await f.install({...f.bridge, async read() {
    reads++;
    throw Object.assign(new Error('InjectedTableDataReadFailure'), {code: 'InjectedTableDataReadFailure'});
  }});
  const prepared = await f.prepare(source);
  try {
    await assert.rejects(source.open(prepared), error => {
      failure = error;
      assert.equal(error.code, 'InjectedTableDataReadFailure');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.recovery.cleanupPending(), true);
      return true;
    });
    assert.equal(closes, 1);
    assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger)).reservedTransferBytes > 0n);
    await assert.rejects(failure.recovery.cleanup(), {code: 'MoonBitHostFailure', cause: closeFailure});
    assert.equal(failure.recovery.cleanupPending(), true);
    assert.equal(released, 0);
    permitClose = true;
    assert.equal(await failure.recovery.cleanup(), true);
    assert.equal(failure.recovery.cleanupPending(), false);
    assert.equal(await failure.recovery.cleanup(), true);
    assert.equal(closes, 3);
    assert.equal(released, 1);
    assert.equal(reads, 1);
    assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
      .every(value => value === 0n));
    assert.deepEqual(plain((await f.bridge.read(f.receipt, f.mapping)).result), [{id: 1}]);
  } finally {
    permitClose = true;
    await failure?.recovery?.cleanup();
    await source.close();
  }
});

test('installed Table Source refuses schema drift before data I/O and never defaults a missing Table', async t => {
  const f = await sourceFixture(t, [{id: 1, p: null}]);
  let reads = 0;
  const changed = {...f.bridge,
    async resolveGeneration(...args) {
      const value = await f.bridge.resolveGeneration(...args);
      return {...value, result: {...value.result, schema_wire: f.schemaWire + ' '}};
    },
    async read() { reads++; assert.fail('Mismatched generation cannot read'); }};
  const source = await f.install(changed);
  const changedPreparation = await f.prepare(source);
  await assert.rejects(source.open(changedPreparation), {code: 'InstalledTableReadGenerationMismatch'});
  assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(changedPreparation.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
    .every(value => value === 0n));
  assert.equal(reads, 0);
  await source.close();
  const missing = {...f.bridge, resolveGeneration: selector => f.bridge.resolveGeneration(
    {...selector, table_name: 'absent'})};
  const absent = await f.install(missing);
  const absentPreparation = await f.prepare(absent);
  await assert.rejects(absent.open(absentPreparation), {code: 'TableReadNotFound'});
  assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(absentPreparation.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
    .every(value => value === 0n));
  await absent.close();
});

test('installed Table Source admits the whole physical input within its existing page budget', async t => {
  const expected = [{id: 1}, {id: 2}];
  const f = await sourceFixture(t, expected);
  let reads = 0;
  const source = await f.install({...f.bridge, async read(...args) {
    reads++;
    return f.bridge.read(...args);
  }}, {...limits, maxPageRows: 1});
  const prepared = await f.prepare(source);
  await assert.rejects(source.open(prepared), {code: 'MoonBitHostFailure'});
  assert.equal(reads, 1);
  assert.ok(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(prepared.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes","uncertainTransferBytes"])
    .every(value => value === 0n));
  await source.close();
  assert.deepEqual(plain((await f.bridge.read(f.receipt, f.mapping)).result), expected);
});

test('Table read installation is inert and exact selector values cannot alias under NFC', async t => {
  const f = await sourceFixture(t, []);
  const noIo = {...f.bridge,
    resolveGeneration() { assert.fail('Installation cannot resolve a Table head'); },
    read() { assert.fail('Installation cannot read a Table'); }};
  const sources = [];
  try {
    for (const name of ['\u00e9', 'e\u0301']) {
      const selector = {...f.selector, table_name: name};
      const source = await createInstalledTableSource({moon,
        baseEnvironmentWire: (await read('spec/local-check-environment.json')).trimEnd(),
        connectorId: 'table-local', connectorRegistration: 'local', connectorRevision: 'local/0.1',
        site: {connection, issueReadGrant() {}, close() {}},
        authorization: {authorize() {}}, bridge: noIo, limits,
        targets: [{resource: 'rows', selector, schemaWire: f.schemaWire}]});
      sources.push(source);
      selector.table_name = 'mutated-after-installation';
      assert.equal(source.tableReadTargets[0].selector.table_name, name);
    }
    assert.notEqual(sources[0].tableReadTargets[0].selector_cid,
      sources[1].tableReadTargets[0].selector_cid);
    assert.notEqual(sources[0].connectorBindings[0].bindingCid,
      sources[1].connectorBindings[0].bindingCid);
    assert.equal(sources[0].environmentWire, sources[1].environmentWire);
    for (const selector of [{...f.selector, extra: true},
      {...f.selector, table_uuid: 'rows'}, {...f.selector, catalog_identity_cid: cid('4')}]) {
      assert.throws(() => noIo.checkReadSelector(selector), {code: 'InvalidTableReadSelector'});
    }
  } finally { for (const source of sources) await source.close(); }
});
