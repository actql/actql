// Tests-only real installed source fixture. Runtime bundles are prepared by
// the calling gate; importing this helper never starts a build.
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {loadInstalledSource} from './installed-source.mjs';
import {capturedDuckDBNativeConfiguration, capturedDuckDBPhysicalCapacity} from
  './captured-duckdb-source.mjs';
import {acquiredTaskRunAdmission, acquiredMultiTaskPublicationPlan} from
  './local-values-plan.mjs';

const {DuckDBInstance, DuckDBConnection, DuckDBExtractedStatements} = createRequire(new URL(
  '../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
const fixtures = new URL('./fixtures/two-source/', import.meta.url);
export const boundaryCid = digit => `sha256:${digit.repeat(64)}`;
const read = name => readFile(new URL(name, fixtures), 'utf8');
const authorityScopeCid = boundaryCid('a');
const now = () => new Date().toISOString();

export function observeDuckDBCalls(t) {
  const calls = {creates: 0, connects: 0, prepares: 0, runs: 0};
  for (const [owner, method, count] of [
    [DuckDBInstance, 'create', 'creates'],
    [DuckDBInstance.prototype, 'connect', 'connects'],
    [DuckDBExtractedStatements.prototype, 'prepare', 'prepares'],
    [DuckDBConnection.prototype, 'run', 'runs'],
  ]) {
    const original = owner[method];
    t.mock.method(owner, method, function (...args) {
      calls[count]++;
      return original.apply(this, args);
    });
  }
  return () => ({...calls});
}

export async function twoSourceCaptureFixture(t, {equalContent = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-two-capture-boundary-'));
  const adapters = [];
  const opened = new Set();
  t.after(async () => {
    for (const capture of opened) await capture.close();
    for (const adapter of adapters) {
      await adapter.close();
      await adapter.sourceAccess.authorization.close?.();
    }
    await rm(root, {recursive: true, force: true});
  });
  const databaseRows = JSON.parse(await read('database-rows.json'));
  const rows = [databaseRows.left, equalContent
    ? databaseRows.equal_content : databaseRows.right];
  const environmentWire = canonicalJson(JSON.parse(await read('two-source.environment.json')));
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment, 'independently pinned Check Environment is admitted');
  const document = await read('two-source-join.program.json');
  const prepare = () => {
    const result = moon.clientProgramPrepareEffectFreeWithParameters(
      document, 'json', environment, '{}');
    const value = moon.clientProgramPreparationReady(result);
    assert.ok(value, String(moon.clientProgramPreparationIssueCode(result)));
    return value;
  };
  const prepared = prepare();
  assert.equal(moon.clientProgramAcquisitionCount(prepared), 2);
  const registry = await readFile(new URL(
    '../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const aoa = JSON.parse(await readFile(new URL(
    '../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8')).execution_contracts;
  const common = {registry, values: JSON.stringify(aoa['REL.values']),
    fragment: JSON.stringify(aoa['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa['REL.derive.ordered'])};
  for (const [task, side] of ['left', 'right'].entries()) {
    const database = join(root, `${side}.duckdb`);
    const instance = await DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      // Only independently authored numeric/null fixture values enter SQL.
      await connection.run('INSERT INTO records VALUES ' + rows[task].map(row =>
        `(${row.id},${row.amount === null ? 'NULL' : row.amount})`).join(','));
    } finally { connection.closeSync(); instance.closeSync(); }
    const profilePath = join(root, `${side}.json`);
    const sourceRef = task === 0 ? 'connector://crm/main/r#v'
      : 'connector://crm/right/r#v';
    const accountConfigurationWire = canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: `${side}-account`,
      entries: [{entry_id: `${side}-read`, outcome: 'allow',
        principal: {any_of: ['owner']}, connection: {any_of: ['local-database']},
        resource: {any_of: [database]}, operation: {any_of: ['read']}, exclusions: []}],
    });
    await writeFile(profilePath, JSON.stringify({
      acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database,
      schema: 'main', table: 'records', sourceRef, accountConfigurationWire,
      checkEnvironmentWire: canonicalJson(JSON.parse(await read(`${side}.environment.json`))),
    }));
    adapters.push(await loadInstalledSource(profilePath, {root,
      principalId: 'owner', moon}));
  }
  const prepareSources = async (owner = prepared) => Promise.all(adapters.map(
    async (adapter, task) => {
      const occurrence = {stage: task, input: 0, task};
      const sourceAccess = adapter.sourceAccess;
      const source = await adapter.prepare({preparedProgram: owner,
        ...common, sourceAccess, occurrence});
      return {adapter, prepared: source, occurrence, sourceAccess};
    }));
  const preparedSources = await prepareSources();
  const ledgerFor = (sources, owner = prepared) => {
    const capacities = sources.map(source => capturedDuckDBPhysicalCapacity(source.prepared));
    const ledger = moon.clientProgramPrepareMultiCapturedLocalLedger(owner,
      sources.map(source => capturedDuckDBNativeConfiguration(source.prepared)),
      capacities.map(value => value.transferBytes),
      capacities.map(value => value.executionBytes), common.registry, common.values,
      common.fragment, common.ordered);
    assert.ok(ledger, 'both native capacities use the standard shared Run ledger');
    return ledger;
  };
  const openOne = async (source, ledger, owner = prepared, overrides = {}) => {
    const value = await source.adapter.open({preparedProgram: owner, ...common,
      sourceAccess: source.sourceAccess, occurrence: source.occurrence,
      preparedSource: source.prepared, ledger, ...overrides});
    opened.add(value);
    return value;
  };
  const capturePair = async (owner = prepared, sources = preparedSources) => {
    const captureStartedAt = now();
    const ledger = ledgerFor(sources, owner);
    const captured = [];
    const sourceEvidenceWires = [];
    for (const source of sources) {
      const value = await openOne(source, ledger, owner);
      captured.push(value);
      sourceEvidenceWires.push(await value.issueSourceEvidence({authorityScopeCid,
        effectiveDataPolicyCid: value.checkedSource.sourceDataPolicyCid}));
    }
    return {owner, captured, ledger, captureStartedAt, captureCompletedAt: now(),
      captures: captured.map(value => value.capture.source()),
      identities: captured.map(value => value.identity),
      requirements: captured.map(value => value.requirement), sourceEvidenceWires,
      inputLogicalWires: captured.map(value => moon.strategyRunEvidenceJson(value.logicalInput))};
  };
  const compile = (owner = prepared) => {
    const createdAt = now();
    const validUntil = new Date(Date.parse(createdAt) + 86400000).toISOString();
    const compilation = checked(moon.clientProgramCompileLocalTasks(owner));
    const compiled = checked(moon.clientProgramIssueTaskCompiledRun(owner,
      compilation, boundaryCid('b'), boundaryCid('c'), validUntil));
    const definition = checked(moon.clientProgramIssueCompiledRunDefinition(compiled,
      'capture-boundary', 'capture-boundary-run', createdAt, validUntil));
    return {compiled, definition};
  };
  const issue = (pair, run = compile(pair.owner), overrides = {}) => {
    const tuple = {...pair, ...overrides};
    return moon.clientProgramIssueCompiledMultiTaskInvocation(run.compiled, run.definition,
      tuple.captures, tuple.identities, tuple.requirements,
      tuple.sourceEvidenceWires, tuple.inputLogicalWires, authorityScopeCid,
      moon.clientProgramPublicationDataPolicyCid(pair.owner),
      pair.captureStartedAt, pair.captureCompletedAt, 1000000, 100000, 64);
  };
  const publication = pair => {
    const control = runtimeCore(moon).publicationControl;
    return acquiredMultiTaskPublicationPlan({moon, control,
      acquired: acquiredTaskRunAdmission({moon, control, preparedProgram: pair.owner,
        authorityScopeCid, namespaceId: 'capture-boundary', now}),
      preparedProgram: pair.owner, sources: pair.captured.map((captured, task) =>
        ({captured, sourceEvidenceWire: pair.sourceEvidenceWires[task]})),
      authorityScopeCid, effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(pair.owner),
      captureStartedAt: pair.captureStartedAt, captureCompletedAt: pair.captureCompletedAt,
      namespaceId: 'capture-boundary', storeAuthorityCid: boundaryCid('d'), now});
  };
  return {moon, root, rows, prepare, prepared, adapters, common, preparedSources,
    prepareSources, ledgerFor, openOne, capturePair, compile, issue, publication,
    authorityScopeCid, now};
}
