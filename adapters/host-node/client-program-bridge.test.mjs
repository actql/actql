import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import assert from 'node:assert/strict';import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';
import {mkdir, mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {join} from 'node:path';

import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {composeInstalledCheckEnvironment} from
  './installed-check-environment.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientEffectProgramPreparation,
  installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {completeCapturedEffectRun, recoverAdmittedEffectRun,
  runCapturedEffectComputation,
  runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority, installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {acquiredTaskRunAdmission, acquiredTaskPublicationPlan,
  acquiredEffectPublicationAdmission, acquiredEffectPublicationPlan} from
  './local-values-plan.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';
import {openCapturedDuckDBSource, prepareCapturedDuckDBSource} from
  './captured-duckdb-source.mjs';
import {fixtureSourceAccess, accountEntry, FIXTURE_CONTEXT, fixtureAuthorization} from './authorization-fixture.mjs';
import {admitSourceInputLogical} from '../../scripts/source-input-logical-contract.mjs';
import {spawn, spawnSync} from 'node:child_process';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {applyCapturedEffectSet, applyRecoveredEffectSet} from './effect-run-apply.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
import {issueAuthorizedEffectSetReceipt} from './effect-response-recovery.mjs';
import {commitPinnedEffectSourceHolding, exportPinnedEffectInput,
  exportPinnedEffectLocalResult,
  preparePinnedEffectSourcePayload, preparePinnedEffectSourceSet,
  preparePinnedEffectSourceHoldings, retainPinnedEffectDependencyPayloads,
  preparePinnedEffectDependencyInventory} from
  './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {canonicalJson} from '../host-common/publication-contract-control.fixture.mjs';
import {issueCompletedEffectfulComputationEvidence, prepareCompletedEffectfulPublication, publishCompletedEffectfulRun, recoverCompletedEffectfulComputation, releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from '../host-common/completed-run-publication.mjs';
import {retainCompletedEffectDependencyPayloads} from
  '../host-common/completed-run-publication.mjs';
import {suspendCompletedEffectfulComputation, retireCompletedEffectfulCapture} from
  '../host-common/completed-run-publication.mjs';

import {nativeSourceIdentityMatches, runNativeHostQuery, issueNativeSourceEvidence} from
  '../connectors/duckdb/node/host.mjs';
import {authorizeLocalDatabase, revokeLocalDatabase} from
  '../connectors/duckdb/node/session.mjs';
import {machineCid} from '../../scripts/actql-spec-family.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

const {DuckDBInstance} = createRequire(new URL(
  '../connectors/duckdb/node/package.json', import.meta.url))(
  '@duckdb/node-api');

const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../_build/client-program-bridge-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
const hashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(JSON.stringify(body))
    .digest('hex')}`;
};
const evidenceCid =
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904';

test('public source preparation binds installed aliases before checking a Program', async () => {
  const source = await readFile(new URL(
    '../../src/query_integration/query_amount_catalog_wbtest.mbt', import.meta.url), 'utf8');
  const match = source.slice(source.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")/u);
  assert.ok(match);
  const body = JSON.parse(JSON.parse(match[1]));
  const viewCid = 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3';
  const schemaCid = 'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4';
  const sourceRef = 'connector://crm/main/r#v';
  const selector = {source_ref: sourceRef, source_contract_cid: viewCid,
    source_view_contract_cid: viewCid, read_mode: 'snapshot'};
  body.schema_snapshots = [{...selector, output_carrier: 'relation',
    carrier_schema_contract_cid: schemaCid,
    source_data_policy_cid: 'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf',
    data_classification: 'unknown'}];
  body.connector_capabilities = [{...selector, capability_contract_cids: [
    'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8']}];
  delete body.evidence_bundle_cid;
  body.evidence_bundle_cid = machineCid(body);
  const environment = moon.clientProgramCheckEnvironment(canonicalText(body),
    body.evidence_bundle_cid, false, false, true, false, false, false, false);
  assert.ok(environment);
  assert.equal(moon.clientProgramCheckingEnvironmentCid(environment),
    body.evidence_bundle_cid);
  const alias = {name: 'records', sourceRef, sourceViewContractCid: viewCid,
    schemaContractCid: schemaCid};
  const publication = {environmentCid: body.evidence_bundle_cid, aliases: [alias]};
  const prepare = (text, format = 'sql', published = publication,
    declarations, parameters) => moon.clientProgramPrepareSourceWithParameters(
    text, format, environment, JSON.stringify(published), declarations, parameters);
  const valid = published => moon.clientProgramSourcePublicationValid(
    environment, JSON.stringify(published));
  assert.equal(valid(publication), true);
  for (const text of ['SELECT id FROM records',
    'SELECT id FROM records WHERE amount >= @minimum']) {
    const outcome = prepare(text, 'sql', publication,
      text.includes('@minimum') ? JSON.stringify({minimum: {type: 'number'}}) : undefined,
      text.includes('@minimum') ? JSON.stringify({minimum: 20}) : undefined);
    assert.ok(moon.clientProgramPreparationReady(outcome),
      inspect(moon.clientProgramPreparationIssue(outcome), {depth: 8}));
  }
  const pipe = prepare('FROM records |> SELECT id', 'aql-text');
  assert.ok(moon.clientProgramPreparationReady(pipe),
    String(moon.clientProgramPreparationIssueCode(pipe)));
  for (const changed of [
    {...publication, environmentCid: cid('0')},
    {...publication, aliases: [{...alias, sourceRef: 'connector://crm/main/other#v'}]},
    {...publication, aliases: [{...alias, schemaContractCid: cid('0')}]},
    {...publication, aliases: [{...alias, sourceViewContractCid: cid('0')}]},
    {...publication, aliases: [alias, {...alias, name: 'RECORDS'}]},
    {...publication, aliases: [{...alias, name: 'records..bad'}]},
    {...publication, aliases: [{...alias, extra: 'not permitted'}]},
  ]) {
    assert.equal(valid(changed), false);
    const outcome = prepare('SELECT id FROM records', 'sql', changed);
    assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
    assert.equal(moon.clientProgramPreparationIssueCode(outcome), 'source_rejected');
  }
  for (const [text, format, code] of [
    ['SELECT id FROM', 'sql', 'source_invalid_input'],
    ['FROM records |> SELECT id', 'sql', 'source_invalid_input'],
    ['SELECT id FROM absent', 'sql', 'source_rejected'],
    ['SELECT absent FROM records', 'sql', 'source_rejected'],
  ]) {
    const outcome = prepare(text, format);
    assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
    assert.equal(moon.clientProgramPreparationIssueCode(outcome), code);
  }
});
const programCid =
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c';
const parametersCid =
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52';
const publicationLimits = Object.freeze({
  maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64,
});
const outputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 100, maxValueNodes: 10000, maxValueTextBytes: 100000,
  maxValueDepth: 64, maxValueWork: 100000, maxWireBytes: 100000,
  maxWireNodes: 10000, maxWireDepth: 64, maxColumns: 10,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003, maxLogicalWireDepth: 66,
  maxSchemaFields: 10, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 4096,
});

async function checkedFixture() {
  const [document, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const environment = moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(), evidenceCid,
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  return {document, environment};
}

test('checked acquired source and downstream task emit their input ports',
  async () => {
    const source = await readFile(new URL(
      '../../src/query_integration/query_amount_catalog_wbtest.mbt',
      import.meta.url), 'utf8');
    const catalog = source.slice(source.indexOf(
      'fn query_amount_nullable_catalog')).match(
      /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/u);
    assert.ok(catalog);
    const environmentBody = JSON.parse(JSON.parse(catalog[1]));
    const sourceSelector = {
      source_ref: 'connector://crm/main/r#v',
      source_contract_cid:
        'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
      source_view_contract_cid:
        'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
      read_mode: 'snapshot',
    };
    environmentBody.schema_snapshots = [{...sourceSelector,
      output_carrier: 'relation',
      carrier_schema_contract_cid:
        'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4',
      source_data_policy_cid:
        'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf',
      data_classification: 'unknown',
    }];
    environmentBody.connector_capabilities = [{...sourceSelector,
      capability_contract_cids: [
        'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8'],
    }];
    delete environmentBody.evidence_bundle_cid;
    environmentBody.evidence_bundle_cid = machineCid(environmentBody);
    const environment = moon.clientProgramCheckEnvironment(
      canonicalText(environmentBody), environmentBody.evidence_bundle_cid,
      false, false, true, false, false, false, false);
    assert.ok(environment);
    const [document, parameters] = await Promise.all([
      readFile(new URL(
        '../connectors/duckdb/node/examples/program.json', import.meta.url),
      'utf8'),
      readFile(new URL(
        '../connectors/duckdb/node/examples/parameters.json', import.meta.url),
      'utf8'),
    ]);
    const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
      document, 'json', environment, parameters);
    const prepared = moon.clientProgramPreparationReady(outcome);
    assert.ok(prepared,
      String(moon.clientProgramPreparationIssueCode(outcome)));
    const acquisition = checked(
      moon.clientProgramPrepareQueryAcquisition(prepared, 0, 0));
    assert.equal(moon.clientProgramQueryAcquisitionSourceIndex(acquisition),
      0);
    assert.throws(() => checked(
      moon.clientProgramPrepareQueryAcquisition(prepared, 0, 1)));
    assert.throws(() => checked(
      moon.clientProgramPrepareQueryAcquisition(prepared, 1, 0)));
    assert.throws(() => checked(
      moon.clientProgramPrepareQueryAcquisition(prepared, 4, 0)));
    const [registry, contracts] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const aoa = JSON.parse(contracts);
    const requirement = checked(
      moon.clientProgramPrepareLocalQueryRequirement(prepared, 0, 0,
        registry, JSON.stringify(aoa.execution_contracts['REL.values']),
        JSON.stringify(aoa.execution_contracts[
          'ACTQL.expression_fragment/0.1']),
        JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
    assert.match(moon.clientProgramQueryRequirementCid(requirement),
      /^sha256:[0-9a-f]{64}$/u);
    assert.equal(moon.clientProgramQueryRequirementSourceRef(requirement),
      'connector://crm/main/r#v');
    assert.equal(
      moon.clientProgramQueryRequirementSourceContractCid(requirement),
      'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3');
    const [queryContract, evidenceContract, twoReceiptContract] =
      await Promise.all([
        'actql-query-acquisition.json',
        'actql-query-process-evidence.json',
        'actql-query-two-receipt.json',
      ].map(name => readFile(new URL(`../../spec/contracts/${name}`,
        import.meta.url), 'utf8')));
    const nativeSetup = checked(moon.clientProgramPrepareDuckDBAcquisition(
      requirement, 'main', 'records', queryContract, evidenceContract,
      twoReceiptContract));
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'checked-source-'));
    try {
      const path = join(directory, 'records.duckdb');
      const database = await DuckDBInstance.create(path);
      const connection = await database.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
        await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),'
          + '(2,20),(3,30)');
      } finally {
        connection.closeSync();
        database.closeSync();
      }
      const sourceAccess = {...fixtureSourceAccess,
        sourceRef: sourceSelector.source_ref};
      const sourceOptions = {moon,
        preparedProgram: prepared, registry,
        values: JSON.stringify(aoa.execution_contracts['REL.values']),
        fragment: JSON.stringify(aoa.execution_contracts[
          'ACTQL.expression_fragment/0.1']),
        ordered: JSON.stringify(aoa.execution_contracts[
          'REL.derive.ordered']), database: path,
        sourceAccess,
        schema: 'main', table: 'records', transportLimits: {
          maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
          maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
          memoryBytes: 128 * 1024 * 1024, threads: 1,
        }};
      const preparedSource = await prepareCapturedDuckDBSource(sourceOptions);
      assert.equal(preparedSource.checkedSource.sourceRef,
        sourceSelector.source_ref);
      assert.deepEqual(preparedSource.readTuple, {connection:
        sourceAccess.connection ?? 'local-database',
      resource: sourceAccess.resource ?? path, operation: 'read'});
      await assert.rejects(openCapturedDuckDBSource({...sourceOptions,
        preparedSource: {...preparedSource}}),
      {message: 'InstalledSourcePreparationMismatch'});
      const opened = await openCapturedDuckDBSource({...sourceOptions,
        preparedSource});
      const capturedSource = opened.capture.source();
      try {
        assert.deepEqual(opened.checkedSource, {
          requirementCid: moon.clientProgramQueryRequirementCid(requirement),
          sourceRef: 'connector://crm/main/r#v',
          sourceContractCid:
            'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
          carrierSchemaContractCid:
            'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4',
          sourceDataPolicyCid:
            'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf',
          dataClassification: 'unknown',
          sourceViewContractCid:
            'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
          inputContractCid:
            moon.clientProgramQueryRequirementInputContractCid(requirement),
          outputContractCid:
            moon.clientProgramQueryRequirementOutputContractCid(requirement),
        });
        assert.equal(Object.isFrozen(opened.checkedSource), true);
        assert.equal(JSON.parse(opened.capture.document()).output.row_count,
          3);
        assert.equal(moon.clientProgramCapturedSourceMatches(prepared,
          opened.capture.source()), true);
        const observed = opened.identity;
        assert.equal(moon.clientProgramCapturedSourceDependencyBodies(
          observed, capturedSource), undefined,
        'ordinary read identity does not retain Effect recovery bodies');
        assert.equal(nativeSourceIdentityMatches(opened.capture, observed), true);
        assert.equal(nativeSourceIdentityMatches({...opened.capture}, observed),
          false);
        assert.equal(opened.capture.source(), capturedSource);
        const otherGrant = await authorizeLocalDatabase(path,
          {...fixtureSourceAccess, sourceRef: sourceSelector.source_ref});
        const other = await runNativeHostQuery(
          otherGrant,
          nativeSetup, {
            maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
            maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
            memoryBytes: 128 * 1024 * 1024, threads: 1,
          });
        try {
          const otherIdentity = checked(
            moon.clientProgramIdentifyCapturedSourceRelation(other.source()));
          assert.equal(moon.clientProgramCapturedSourceLogicalCid(otherIdentity),
            moon.clientProgramCapturedSourceLogicalCid(observed));
          assert.equal(nativeSourceIdentityMatches(other, otherIdentity), true);
          assert.equal(nativeSourceIdentityMatches(opened.capture, otherIdentity),
            false);
          assert.equal(nativeSourceIdentityMatches(other, observed), false);
          const retainedIdentity = checked(
            moon.clientProgramIdentifyCapturedEffectSourceRelation(
              other.source()));
          assert.equal(moon.clientProgramCapturedSourceDependencyBodies(
            retainedIdentity, capturedSource), undefined,
          'equal content from a foreign capture is not the retained owner');
          assert.equal(typeof moon.clientProgramCapturedSourceDependencyBodies(
            retainedIdentity, other.source())._0, 'string');
          const context = checked(
            moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
          const logicalInput = checked(moon.clientProgramIssueCapturedSourceLogical(
            prepared, other.source(), otherIdentity, requirement));
          assert.equal(revokeLocalDatabase(otherGrant), true);
          await assert.rejects(issueNativeSourceEvidence(other, {
            context, identity: otherIdentity, logicalInput,
            authorityScopeCid: cid('a'),
            effectiveDataPolicyCid: opened.checkedSource.sourceDataPolicyCid,
          }), {code: 'UnauthorizedSourceEvidence'});
        } finally { other.close(); }
        assert.equal(nativeSourceIdentityMatches(other, observed), false);
        assert.equal(moon.clientProgramCapturedSourceRowCount(observed), 3);
        assert.match(moon.clientProgramCapturedSourceLogicalCid(observed),
          /^sha256:[0-9a-f]{64}$/u);
        assert.match(moon.clientProgramCapturedSourceSchemaCid(observed),
          /^sha256:[0-9a-f]{64}$/u);
        const repeated = checked(
          moon.clientProgramIdentifyCapturedSourceRelation(
            opened.capture.source()));
        assert.equal(moon.clientProgramCapturedSourceLogicalCid(repeated),
          moon.clientProgramCapturedSourceLogicalCid(observed));
        assert.equal(moon.clientProgramCapturedSourceSchemaCid(repeated),
          moon.clientProgramCapturedSourceSchemaCid(observed));
        const logicalInput = opened.logicalInput;
        const logicalBody = JSON.parse(
          moon.strategyRunEvidenceJson(logicalInput));
        assert.equal(admitSourceInputLogical(logicalBody, {
          logicalRelationCid:
            moon.clientProgramCapturedSourceLogicalCid(observed),
          relationSchemaCid:
            moon.clientProgramCapturedSourceSchemaCid(observed),
          sourceContractCid: opened.checkedSource.sourceContractCid,
          completeness: 'complete',
          orderingEvidence: {stable: false, keys: []},
        }), moon.strategyRunEvidenceIdentity(logicalInput));
        assert.throws(() => admitSourceInputLogical(logicalBody, {
          logicalRelationCid: cid('0'),
          relationSchemaCid:
            moon.clientProgramCapturedSourceSchemaCid(observed),
          sourceContractCid: opened.checkedSource.sourceContractCid,
          completeness: 'complete',
          orderingEvidence: {stable: false, keys: []},
        }));
        const control = runtimeCore(moon).publicationControl;
        const authorityScopeCid = cid('a');
        const dataPolicyCid = opened.checkedSource.sourceDataPolicyCid;
        const sourceEvidenceWire = await opened.issueSourceEvidence({
          authorityScopeCid, effectiveDataPolicyCid: dataPolicyCid});
        const {source_evidence_cid: sourceEvidenceCid,
          ...sourceEvidenceBody} = JSON.parse(sourceEvidenceWire);
        assert.equal(sourceEvidenceBody.schema_evidence_cid,
          machineCid(environmentBody.schema_snapshots[0]));
        assert.equal(sourceEvidenceBody.capability_evidence_cid,
          machineCid(environmentBody.connector_capabilities[0]));
        assert.equal(sourceEvidenceBody.snapshot_ref,
          `sha256:${createHash('sha256').update(opened.capture.document()).digest('hex')}`);
        assert.equal(sourceEvidenceBody.completeness, 'complete');
        assert.equal(machineCid(sourceEvidenceBody), sourceEvidenceCid);
        await assert.rejects(issueNativeSourceEvidence({...opened.capture}, {
          identity: opened.identity, logicalInput: opened.logicalInput,
          authorityScopeCid, effectiveDataPolicyCid: dataPolicyCid}));
        await assert.rejects(opened.issueSourceEvidence({authorityScopeCid,
          effectiveDataPolicyCid: cid('9')}));
        const foreignContext = checked(
          moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
        await assert.rejects(issueNativeSourceEvidence(opened.capture, {
          context: foreignContext, identity: opened.identity,
          logicalInput: opened.logicalInput, authorityScopeCid,
          effectiveDataPolicyCid: dataPolicyCid,
        }), {code: 'MoonBitHostFailure'});
        const admitted = acquiredTaskRunAdmission({moon, control,
          preparedProgram: prepared, document, format: 'json',
          parameters: JSON.parse(parameters),
          environmentWire: canonicalText(environmentBody),
          environmentCid: environmentBody.evidence_bundle_cid, authorityScopeCid,
          namespaceId: 'local', now: () => '2026-09-26T00:00:02.000Z'});
        const storeAuthorityCid = cid('7');
        const plan = acquiredTaskPublicationPlan({moon, control,
          acquired: admitted, preparedProgram: prepared, captured: opened,
          sourceEvidenceWire, authorityScopeCid,
          effectiveDataPolicyCid: dataPolicyCid,
          captureStartedAt: '2026-09-26T00:00:00.000Z',
          captureCompletedAt: '2026-09-26T00:00:01.000Z',
          namespaceId: 'local', requestId: 'acquired-result-request',
          storeAuthorityCid, now: () => '2026-09-26T00:00:02.000Z'});
        assert.equal(plan.results.length, 2);
        for (const changed of [
          {...sourceEvidenceBody, input_logical_cid: cid('9')},
          {...sourceEvidenceBody, completeness: 'partial'},
        ]) {
          const wire = control.sealRunEvidence('source_evidence',
            JSON.stringify(changed), publicationLimits).wire;
          assert.throws(() => acquiredTaskPublicationPlan({moon,
            control, acquired: admitted, preparedProgram: prepared,
            captured: opened, sourceEvidenceWire: wire,
            authorityScopeCid, effectiveDataPolicyCid: dataPolicyCid,
            captureStartedAt: '2026-09-26T00:00:00.000Z',
            captureCompletedAt: '2026-09-26T00:00:01.000Z',
            namespaceId: 'local', requestId: 'acquired-result-request',
            storeAuthorityCid,
            now: () => '2026-09-26T00:00:02.000Z'}));
        }
        const store = await openLocalPublicationStore({
          directory: join(directory, 'publication'), storeAuthorityCid,
          capacityBytes: 512 * 1024 * 1024,
          maxObjectBytes: 10 * 1024 * 1024,
          maxObjects: 100, maxContractNodes: 10000,
          maxContractDepth: 64,
        }, control);
        let published;
        try {
          let retainedExecution;
          published = await runPublishedCapturedStrategy(opened.setup,
            {store, plan}, {}, undefined, undefined, execution => {
              assert.equal(published, undefined);
              retainedExecution = execution;
            });
          const execution = published.execution;
          assert.equal(retainedExecution, execution);
          assert.equal(execution.status, 'host-tasks-completed');
          assert.deepEqual(execution.resultInventory.map(result =>
            result.name), ['b', 'c']);
          assert.equal(execution.completed.length, 3);
          assert.deepEqual(execution.completed.map(value => value.task),
            [1, 2, 3]);
          assert.equal(published.publication.publication.state, 'succeeded');
        } finally {
          if (published !== undefined) {
            await published.close();
            assert.equal(published.cleanupPending(), false);
          }
          await store.close();
        }
      } finally {
        opened.close();
        assert.throws(() => checked(
          moon.clientProgramIdentifyCapturedSourceRelation(capturedSource)));
        assert.throws(() => checked(
          moon.clientProgramIssueCapturedSourceLogical(prepared,
            capturedSource, opened.identity, requirement)));
      }
    } finally {
      await rm(directory, {recursive: true, force: true});
    }
    assert.throws(() => checked(moon.clientProgramPrepareDuckDBAcquisition(
      requirement, 'main', 'records', '{}', evidenceContract,
      twoReceiptContract)));
    assert.throws(() => checked(
      moon.clientProgramPrepareLocalQueryRequirement(prepared, 1, 0,
        registry, JSON.stringify(aoa.execution_contracts['REL.values']),
        JSON.stringify(aoa.execution_contracts[
          'ACTQL.expression_fragment/0.1']),
        JSON.stringify(aoa.execution_contracts['REL.derive.ordered']))));
    const acquired = JSON.parse(checked(
      moon.clientProgramTaskPipelineWire(prepared, 0)));
    const downstream = JSON.parse(checked(
      moon.clientProgramTaskPipelineWire(prepared, 1)));
    assert.deepEqual(acquired.sources, {remote: {sort: 'relation'}});
    assert.deepEqual(acquired.steps.map(step => step.op),
      ['REL.where', 'REL.select']);
    assert.deepEqual(downstream.sources, {x: {sort: 'relation'}});
    assert.deepEqual(downstream.steps.map(step => step.op),
      ['REL.where', 'REL.select']);
    const acquiredNode = JSON.parse(moon.clientProgramTaskFragmentWire(
      checked(moon.clientProgramIssueTaskFragment(prepared, 0))));
    const downstreamNode = JSON.parse(moon.clientProgramTaskFragmentWire(
      checked(moon.clientProgramIssueTaskFragment(prepared, 1))));
    assert.equal(acquiredNode.kind, 'aoa_fragment');
    assert.equal(acquiredNode.pipeline.output, 'select_1');
    assert.equal(downstreamNode.pipeline.output, 'select_1');
    assert.notEqual(acquiredNode.node_id, downstreamNode.node_id);
    assert.notEqual(acquiredNode.input_contracts.remote,
      acquiredNode.output_contracts[acquiredNode.pipeline.output]);
    assert.equal(downstreamNode.input_contracts.x,
      acquiredNode.output_contracts[acquiredNode.pipeline.output]);
    const resultNode = JSON.parse(moon.clientProgramTaskFragmentWire(
      checked(moon.clientProgramIssueTaskFragment(prepared, 2))));
    const root = JSON.parse(moon.clientProgramDirectValuesResultRootWire(
      checked(moon.clientProgramIssueDirectTaskResultRoot(prepared, 0))));
    assert.deepEqual(root.ref, {
      node_id: resultNode.node_id, port: resultNode.pipeline.output,
    });
    const graph = JSON.parse(moon.clientProgramTaskPlanGraphWire(
      checked(moon.clientProgramIssueTaskPlanGraph(prepared))));
    assert.deepEqual(graph.nodes.map(node => node.node_id),
      ['task_0', 'task_1', 'task_2', 'task_3']);
    assert.deepEqual(graph.data_edges.map(edge => edge.from.node_id),
      ['task_0', 'task_0', 'task_1']);
    assert.deepEqual(graph.data_edges.map(edge => edge.to.node_id),
      ['task_1', 'task_2', 'task_3']);
    assert.deepEqual(graph.root_refs[0], root);
    for (const edge of graph.data_edges) {
      const from = graph.nodes.find(node => node.node_id === edge.from.node_id);
      const to = graph.nodes.find(node => node.node_id === edge.to.node_id);
      assert.equal(edge.carrier, 'relation');
      assert.equal(edge.contract_cid, from.output_contracts[edge.from.port]);
      assert.equal(edge.contract_cid, to.input_contracts[edge.to.port]);
    }
    const graphWire = JSON.stringify(graph);
    assert.equal(moon.clientProgramTaskPlanGraphWire(checked(
      moon.clientProgramAdmitTaskPlanGraph(prepared, graphWire))), graphWire);
    assert.throws(() => checked(moon.clientProgramAdmitTaskPlanGraph(
      prepared, graphWire.replace('task_0', 'task_7'))));
    const executable = JSON.parse(moon.clientProgramTaskExecutablePlanWire(
      checked(moon.clientProgramIssueTaskExecutablePlan(prepared))));
    assert.deepEqual(executable.nodes, graph.nodes);
    assert.deepEqual(executable.data_edges, graph.data_edges);
    assert.deepEqual(executable.root_refs, graph.root_refs);
    const compilation = checked(
      moon.clientProgramCompileLocalTasks(prepared));
    assert.deepEqual(JSON.parse(
      moon.clientProgramTaskCompilationPlanWire(compilation)), executable);
    const template = JSON.parse(
      moon.clientProgramTaskCompilationTemplateWire(compilation));
    const compiledPlan = JSON.parse(
      moon.clientProgramTaskCompilationCompiledPlanWire(compilation));
    assert.equal(template.program_definition_cid,
      executable.execution_material.program_definition_cid);
    assert.equal(compiledPlan.executable_plan_cid,
      executable.executable_plan_cid);
    const admissionOptions = {moon,
      control: runtimeCore(moon).publicationControl,
      preparedProgram: prepared, document, format: 'json',
      parameters: JSON.parse(parameters), environmentWire: canonicalText(environmentBody),
      environmentCid: environmentBody.evidence_bundle_cid, authorityScopeCid: cid('a'),
      namespaceId: 'local', now: () => '2026-09-26T00:00:00.000Z'};
    const admitted = acquiredTaskRunAdmission(admissionOptions);
    const restored = acquiredTaskRunAdmission({...admissionOptions,
      retainedDefinitionWire: admitted.runDefinition.wire});
    assert.equal(restored.runDefinition.identity,
      admitted.runDefinition.identity);
    assert.equal(admitted.compiledPlan.identity,
      compiledPlan.compiled_plan_cid);
    const changedPrepared = moon.clientProgramPreparationReady(
      moon.clientProgramPrepareEffectFreeWithParameters(document, 'json',
        environment, JSON.stringify({minimum: 7})));
    assert.ok(changedPrepared);
    assert.throws(() => acquiredTaskRunAdmission({...admissionOptions,
      preparedProgram: changedPrepared, parameters: {minimum: 7},
      retainedDefinitionWire: admitted.runDefinition.wire}),
    {code: 'RunHostTaskDefinitionRejected'});
    assert.throws(() => checked(
      moon.clientProgramTaskPipelineWire(prepared, 4)));
  });

test('private Plan binding uses the escaped checked Unit Result name', async () => {
  const {document, environment} = await checkedFixture();
  const renamed = JSON.parse(document);
  renamed.stages[0].results['a~/b'] = renamed.stages[0].results.rows;
  delete renamed.stages[0].results.rows;
  renamed.results.answer.from.result = 'a~/b';
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(renamed), 'json', environment);
  assert.ok(prepared);
  const body = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const binding = JSON.parse(body);
  assert.deepEqual([
    binding.target.unit_definition_cid,
    binding.target.result_name,
    binding.subject_ref,
    binding.resolved_limit_cid,
    binding.binding_cid,
  ], [
    'sha256:87fbe52e6d002927b0ef3808c1e34b64cc05f5fe72636a7b3e3b1bc26b4c55d0',
    'a~/b',
    'unit:sha256:87fbe52e6d002927b0ef3808c1e34b64cc05f5fe72636a7b3e3b1bc26b4c55d0#/results/a~0~1b/rows',
    'sha256:af61d9586bf003fcbc3b11b9ae73618a17eba72f93fa05a858fa83a9d5df949c',
    'sha256:ecc6be2770eb2454dae19082be8a632b494dfa296af148a884752232698c81fa',
  ]);
  assert.equal(binding.binding_cid,
    hashWithoutSelf(binding, 'binding_cid'));
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body)));
});

test('binding set covers every checked Unit Result port', async () => {
  const {document, environment} = await checkedFixture();
  const doubled = JSON.parse(document);
  doubled.stages[0].results.second =
    structuredClone(doubled.stages[0].results.rows);
  doubled.results.second = {from: {stage: 'source', result: 'second'}};
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(doubled), 'json', environment);
  assert.ok(prepared);
  const bindings = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsBindingJson(
      prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesBindingJson(
      prepared, 0, index)),
  ]);
  const limits = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsLimitJson(prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesLimitJson(prepared, 0, index)),
  ]);
  const issued = checked(moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issued), limits);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issued),
    bindings);
  const entries = limits.map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issued),
    entries);
  const witnesses = checked(
    moon.clientProgramIssuePublicationWitnesses(prepared));
  const witnessBodies = moon.clientProgramPublicationWitnessBodies(witnesses);
  const witnessCids = moon.clientProgramPublicationWitnessCids(witnesses);
  assert.equal(witnessBodies.length, witnessCids.length);
  assert.ok(witnessBodies.length > 1);
  assert.equal(new Set(witnessCids).size, witnessCids.length);
  for (const body of witnessBodies) {
    const witness = JSON.parse(body);
    assert.ok(witnessCids.includes(witness.witness_cid));
  }
  for (const body of limits) {
    for (const candidate of JSON.parse(body).candidates) {
      assert.ok(witnessCids.includes(candidate.witness_cid));
    }
  }
  assert.deepEqual(moon.clientProgramPublicationWitnessBodies(checked(
    moon.clientProgramAdmitPublicationWitnesses(
      prepared, witnessBodies))), witnessBodies);
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.slice(1))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.toReversed())), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      entries.toReversed())));
  const manifestBody = {
    plan_facts: entries.map(entry => JSON.parse(entry)),
    version: 'actql-plan-fact-manifest/0.1',
  };
  const manifestCid = hashWithoutSelf(manifestBody,
    'plan_fact_manifest_cid');
  const manifest = JSON.stringify({...manifestBody,
    plan_fact_manifest_cid: manifestCid});
  const encodedManifest = checked(
    moon.clientProgramEncodePlanFactManifestIdentity(
      JSON.stringify(manifestBody.plan_facts)));
  assert.equal(moon.clientProgramPlanFactManifestCid(encodedManifest),
    manifestCid);
  assert.deepEqual(JSON.parse(moon.clientProgramPlanFactManifestWire(
    encodedManifest)), JSON.parse(manifest));
  assert.equal(checked(moon.clientProgramCheckPlanFactManifestIdentity(
    manifest, JSON.stringify(manifestBody.plan_facts))), manifestCid);
  assert.throws(() => checked(
    moon.clientProgramCheckPlanFactManifestIdentity(manifest,
      JSON.stringify(manifestBody.plan_facts.slice(1)))),
  {code: 'MoonBitHostFailure'});
  assert.equal(new Set(bindings.map(body => JSON.parse(body).binding_cid))
    .size, 4);
  assert.equal(new Set(limits.map(body => JSON.parse(body).resolved_limit_cid))
    .size, 4);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared,
      bindings.toReversed())));
  const admitFacts = (limitBodies, bindingBodies) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(
      prepared, limitBodies, bindingBodies));
  assert.doesNotThrow(() => admitFacts(
    limits.toReversed(), bindings.toReversed()));
  for (const omitted of [0, 1, 2, 3]) {
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationFactEntries(prepared,
        entries.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits.filter((_, index) => index !== omitted), bindings),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits, bindings.filter((_, index) => index !== omitted)),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationBindingSet(prepared,
        bindings.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
  }
});

// Test-only evidence isolates checked Program binding. Product admission must
// derive every other evidence CID from its real compiler and Host authority.
function publicationEvidence(program, parameters, semantics,
  checkEnvironmentCid,
  invocationBindingsCid =
    'sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f',
  aoaLogicalCid = cid('9')) {
  const limits = [100000, 10000, 64];
  const evidence = (name, body) => checked(moon.strategyRunEvidenceSeal(
    name, JSON.stringify(body), ...limits));
  const template = evidence('bound_invocation_template', {
    version: 'actql-bound-invocation-template/0.1',
    program_definition_cid: program,
    parameter_values_cid: parameters,
    invocation_bindings_cid: invocationBindingsCid,
    check_environment_cid: checkEnvironmentCid,
    grammar_manifest_cid: cid('5'),
    required_profile_contracts: [],
    barrier_contract_manifest_cid: cid('6'),
    source_evidence: 'unbound',
  });
  const plan = checked(moon.strategyPublicationSeal('compiled_plan',
    JSON.stringify({
      version: 'actql-compiled-plan/0.1',
      compiler_version: 'compiler-test-0.1',
      aoa_ir_version: 'aoa-ir-test-0.1',
      executable_plan_cid: cid('7'),
      program_definition_cid: program,
      program_semantics_cid: semantics,
      aoa_contract_cid: cid('8'),
      aoa_logical_cid: aoaLogicalCid,
    }), ...limits));
  const prepared = evidence('prepared_invocation', {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: moon.strategyRunEvidenceIdentity(template),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(plan),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  });
  const authorization = evidence('run_authorization', {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: moon.strategyRunEvidenceIdentity(prepared),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    decision: 'allowed',
  });
  return [template, prepared, authorization, plan];
}

// This fixture provides missing compiler/Host policy evidence. Its checked
// Program identity and the physical Result bytes come from product owners.
function checkedValuesPublicationPlan(prepared, control,
  executionContextCid = cid('a')) {
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'published-values-request', cid('b'));
  const compilation = checked(moon.clientProgramCompileLocalValues(prepared));
  const template = control.admitRunEvidence('bound_invocation_template',
    moon.clientProgramCompilationTemplateWire(compilation),
    publicationLimits);
  const compiledPlan = control.admit('compiled_plan',
    moon.clientProgramCompilationCompiledPlanWire(compilation),
    publicationLimits);
  assert.equal(JSON.parse(moon.clientProgramCompilationExecutablePlanWire(
    compilation)).executable_plan_cid,
  JSON.parse(compiledPlan.wire).executable_plan_cid);
  const preparedEvidence = control.sealRunEvidence('prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: executionContextCid,
      host_policy_cid: cid('b'),
      policy_decision: 'allow', expires_at: '2099-01-01T00:00:00.000Z',
    }), publicationLimits);
  const authorization = control.sealRunEvidence('run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: preparedEvidence.identity,
      execution_context_cid: executionContextCid,
      host_policy_cid: cid('b'),
      decision: 'allowed',
    }), publicationLimits);
  const admission = control.admitCheckedClientRunPublication(
    prepared, template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'namespace-a-scope', runId: 'checked-values-published',
    inputArtifactSetCid: cid('c'),
    createdAt: '2026-09-24T00:00:00.000Z',
    validUntil: '2027-01-01T00:00:00.000Z',
  }, publicationLimits);
  control.checkClientRunDefinitionBinding(prepared, admission,
    runDefinition);
  const effectiveDataPolicyCid = cid('d');
  const observation = control.sealRunEvidence('observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [], captured_input_artifact_cids: [],
      consistency: 'no_external_sources', capture_started_at: null,
      capture_completed_at: null,
      replayability: {materialized: false, availability_evidence_cids: []},
      data_policy_cid: effectiveDataPolicyCid,
    }), publicationLimits);
  const invocation = control.issueRunInvocation(
    template, observation, publicationLimits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('e'),
    effective_data_policy_cid: effectiveDataPolicyCid,
    available_until: '2026-09-24T01:00:00.000Z',
    delete_by: '2026-09-24T02:00:00.000Z',
    extension_ceiling_at: '2026-09-24T03:00:00.000Z',
    metadata_retention_policy_cid: cid('f'),
    metadata_delete_by: '2026-09-24T04:00:00.000Z',
    clock_contract_cid: cid('0'),
  }), publicationLimits);
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: [],
    }), publicationLimits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: moon.clientRequestProgramCid(request),
      annotations: [],
    }), publicationLimits);
  return Object.freeze({
    admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze([Object.freeze({
      retention,
      evidenceContext: Object.freeze({
        computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid,
        authorityScopeCid: cid('a'),
      }),
    })]),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({
      namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      publicationPolicyCid: cid('4'), publicationTargetCid: cid('5'),
      requestedAt: '2026-09-24T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId: 'published-values-attempt', fenceCid: cid('6'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-24T00:00:01.000Z',
    }),
    outputLimits, contractLimits: publicationLimits,
    now: () => '2026-09-24T00:02:00.000Z',
  });
}

test('Node ABI derives the checked named Result and request identity', async () => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  assert.ok(prepared);
  const invocationBindings = checked(
    moon.clientProgramIssueEmptyInvocationBindings(prepared));
  assert.equal(moon.strategyRunEvidenceIdentity(invocationBindings),
    'sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f');
  assert.deepEqual(JSON.parse(moon.strategyRunEvidenceJson(invocationBindings)), {
    version: 'actql-invocation-bindings/0.1', bindings: {},
    invocation_bindings_cid:
      moon.strategyRunEvidenceIdentity(invocationBindings),
  });
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
  assert.equal(moon.clientProgramResultName(prepared, 1), undefined);
  assert.equal(moon.clientProgramCheckEnvironmentCid(prepared), evidenceCid);
  const steps = checked(moon.clientProgramLocalAoASteps(prepared, 0));
  assert.deepEqual(JSON.parse(steps), [{
    id: 'values_0', in: [], op: 'REL.values',
    params: {rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}}},
  }]);
  const pipeline = checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 0));
  assert.equal(pipeline, JSON.stringify({
    output: 'values_0', sources: {}, steps: JSON.parse(steps),
    version: 'aoa-pipeline/0.1',
  }));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesAoAWire(aoa), pipeline);
  assert.equal(moon.clientProgramLocalValuesAoACid(aoa),
    'sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723');
  const unitSource = checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 0));
  assert.deepEqual(JSON.parse(unitSource), {
    id: 'source', inputs: {},
    results: {rows: {fields: ['id'], from: 'selected'}},
    steps: [{as: 'selected', values: {
      rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}},
    }}],
    version: 'actql/0.1',
  });
  const outputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesOutputSchemaWire(outputSchema),
    '{"id":{"nullable":false,"type":"number"}}');
  assert.equal(moon.clientProgramLocalValuesOutputSchemaCid(outputSchema),
    'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513');
  const fragment = checked(moon.clientProgramIssueLocalValuesFragment(
    prepared, 0));
  const fragmentWire = moon.clientProgramLocalValuesFragmentWire(fragment);
  assert.equal(moon.clientProgramLocalValuesFragmentOutputContractCid(fragment),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.deepEqual(JSON.parse(fragmentWire), {
    input_contracts: {}, kind: 'aoa_fragment',
    logical_cid: moon.clientProgramLocalValuesAoACid(aoa),
    node_id: 'values_0',
    output_contracts: {values_0:
      moon.clientProgramLocalValuesFragmentOutputContractCid(fragment)},
    pipeline: JSON.parse(pipeline),
  });
  assert.equal(moon.clientProgramLocalValuesFragmentWire(checked(
    moon.clientProgramAdmitLocalValuesFragment(prepared, 0, fragmentWire))),
  fragmentWire);
  const resultRow = checked(moon.clientProgramIssueResultRowContract(
    prepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractName(resultRow), 'rows');
  assert.equal(moon.clientProgramResultRowContractWire(resultRow),
    '{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"}');
  assert.equal(moon.clientProgramResultRowContractCid(resultRow),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.match(moon.clientProgramResultRowContractUnitCid(resultRow),
    /^sha256:[0-9a-f]{64}$/u);
  const resultPlan = checked(moon.clientProgramIssueResultPlan(prepared, 0));
  const resultPlanWire = moon.clientProgramResultPlanWire(resultPlan);
  assert.equal(moon.clientProgramResultPlanName(resultPlan), 'answer');
  assert.equal(moon.clientProgramResultPlanCid(resultPlan),
    'sha256:8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38');
  assert.equal(moon.clientProgramResultPlanCid(resultPlan),
    canonicalHashWithoutSelf(JSON.parse(resultPlanWire),
      'result_plan_logical_cid'));
  assert.equal(moon.clientProgramResultPlanRowContractCid(resultPlan),
    moon.clientProgramResultRowContractCid(resultRow));
  assert.deepEqual(JSON.parse(resultPlanWire), {
    version: 'actql-result-plan/0.1', result_name: 'answer',
    unit_definition_cid:
      'sha256:63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9',
    unit_result_name: 'rows', unit_result_ordinal: 0,
    projection: [{input: 'id', output: 'id', value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    order: {strategy: 'inherited', terms: []},
    typed_output_port: {carrier: 'relation', name: 'rows',
      row_contract_cid: moon.clientProgramResultRowContractCid(resultRow)},
    result_plan_logical_cid: moon.clientProgramResultPlanCid(resultPlan),
  });
  assert.equal(moon.clientProgramResultPlanWire(checked(
    moon.clientProgramAdmitResultPlan(prepared, 0, resultPlanWire))),
  resultPlanWire);
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    prepared, 0, resultPlanWire.replace('"result_name":"answer"',
      '"result_name":"foreign"'))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueResultPlan(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const directRoot = checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 0));
  const directRootWire = moon.clientProgramDirectValuesResultRootWire(directRoot);
  assert.deepEqual(JSON.parse(directRootWire), {
    name: 'answer', ref: {node_id: 'values_0', port: 'values_0'},
    role: 'requested_result',
  });
  const graph = checked(moon.clientProgramIssueLocalValuesPlanGraph(prepared));
  assert.deepEqual(JSON.parse(moon.clientProgramLocalValuesPlanGraphWire(graph)), {
    data_edges: [], nodes: [JSON.parse(fragmentWire)],
    root_refs: [JSON.parse(directRootWire)],
  });
  assert.equal(moon.clientProgramLocalValuesPlanGraphWire(checked(
    moon.clientProgramAdmitLocalValuesPlanGraph(prepared,
      moon.clientProgramLocalValuesPlanGraphWire(graph)))),
  moon.clientProgramLocalValuesPlanGraphWire(graph));
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesPlanGraph(
    prepared, moon.clientProgramLocalValuesPlanGraphWire(graph)
      .replace('"answer"', '"foreign"'))),
  {code: 'MoonBitHostFailure'});
  const executable = checked(
    moon.clientProgramIssueLocalValuesExecutablePlan(prepared));
  const executableBody = JSON.parse(
    moon.clientProgramLocalValuesExecutablePlanWire(executable));
  const factManifest = JSON.parse(
    moon.clientProgramLocalValuesPlanFactManifestWire(executable));
  assert.equal(executableBody.version, 'actql-executable-plan/0.1');
  assert.equal(executableBody.executable_plan_cid,
    moon.clientProgramLocalValuesExecutablePlanCid(executable));
  assert.equal(executableBody.executable_plan_cid,
    hashWithoutSelf(executableBody, 'executable_plan_cid'));
  assert.deepEqual(executableBody.nodes, [JSON.parse(fragmentWire)]);
  assert.deepEqual(executableBody.data_edges, []);
  assert.deepEqual(executableBody.root_refs, [JSON.parse(directRootWire)]);
  assert.deepEqual(executableBody.required_profiles, []);
  assert.deepEqual(executableBody.source_state_requirements, []);
  assert.deepEqual(executableBody.plan_facts, factManifest.plan_facts);
  assert.equal(executableBody.plan_fact_manifest_cid,
    factManifest.plan_fact_manifest_cid);
  assert.equal(factManifest.plan_fact_manifest_cid,
    hashWithoutSelf(factManifest, 'plan_fact_manifest_cid'));
  assert.deepEqual(executableBody.execution_material.result_plan_logical_cids,
    {answer: moon.clientProgramResultPlanCid(resultPlan)});
  const aoaContract = JSON.parse(await readFile(new URL(
    '../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  assert.equal(executableBody.execution_material.aoa_contract_cid,
    `sha256:${createHash('sha256').update(canonicalText(aoaContract))
      .digest('hex')}`);
  assert.equal(executableBody.resolved_limits.length, 2);
  assert.equal(executableBody.limit_bindings.length, 2);
  assert.ok(executableBody.bound_witnesses.length > 1);
  assert.equal(moon.clientProgramDirectValuesResultRootPlanCid(directRoot),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.equal(moon.clientProgramDirectValuesResultRootRowContractCid(directRoot),
    moon.clientProgramLocalValuesFragmentOutputContractCid(fragment));
  assert.equal(moon.clientProgramDirectValuesResultRootWire(checked(
    moon.clientProgramAdmitDirectValuesResultRoot(
      prepared, 0, directRootWire))), directRootWire);
  assert.throws(() => checked(moon.clientProgramAdmitDirectValuesResultRoot(
    prepared, 0, directRootWire.replace('"answer"', '"foreign"'))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 1)), {code: 'MoonBitHostFailure'});
  const wider = JSON.parse(document);
  const wideValues = wider.stages[0].steps[0].values;
  wideValues.schema.hidden = {nullable: false, type: 'string'};
  wideValues.rows[0].hidden = 'a';
  wideValues.rows[1].hidden = 'b';
  const widePrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(wider), 'json', environment);
  assert.ok(widePrepared);
  const wideResultPlan = checked(
    moon.clientProgramIssueResultPlan(widePrepared, 0));
  const wideGraph = JSON.parse(moon.clientProgramLocalValuesPlanGraphWire(
    checked(moon.clientProgramIssueLocalValuesPlanGraph(widePrepared))));
  assert.equal(wideGraph.nodes.length, 2);
  assert.deepEqual(wideGraph.nodes[1].pipeline, {
    output: 'projected', sources: {input_0: {sort: 'relation'}},
    steps: [{id: 'projected', in: ['input_0'], op: 'REL.select',
      params: {columns: ['id']}}], version: 'aoa-pipeline/0.1',
  });
  assert.deepEqual(wideGraph.root_refs, [{name: 'answer',
    ref: {node_id: 'result_0', port: 'projected'}, role: 'requested_result'}]);
  assert.deepEqual(wideGraph.data_edges.map(({from, to}) => ({from, to})), [{
    from: {node_id: 'values_0', port: 'values_0'},
    to: {node_id: 'result_0', port: 'input_0'},
  }]);
  const alteredProjection = structuredClone(wideGraph);
  alteredProjection.nodes[1].pipeline.steps[0].params.columns = ['hidden'];
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesPlanGraph(
    widePrepared, JSON.stringify(alteredProjection))),
  {code: 'MoonBitHostFailure'});
  assert.notEqual(moon.clientProgramResultPlanCid(wideResultPlan),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    widePrepared, 0, resultPlanWire)), {code: 'MoonBitHostFailure'});
  const wideOutputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesOutputSchemaCid(
    wideOutputSchema), moon.clientProgramLocalValuesOutputSchemaCid(outputSchema));
  const projectedRow = checked(moon.clientProgramIssueResultRowContract(
    widePrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(projectedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const wideFragment = checked(moon.clientProgramIssueLocalValuesFragment(
    widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesFragmentOutputContractCid(
    wideFragment), moon.clientProgramResultRowContractCid(projectedRow));
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    widePrepared, 0)), {code: 'MoonBitHostFailure'});
  assert.deepEqual(JSON.parse(
    moon.clientProgramLocalValuesFragmentOutputContractWire(wideFragment)), {
    additional_properties: false,
    fields: {hidden: {nullable: false, type: 'string'},
      id: {nullable: false, type: 'number'}},
    nullable: false, type: 'object',
  });
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    widePrepared, 0, fragmentWire)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    prepared, 0, JSON.stringify({...JSON.parse(fragmentWire),
    unrecognized: true}))), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline, moon.clientProgramLocalValuesAoACid(aoa))));
  assert.throws(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline.replace('"id":2', '"id":3'),
      moon.clientProgramLocalValuesAoACid(aoa))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesFragment(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueResultRowContract(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramLocalAoASteps(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const semanticDocument = checked(
    moon.clientProgramSemanticDocumentJson(prepared));
  assert.deepEqual(JSON.parse(semanticDocument), JSON.parse(document));
  const annotated = JSON.parse(document);
  annotated.meta = {note: 'root'};
  annotated.stages[0].meta = {note: 'stage'};
  annotated.stages[0].steps[0].meta = {note: 'step'};
  const annotatedPrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(annotated), 'json', environment);
  assert.ok(annotatedPrepared);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(annotatedPrepared)),
  semanticDocument);
  assert.equal(checked(
    moon.clientProgramLocalValuesUnitSourceJson(annotatedPrepared, 0)),
  unitSource);
  const annotatedRow = checked(moon.clientProgramIssueResultRowContract(
    annotatedPrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(annotatedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const semanticsCid = moon.clientProgramSemanticsCid(prepared);
  assert.match(semanticsCid, /^sha256:[a-f0-9]{64}$/u);
  const definition = checked(moon.clientProgramDefinitionJson(prepared));
  assert.deepEqual(JSON.parse(definition), {
    id: 'client-values', program_semantics_cid: semanticsCid,
    version: 'actql-program-definition/0.1',
  });
  assert.equal(`sha256:${createHash('sha256').update(definition)
    .digest('hex')}`, programCid);
  const semantics = checked(moon.clientProgramSemanticsJson(prepared));
  assert.equal(`sha256:${createHash('sha256').update(semantics)
    .digest('hex')}`, semanticsCid);
  const stageSemantics = checked(
    moon.clientProgramStageSemanticsJson(prepared, 0));
  assert.equal(`sha256:${createHash('sha256').update(stageSemantics)
    .digest('hex')}`,
  JSON.parse(semantics).program_template.stages[0].stage_semantics_cid);
  assert.throws(() => checked(
    moon.clientProgramStageSemanticsJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  const rowsLimitBody = checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 0));
  const bytesLimitBody = checked(
    moon.clientProgramPublicationBytesLimitJson(prepared, 0, 0));
  const rowsLimit = JSON.parse(rowsLimitBody);
  const bytesLimit = JSON.parse(bytesLimitBody);
  const unit =
    'unit:sha256:63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9';
  assert.deepEqual([rowsLimit.subject_ref, bytesLimit.subject_ref],
    [`${unit}#/results/rows/rows`, `${unit}#/results/rows/bytes`]);
  assert.deepEqual([rowsLimit.unit, rowsLimit.effective_max,
    bytesLimit.unit, bytesLimit.effective_max],
  ['rows', 2, 'bytes', 1000]);
  assert.deepEqual(rowsLimit.candidates.map(candidate => candidate.role),
    ['host_ceiling', 'proven_upper_bound']);
  for (const limit of [rowsLimit, bytesLimit]) {
    assert.equal(limit.version, 'actql-resolved-limit/0.1');
    assert.equal(limit.resolved_limit_cid,
      hashWithoutSelf(limit, 'resolved_limit_cid'));
    for (const witness of limit.candidates) {
      assert.equal(witness.witness_cid,
        hashWithoutSelf(witness, 'witness_cid'));
    }
  }
  const rowsBindingBody = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const bytesBindingBody = checked(
    moon.clientProgramPublicationBytesBindingJson(prepared, 0, 0));
  const issuedFacts = checked(
    moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issuedFacts),
    [rowsLimitBody, bytesLimitBody]);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issuedFacts),
    [rowsBindingBody, bytesBindingBody]);
  const factEntries = [rowsLimitBody, bytesLimitBody].map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issuedFacts),
    factEntries);
  assert.throws(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      [factEntries[0], factEntries[0]])),
  {code: 'MoonBitHostFailure'});
  const rowsBinding = JSON.parse(rowsBindingBody);
  const bytesBinding = JSON.parse(bytesBindingBody);
  assert.deepEqual([
    rowsLimit.resolved_limit_cid, bytesLimit.resolved_limit_cid,
    rowsBinding.binding_cid, bytesBinding.binding_cid,
  ], [
    'sha256:d1b8cac20c88b332522c591586126319f5bd20393c081fb0bc9a27d38eece4d1',
    'sha256:1d01310da1218b834d27dbcd7363f3c4a46f9b38a87173474e7ef45e0fede8da',
    'sha256:cd90e6f813ff852cb0b453e2d862ee91e8051802217323fa950862e6d09edd51',
    'sha256:82ab94c9ff4d94f6b11d7c9e27ddbcfd2a4b1c7b7312f062690a1c1963a581b7',
  ]);
  for (const [binding, limit, measure] of [
    [rowsBinding, rowsLimit, 'rows'],
    [bytesBinding, bytesLimit, 'bytes'],
  ]) {
    assert.deepEqual(binding, {
      binding_cid: binding.binding_cid,
      effective_max: limit.effective_max,
      resolved_limit_cid: limit.resolved_limit_cid,
      subject_ref: `${unit}#/results/rows/${measure}`,
      target: {
        kind: 'result_publication', measure, result_name: 'rows',
        unit_definition_cid: unit.slice('unit:'.length),
      },
      unit: measure,
      version: 'actql-execution-limit-binding/0.1',
    });
    assert.equal(binding.binding_cid, hashWithoutSelf(binding, 'binding_cid'));
    assert.notEqual(binding.binding_cid, hashWithoutSelf({
      ...binding, target: {...binding.target, result_name: 'answer'},
    }, 'binding_cid'));
  }
  const admitRows = body => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body));
  const admitBytes = body => checked(
    moon.clientProgramAdmitPublicationBytesBinding(prepared, 0, 0, body));
  const admitSet = bodies => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared, bodies));
  const admitFacts = (limits, bindings) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(prepared, limits, bindings));
  assert.doesNotThrow(() => admitRows(rowsBindingBody));
  assert.doesNotThrow(() => admitBytes(bytesBindingBody));
  assert.doesNotThrow(() => admitSet([bytesBindingBody, rowsBindingBody]));
  assert.doesNotThrow(() => admitFacts(
    [bytesLimitBody, rowsLimitBody],
    [bytesBindingBody, rowsBindingBody]));
  for (const invalid of [
    [rowsLimitBody],
    [rowsLimitBody, rowsLimitBody],
    [rowsLimitBody, '{}'],
    [rowsLimitBody, JSON.stringify({...bytesLimit,
      effective_max: bytesLimit.effective_max + 1})],
  ]) assert.throws(() => admitFacts(invalid,
    [rowsBindingBody, bytesBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => admitFacts(
    [rowsLimitBody, bytesLimitBody], [rowsBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitSet([JSON.stringify({
    version: rowsBinding.version, target: rowsBinding.target,
    unit: rowsBinding.unit, subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  }), bytesBindingBody]));
  for (const invalid of [
    [rowsBindingBody],
    [rowsBindingBody, rowsBindingBody],
    [rowsBindingBody, JSON.stringify({...bytesBinding,
      binding_cid: cid('f')})],
    [bytesBindingBody, '{}'],
  ]) assert.throws(() => admitSet(invalid),
    {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitRows(JSON.stringify({
    version: rowsBinding.version,
    target: rowsBinding.target,
    unit: rowsBinding.unit,
    subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  })));
  const wrongPort = {
    ...rowsBinding,
    target: {...rowsBinding.target, result_name: 'answer'},
  };
  wrongPort.binding_cid = hashWithoutSelf(wrongPort, 'binding_cid');
  for (const invalid of [
    JSON.stringify(wrongPort),
    JSON.stringify({...rowsBinding, target: {
      ...rowsBinding.target, unit_definition_cid: cid('f'),
    }}),
    JSON.stringify({...rowsBinding, resolved_limit_cid: cid('f')}),
    JSON.stringify({...rowsBinding, binding_cid: cid('f')}),
    JSON.stringify({...rowsBinding, unknown: true}),
    rowsBindingBody.replace('"unit":"rows","version"',
      '"unit":"rows","unit":"rows","version"'),
  ]) assert.throws(() => admitRows(invalid), {code: 'MoonBitHostFailure'});
  assert.throws(() => admitBytes(rowsBindingBody),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  assert.ok(request);
  assert.equal(moon.clientRequestProgramCid(request), programCid);
  assert.equal(moon.clientRequestParametersCid(request), parametersCid);
  assert.equal(moon.clientRequestScopeCid(request),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3');
  assert.equal(moon.clientRequestIntentCid(request),
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const yaml = await readFile(new URL('values.yaml', fixture), 'utf8');
  const yamlPrepared = moon.clientProgramPrepareEffectFree(
    yaml, 'yaml', environment);
  assert.ok(yamlPrepared);
  assert.equal(moon.clientRequestProgramCid(
    moon.clientProgramRequestIdentity(
      yamlPrepared, cid('a'), 'saved-request', cid('b'))),
  programCid);
  assert.equal(moon.clientProgramSemanticsCid(yamlPrepared), semanticsCid);
  assert.equal(checked(moon.clientProgramDefinitionJson(yamlPrepared)),
    definition);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(yamlPrepared)), semanticDocument);
  assert.equal(checked(moon.clientProgramSemanticsJson(yamlPrepared)),
    semantics);
  assert.equal(checked(moon.clientProgramStageSemanticsJson(yamlPrepared, 0)),
    stageSemantics);
  assert.equal(checked(
    moon.clientProgramPublicationRowsLimitJson(yamlPrepared, 0, 0)),
  rowsLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesLimitJson(yamlPrepared, 0, 0)),
  bytesLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationRowsBindingJson(yamlPrepared, 0, 0)),
  rowsBindingBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesBindingJson(yamlPrepared, 0, 0)),
  bytesBindingBody);
  assert.equal(checked(moon.clientProgramLocalAoASteps(yamlPrepared, 0)), steps);
  assert.equal(checked(
    moon.clientProgramLocalValuesPipelineJson(yamlPrepared, 0)), pipeline);
  assert.equal(moon.clientProgramPrepareEffectFree(document, 'auto', environment),
    undefined);
  assert.equal(moon.clientProgramPrepareEffectFree(
    document.replace('actql/0.1', 'actql/9.9'), 'json', environment),
  undefined);
  assert.equal(moon.clientProgramCheckEnvironment(
    '{}', evidenceCid, false, false, true, false, false, false, false),
  undefined);
});

test('Node ABI binds separately supplied Parameters through the shared checker',
  async t => {
    const {environment} = await checkedFixture();
    const [json, yaml] = await Promise.all([
      readFile(new URL('parameter-values.json', fixture), 'utf8'),
      readFile(new URL('parameter-values.yaml', fixture), 'utf8'),
    ]);
    const prepare = (document, format, parameters) =>
      moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, environment, parameters);
    const issue = outcome => moon.clientProgramPreparationIssueCode(outcome);
    const ready = outcome => moon.clientProgramPreparationReady(outcome);
    assert.equal(issue(prepare(json, 'json', undefined)), 'needs_inputs');
    assert.equal(issue(prepare(json, 'json', '{"n":"bad"}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":null}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":2')),
      'supplied_syntax');
    assert.equal(issue(prepare(json, 'json', `{"n":"${'x'.repeat(65536)}"}`)),
      'supplied_too_large');
    assert.equal(issue(prepare(json, 'auto', '{"n":2}')),
      'invalid_format');
    const supplied = ready(prepare(json, 'json', '{"n":2}'));
    const repeated = ready(prepare(json, 'json', '{"n":2}'));
    const yamlSupplied = ready(prepare(yaml, 'yaml', '{"n":2}'));
    const changed = ready(prepare(json, 'json', '{"n":3}'));
    for (const value of [supplied, repeated, yamlSupplied, changed]) {
      assert.ok(value);
      assert.equal(moon.clientProgramResultName(value, 0), 'answer');
    }
    const identity = value => moon.clientProgramRequestIdentity(
      value, cid('a'), 'parameter-request', cid('b'));
    const first = identity(supplied);
    const same = identity(repeated);
    const yamlIdentity = identity(yamlSupplied);
    const other = identity(changed);
    assert.equal(moon.clientRequestProgramCid(first),
      moon.clientRequestProgramCid(yamlIdentity));
    assert.equal(moon.clientProgramSemanticsCid(supplied),
      moon.clientProgramSemanticsCid(yamlSupplied));
    assert.equal(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(yamlIdentity));
    assert.equal(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(same));
    assert.notEqual(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(other));
    assert.notEqual(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(other));
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'parameters-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const admission = {namespaceId: 'namespace-a', runDefinitionCid: cid('c'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    assert.equal(journal.accept(first, admission, moon).inserted, true);
    assert.equal(journal.accept(same, admission, moon).inserted, false);
    assert.throws(() => journal.accept(other, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    const withDefault = json.replace('"n": {"type": "number"}',
      '"n": {"type": "number", "default": 5}');
    assert.notEqual(withDefault, json);
    assert.ok(ready(prepare(withDefault, 'json', undefined)));
  });

test('public submit rejects checker failures before Run admission', async () => {
  const {environment} = await checkedFixture();
  const document = await readFile(new URL('parameter-values.json', fixture),
    'utf8');
  const prepareSubmit = installNodeClientProgramPreparation({
    moon, environment});
  let admissions = 0;
  let admittedIdentity;
  const server = createServer(createClientHttpHandler({
    authenticate: header => header === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: () => true,
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'principal-a', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 100, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 2048},
    }),
    prepareSubmit,
    maxRequestBytes: 100000,
    submit: ({preparedProgram, requestId}) => {
      admissions++;
      admittedIdentity = moon.clientProgramRequestIdentity(preparedProgram,
        cid('a'), requestId, cid('b'));
      return {ref: {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
        runDefinitionCid: cid('c')}, durability: 'volatile', revision: 0};
    },
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const origin = `http://127.0.0.1:${server.address().port}/`;
    const submit = parameters => fetch(new URL('actql/client/0.1/submit',
      origin), {
      method: 'POST', headers: {authorization: 'Bearer scoped-token',
        'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'local', owner: 'local',
        runners: [], consentRefs: []}, requestId: 'saved-parameter-id',
      kind: 'aql', input: {text: document, format: 'json'}, parameters}),
    });
    for (const [parameters, status, code] of [
      [null, 422, 'ClientProgramNeedsInputs'],
      [{n: null}, 422, 'ClientProgramRejected'],
      [{n: 'bad'}, 422, 'ClientProgramRejected'],
      [{n: 2, extra: true}, 422, 'ClientProgramRejected'],
      [{n: 'x'.repeat(65536)}, 413, 'ClientParametersTooLarge'],
    ]) {
      const response = await submit(parameters);
      assert.equal(response.status, status);
      assert.deepEqual(await response.json(), {code});
    }
    assert.equal(admissions, 0);
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: origin, token: 'scoped-token'});
    try {
      await assert.rejects(client.aql(document, {format: 'json',
        requestId: 'sdk-invalid-parameter', parameters: {n: null}}),
      {code: 'ClientProgramRejected'});
      assert.equal(admissions, 0);
    } finally {
      client.close();
    }
    const prepared = prepareSubmit({kind: 'aql',
      input: {text: document, format: 'json'}, parameters: {n: 2}});
    assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
    const objectPrepared = prepareSubmit({kind: 'program',
      input: JSON.parse(document), parameters: {n: 2}});
    assert.equal(moon.clientProgramSemanticsCid(objectPrepared),
      moon.clientProgramSemanticsCid(prepared));
    const accepted = await submit({n: 2});
    assert.equal(accepted.status, 200);
    assert.equal(admissions, 1);
    assert.equal(moon.clientRequestParametersCid(admittedIdentity),
      moon.clientRequestParametersCid(moon.clientProgramRequestIdentity(
        prepared, cid('a'), 'saved-parameter-id', cid('b'))));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('Node publication admission rejects evidence from another checked Program',
  async t => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'saved-request', cid('b'));
    const invocationBindingsCid = moon.strategyRunEvidenceIdentity(checked(
      moon.clientProgramIssueEmptyInvocationBindings(prepared)));
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared),
      moon.clientProgramCheckEnvironmentCid(prepared),
      invocationBindingsCid);
    assert.ok(moon.clientProgramAdmitPublication(prepared, ...evidence));
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), limits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]), limits);
    const admitted = control.admitCheckedClientRunPublication(
      prepared, ...bound, plan);
    assert.equal(admitted.kind, 'run-publication-admission');
    const definition = control.issueRunDefinition(admitted, {
      scopeId: 'namespace-a-scope',
      runId: 'checked-values-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, limits);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    const accepted = journal.acceptDefinition(identity, {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    journal.close(); // Lose the acceptance reply before using the Run ref.
    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const retained = restarted.resolveDefinition(identity,
      {namespaceId: 'namespace-a'}, moon, control);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const changed = moon.clientProgramPrepareEffectFree(
      document.replace('"id": 2', '"id": 3'), 'json', environment);
    assert.ok(changed);
    assert.equal(moon.clientProgramAdmitPublication(changed, ...evidence),
      undefined);
    assert.throws(() => control.admitCheckedClientRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Program/u);
    const changedRequest = moon.clientProgramRequestIdentity(
      changed, cid('a'), 'saved-request', cid('b'));
    assert.throws(() => restarted.resolveDefinition(changedRequest,
      {namespaceId: 'namespace-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => restarted.acceptDefinition(changedRequest, {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control), {code: 'ClientRequestIntentConflict'});
    const foreignSemantics = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity), cid('f'), evidenceCid,
      invocationBindingsCid);
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignSemantics), undefined);
    const foreignEnvironment = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared), cid('f'),
      invocationBindingsCid);
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignEnvironment), undefined);
  });

test('Node Run Definition binding rejects changed supplied Parameters',
  async t => {
    const {environment} = await checkedFixture();
    const document = await readFile(new URL('parameter-values.json', fixture),
      'utf8');
    const prepare = parameters => moon.clientProgramPreparationReady(
      moon.clientProgramPrepareEffectFreeWithParameters(document, 'json',
        environment, JSON.stringify({n: parameters})));
    const preparedA = prepare(2);
    const preparedB = prepare(3);
    assert.ok(preparedA && preparedB);
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const checkedDefinition = prepared => {
      const request = moon.clientProgramRequestIdentity(prepared,
        cid('a'), 'parameter-definition-request', cid('b'));
      const bindings = checked(moon.clientProgramIssueEmptyInvocationBindings(
        prepared));
      const evidence = publicationEvidence(
        moon.clientRequestProgramCid(request),
        moon.clientRequestParametersCid(request),
        moon.clientProgramSemanticsCid(prepared),
        moon.clientProgramCheckEnvironmentCid(prepared),
        moon.strategyRunEvidenceIdentity(bindings));
      const bound = evidence.slice(0, 3).map((value, index) =>
        control.admitRunEvidence(
          ['bound_invocation_template', 'prepared_invocation',
            'run_authorization'][index],
          moon.strategyRunEvidenceJson(value), limits));
      const plan = control.admit('compiled_plan',
        moon.strategyPublicationContractJson(evidence[3]), limits);
      const admission = control.admitCheckedClientRunPublication(
        prepared, ...bound, plan);
      const definition = control.issueRunDefinition(admission, {
        scopeId: 'namespace-a-scope', runId: 'parameter-run',
        inputArtifactSetCid: cid('c'),
        createdAt: '2026-09-24T00:00:00.000Z',
        validUntil: '2027-01-01T00:00:00.000Z',
      }, limits);
      control.checkClientRunDefinitionBinding(prepared, admission,
        definition);
      return {request, admission, definition};
    };
    const first = checkedDefinition(preparedA);
    const second = checkedDefinition(preparedB);
    assert.notEqual(moon.clientRequestParametersCid(first.request),
      moon.clientRequestParametersCid(second.request));
    assert.throws(() => control.checkClientRunDefinitionBinding(preparedA,
      first.admission, second.definition),
    /Run Definition differs from checked Program/u);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'foreign-parameters-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    await assert.rejects(journal.admitOrLookupDefinition(first.request, {
      namespaceId: 'namespace-a',
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      issueDefinition: () => {
        control.checkClientRunDefinitionBinding(preparedA,
          first.admission, second.definition);
        return second.definition;
      },
    }, moon, control), /Run Definition differs from checked Program/u);
    assert.equal(journal.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'),
      requestId: 'parameter-definition-request'}, moon), undefined);
  });

test('durable request deduplication uses checked Program identity', async t => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  await mkdir(scratch, {recursive: true});
  const path = await mkdtemp(join(scratch.pathname, 'case-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const admission = {
    namespaceId: 'namespace-a',
    runDefinitionCid: cid('d'),
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  };
  assert.equal(journal.accept(request, admission, moon).inserted, true);
  assert.equal(journal.accept(request, {...admission,
    runDefinitionCid: cid('e')}, moon).inserted, false);
  const changed = moon.clientProgramPrepareEffectFree(
    document.replace('"id": 2', '"id": 3'), 'json', environment);
  assert.ok(changed);
  const changedRequest = moon.clientProgramRequestIdentity(
    changed, cid('a'), 'saved-request', cid('b'));
  assert.equal(moon.clientRequestRelation(request, changedRequest), 2);
  assert.throws(() => journal.accept(changedRequest, {...admission,
    runDefinitionCid: cid('e')}, moon),
  {code: 'ClientRequestIntentConflict'});
  assert.equal(journal.lookup({namespaceId: 'namespace-a',
    authorityScopeCid: cid('a'), requestId: 'saved-request'}, moon)
    .ref.runDefinitionCid, cid('d'));
});

test('checked source-free Program executes through the standard Local Host',
  async () => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, -1n, 0n, 0n, 0n), undefined);
    const setup = moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const execution = await runCapturedStrategy(setup);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.deepEqual(execution.resultInventory.map(result => result.name),
        ['answer']);
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].task, 0);
      assert.equal(execution.completed[0].outputRows, 2);
      assert.throws(() => execution.effectPhysicalSource(0),
        {code: 'InvalidEffectPhysicalSource'});
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('normal Node Run issuance rejects a valid foreign Definition before journaling',
  async t => {
    const {document, environment} = await checkedFixture();
    const preparedA = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(preparedA);
    const otherDocument = JSON.parse(document);
    otherDocument.stages[0].steps[0].values.rows[1].id = 3;
    const preparedB = moon.clientProgramPrepareEffectFree(
      JSON.stringify(otherDocument), 'json', environment);
    assert.ok(preparedB);
    const control = runtimeCore(moon).publicationControl;
    const planA = checkedValuesPublicationPlan(preparedA, control);
    const planB = checkedValuesPublicationPlan(preparedB, control);
    const otherContext = checkedValuesPublicationPlan(preparedA, control,
      cid('f'));
    assert.throws(() => control.checkClientRunDefinitionBinding(
      preparedA, planA.admission, planB.runDefinition),
    /Run Definition differs from checked Program/u);
    assert.throws(() => control.checkClientRunDefinitionBinding(
      preparedA, planA.admission, otherContext.runDefinition),
    /Run Definition differs from checked Program/u);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'foreign-run-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const request = moon.clientProgramRequestIdentity(preparedA,
      cid('a'), 'foreign-definition-request', cid('b'));
    await assert.rejects(journal.admitOrLookupDefinition(request, {
      namespaceId: 'namespace-a',
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      issueDefinition: () => {
        control.checkClientRunDefinitionBinding(preparedA,
          planA.admission, planB.runDefinition);
        return planB.runDefinition;
      },
    }, moon, control), /Run Definition differs from checked Program/u);
    assert.equal(journal.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: 'foreign-definition-request'},
    moon), undefined);
  });

test('public Values submit computes and reads its real Local Result',
  async t => {
    const {document, environment} = await checkedFixture();
    const expected = JSON.parse(await readFile(new URL('values.expected.json',
      fixture), 'utf8'));
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const control = runtimeCore(moon).publicationControl;
    let plan;
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory: join(directory, 'publication'), storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    };
    const journalDirectory = join(directory, 'requests');
    await mkdir(journalDirectory);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'published-values-request', cid('b'));
    let store = await openLocalPublicationStore(configuration, control);
    let published;
    try {
      const journal = openClientRequestJournal(journalDirectory);
      const lookupRequest = installNodeClientRequestLookup({
        journal, control: moon,
        authorizedScope: ({principalId}) => principalId ===
          'principal-before-restart' ? {namespaceId: 'namespace-a',
            authorityScopeCid: cid('a')} : undefined,
      });
      const startRun = installNodeClientRunStart({
        journal, requestControl: moon, publicationControl: control,
        authorizeRunStart: ({namespaceId, principalId, connection, ref}) =>
          namespaceId === 'namespace-a' &&
          principalId === 'principal-before-restart' &&
          connection.mode === 'local' && connection.owner === 'local' &&
          ref.authorityScopeCid === cid('a'),
      });
      let issues = 0;
      let computes = 0;
      const negotiate = () => ({
        version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'principal-before-restart',
        capabilities: ['result-jsonl'],
        limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
          maxRowRetainedValueBytes: 1024,
          maxRetainedValueBytes: 4096, maxRows: 100,
          maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
      });
      const prepareSubmit = installNodeClientProgramPreparation({
        moon, environment});
      const submit = async ({preparedProgram, requestId, principalId,
        connection}) => {
        const requested = moon.clientProgramRequestIdentity(
          preparedProgram, cid('a'), requestId, cid('b'));
        const accepted = await journal.admitOrLookupDefinition(requested, {
          namespaceId: 'namespace-a',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z',
          issueDefinition: () => {
            issues++;
            plan = checkedValuesPublicationPlan(preparedProgram, control);
            return plan.runDefinition;
          },
        }, moon, control);
        const start = await startRun({identity: requested,
          namespaceId: 'namespace-a', principalId, connection});
        assert.deepEqual(start.ref, accepted.ref);
        if (start.kind === 'reserved') {
          const setup = moon.clientProgramOpenSourceFreeLocalHost(
            preparedProgram, registry, values, 1n, 0n, 0n, 0n);
          assert.ok(setup);
          computes++;
          published = await runPublishedCapturedStrategy(setup,
            {store, plan});
        }
        return {ref: start.ref, durability: start.durability,
          revision: start.revision};
      };
      const submitServer = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-before-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local',
        negotiate, prepareSubmit, lookupRequest, submit,
      }));
      await new Promise(resolve => submitServer.listen(0, '127.0.0.1',
        resolve));
      try {
        const local = await connectInProcess({mode: 'local',
          owner: 'local', durability: 'durable'},
        createNodeInProcessClientHost({
          authenticate: () => 'principal-before-restart',
          authorizeConnection: facts => facts.connection.mode === 'local' &&
            facts.connection.owner === 'local',
          negotiate, prepareSubmit, lookupRequest, submit,
          maxRowBytes: 1024,
        }));
        try {
          const transport = globalThis.fetch;
          globalThis.fetch = () => {
            throw new Error('NetworkOnEmbeddedLocalSubmit');
          };
          try {
            const accepted = await local.aql(document, {format: 'json',
              requestId: 'published-values-request'});
            assert.equal(accepted.profile.durability, 'durable');
            assert.equal(issues, 1);
            assert.equal(computes, 1);
          } finally { globalThis.fetch = transport; }
        } finally { local.close(); }
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${submitServer.address().port}/`,
          token: 'scoped-token', durability: 'durable',
        });
        try {
          const transport = globalThis.fetch;
          let responseLost = false;
          globalThis.fetch = async (url, options) => {
            const reply = await transport(url, options);
            if (!responseLost && new URL(url).pathname.endsWith('/submit')) {
              responseLost = true;
              await reply.arrayBuffer();
              throw new Error('Acceptance response lost after Host send');
            }
            return reply;
          };
          try {
            await assert.rejects(client.aql(document, {format: 'json',
              requestId: 'published-values-request'}), error =>
              error.code === 'SubmissionUnknown' &&
              error.requestId === 'published-values-request');
          } finally { globalThis.fetch = transport; }
          assert.equal(responseLost, true);
          const recovered = await client.lookupRequest(
            'published-values-request');
          assert.equal(recovered.kind, 'found');
          assert.equal(recovered.ref.runDefinitionCid,
            plan.runDefinition.identity);
          const submitted = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.deepEqual(submitted.ref, recovered.ref);
          assert.equal(submitted.profile.durability, 'durable');
          assert.equal(submitted.ref.runDefinitionCid,
            plan.runDefinition.identity);
          const repeated = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.deepEqual(repeated.ref, submitted.ref);
          const changed = document.replace('"id": 2', '"id": 3');
          assert.notEqual(changed, document);
          await assert.rejects(client.aql(changed, {format: 'json',
            requestId: 'published-values-request'}),
          {code: 'ClientRequestIntentConflict'});
          const found = await client.lookupRequest('published-values-request');
          assert.deepEqual(found.ref, submitted.ref);
          assert.equal(found.durability, 'durable');
          assert.equal(found.lookupExpiresAt, '2099-01-01T00:00:00.000Z');
          assert.deepEqual(await client.lookupRequest('absent-request'),
            {kind: 'not_found'});
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => submitServer.close(resolve));
        journal.close();
      }
      assert.equal(issues, 1);
      assert.equal(computes, 1);
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.deepEqual(published.execution.resultInventory.map(
        result => result.name), ['answer']);
      assert.equal(published.execution.completed[0].outputRows,
        expected.length);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close();
      assert.equal(published.cleanupPending(), false);
      assert.equal(await published.cleanup(), true);
      published = undefined;
      await store.close();
      store = await openLocalPublicationStore(configuration, control);
      const reopened = openClientRequestJournal(journalDirectory);
      let ref;
      try {
        const retained = await reopened.admitOrLookupDefinition(identity, {
          namespaceId: 'namespace-a',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z',
          issueDefinition: () => {
            throw new Error('Duplicate request reissued Run authority');
          },
        }, moon, control);
        assert.equal(retained.inserted, false);
        assert.equal(retained.runDefinition.wire, plan.runDefinition.wire);
        ref = retained.ref;
      } finally {
        reopened.close();
      }
      const lookupJournal = openClientRequestJournal(journalDirectory);
      const authority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: facts => ({
          authorizationContextCid: `sha256:${createHash('sha256')
            .update(facts.attemptId).digest('hex')}`,
          dataCeilingCid: cid('9'),
          egressAdmissionCid: cid('a'),
          expiresAt: '2026-09-24T01:00:00.000Z',
          maxBytes: 100000, maxUses: 1,
        }),
        authorizeResultRead: () => true,
        authorizeDeliveryAttemptLookup: () => true,
      });
      const service = installNodeResultAccessService({
        store, control, authority,
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      const stateService = installRunStateService({
        store, control,
        authority: installRunStateAuthority({
          authorizeRunState: () => true,
          resultPolicyAvailable: () => true,
        }),
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
      });
      const server = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-after-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local' &&
          (facts.ref === undefined || facts.ref.namespaceId === 'namespace-a'),
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-after-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        attach: installNodeClientRunAttach({
          journal: lookupJournal, requestControl: moon,
          publicationControl: control,
          authorizedScope: ({principalId}) => principalId ===
            'principal-after-restart' ? {namespaceId: 'namespace-a',
              authorityScopeCid: cid('a')} : undefined,
          authorizeRun: async ({principalId, ref: requested}) => {
            await inspectAuthorizedRunState(stateService, {
              indexKey: requested, principalId, purpose: 'inspect',
            });
            return true;
          },
        }),
        lookupRequest: installNodeClientRequestLookup({
          journal: lookupJournal, control: moon,
          authorizedScope: ({principalId}) => principalId ===
            'principal-after-restart' ? {namespaceId: 'namespace-a',
              authorityScopeCid: cid('a')} : undefined,
        }),
        stateService, resultService: service,
      }));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${server.address().port}/`,
          token: 'scoped-token',
        });
        const execution = await client.attach(ref);
        const found = await client.lookupRequest('published-values-request');
        assert.deepEqual(found.ref, ref);
        assert.equal(found.durability, 'durable');
        assert.equal(execution.profile.durability, 'durable');
        const state = await execution.status();
        assert.equal(validRunState(state), true);
        assert.equal(state.status, 'succeeded');
        assert.deepEqual(await execution.result('answer').all(), expected);
        const reader = execution.result('answer').rows();
        assert.deepEqual(await Array.fromAsync(reader), expected);
        assert.equal(reader.state(), 'complete');
        let attempt = await execution.result('answer')
          .deliveryAttempt(reader.attemptId);
        assert.equal(attempt.kind, 'found');
        for (let tries = 0; tries < 100 &&
          attempt.record?.state !== 'succeeded'; tries++) {
          await new Promise(resolve => setTimeout(resolve, 10));
          attempt = await execution.result('answer')
            .deliveryAttempt(reader.attemptId);
        }
        assert.equal(attempt.record.state, 'succeeded');
        client.close();
        const localAttach = installNodeClientRunAttach({
          journal: lookupJournal, requestControl: moon,
          publicationControl: control,
          authorizedScope: () => ({namespaceId: 'namespace-a',
            authorityScopeCid: cid('a')}),
          authorizeRun: async ({ref: requested}) => {
            await inspectAuthorizedRunState(stateService, {
              indexKey: requested, principalId: 'principal-after-restart',
              purpose: 'inspect',
            });
            return true;
          },
        });
        const embedded = await connectInProcess({mode: 'local',
          owner: 'local'}, createNodeInProcessClientHost({
          authenticate: () => 'principal-after-restart',
          authorizeConnection: ({connection, ref: requested}) =>
            connection.mode === 'local' && connection.owner === 'local' &&
            (requested === undefined || requested.namespaceId === 'namespace-a'),
          negotiate: () => ({
            version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
            durability: 'durable', scopeRef: 'principal-after-restart',
            capabilities: ['result-jsonl'],
            limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
              maxRowRetainedValueBytes: 1024,
              maxRetainedValueBytes: 4096, maxRows: 100,
              maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
          }),
          attach: localAttach, stateService, resultService: service,
          maxRowBytes: 1024,
        }));
        try {
          const localExecution = await embedded.attach(ref);
          assert.equal((await localExecution.status()).status, 'succeeded');
          const localRows = localExecution.result('answer').rows();
          assert.deepEqual(await Array.fromAsync(localRows), expected);
          assert.equal(localRows.state(), 'complete');
          const localAttempt = await localExecution.result('answer')
            .deliveryAttempt(localRows.attemptId);
          assert.equal(localAttempt.kind, 'found');
          assert.equal(localAttempt.record.state, 'succeeded');
          const partial = localExecution.result('answer').rows();
          const prefix = [];
          for await (const row of partial) {
            prefix.push(row);
            break;
          }
          assert.deepEqual(prefix, [expected[0]]);
          assert.equal(partial.state(), 'prefix');
          const partialAttempt = await localExecution.result('answer')
            .deliveryAttempt(partial.attemptId);
          assert.equal(partialAttempt.kind, 'found');
          assert.equal(partialAttempt.record.state, 'cancelled');
          assert.equal((await localExecution.status()).status, 'succeeded');
        } finally { embedded.close(); }
      } finally {
        await new Promise(resolve => server.close(resolve));
        lookupJournal.close();
      }
    } finally {
      await published?.close();
      await store.close();
    }
  });
const runChildWithLiveSite = (script, input) => new Promise((resolve,
  reject) => {
  const child = spawn(process.execPath, [fileURLToPath(new URL(script,
    import.meta.url))], {stdio: ['pipe', 'pipe', 'pipe']});
  const stdout = [];
  const stderr = [];
  const timeout = setTimeout(() => child.kill(), 20_000);
  child.stdout.on('data', chunk => stdout.push(Buffer.from(chunk)));
  child.stderr.on('data', chunk => stderr.push(Buffer.from(chunk)));
  child.once('error', reject);
  child.once('close', status => {
    clearTimeout(timeout);
    resolve({status, stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: Buffer.concat(stderr).toString('utf8')});
  });
  child.stdin.on('error', reject);
  child.stdin.end(JSON.stringify(input));
});
const effectParametersCid = prepared => moon.clientRequestParametersCid(
  moon.clientProgramEffectRequestIdentity(
    prepared, cid('a'), 'effect-fixture', cid('b')));
const canonicalHashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(canonicalJson(body))
    .digest('hex')}`;
};
const previewPlanLimits = Object.freeze({
  maxFields: 10, maxWork: 100, maxBytes: 20000,
  maxNodes: 1000, maxDepth: 20,
});
const effectInputExportArgs = limits => [
  limits.maxResultFields, limits.maxResultMappingWork,
  limits.maxResultOrderWork, limits.maxResultWorkspaceEntries,
  limits.maxRows, limits.maxValueNodes, limits.maxValueTextBytes,
  limits.maxValueDepth, limits.maxValueWork, limits.maxWireBytes,
  limits.maxWireNodes, limits.maxWireDepth, limits.maxColumns,
  limits.maxOrderWork, limits.maxLogicalWireBytes,
  limits.maxLogicalWireNodes, limits.maxLogicalWireDepth,
  limits.maxSchemaFields, limits.maxSchemaBytes, limits.maxSchemaNodes,
  limits.maxSchemaDepth, limits.maxBatchBytes,
];

async function effectFixture({splitSource = false,
  splitEffectSource = 'consumer', writeKind = 'create',
  memberIds = ['save'], target = 'connector://crm/account',
  mappingRef = 'mapping:crm.account.v1', sourceIds,
  continueMembers = []} = {}) {
  const [documentBody, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const targetSchema = {
    additional_properties: false,
    fields: {
      Id: {nullable: false, type: sourceIds || writeKind === 'create' ?
        'string' : 'number'},
      Name: {nullable: true, type: sourceIds ? 'string' : 'number'},
    },
    nullable: false,
    type: 'object',
  };
  if (writeKind === 'create' && sourceIds) {
    targetSchema.fields.External_Key__c = {nullable: false,
      type: 'string'};
  }
  const mapping = {
    connector_manifest_cid: cid('a'),
    conversions: [],
    mapping_contract_cid: '',
    mapping_ref: mappingRef,
    minimum_approval: 'none',
    permission_rules: [{
      effect_kind: writeKind, permissions: ['scope:' + writeKind],
      selector_class: writeKind === 'create' ? 'none' :
        writeKind === 'upsert' ? 'key' : 'id',
      write_fields: writeKind === 'create' && sourceIds ?
        ['Name', 'External_Key__c'] : ['Name'],
    }],
    primary_identity: 'Id',
    required_fields: writeKind === 'create' && sourceIds ?
      ['External_Key__c'] : [],
    required_permissions: [],
    resource_identity_cid: cid('b'),
    row_mapping: writeKind === 'create' && sourceIds ? {
      Name: {field: 'id', null_behavior: 'reject'},
      External_Key__c: {field: 'id', null_behavior: 'reject'},
    } : {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1',
    target_ref: target,
    target_schema: targetSchema,
    target_schema_identity: `sha256:${createHash('sha256')
      .update(canonicalJson(targetSchema)).digest('hex')}`,
    version: 'reference-v1',
    writable_fields: writeKind === 'create' && sourceIds ?
      ['Name', 'External_Key__c'] : ['Name'],
  };
  mapping.mapping_contract_cid = writeKind === 'create' && sourceIds
    ? canonicalHashWithoutSelf(mapping, 'mapping_contract_cid')
    : hashWithoutSelf(mapping, 'mapping_contract_cid');
  const environmentDocument = JSON.parse(environmentBody);
  mapping.connector_manifest_cid = withFixtureConnector(environmentDocument,
    mapping.target_ref);
  mapping.mapping_contract_cid = canonicalHashWithoutSelf(mapping,
    'mapping_contract_cid');
  environmentDocument.mapping_contracts = [mapping];
  if (splitSource) {
    environmentDocument.host_policy_profile.capacity = JSON.parse(
      canonicalJson({
        ...environmentDocument.host_policy_profile.capacity,
        max_graph_construction_edges: 1000,
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000,
      }));
  }
  environmentDocument.evidence_bundle_cid = canonicalHashWithoutSelf(
    environmentDocument, 'evidence_bundle_cid');
  const environment = moon.clientProgramCheckEnvironment(
    canonicalJson(environmentDocument),
    environmentDocument.evidence_bundle_cid,
    false, false, true, splitSource, false, false, false,
  );
  assert.ok(environment);
  const document = JSON.parse(documentBody);
  if (sourceIds) {
    document.stages[0].steps[0].values.schema.id.type = 'string';
    document.stages[0].steps[0].values.rows = sourceIds.map(id => ({id}));
  }
  const write = writeKind === 'create'
    ? {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'}}
    : {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'},
      [writeKind === 'upsert' ? 'key' : 'id']: 'id',
      set: {Name: {field: 'id'}}};
  const effects = Object.fromEntries(memberIds.map(id =>
    [id, {[writeKind]: continueMembers.includes(id)
      ? {...write, on_item_failure: 'continue'} : write}]));
  document.stages[0].effects = effects;
  if (splitSource) {
    delete document.stages[0].effects;
    document.stages.push({
      id: 'middle',
      inputs: {rows: {result: {stage: 'source', result: 'rows'}}},
      steps: [
        {graph: {
          nodes: {from: 'rows', id: 'id', fields: []},
          edges: {from: 'rows', source: 'id', target: 'id', fields: []},
        }, as: 'g'},
        {from: 'g', normalize_graph: true, as: 'normalized'},
        {from: 'normalized', node_rows: true, as: 'projected'},
        {from: 'projected', take: 2, as: 'selected'},
      ],
      results: {
        rows: {from: 'selected', fields: ['id']},
        early: {from: 'projected', fields: ['id']},
      },
    }, {
      id: 'consumer',
      inputs: {rows: {result: {stage: 'middle', result: 'rows'}}},
      steps: [{take: 2, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects,
    });
    document.results.answer.from.stage = 'consumer';
    if (splitEffectSource !== 'consumer') {
      document.stages.pop();
      document.results.answer.from.stage = 'middle';
      document.stages[1].effects = Object.fromEntries(memberIds.map(id =>
        [id, {[writeKind]: {
          ...write,
          from: {result: splitEffectSource === 'early' ? 'early' : 'rows'},
        }}]));
    }
  }
  return {document: JSON.stringify(document), environment,
    environmentWire: canonicalJson(environmentDocument),
    mappingCid: mapping.mapping_contract_cid};
}

test('one acquired Effect Program captures and computes from its owner',
  async t => {
    const effect = await effectFixture({writeKind: 'update'});
    const baseWire = await readFile(new URL(
      '../../spec/local-check-environment.json', import.meta.url), 'utf8');
    const source = JSON.parse(await readFile(new URL(
      './fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
    source.host_policy_profile = JSON.parse(baseWire).host_policy_profile;
    source.evidence_bundle_cid = canonicalHashWithoutSelf(source,
      'evidence_bundle_cid');
    assert.ok(moon.clientProgramCheckEnvironment(canonicalJson(source),
      source.evidence_bundle_cid, false, false, true, false, false,
      false, false), 'source environment');
    const effectWire = effect.environmentWire;
    assert.ok(moon.clientProgramCheckEnvironment(effectWire,
      JSON.parse(effectWire).evidence_bundle_cid, false, false, true,
      false, false, false, false), 'Effect environment');
    const wire = composeInstalledCheckEnvironment(moon,
      canonicalJson(JSON.parse(baseWire)),
      canonicalJson(source), effectWire);
    const environment = moon.clientProgramCheckEnvironment(wire,
      JSON.parse(wire).evidence_bundle_cid,
      false, false, true, false, false, false, false);
    assert.ok(environment);
    const document = JSON.parse(await readFile(new URL(
      '../connectors/duckdb/node/examples/program.json', import.meta.url),
    'utf8'));
    delete document.params;
    document.stages = document.stages.slice(0, 2);
    document.stages[0].steps[0].filter = 'id > 1';
    document.stages[1].effects = JSON.parse(effect.document).stages[0].effects;
    document.stages[1].effects.save.update.from.result = 'r';
    document.results = {answer: {from: {stage: 'compute_a', result: 'r'}}};
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      canonicalJson(document), 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    checked(moon.clientProgramEffectPrepareQueryAcquisition(prepared, 0, 0));
    const compileOutcome = moon.clientProgramCompileLocalEffects(prepared);
    assert.equal(moon.clientProgramEffectCompilationIssueCode(compileOutcome),
      undefined);
    const compiled = checked(compileOutcome);
    assert.deepEqual(moon.clientProgramEffectCompilationResultNames(compiled),
      ['answer']);
    const [registry, contracts] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const aoa = JSON.parse(contracts).execution_contracts;
    const values = JSON.stringify(aoa['REL.values']);
    const fragment = JSON.stringify(aoa['ACTQL.expression_fragment/0.1']);
    const ordered = JSON.stringify(aoa['REL.derive.ordered']);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'acquired-effect-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const databasePath = join(directory, 'records.duckdb');
    const database = await DuckDBInstance.create(databasePath);
    const connection = await database.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      await connection.run('INSERT INTO records VALUES (1,10),(2,20),(3,30)');
    } finally {
      connection.closeSync();
      database.closeSync();
    }
    const sourceOptions = {moon, preparedEffect: prepared, registry,
      values, fragment, ordered, database: databasePath,
      schema: 'main', table: 'records', sourceAccess: {
        ...fixtureSourceAccess, sourceRef: 'connector://crm/main/r#v',
      }, transportLimits: {maxRows: 100, maxCells: 1000,
        maxTransportBytes: 100000, maxSqlBytes: 10000,
        maxParameters: 10, maxColumns: 10,
        memoryBytes: 128 * 1024 * 1024, threads: 1}};
    const preparedSource = await prepareCapturedDuckDBSource(sourceOptions);
    const opened = await openCapturedDuckDBSource({...sourceOptions,
      preparedSource});
    try {
      assert.equal(opened.setup, undefined);
      assert.equal(moon.clientProgramEffectCapturedSourceMatches(prepared,
        opened.capture.source()), true);
      const allowed = checked(moon.clientProgramIssueAllowedEffectRun(
        compiled, cid('a'), cid('b'), '2099-01-01T00:00:00.000Z'));
      const definition = checked(moon.clientProgramIssueEffectRunDefinition(
        allowed, 'namespace-a', 'acquired-effect-run',
        '2026-09-29T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
      const bound = checked(moon.clientProgramBindCompiledEffectRun(
        prepared, allowed, definition));
      const template = checked(moon.strategyRunEvidenceAdmit(
        'bound_invocation_template',
        moon.clientProgramEffectCompilationTemplateWire(compiled),
        1000000, 100000, 64));
      const preparedEvidence = checked(moon.strategyRunEvidenceAdmit(
        'prepared_invocation', moon.strategyRunEvidenceJson(
          moon.clientProgramAllowedEffectRunPrepared(allowed)),
        1000000, 100000, 64));
      const authorization = checked(moon.strategyRunEvidenceAdmit(
        'run_authorization', moon.strategyRunEvidenceJson(
          moon.clientProgramAllowedEffectRunAuthorization(allowed)),
        1000000, 100000, 64));
      const compiledPlan = checked(moon.strategyPublicationAdmit(
        'compiled_plan',
        moon.clientProgramEffectCompilationCompiledPlanWire(compiled),
        1000000, 100000, 64));
      const admission = moon.clientProgramAdmitEffectPublication(prepared,
        template, preparedEvidence, authorization, compiledPlan);
      assert.ok(admission);
      const sourceEvidenceWire = await opened.issueSourceEvidence({
        authorityScopeCid: cid('a'),
        effectiveDataPolicyCid:
          opened.checkedSource.sourceDataPolicyCid});
      const sourceRequirement = checked(
        moon.clientProgramEffectPrepareLocalQueryRequirement(prepared,
          0, 0, registry, values, fragment, ordered));
      const sourceObservation = checked(moon.strategyRunEvidenceAdmit(
        'source_evidence', sourceEvidenceWire, 1000000, 100000, 64));
      const capturedSourceHandle = opened.capture.source();
      const localInvocation = (owner = prepared, input = opened.logicalInput,
        observation = sourceObservation) => checked(
        moon.clientProgramIssueAcquiredLocalEffectInvocation(owner,
          capturedSourceHandle, opened.identity, sourceRequirement,
          input, observation, cid('a'),
          opened.checkedSource.sourceDataPolicyCid, 1000000, 100000, 64));
      const local = localInvocation();
      const sourceRetention = checked(moon.strategyPublicationSeal(
        'result_retention_policy', JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: opened.checkedSource.sourceDataPolicyCid,
          available_until: '2026-09-29T01:00:00.000Z',
          delete_by: '2026-09-29T02:00:00.000Z',
          extension_ceiling_at: '2026-09-29T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-29T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), 1000000, 100000, 64));
      const acquiredEvidence = checked(
        moon.clientProgramIssueAcquiredEffectEvidence(prepared,
          capturedSourceHandle, opened.identity, sourceRequirement,
          opened.logicalInput, sourceObservation, cid('a'),
          opened.checkedSource.sourceDataPolicyCid, sourceRetention,
          1000000, 100000, 64));
      const sourceBodies = new Map(
        moon.clientProgramAcquiredEffectDependencyBodies(acquiredEvidence)
          .map(pair => [pair._0, JSON.parse(pair._1)]));
      assert.equal(sourceBodies.size, 6);
      assert.equal(sourceBodies.get('acquisition_relation').actual_row_count, 2);
      assert.equal(sourceBodies.get('acquisition_relation').logical_value_cid,
        JSON.parse(moon.strategyRunEvidenceJson(opened.logicalInput))
          .logical_relation_cid);
      assert.equal(sourceBodies.get('acquisition_scope').sources[0]
        .source_contract_cid, opened.checkedSource.sourceContractCid);
      const localBody = JSON.parse(moon.clientProgramLocalEffectInvocationJson(
        local));
      // Durable dependency bodies come from this same checked owner, not a
      // second compiler or a caller-authored CID inventory.
      const definitions = [];
      for (const unit of [0, 1]) {
        for (const kind of ['local_dependencies', 'local_body',
          'parameter_declarations', 'used_values', 'local_contracts',
          'schema_evidence', 'capability_evidence',
          'source_view_contract', 'catalog_contract',
          ...(unit === 1 ? ['result_import_interface',
            'result_import_type'] : [])]) {
          const body = checked(moon.clientProgramEffectLocalDependencyBody(
            prepared, unit, kind, 0, 1000000, 100000, 64));
          const wire = moon.clientProgramEffectLocalDependencyBodyJson(body);
          const value = JSON.parse(wire);
          assert.equal(wire, canonicalJson(value));
          assert.equal(checked(moon.clientProgramAdmitEffectLocalDependencyBody(
            prepared, unit, kind, 0, body, wire)), body);
          assert.throws(() => checked(
            moon.clientProgramAdmitEffectLocalDependencyBody(
              prepared, unit, kind, 0, body, wire + ' ')));
          assert.throws(() => checked(
            moon.clientProgramAdmitEffectLocalDependencyBody(
              prepared, 1 - unit, kind, 0, body, wire)));
          assert.equal(moon.clientProgramEffectLocalDependencyBodyCid(body),
            canonicalHashWithoutSelf(value, kind === 'source_view_contract'
              ? 'contract_cid' : kind === 'catalog_contract' ? 'cid' : 'self_cid'));
          if (kind === 'schema_evidence' || kind === 'capability_evidence') {
            assert.equal(moon.clientProgramEffectLocalDependencyBodyCid(body),
              JSON.parse(sourceEvidenceWire)[`${kind}_cid`]);
          }
          if (kind === 'source_view_contract') {
            assert.equal(value.contract_cid,
              JSON.parse(sourceEvidenceWire).source_view_contract_cid);
          }
          if (kind === 'local_dependencies') definitions[unit] = value;
          if (kind === 'result_import_interface') {
            assert.equal(value.producer_unit_definition_cid,
              definitions[0].self_cid);
          }
        }
      }
      assert.throws(() => checked(moon.clientProgramEffectLocalDependencyBody(
        prepared, 1, 'unknown', 0, 1000000, 100000, 64)));
      assert.throws(() => checked(moon.clientProgramEffectLocalDependencyBody(
        prepared, 1, 'local_dependencies', 1, 1000000, 100000, 64)));
      assert.deepEqual(localBody.observation_cids,
        [JSON.parse(sourceEvidenceWire).source_evidence_cid]);
      assert.equal(moon.clientProgramLocalEffectInvocationCid(local),
        canonicalHashWithoutSelf(localBody, 'self_cid'));
      const foreignPrepared = moon.clientProgramEffectPreparationReady(
        moon.clientProgramPrepareEffectComputationWithParameters(
          canonicalJson(document), 'json', environment, undefined, []));
      assert.ok(foreignPrepared);
      assert.throws(() => localInvocation(foreignPrepared));
      const alteredInput = JSON.parse(moon.strategyRunEvidenceJson(
        opened.logicalInput));
      alteredInput.logical_relation_cid = cid('e');
      alteredInput.input_logical_cid = canonicalHashWithoutSelf(alteredInput,
        'input_logical_cid');
      const admittedAlteredInput = checked(moon.strategyRunEvidenceAdmit(
        'source_input_logical', canonicalJson(alteredInput),
        1000000, 100000, 64));
      assert.throws(() => localInvocation(prepared, admittedAlteredInput));
      const alteredObservation = JSON.parse(sourceEvidenceWire);
      alteredObservation.authority_scope_cid = cid('e');
      alteredObservation.source_evidence_cid = canonicalHashWithoutSelf(
        alteredObservation, 'source_evidence_cid');
      const admittedAlteredObservation = checked(moon.strategyRunEvidenceAdmit(
        'source_evidence', canonicalJson(alteredObservation),
        1000000, 100000, 64));
      assert.throws(() => localInvocation(prepared, opened.logicalInput,
        admittedAlteredObservation));
      const invoked = checked(moon.clientProgramIssueEffectCapturedInvocation(
        prepared, compiled, admission, definition, opened.capture.source(),
        sourceEvidenceWire,
        moon.strategyRunEvidenceJson(opened.logicalInput),
        opened.checkedSource.sourceRef,
        opened.checkedSource.sourceContractCid, cid('a'),
        opened.checkedSource.sourceDataPolicyCid,
        '2026-09-29T00:00:00.000Z', '2026-09-29T00:00:01.000Z',
        1000000, 100000, 64));
      assert.deepEqual(JSON.parse(moon.strategyRunEvidenceJson(
        invoked._0)).source_evidence_cids,
      [JSON.parse(sourceEvidenceWire).source_evidence_cid]);
      const publication = acquiredEffectPublicationPlan({
        acquired: acquiredEffectPublicationAdmission({moon,
          control: runtimeCore(moon).publicationControl, prepared,
          compilation: compiled, allowed, definition,
          authorityScopeCid: cid('a'), namespaceId: 'namespace-a',
          storeAuthorityCid: cid('7'),
          now: () => '2026-09-29T00:00:02.000Z'}),
        captured: opened, sourceEvidenceWire,
        captureStartedAt: '2026-09-29T00:00:00.000Z',
        captureCompletedAt: '2026-09-29T00:00:01.000Z'});
      assert.equal(publication.invocation.identity,
        moon.strategyPublicationContractIdentity(invoked._1));
      assert.equal(publication.receiptEvidence.sourceEvidence.length, 1);
      const inputDependencies = publication.localEvidenceContext
        .acquisitionDependencies;
      assert.deepEqual(inputDependencies.map(body => body.kind),
        ['relation_value', 'relation_schema']);
      assert.deepEqual(JSON.parse(inputDependencies[0].wire),
        {sort: 'relation', value: [{id: 2}, {id: 3}]});
      for (const body of inputDependencies) {
        assert.equal(body.cid, canonicalHashWithoutSelf(
          JSON.parse(body.wire), 'unused'));
      }
      assert.equal(moon.clientProgramLocalEffectInvocationCid(
        publication.localEvidenceContext.sourceLocalInvocation),
      moon.clientProgramLocalEffectInvocationCid(local));
      const foreignSourceEvidence = JSON.parse(sourceEvidenceWire);
      foreignSourceEvidence.source_contract_cid = cid('f');
      foreignSourceEvidence.source_evidence_cid =
        canonicalHashWithoutSelf(foreignSourceEvidence,
          'source_evidence_cid');
      assert.throws(() => acquiredEffectPublicationPlan({
        acquired: acquiredEffectPublicationAdmission({moon,
          control: runtimeCore(moon).publicationControl, prepared,
          compilation: compiled, allowed, definition,
          authorityScopeCid: cid('a'), namespaceId: 'namespace-a',
          storeAuthorityCid: cid('7'),
          now: () => '2026-09-29T00:00:02.000Z'}),
        captured: opened,
        sourceEvidenceWire: canonicalJson(foreignSourceEvidence),
        captureStartedAt: '2026-09-29T00:00:00.000Z',
        captureCompletedAt: '2026-09-29T00:00:01.000Z'}));
      let retained;
      const instants = ['2026-09-29T00:00:00.000Z',
        '2026-09-29T00:00:01.000Z'];
      const computed = await openAcquiredEffectComputation({moon,
        owner: bound, acquired: acquiredEffectPublicationAdmission({moon,
          control: runtimeCore(moon).publicationControl, prepared,
          compilation: compiled, allowed, definition,
          authorityScopeCid: cid('a'), namespaceId: 'namespace-a',
          storeAuthorityCid: cid('7'),
          now: () => '2026-09-29T00:00:02.000Z'}),
        sourceProfile: {
          prepare(options) {
            assert.equal(options.preparedEffect, prepared);
            return preparedSource;
          },
          open() { return opened; },
        }, registry, values, fragment, ordered,
        sourceAccess: sourceOptions.sourceAccess,
        now: () => instants.shift(),
        retainComputationOwner(value) { retained = value; }});
      const {execution, checkedHost: host} = computed;
      assert.equal(computed.cleanupOwner, retained);
      assert.equal(computed.publicationPlan.invocation.identity,
        publication.invocation.identity);
      try {
        assert.equal(execution.status, 'host-tasks-completed');
        assert.equal(moon.clientProgramLocalEffectSourceCount(host), 1);
        assert.deepEqual(execution.completed.map(value => value.task), [1]);
        assert.deepEqual(execution.completed.map(value => value.outputRows),
          [1]);
        // Effect input custody also pins the complete upstream local Result
        // inventory from the checked graph, not a caller dependency list.
        assert.throws(() => checked(moon.clientProgramPinEffectSources(host,
          1)), 'the upstream Result also consumes a bounded pin');
        const pinResult = moon.clientProgramPinEffectSources(host, 2);
        assert.equal(pinResult.$tag, 1,
          pinResult.$tag === 0 ? `RunIssue ${pinResult._0.$tag}: ${JSON.stringify(pinResult._0)}` : undefined);
        const pins = checked(pinResult);
        let imported, rootResult;
        try {
          assert.equal(moon.clientProgramEffectLocalResultCount(pins), 2);
          assert.deepEqual([0, 1].map(index => {
            const result = moon.clientProgramEffectLocalResultAt(pins, index);
            assert.ok(result);
            return [moon.clientProgramEffectLocalResultStage(result),
              moon.clientProgramEffectLocalResultName(result)];
          }), [[0, 'r'], [1, 'r']]);
          imported = checked(moon.clientProgramEffectCaptureResultImport(
            pins, 1, 0, 100));
          rootResult = moon.clientProgramEffectLocalResultAt(pins, 0);
          assert.equal(moon.clientProgramEffectResultImportMatches(
            imported, pins, 1, rootResult), true);
          assert.equal(moon.clientProgramEffectResultImportMatches(
            imported, pins, 0, rootResult), false, 'consumer position');
          assert.equal(moon.clientProgramEffectResultImportMatches(
            imported, pins, 1,
            moon.clientProgramEffectLocalResultAt(pins, 1)), false,
          'same schema does not replace the producer');
          for (const [consumer, index, work] of [[0, 0, 100], [1, 1, 100],
            [1, 0, 0]]) {
            assert.throws(() => checked(moon.clientProgramEffectCaptureResultImport(
              pins, consumer, index, work)), {code: 'MoonBitHostFailure'});
          }
          const secondPins = checked(moon.clientProgramPinEffectSources(host, 4));
          try {
            assert.equal(moon.clientProgramEffectResultImportMatches(
              imported, secondPins, 1, rootResult), false,
            'another inventory does not transfer read ownership');
          } finally { moon.clientProgramReleaseEffectInputs(secondPins); }
          const limits = moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits));
          const rootChunks = [];
          let rootExport, rootReceipt;
          const exported = await exportPinnedEffectLocalResult({
            moon, execution, inputs: pins, resultIndex: 0, limits,
            onChunk: chunk => rootChunks.push(chunk),
            async onReceipt(_result, receipt, exportedOwner) {
              rootExport = exportedOwner;
              rootReceipt = receipt;
              assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
                pins, rootExport, rootReceipt), true);
              const rootDefinition = checked(
                moon.clientProgramIssueLocalEffectResultDefinition(
                  prepared, 0, 'r', 1000000, 100000, 64));
              const issueRoot = (exportOwner = rootExport,
                exportReceipt = rootReceipt) => {
                const result = moon.clientProgramIssueAcquiredEffectLocalResultArtifact(
                  prepared, pins, exportOwner, acquiredEvidence,
                  rootDefinition, exportReceipt, admission, definition,
                  invoked._1, invoked._0, 1000000, 100000, 64);
                assert.equal(result.$tag, 1,
                  result.$tag === 0 ? `Artifact issue ${result._0.$tag}: ${JSON.stringify(result._0)}` : undefined);
                return checked(result);
              };
              const rootArtifact = issueRoot();
              const rootManifest = checked(
                moon.clientProgramIssueLocalEffectResultManifest(prepared,
                  moon.clientProgramAcquiredEffectInvocation(acquiredEvidence),
                  [rootArtifact], 1000000, 100000, 64));
              const importObservation = checked(
                moon.clientProgramIssueEffectResultImportObservation(prepared,
                  pins, imported, rootManifest, rootArtifact,
                  1000000, 100000, 64));
              const importBody = JSON.parse(
                moon.clientProgramEffectResultImportObservationJson(
                  importObservation));
              assert.equal(importBody.producer_local_manifest_cid,
                moon.clientProgramLocalEffectResultManifestCid(rootManifest));
              assert.equal(importBody.result_artifact_cid,
                moon.clientProgramLocalEffectResultArtifactCid(rootArtifact));
              const consumerInvocation = checked(
                moon.clientProgramIssueImportedLocalEffectInvocation(prepared,
                  pins, 1, [importObservation], 1000000, 100000, 64));
              assert.deepEqual(JSON.parse(
                moon.clientProgramLocalEffectInvocationJson(consumerInvocation))
                .observation_cids, [importBody.self_cid]);
              assert.throws(() => checked(
                moon.clientProgramIssueImportedLocalEffectInvocation(prepared,
                  pins, 1, [], 1000000, 100000, 64)));
              const importedEvidence = checked(
                moon.clientProgramIssueImportedEffectEvidence(prepared,
                  pins, 1, [importObservation], 1000000, 100000, 64));
              assert.equal(moon.clientProgramLocalEffectInvocationCid(
                moon.clientProgramImportedEffectInvocation(importedEvidence)),
              moon.clientProgramLocalEffectInvocationCid(consumerInvocation));
              const inputRelations = moon.clientProgramImportedEffectRelationBodies(
                importedEvidence).map(text => JSON.parse(text));
              assert.equal(inputRelations.length, 1);
              assert.equal(inputRelations[0].actual_row_count, 2);
              assert.deepEqual(inputRelations[0].provenance_evidence, [{
                kind: 'derivation', cid: JSON.parse(
                  moon.clientProgramLocalEffectResultDerivationJson(rootArtifact))
                  .self_cid,
              }]);
              // Equal bytes from another export do not transfer ownership.
              await exportPinnedEffectLocalResult({moon, execution,
                inputs: pins, resultIndex: 0, limits, onChunk() {},
                onReceipt(_other, otherReceipt, otherOwner) {
                  assert.throws(() => issueRoot(rootExport, otherReceipt));
                  assert.throws(() => issueRoot(otherOwner, rootReceipt));
                  assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
                    pins, rootExport, otherReceipt), false);
                  assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
                    pins, otherOwner, rootReceipt), false);
                }});
              const computedChunks = [];
              const computedResult = await exportPinnedEffectLocalResult({
                moon, execution, inputs: pins, resultIndex: 1, limits,
                onChunk: chunk => computedChunks.push(chunk),
                onReceipt(_other, otherReceipt, otherOwner) {
                  assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
                    pins, otherOwner, otherReceipt), true);
                  assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
                    pins, otherOwner, rootReceipt), false);
                  const computedDefinition = checked(
                    moon.clientProgramIssueLocalEffectResultDefinition(
                      prepared, 1, 'r', 1000000, 100000, 64));
                  const issueComputed = (resultDefinition = computedDefinition,
                    exported = otherOwner, receipt = otherReceipt) => checked(
                    moon.clientProgramIssueImportedEffectLocalResultArtifact(
                      prepared, pins, exported, importedEvidence,
                      resultDefinition, receipt, sourceRetention, admission,
                      definition, invoked._1, invoked._0, 1000000, 100000, 64));
                  const computedArtifact = issueComputed();
                  assert.equal(JSON.parse(
                    moon.clientProgramLocalEffectResultArtifactJson(computedArtifact))
                    .actual_row_count, 1);
                  assert.deepEqual(JSON.parse(
                    moon.clientProgramLocalEffectResultDerivationJson(computedArtifact))
                    .input_relation_cids, [inputRelations[0].self_cid]);
                  checked(moon.clientProgramIssueLocalEffectResultManifest(
                    prepared,
                    moon.clientProgramImportedEffectInvocation(importedEvidence),
                    [computedArtifact], 1000000, 100000, 64));
                  assert.throws(() => issueComputed(rootDefinition));
                  assert.throws(() => issueComputed(computedDefinition,
                    rootExport, rootReceipt));
                }});
              assert.equal(computedResult.rowCount, 1);
              assert.deepEqual(JSON.parse(computedChunks.join('')), [{id: 3}]);
            }});
          assert.equal(exported.rowCount, 2);
          assert.deepEqual(JSON.parse(rootChunks.join('')), [{id: 2}, {id: 3}]);
          assert.equal(moon.clientProgramEffectLocalResultExportMatchesReceipt(
            pins, rootExport, rootReceipt), false, 'released receipt');
          // Use the production Host publication/export boundary as well as
          // the issuer probes above. Both upstream and consumed Results are
          // retained by the same Store preparation owner after Compute ends.
          await mkdir(scratch, {recursive: true});
          const directory = await mkdtemp(join(scratch.pathname,
            'acquired-dependencies-'));
          t.after(() => rm(directory, {recursive: true, force: true}));
          const control = runtimeCore(moon).publicationControl;
          let failDependencySync = false;
          const dependencySyncFailure = Object.assign(
            new Error('DependencyPayloadDeletionSyncFailed'), {code: 'EIO'});
          const storeConfiguration = {
            directory, storeAuthorityCid: cid('7'),
            capacityBytes: 4 * 1024 * 1024,
            maxObjectBytes: outputLimits.maxWireBytes, maxObjects: 100,
            maxContractNodes: 100000, maxContractDepth: 64,
            privateEvidenceKey: Buffer.alloc(32, 4),
          };
          let store = await openLocalPublicationStore(storeConfiguration,
            control, {async syncDirectory(path) {
            if (failDependencySync && path === join(directory, 'objects')) {
              failDependencySync = false;
              throw dependencySyncFailure;
            }
            const handle = await open(path, 'r');
            try { await handle.sync(); }
            finally { await handle.close(); }
          }});
          const plan = computed.publicationPlan;
          const options = {moon, checkedOwner: prepared, execution, inputs: pins,
            maxMembers: 1, maxGroupingWork: 100, limits,
            store, maxBytes: outputLimits.maxWireBytes, control,
            invocation: plan.invocation, retention: plan.results[0].retention,
            sourceBindingCid: cid('c'), contractLimits: plan.contractLimits,
            localEvidenceContext: plan.localEvidenceContext};
          let sources;
          try {
            sources = await preparePinnedEffectSourceSet(options);
            assert.equal(sources.members.length, 1);
            assert.deepEqual(sources.dependencies.map(entry =>
              [entry.unitIndex, entry.payload.summary.rowCount]), [[0, 2], [1, 1]]);
            const [producer, consumer] = sources.payloads;
            assert.equal(control.prepareLocalEffectDependencyInventory([], [],
              plan.contractLimits), '[]');
            assert.throws(() => control.prepareLocalEffectDependencyInventory(
              [{...consumer.localResultArtifact}], [], plan.contractLimits),
            /Foreign Effect dependency root/);
            const dependencyInventoryWire = preparePinnedEffectDependencyInventory({
              sources, store, control, contractLimits: plan.contractLimits,
            });
            const dependencyInventory = JSON.parse(dependencyInventoryWire);
            // Two checked Stages, one import, one acquisition and two local
            // Results. Only the producer Manifest is an import dependency.
            const entriesOf = kind => dependencyInventory.filter(entry =>
              entry.kind === kind);
            for (const kind of ['local_body', 'local_dependencies',
              'local_result_definition', 'local_computation', 'result_artifact',
              'derivation_evidence', 'acquisition_relation']) {
              assert.equal(entriesOf(kind).length, 2, kind);
            }
            assert.deepEqual(entriesOf('local_manifest').map(entry => entry.cid),
              [producer.localManifest.identity]);
            assert.deepEqual(entriesOf('relation_value').map(entry => entry.cid)
              .sort(), [
              canonicalHashWithoutSelf({sort: 'relation',
                value: [{id: 2}, {id: 3}]}, 'unused'),
              canonicalHashWithoutSelf({sort: 'relation',
                value: [{id: 3}]}, 'unused'),
            ].sort());
            assert.equal(entriesOf('result_import_observation').length, 1);
            assert.equal(entriesOf('result_import_interface').length, 1);
            for (const body of plan.localEvidenceContext.acquiredEvidence
              .catalogBodies) {
              assert.deepEqual(entriesOf(body.kind).find(entry =>
                entry.cid === body.cid)?.body, JSON.parse(body.wire));
            }
            const reissue = entries => control.prepareLocalEffectDependencyInventory(
              [consumer.localResultArtifact], entries.map(entry => ({
                kind: entry.kind, cid: entry.cid,
                wire: canonicalJson(entry.body),
              })), plan.contractLimits);
            assert.equal(reissue(dependencyInventory), dependencyInventoryWire);
            for (const kind of ['source_evidence', 'schema_evidence',
              'capability_evidence', 'source_contract', 'source_view_contract',
              'data_policy', 'local_manifest', 'result_import_observation']) {
              assert.throws(() => reissue(dependencyInventory.filter(entry =>
                entry.kind !== kind)), {code: 'MoonBitHostFailure'},
              `missing ${kind} is not repaired`);
            }
            const changedInput = structuredClone(dependencyInventory);
            const inputBody = changedInput.find(entry =>
              entry.kind === 'relation_value' && entry.body.value.length === 2);
            inputBody.body.value[0].id = 99;
            assert.throws(() => reissue(changedInput),
              {code: 'MoonBitHostFailure'}, 'changed input bytes reject');
            inputBody.cid = canonicalHashWithoutSelf(inputBody.body, 'unused');
            assert.throws(() => reissue(changedInput),
              {code: 'MoonBitHostFailure'},
              'rehashing the same-typed replacement cannot change the input');
            assert.throws(() => preparePinnedEffectDependencyInventory({
              sources: {...sources}, store, control,
              contractLimits: plan.contractLimits,
            }), /InvalidEffectDependencySetOwner/);
            for (const [payload, rows] of [[producer, [{id: 2}, {id: 3}]],
              [consumer, [{id: 3}]]]) {
              const logical = payload.dependencyBodies.find(body =>
                body.kind === 'relation_value' &&
                body.cid === payload.summary.logicalCid);
              const schema = payload.dependencyBodies.find(body =>
                body.kind === 'relation_schema');
              assert.deepEqual(JSON.parse(logical.wire),
                {sort: 'relation', value: rows});
              assert.equal(logical.cid,
                canonicalHashWithoutSelf({sort: 'relation', value: rows},
                  'unused'));
              assert.equal(logical.cid, payload.summary.logicalCid);
              assert.notEqual(logical.cid, payload.physical.cid);
              assert.equal(schema.cid, payload.summary.schemaCid);
              assert.deepEqual(JSON.parse(schema.wire),
                {id: {nullable: false, type: 'number'}});
              const retentionBody = JSON.parse(plan.results[0].retention.wire);
              for (const [kind, field, expectedCid] of [
                ['retention_contract', 'retention_contract_cid',
                  'sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a'],
                ['metadata_retention_policy', 'metadata_retention_policy_cid',
                  'sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095'],
                ['clock_contract', 'clock_contract_cid',
                  'sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356'],
              ]) {
                const body = payload.dependencyBodies.find(value =>
                  value.kind === kind);
                assert.equal(body.cid, expectedCid);
                assert.equal(body.cid, retentionBody[field]);
                assert.equal(body.wire, canonicalJson(JSON.parse(body.wire)));
              }
            }
            assert.equal(producer.summary.artifact, undefined,
              'upstream Result is not a fictitious Effect member');
            assert.equal(sources.members[0].payload, consumer);
            assert.throws(() => preparePinnedEffectSourceHoldings({sources,
              store, control, invocation: plan.invocation}),
            /IncompleteEffectDependencyHoldings/,
            'member-only holdings cannot expose a resumable dependency capture');
            const observation = consumer.dependencyBodies.find(body =>
              body.kind === 'result_import_observation');
            assert.ok(observation);
            const importBody = JSON.parse(observation.wire);
            assert.equal(importBody.producer_local_manifest_cid,
              producer.localManifest.identity);
            assert.equal(importBody.result_artifact_cid,
              producer.localResultArtifact.identity);
            const staticRoles = ['local_dependencies', 'local_body',
              'parameter_declarations', 'used_values', 'local_contracts',
              'local_policy'];
            for (const payload of [producer, consumer]) {
              for (const role of staticRoles) {
                assert.equal(payload.dependencyBodies.filter(body =>
                  body.kind === role).length, 1, role);
              }
              const unit = payload.dependencyBodies.find(body =>
                body.kind === 'local_dependencies');
              assert.equal(unit.cid, JSON.parse(payload.localInvocation.wire)
                .unit_definition_cid);
            }
            assert.deepEqual(producer.dependencyBodies.filter(body =>
              body.kind === 'result_import_interface'), []);
            const interfaces = consumer.dependencyBodies.filter(body =>
              body.kind === 'result_import_interface');
            assert.equal(interfaces.length, 1);
            assert.equal(interfaces[0].cid, importBody.import_interface_cid);
            assert.deepEqual(JSON.parse(consumer.localInvocation.wire)
              .observation_cids, [importBody.self_cid]);
            assert.equal(moon.clientProgramEffectLocalResultMatchesMember(
              pins, 0, 0), false);
            assert.equal(moon.clientProgramEffectLocalResultMatchesMember(
              pins, 1, 0), true);
            assert.throws(() => control.issueImportedEffectEvidence(
              prepared, pins, 1, [{wire: observation.wire}],
              plan.contractLimits), /Foreign Effect Result import observation/);
            const retainedResults = await storeCompletedRunResultSet({
              execution, store, control, runDefinition: plan.runDefinition,
              invocation: plan.invocation, results: plan.results,
              outputLimits, contractLimits: plan.contractLimits,
            });
            const adopt = sourceSet => retainPinnedEffectDependencyPayloads({
              sources: sourceSet, execution, store, storedResults: retainedResults,
              control, runDefinition: plan.runDefinition,
            });
            assert.throws(() => adopt({...sources}), /InvalidEffectDependencySetOwner/);
            assert.throws(() => retainCompletedEffectDependencyPayloads({
              execution, store, storedResults: retainedResults, control,
              runDefinition: plan.runDefinition,
              dependencies: [{artifact: producer.localResultArtifact,
                physical: consumer.physical, prepared: producer.prepared}],
            }), /InvalidCompletedEffectDependencyBinding/);
            assert.throws(() => control.localEffectResultPayloadBinding(
              {...producer.localResultArtifact}, plan.runDefinition),
            /Foreign local Effect Result artifact/);
            const foreignRun = JSON.parse(plan.runDefinition.wire);
            delete foreignRun[plan.runDefinition.identityField];
            foreignRun.run_id += '-foreign';
            assert.throws(() => control.localEffectResultPayloadBinding(
              producer.localResultArtifact, control.seal('run_definition',
                JSON.stringify(foreignRun), plan.contractLimits)));
            assert.deepEqual(adopt(sources), sources.payloads.map(payload => ({
              artifactCid: payload.localResultArtifact.identity,
              physicalCid: payload.physical.cid,
              byteCount: payload.physical.bytes,
            })));
            assert.throws(() => adopt(sources), /InvalidCompletedEffectDependencyOwner/);
            failDependencySync = true;
            let dependencyCleanup;
            await assert.rejects(releaseCompletedRunPreparedPayloads(
              retainedResults, control), error => {
              dependencyCleanup = error;
              return error.cleanupPending === true &&
                error.cleanupErrors.includes(dependencySyncFailure);
            });
            assert.equal(producer.prepared.status().pending, true,
              'failed unlink durability keeps the upstream payload owner');
            assert.equal((await dependencyCleanup.cleanupHandle.retry()).pending,
              false);
            await releaseCompletedRunPreparedPayloads(retainedResults, control);
            for (const payload of sources.payloads) {
              assert.equal(payload.prepared.status().pending, false,
                'completed owner releases upstream and member payloads');
            }
            assert.equal(await releaseCompletedRunPreparedPayloads(
              retainedResults, control), false);
            sources = undefined;
            // A later reservation failure must retain an earlier producer's
            // failed deletion owner, not leak it or rerun Compute on retry.
            const reserveFailure = new Error('ConsumerReservationFailed');
            const releaseFailure = new Error('ProducerReleaseFailed');
            let reservations = 0;
            let failedRelease = false;
            let producerPrepared;
            const failingStore = Object.freeze({...store,
              createPreparedObjectWriter(...args) {
                if (++reservations === 2) throw reserveFailure;
                const writer = store.createPreparedObjectWriter(...args);
                return Object.freeze({...writer,
                  async seal(...sealArgs) {
                    const sealed = await writer.seal(...sealArgs);
                    producerPrepared = sealed.prepared;
                    return Object.freeze({...sealed,
                      prepared: Object.freeze({...sealed.prepared,
                        async release() {
                          if (!failedRelease) {
                            failedRelease = true;
                            throw releaseFailure;
                          }
                          return sealed.prepared.release();
                        },
                      }),
                    });
                  },
                });
              },
            });
            let failure;
            try {
              await preparePinnedEffectSourceSet({...options, store: failingStore});
            } catch (error) { failure = error; }
            assert.ok(failure);
            assert.equal(failure.cause, reserveFailure);
            assert.equal(failure.cleanupPending, true);
            assert.equal(producerPrepared.status().pending, true);
            assert.equal((await failure.cleanupHandle.retry()).pending, false);
            assert.equal(producerPrepared.status().pending, false);
            assert.equal(reservations, 2,
              'cleanup never prepares a new consumer or recomputes input');

            // Re-export the same retained computation for durable custody;
            // no Source query or Compute is executed by capture or recovery.
            sources = await preparePinnedEffectSourceSet(options);
            const durableResults = await storeCompletedRunResultSet({
              execution, store, control, runDefinition: plan.runDefinition,
              invocation: plan.invocation, results: plan.results,
              outputLimits, contractLimits: plan.contractLimits,
            });
            retainPinnedEffectDependencyPayloads({sources, execution, store,
              storedResults: durableResults, control,
              runDefinition: plan.runDefinition});
            const requestScope = runtimeCore(moon).effectApplicationControl
              .logicalRequestScope(cid('e'), 'acquired-capture', 128);
            const previewDocument = effectInputPreview(prepared,
              [template, preparedEvidence, authorization, compiledPlan],
              definition, invoked._1, effect.mappingCid,
              sources.members[0].payload.summary.artifact.identity,
              'update', [3], [3], ['save'], [cid('0')], requestScope,
              {sourceResult: 'r'});
            const authoring = control.admitRunEvidence('authoring_context',
              canonicalJson(JSON.parse(previewDocument.wire).authoring_context),
              plan.contractLimits);
            const preview = control.admitEffectComputationPreview(
              previewDocument.wire, plan.runDefinition, authoring,
              plan.contractLimits);
            const previewInputs = checked(moon.clientProgramBindEffectPreviewInputs(
              host, pins, invoked._1, 1, previewDocument.wire,
              previewDocument.authoringCid,
              moon.clientProgramEffectPreviewInputLimits(
                20000, 1000, 20, 1000, 100, 20000, 1000, 20,
                1, 2, 100, 100)));
            const planChunks = [];
            await verifyPinnedEffectPlan({moon, execution, previewInputs,
              previewIndex: 0, limits,
              planLimits: {maxFields: 10, maxWork: 100, maxBytes: 20000,
                maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000},
              onChunk: chunk => { planChunks.push(chunk); }});
            const holdings = preparePinnedEffectSourceHoldings({sources,
              store, control, preview, invocation: plan.invocation});
            await holdings.commit();
            const computation = await issueCompletedEffectfulComputationEvidence({
              execution, store, storedResults: durableResults, control,
              admission: plan.localEvidenceContext.admission,
              runDefinition: plan.runDefinition, invocation: plan.invocation,
              observation: plan.localEvidenceContext.observation,
              normalizationJournal: plan.normalizationJournal,
              authoringContext: authoring, receiptEvidence: plan.receiptEvidence,
              captureEvidence: plan.captureEvidence, preview,
              plans: [{name: 'save', wire: planChunks.join('')}],
              effectSourceHoldings: holdings.holdings, connectorRecovery: [],
              contractLimits: plan.contractLimits,
            });
            const savedInventory = JSON.parse(computation.capturedRun.wire)
              .effect_context.effect_dependency_inventory;
            assert.deepEqual(savedInventory, dependencyInventory);
            await suspendCompletedEffectfulComputation({execution, store,
              storedResults: durableResults, control, computation, preview});
            for (const payload of sources.payloads) {
              assert.equal(payload.prepared.status().pending, false);
            }
            sources = undefined;
            await store.close();
            store = await openLocalPublicationStore(storeConfiguration, control);
            const recovered = await recoverCompletedEffectfulComputation({
              store, control, runDefinition: plan.runDefinition,
              contractLimits: plan.contractLimits});
            assert.equal(recovered.execution, null);
            assert.equal(recovered.computation.capturedRun.wire,
              computation.capturedRun.wire);
            await releaseCompletedRunPreparedPayloads(recovered.storedResults,
              control);
            assert.equal(await retireCompletedEffectfulCapture({store, control,
              runDefinition: plan.runDefinition,
              contractLimits: plan.contractLimits}), false,
            'completed cleanup already retired the exact saved capture');
          } finally {
            for (const payload of sources?.payloads ?? []) {
              await payload.prepared.release();
            }
            await store.close();
          }
        } finally { moon.clientProgramReleaseEffectInputs(pins); }
        assert.equal(moon.clientProgramEffectResultImportMatches(
          imported, pins, 1, rootResult), false, 'released input owner');
        assert.equal(moon.clientProgramEffectLocalResultCount(pins), 0);
        assert.equal(moon.clientProgramEffectLocalResultAt(pins, 0), undefined);
      } finally {
        await retained.close();
        assert.equal(await retained.cleanup(), true);
        assert.equal(retained.cleanupPending(), false);
      }
      assert.throws(() => localInvocation(), 'released capture is rejected');
    } finally { opened.close(); }
  });

function effectInputPreview(prepared, evidence, definition, invocation,
  mappingCid, artifactCid, writeKind = 'create',
  approvedValues = [], targetRows = approvedValues.map((_, index) =>
    index + 1), memberIds = ['save'],
  memberBoundaries = memberIds.map((_, index) => cid(String(index))),
  scope, {target = 'connector://crm/account',
    mapping = 'mapping:crm.account.v1', resourceKind = 'Account',
    footprints, continueMembers = [], guardVersions,
    templateOnly = false, sourceResult = 'rows'} = {}) {
  const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = {
    version: 'actql-authoring-context/0.1',
    program_definition_cid: definitionCid, annotations: [],
  };
  authoring.authoring_context_cid = `sha256:${createHash('sha256')
    .update(canonicalJson(authoring)).digest('hex')}`;
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: definitionCid,
    invocation_cid: moon.strategyPublicationContractIdentity(invocation),
    run_identity_cid: moon.strategyPublicationContractIdentity(definition),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(evidence[3]),
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: authoring, barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [],
    model_invocation_evidence_cids: [], model_response_artifact_cids: [],
    effects: memberIds.map((effectId, memberIndex) => ({
      effect_id: effectId, effect_kind: writeKind,
      target, mapping,
      resolved_mapping_contract_cid: mappingCid,
      effect_identity_cid: cid(String(memberIndex + 1)),
      source_result: sourceResult,
      result_artifact_cid: artifactCid, preview_strength: 'full_diff',
      source_binding_cid: cid('c'), capability_evidence_cid: cid('d'),
      authority_scope_cid: cid('e'),
      write_footprint: footprints?.[memberIndex] ?? {
        kind: 'collection', resource_identity_scheme_cid: cid('f'),
        provider_namespace: 'reference',
        provider_boundary_cid: memberBoundaries[memberIndex],
        resource_kind: resourceKind, provider_object_identity_cids: [],
      },
      count: approvedValues.length, max_items: 2,
      required_permissions: ['write'],
      approval: 'none', on_item_failure:
        continueMembers.includes(effectId) ? 'continue' : 'halt',
      changes: approvedValues.map((value, index) => ({
        target_row_identity: targetRows[index],
        target_guard: writeKind === 'create'
          ? {state: 'not_applicable'}
          : {state: 'version', version_cid:
            guardVersions?.[memberIndex]?.[index] ?? cid('6')},
        intended_changes: {state: 'present', value: writeKind === 'create'
          ? {Name: value, External_Key__c: value} : {Name: value}},
        before: writeKind === 'create' ? {state: 'absent'}
          : {state: 'present', value: {Name: typeof value === 'string'
            ? 'before' : 0}},
        after: {state: 'present', value: writeKind === 'create'
          ? {Name: value, External_Key__c: value} : {Name: value}},
        row_preview_cid: cid('1'), row_idempotency_key: cid('8'),
      })),
      row_order: [],
      effect_member_preview_cid: cid('1'), executed: false,
    })),
    executed: false, effect_preview_cid: cid('2'),
  };
  if (writeKind !== 'create') {
    for (const [index, member] of preview.effects.entries()) {
      member.effect_plan_logical_cid = checked(
        moon.clientProgramEffectPlanCid(prepared, index, 10, 100,
          20000, 1000, 20));
    }
  }
  if (templateOnly) {
    return {wire: canonicalJson(preview),
      authoringCid: authoring.authoring_context_cid};
  }
  if (scope !== undefined) {
    const authored = checked(moon.clientProgramAuthorEffectPreview(
      canonicalJson(preview), preview.run_identity_cid,
      authoring.authoring_context_cid, scope, 20000, 1000, 20,
      memberIds.length, approvedValues.length * memberIds.length,
      128, 8, 3));
    return {wire: authored._0,
      authoringCid: authoring.authoring_context_cid, keys: authored._1};
  }
  if (approvedValues.length > 0) {
    const rowsByMember = checked(moon.strategyEffectPreviewRowIdentities(
      canonicalJson(preview), 20000, 1000, 20));
    for (const [memberIndex, member] of preview.effects.entries()) {
      const rows = rowsByMember[memberIndex];
      member.changes.forEach((change, index) => {
        change.row_preview_cid = rows[index];
        change.row_idempotency_key = cid(String(index + 7));
      });
      member.row_order = rows;
    }
  }
  const identities = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20));
  preview.effects.forEach((member, index) => {
    member.effect_member_preview_cid = identities[index + 1];
  });
  preview.effect_preview_cid = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20))[0];
  const keys = scope === undefined ? undefined : preview.effects.map(member =>
    member.changes.map(change => {
      const key = checked(moon.strategyEffectDispatchKey(
        scope, preview.effect_preview_cid,
        canonicalJson(change.target_row_identity), 128, 8, 3));
      change.row_idempotency_key = moon.strategyEffectDispatchKeyCid(key);
      return key;
    }));
  return {wire: canonicalJson(preview), authoringCid:
    authoring.authoring_context_cid, keys};
}

test('internal Client bridge retains Effect closure without public apply',
  async () => {
    const {document, environment} = await effectFixture();
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const localInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    const localInvocationBody = JSON.parse(
      moon.clientProgramLocalEffectInvocationJson(localInvocation));
    assert.equal(localInvocationBody.self_cid,
      moon.clientProgramLocalEffectInvocationCid(localInvocation));
    assert.equal(localInvocationBody.observation_cids.length, 0);
    const localResult = checked(
      moon.clientProgramIssueLocalEffectResultDefinition(
        prepared, 0, 'rows', 4096, 16, 4));
    const localResultBody = JSON.parse(
      moon.clientProgramLocalEffectResultDefinitionJson(localResult));
    assert.equal(localResultBody.version,
      'actql-local-result-definition/0.1');
    assert.equal(localResultBody.result_name, 'rows');
    assert.equal(localResultBody.self_cid,
      moon.clientProgramLocalEffectResultDefinitionCid(localResult));
    assert.equal('program_definition_cid' in localResultBody, false);
    assert.equal('invocation_cid' in localResultBody, false);
    assert.equal(moon.clientProgramIssueLocalEffectResultDefinition(
      prepared, 0, 'other', 4096, 16, 4).$tag, 0);
    assert.equal(moon.clientProgramEffectPreparationIssue(outcome), undefined);
    assert.equal(moon.clientProgramPrepareEffectFree(
      document, 'json', environment), undefined);
    const foreign = moon.clientProgramPrepareEffectComputationWithParameters(
      document.replace('mapping:crm.account.v1', 'mapping:crm.foreign.v1'),
      'json', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationReady(foreign), undefined);
    assert.ok(moon.clientProgramEffectPreparationIssueCode(foreign));
    const invalidFormat = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'text', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidFormat),
      'invalid_format');
    const invalidParameters = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, '{', []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidParameters),
      'supplied_syntax');
    assert.equal(checked(moon.clientProgramEffectPlanCid(
      prepared, 0, 10, 100, 10000, 1000, 20)), undefined);
    const update = await effectFixture({writeKind: 'update'});
    const updateOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        update.document, 'json', update.environment, undefined, []);
    const updatePrepared = moon.clientProgramEffectPreparationReady(
      updateOutcome);
    assert.ok(updatePrepared,
      moon.clientProgramEffectPreparationIssueCode(updateOutcome));
    assert.match(checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 0, 10, 100, 10000, 1000, 20)),
    /^sha256:[0-9a-f]{64}$/);
    assert.throws(() => checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 1, 10, 100, 10000, 1000, 20)),
    {code: 'MoonBitHostFailure'});
  });

test('installed Effect preparation retains the checked Program owner',
  async () => {
    const {document, environment} = await effectFixture();
    const prepare = installNodeClientEffectProgramPreparation({
      moon, environment, evidence: [],
    });
    const owned = prepare({kind: 'program', input: JSON.parse(document),
      parameters: null});
    const direct = moon.clientProgramEffectPreparationReady(
      moon.clientProgramPrepareEffectComputationWithParameters(
        document, 'json', environment, undefined, []));
    assert.ok(owned && direct);
    assert.equal(moon.clientProgramEffectDefinitionCid(owned),
      moon.clientProgramEffectDefinitionCid(direct));
    assert.equal(moon.clientProgramEffectEnvironmentCid(owned),
      moon.clientProgramEffectEnvironmentCid(direct));
    assert.throws(() => prepare({kind: 'aql',
      input: {text: document, format: 'auto'}, parameters: null}),
    {code: 'ClientProgramInvalidInput'});
    assert.throws(() => prepare({kind: 'aql',
      input: {text: document.replace('mapping:crm.account.v1',
        'mapping:crm.foreign.v1'), format: 'json'}, parameters: null}),
    {code: 'ClientProgramRejected'});
    assert.throws(() => installNodeClientProgramPreparation({
      moon, environment,
    })({kind: 'program', input: JSON.parse(document), parameters: null}),
    {code: 'ClientProgramUnsupported'});
  });

test('one installed preparation distinguishes Effect and pure owners',
  async () => {
    const {document, environment} = await effectFixture();
    const prepare = installNodeClientProgramPreparation({moon, environment,
      allowEffects: true});
    const effectRequest = {kind: 'aql', input: {text: document,
      format: 'json'}, parameters: null};
    const effect = prepare(effectRequest);
    assert.equal(prepare.kindOf(effect), 'effectful');
    prepare.assertOwned(effect);
    assert.equal(moon.clientProgramEffectResultCount(effect), 1);
    assert.equal(moon.clientProgramEffectResultName(effect, 0), 'answer');
    assert.equal(moon.clientProgramEffectResultName(effect, 1), undefined);
    const compiled = checked(moon.clientProgramCompileLocalEffects(effect));
    assert.deepEqual(moon.clientProgramEffectCompilationResultNames(compiled),
      ['answer']);
    const pureDocument = JSON.parse(document);
    delete pureDocument.stages[0].effects;
    const pure = prepare({kind: 'program', input: pureDocument,
      parameters: null});
    assert.equal(prepare.kindOf(pure), 'effect_free');
    prepare.assertOwned(pure);
    const foreign = installNodeClientProgramPreparation({moon,
      environment, allowEffects: true})(effectRequest);
    assert.throws(() => prepare.kindOf(foreign),
      {message: 'Foreign Client preparation'});
    assert.throws(() => prepare.assertOwned(foreign),
      {message: 'Foreign Client preparation'});
  });

test('checked Effect member resolution is Stage-scoped', async () => {
  const fixture = await effectFixture({splitSource: true,
    memberIds: ['late'], sourceIds: ['record-a', 'record-b']});
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    fixture.document, 'json', fixture.environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared,
    moon.clientProgramEffectPreparationIssueCode(outcome));
  const late = checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 2, 'late', 100));
  assert.equal(late._0, 0);
  assert.equal(late._1, 'late');
  assert.equal(late._3, 'connector://crm/account');
  assert.equal(late._5, fixture.mappingCid);
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 0, 'late', 100)), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(
    prepared, 2, 'foreign', 100)), {code: 'MoonBitHostFailure'});
});

test('Effectful Client request identity binds checked intent before Run',
  async t => {
    const create = await effectFixture({writeKind: 'create'});
    const update = await effectFixture({writeKind: 'update'});
    const prepare = fixture => {
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        fixture.document, 'json', fixture.environment, undefined, []);
      const value = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(value,
        moon.clientProgramEffectPreparationIssueCode(outcome));
      return value;
    };
    const original = prepare(create);
    const changed = prepare(update);
    const request = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', cid('b'));
    const replay = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', cid('b'));
    const conflict = moon.clientProgramEffectRequestIdentity(
      changed, cid('a'), 'write-request', cid('b'));
    const next = moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'another-request', cid('b'));
    assert.ok(request && replay && conflict && next);
    assert.equal(moon.clientRequestProgramCid(request),
      moon.clientProgramEffectDefinitionCid(original));
    const expectedIntent = `sha256:${createHash('sha256').update(JSON.stringify({
      caller_input_intent_cid: cid('b'),
      parameter_values_cid: moon.clientRequestParametersCid(request),
      program_definition_cid: moon.clientProgramEffectDefinitionCid(original),
      version: 'actql-logical-request-intent/0.1',
    })).digest('hex')}`;
    assert.equal(moon.clientRequestIntentCid(request), expectedIntent);
    assert.equal(moon.clientRequestRelation(request, replay), 1);
    assert.equal(moon.clientRequestRelation(request, conflict), 2);
    assert.equal(moon.clientRequestRelation(request, next), 0);
    const effect = runtimeCore(moon).effectApplicationControl;
    const scope = moon.clientProgramEffectRequestScope(original, request);
    assert.ok(scope);
    assert.equal(scope, moon.clientRequestLogicalScope(request));
    assert.equal(effect.logicalRequestScopeCid(scope),
      moon.clientRequestScopeCid(request));
    assert.equal(moon.clientProgramEffectRequestScope(changed, request), undefined);
    assert.equal(moon.clientProgramEffectRequestIdentity(
      original, cid('a'), '', cid('b')), undefined);
    assert.equal(moon.clientProgramEffectRequestIdentity(
      original, cid('a'), 'write-request', 'foreign'), undefined);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'effect-request-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const admission = {namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    const journal = openClientRequestJournal(path);
    assert.equal(journal.accept(request, admission, moon).inserted, true);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.accept(replay, {...admission,
      runDefinitionCid: cid('e')}, moon).inserted, false);
    assert.throws(() => reopened.accept(conflict, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    assert.equal(reopened.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: 'write-request'}, moon)
      .ref.runDefinitionCid, cid('d'));
    const retained = reopened.lookupIdentity({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: 'write-request'}, moon);
    assert.equal(moon.clientRequestRelation(request, retained), 1);
    assert.equal(effect.logicalRequestScopeCid(
      moon.clientProgramEffectRequestScope(original, retained)),
    effect.logicalRequestScopeCid(scope));
    assert.equal(reopened.lookupIdentity({namespaceId: 'foreign',
      authorityScopeCid: cid('a'), requestId: 'write-request'}, moon), undefined);
  });

test('Host admits and retains the exact checked Effect Run Definition',
  async t => {
    const first = await effectFixture({writeKind: 'create'});
    const second = await effectFixture({writeKind: 'update'});
    const prepare = fixture => {
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        fixture.document, 'json', fixture.environment, undefined, []);
      const value = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(value, moon.clientProgramEffectPreparationIssueCode(outcome));
      return value;
    };
    const prepared = prepare(first);
    const changed = prepare(second);
    const request = moon.clientProgramEffectRequestIdentity(
      prepared, cid('a'), 'effect-run-request', cid('b'));
    const changedRequest = moon.clientProgramEffectRequestIdentity(
      changed, cid('a'), 'effect-run-request', cid('b'));
    const control = runtimeCore(moon).publicationControl;
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(request),
      moon.clientRequestParametersCid(request),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), publicationLimits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]),
      publicationLimits);
    const admission = control.admitCheckedClientEffectRunPublication(
      prepared, ...bound, plan);
    assert.equal(admission.kind, 'run-publication-admission');
    assert.throws(() => control.admitCheckedClientEffectRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Effect/u);
    const definition = control.issueRunDefinition(admission, {
      scopeId: 'namespace-a-scope', runId: 'checked-effect-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, publicationLimits);
    const boundRun = control.bindCheckedClientEffectRun(
      prepared, admission, definition);
    assert.ok(boundRun);
    assert.throws(() => control.bindCheckedClientEffectRun(
      changed, admission, definition),
    /Run Definition differs from checked Effect/u);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const host = moon.clientProgramOpenSourceFreeLocalEffectHost(
      boundRun, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(host);
    await assert.rejects(runCapturedEffectComputation({}),
      {name: 'TypeError', message: 'InvalidCapturedEffectComputation'});
    const execution = await runCapturedEffectComputation(host);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.equal(moon.clientProgramLocalEffectSourceCount(host), 1);
    } finally {
      await execution.close();
    }
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'effect-admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    assert.equal(journal.acceptDefinition(request, {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control).inserted, true);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.resolveDefinition(request,
      {namespaceId: 'namespace-a'}, moon, control).runDefinition.wire,
    definition.wire);
    assert.throws(() => reopened.resolveDefinition(changedRequest,
      {namespaceId: 'namespace-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
    const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      requestId: moon.clientRequestCallerId(request),
      runDefinitionCid: definition.identity};
    const retained = reopened.lookupOwnedDefinition(key, moon, control);
    assert.equal(moon.clientRequestRelation(request,
      retained.requestIdentity), 1);
    assert.equal(retained.runDefinition.identity, definition.identity);
    const forbidLookup = {lookupOwnedDefinition() {
      assert.fail('Denied recovery must not read the request journal');
    }};
    const recoveryOptions = {requests: forbidLookup,
      store: {storeAuthorityCid: cid('7')}, key,
      principalId: 'evidence-reader', contractLimits: publicationLimits,
      authorizeEvidenceRead: () => false};
    await assert.rejects(recoverAdmittedEffectRun(recoveryOptions),
      {code: 'EffectEvidenceAccessDenied'});
    const foreignKey = {...key, runDefinitionCid: cid('f')};
    await assert.rejects(recoverAdmittedEffectRun({...recoveryOptions,
      requests: reopened, key: foreignKey,
      authorizeEvidenceRead: async binding => {
        assert.equal(binding.runDefinitionCid, cid('f'));
        foreignKey.runDefinitionCid = definition.identity;
        foreignKey.namespaceId = 'foreign-namespace';
        await Promise.resolve();
        assert.equal(binding.namespaceId, 'namespace-a');
        return true;
      }}), {code: 'EffectRecoveryRequestMismatch'});
    const abort = new AbortController();
    await assert.rejects(recoverAdmittedEffectRun({...recoveryOptions,
      signal: abort.signal, authorizeEvidenceRead: () => {
        abort.abort();
        return true;
      }}), {name: 'AbortError'});
  });

test('admitted source-free Effect Run computes through the installed Host',
  async t => {
    const {document, environment, mappingCid} = await effectFixture({
      writeKind: 'update',
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const semanticInvocation = checked(
      moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        prepared, 0, 4096, 64, 8));
    assert.equal(JSON.parse(moon.clientProgramLocalEffectInvocationJson(
      semanticInvocation)).self_cid,
      moon.clientProgramLocalEffectInvocationCid(semanticInvocation));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared),
      effectParametersCid(prepared),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    assert.ok(admission);
    for (const changed of [
      publicationEvidence(cid('f'), effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        cid('f'), moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared), cid('f'),
        moon.clientProgramEffectEnvironmentCid(prepared)),
      publicationEvidence(moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared), cid('f')),
    ]) {
      assert.equal(moon.clientProgramAdmitEffectPublication(
        prepared, ...changed), undefined);
    }
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'namespace-a-scope', 'effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    assert.notEqual(moon.clientProgramLocalEffectInvocationCid(
      semanticInvocation), moon.strategyPublicationContractIdentity(invocation));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const foreignDocument = JSON.parse(document);
    foreignDocument.id = 'foreign-effect-compute';
    const foreignOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        JSON.stringify(foreignDocument), 'json', environment, undefined, []);
    const foreign = moon.clientProgramEffectPreparationReady(foreignOutcome);
    assert.ok(foreign);
    assert.equal(moon.clientProgramBindEffectRun(
      foreign, admission, definition), undefined);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
    const execution = await runCapturedEffectComputation(owned);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'effect-result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const runDefinitionContract = control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), publicationLimits);
    const invocationContract = control.admit('run_invocation',
      moon.strategyPublicationContractJson(invocation), publicationLimits);
    const localEvidenceContext = admittedLocalEffectEvidenceContext(
      control, prepared, evidence, definition, invocation, observation);
    const store = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
      privateEvidenceKey: Buffer.alloc(32, 4),
    }, control);
    let storedResults, committedPublicationKey, effectLedger;
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].outputRows, 2);
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control, runDefinition: runDefinitionContract,
        invocation: invocationContract,
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      assert.equal(storedResults.artifacts.length, 1);
      assert.equal(storedResults.results[0].orderedRows.rows, 2);
      assert.equal(storedResults.definitions[0].identity,
        execution.publicationInventory.occurrences[0]
          .definitionContract.identity);
      assert.equal(JSON.parse(storedResults.artifacts[0].wire)
        .actual_row_count, 2);
      const payload = [];
      await store.consumeObject(storedResults.results[0].physical.cid,
        chunk => payload.push(Buffer.from(chunk)));
      const bytes = Buffer.concat(payload);
      assert.equal(bytes.byteLength,
        storedResults.results[0].physical.bytes);
      assert.equal(`sha256:${createHash('sha256').update(bytes)
        .digest('hex')}`, storedResults.results[0].physical.cid);
      const binding = JSON.parse(storedResults.results[0].publication
        .durableBinding.wire);
      assert.equal(binding.logical_result_cid,
        storedResults.results[0].orderedRows.logicalRelationCid);
      assert.equal(binding.run_definition_cid,
        runDefinitionContract.identity);
      assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 0)), {code: 'MoonBitHostFailure'});
      const inputs = checked(moon.clientProgramPinEffectSources(owned, 1));
      let previewInputs;
      let sourcePayload;
      let sourceHoldingCid;
      try {
        assert.equal(moon.clientProgramEffectInputCount(inputs), 1);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 1), false);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.throws(() => checked(moon.clientProgramPinEffectSources(
          owned, 1)), {code: 'MoonBitHostFailure'});
        const input = moon.clientProgramEffectInputAt(inputs, 0);
        assert.ok(input);
        const capturedDefinition = checked(
          moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
            prepared, inputs, 0, 4096, 16, 4));
        assert.equal(JSON.parse(moon.clientProgramLocalEffectResultDefinitionJson(
          capturedDefinition)).result_name, 'rows');
        const foreignPrepared = moon.clientProgramEffectPreparationReady(
          moon.clientProgramPrepareEffectComputationWithParameters(
            document, 'json', environment, undefined, []));
        assert.ok(foreignPrepared);
        assert.throws(() => checked(
          moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
            foreignPrepared, inputs, 0, 4096, 16, 4)),
        {code: 'MoonBitHostFailure'});
        const beforeSource = store.status();
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: 1, control, invocation: invocationContract,
          retention, sourceBindingCid: cid('c'),
          contractLimits: publicationLimits,
          localEvidenceContext,
        }), {message: 'EffectSourceByteLimit'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().objectCount, beforeSource.objectCount);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {issueEffectSourceArtifactFromExport() {
            throw new Error('SourceArtifactRejected');
          }, issueSourceFreeLocalEffectResultArtifact:
            control.issueSourceFreeLocalEffectResultArtifact,
          issueLocalEffectResultManifest:
            control.issueLocalEffectResultManifest},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {message: 'SourceArtifactRejected'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {...control,
            issueSourceFreeLocalEffectResultArtifact(...args) {
              moon.clientProgramEffectInputExportReleaseReceipt(args[6]);
              return control.issueSourceFreeLocalEffectResultArtifact(...args);
            }},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {code: 'MoonBitHostFailure'});
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        const foreignLocalDefinition = checked(
          moon.clientProgramIssueLocalEffectResultDefinition(
            foreignPrepared, 0, 'rows', 4096, 16, 4));
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control: {...control,
            issueSourceFreeLocalEffectResultArtifact(...args) {
              args[4] = foreignLocalDefinition;
              return control.issueSourceFreeLocalEffectResultArtifact(...args);
            }},
          invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        }), {code: 'MoonBitHostFailure'});
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        await assert.rejects(preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: outputLimits.maxWireBytes,
          control, invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
          proposalLimits: {maxFields: 10, maxWork: 100,
            maxBytes: 20000, maxNodes: 1000, maxDepth: 20,
            maxUtf16Units: 20000},
          onProposalRow() { throw new Error('ProposalConsumerStopped'); },
        }), {message: 'ProposalConsumerStopped'});
        assert.equal(store.status().reservedBytes,
          beforeSource.reservedBytes);
        assert.equal(store.status().storedBytes,
          beforeSource.storedBytes);
        let sourceWriters = 0;
        let holdingCommits = 0;
        const sourceStore = {
          storeAuthorityCid: store.storeAuthorityCid,
          createPreparedObjectWriter(maxBytes) {
            sourceWriters++;
            return store.createPreparedObjectWriter(maxBytes);
          },
          async commitPhysicalHolding(...args) {
            holdingCommits++;
            const result = await store.commitPhysicalHolding(...args);
            if (holdingCommits === 1) {
              throw new Error('LostEffectSourceCommitAck');
            }
            return result;
          },
        };
        sourcePayload = await preparePinnedEffectSourcePayload({
          moon, checkedOwner: prepared, execution, inputs, memberIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store: sourceStore, maxBytes: outputLimits.maxWireBytes,
          control, invocation: invocationContract, retention,
          sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext,
        });
        const exportLimits = moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits));
        const capturedInvocation = checked(
          moon.clientProgramIssueCapturedEffectInputLocalInvocation(
            prepared, inputs, 0, publicationLimits.maxWireBytes,
            publicationLimits.maxNodes, publicationLimits.maxDepth));
        await exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 0, limits: exportLimits,
          onChunk() {},
          async onReceipt(firstInput, firstReceipt, firstImporting) {
            await exportPinnedEffectInput({
              moon, execution, inputs, memberIndex: 0,
              limits: exportLimits, onChunk() {},
              onReceipt(secondInput, secondReceipt, secondImporting) {
                assert.equal(firstInput, secondInput);
                assert.notEqual(firstImporting, secondImporting);
                assert.throws(() => control
                  .issueSourceFreeLocalEffectResultArtifact(
                    prepared, inputs, 0, secondImporting,
                    capturedDefinition, capturedInvocation, firstReceipt,
                    retention, localEvidenceContext, publicationLimits),
                {code: 'MoonBitHostFailure'});
                assert.throws(() => control
                  .issueSourceFreeLocalEffectResultArtifact(
                    foreignPrepared, inputs, 0, secondImporting,
                    capturedDefinition, capturedInvocation, secondReceipt,
                    retention, localEvidenceContext, publicationLimits),
                {code: 'MoonBitHostFailure'});
                assert.ok(control.issueSourceFreeLocalEffectResultArtifact(
                  prepared, inputs, 0, secondImporting,
                  capturedDefinition, capturedInvocation, secondReceipt,
                  retention, localEvidenceContext, publicationLimits));
              },
            });
          },
        });
        const sourceArtifact = sourcePayload.summary.artifact;
        assert.equal(JSON.parse(sourceArtifact.wire).source_result, 'rows');
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .result_name, 'rows');
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .self_cid, sourcePayload.localResultDefinition.identity);
        assert.equal(JSON.parse(sourcePayload.localResultDefinition.wire)
          .version, 'actql-local-result-definition/0.1');
        const localArtifact = JSON.parse(sourcePayload.localResultArtifact.wire);
        assert.equal(localArtifact.version, 'actql-result-artifact/0.1');
        assert.equal(localArtifact.result_definition_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localArtifact.invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.notEqual(localArtifact.invocation_cid,
          invocationContract.identity);
        assert.equal(localArtifact.logical_result_cid,
          sourcePayload.summary.logicalCid);
        assert.equal(localArtifact.result_schema_cid,
          sourcePayload.summary.schemaCid);
        assert.equal(localArtifact.actual_row_count,
          sourcePayload.summary.rowCount);
        const localManifest = JSON.parse(sourcePayload.localManifest.wire);
        assert.equal(localManifest.version,
          'actql-local-result-manifest/0.1');
        assert.equal(localManifest.self_cid,
          sourcePayload.localManifest.identity);
        assert.equal(localManifest.local_invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.deepEqual(localManifest.results,
          {rows: sourcePayload.localResultArtifact.identity});
        const localManifestPreimage = {...localManifest};
        delete localManifestPreimage.self_cid;
        assert.equal(sourcePayload.localManifest.identity,
          `sha256:${createHash('sha256')
            .update(JSON.stringify(localManifestPreimage))
            .digest('hex')}`);
        assert.throws(() => control.issueLocalEffectResultManifest(
          prepared, capturedInvocation, [], publicationLimits),
        {name: 'TypeError'});
        assert.throws(() => control.issueLocalEffectResultManifest(
          foreignPrepared, capturedInvocation,
          [sourcePayload.localResultArtifact], publicationLimits),
        {code: 'MoonBitHostFailure'});
        const localIdentity = control.issueSourceFreeLocalEffectIdentity(
          prepared, inputs, 0, sourcePayload.localResultArtifact,
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10});
        const localIdentityBody = JSON.parse(localIdentity.wire);
        assert.equal(localIdentityBody.self_cid, localIdentity.identity);
        assert.equal(localIdentityBody.result_artifact_cid,
          sourcePayload.localResultArtifact.identity);
        assert.equal(localIdentityBody.local_invocation_cid,
          sourcePayload.localInvocation.identity);
        assert.throws(() => control.issueSourceFreeLocalEffectIdentity(
          foreignPrepared, inputs, 0, sourcePayload.localResultArtifact,
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10}), {code: 'MoonBitHostFailure'});
        assert.throws(() => control.issueSourceFreeLocalEffectIdentity(
          prepared, inputs, 0, {...sourcePayload.localResultArtifact},
          {maxWork: 100, maxWireBytes: 4096, maxNodes: 100,
            maxDepth: 10}), {name: 'TypeError'});
        const localDerivation = JSON.parse(
          sourcePayload.localResultArtifact.derivationWire);
        const localOrdering = JSON.parse(
          sourcePayload.localResultArtifact.orderingWire);
        assert.equal(localDerivation.producer_contract_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localOrdering.producer_contract_cid,
          sourcePayload.localResultDefinition.identity);
        assert.equal(localArtifact.ordering_evidence_cid,
          localOrdering.self_cid);
        assert.deepEqual(localArtifact.provenance_evidence_cids,
          [localDerivation.self_cid]);
        assert.equal(JSON.parse(storedResults.artifacts[0].wire)
          .result_definition_cid, storedResults.definitions[0].identity);
        assert.equal(storedResults.results[0].occurrence.name, 'answer');
        const effect = runtimeCore(moon).effectApplicationControl;
        const requestScope = effect.logicalRequestScope(
          cid('e'), 'effect-compute-request', 128);
        const preview = effectInputPreview(
          prepared, evidence, definition, invocation, mappingCid,
          sourceArtifact.identity, 'update', [1, 2], [1, 2],
          ['save'], [cid('0')], requestScope);
        const authoringContext = control.admitRunEvidence(
          'authoring_context',
          canonicalJson(JSON.parse(preview.wire).authoring_context),
          publicationLimits);
        const admittedPreview = control.admitEffectComputationPreview(
          preview.wire, runDefinitionContract, authoringContext,
          publicationLimits);
        const capturePreviewInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, preview.wire,
            preview.authoringCid,
            moon.clientProgramEffectPreviewInputLimits(
              20000, 1000, 20, 1000, 100, 20000, 1000, 20,
              1, 2, 100, 100)));
        const planChunks = [];
        await verifyPinnedEffectPlan({
          moon, execution, previewInputs: capturePreviewInputs,
          previewIndex: 0,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          planLimits: {maxFields: 10, maxWork: 100, maxBytes: 20000,
            maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000},
          onChunk: chunk => { planChunks.push(chunk); },
        });
        let matchedSource;
        const sourceControl = {...control,
          localEffectSourceMatches(...args) {
            matchedSource = args;
            return control.localEffectSourceMatches(...args);
          }};
        const commitSource = () => commitPinnedEffectSourceHolding({
          payload: sourcePayload, store: sourceStore, control: sourceControl,
          preview: admittedPreview,
          memberIndex: 0, invocation: invocationContract,
        });
        await assert.rejects(commitPinnedEffectSourceHolding({
          payload: sourcePayload, store: sourceStore,
          control: {...control, localEffectSourceMatches: () => false},
          preview: admittedPreview,
          memberIndex: 0, invocation: invocationContract,
        }), {message: 'ForeignLocalEffectSource'});
        assert.equal(holdingCommits, 0);
        await assert.rejects(commitSource(),
          {message: 'LostEffectSourceCommitAck'});
        const sourceHolding = await commitSource();
        assert.equal(sourceWriters, 1);
        assert.equal(holdingCommits, 2);
        assert.equal(sourceHolding.localResultArtifact,
          sourcePayload.localResultArtifact);
        assert.equal(sourceHolding.localManifest, sourcePayload.localManifest);
        assert.equal(control.localEffectSourceMatches(...matchedSource), true);
        assert.equal(control.localEffectSourceMatches(
          foreignPrepared, ...matchedSource.slice(1)), false);
        assert.throws(() => control.localEffectSourceMatches(
          ...matchedSource.slice(0, 3), {...sourceHolding.localManifest},
          ...matchedSource.slice(4)), {name: 'TypeError'});
        sourceHoldingCid = sourceHolding.holdingCid;
        assert.deepEqual(await store.inspectPhysicalHolding(
          sourceHoldingCid), sourceHolding.record);
        const runEvidence = evidence.slice(0, 3).map((value, index) =>
          control.admitRunEvidence(
            ['bound_invocation_template', 'prepared_invocation',
              'run_authorization'][index],
            moon.strategyRunEvidenceJson(value), publicationLimits));
        const compiledPlan = control.admit('compiled_plan',
          moon.strategyPublicationContractJson(evidence[3]),
          publicationLimits);
        const runAdmission = control.admitCheckedClientEffectRunPublication(
          prepared, ...runEvidence, compiledPlan);
        const normalizationJournal = control.sealRunEvidence(
          'normalization_journal', JSON.stringify({
            version: 'actql-normalization-journal/0.1',
            rule_catalog_cid: cid('1'), entries: [],
          }), publicationLimits);
        const captureOptions = {
          execution, store, storedResults, control, admission: runAdmission,
          runDefinition: runDefinitionContract,
          invocation: invocationContract,
          observation: control.admitRunEvidence('observation_set',
            moon.strategyRunEvidenceJson(observation), publicationLimits),
          normalizationJournal, authoringContext,
          receiptEvidence: {bindings: [], sourceEvidence: [],
            modelEvidence: [], barrierAttemptReceiptCids: []},
          captureEvidence: {pendingSourceStateAdvances: [],
            modelEvidence: []},
          preview: admittedPreview,
          plans: [{name: 'save', wire: planChunks.join('')}],
          effectSourceHoldings: [sourceHolding],
          connectorRecovery: [],
          contractLimits: publicationLimits,
        };
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          store: {...store,
            async commitPhysicalHolding() {
              throw new Error('EffectSourceSyncFailed');
            }},
        }), {message: 'EffectSourceSyncFailed'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          effectSourceHoldings: [{...sourceHolding,
            record: {...sourceHolding.record, manifest_cid: cid('9')}}],
        }), {code: 'InvalidCompletedEffectSourceHolding'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          effectSourceHoldings: [{...sourceHolding,
            artifact: {...sourceArtifact, identity: cid('9')}}],
        }), {code: 'InvalidCompletedEffectSourceHolding'});
        let captureCommits = 0;
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          store: {...store,
            async commitPhysicalHolding(...args) {
              const committed = await store.commitPhysicalHolding(...args);
              captureCommits++;
              if (captureCommits === 2) {
                throw new Error('LostCaptureHoldingCommitAck');
              }
              return committed;
            }},
        }), {message: 'LostCaptureHoldingCommitAck'});
        assert.ok(await store.inspectPhysicalHolding(
          control.effectComputationCaptureHoldingCid(
            runDefinitionContract, store.storeAuthorityCid)));
        const computation = await issueCompletedEffectfulComputationEvidence(
          captureOptions);
        assert.equal(sourceWriters, 1);
        const finalInventory = prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation, preview: admittedPreview,
        });
        assert.equal(finalInventory.chain.capturedRun.identity,
          computation.capturedRun.identity);
        assert.equal(finalInventory.chain.artifacts[0].identity,
          storedResults.artifacts[0].identity);
        assert.equal(finalInventory.sourceArtifacts[0].identity,
          sourceArtifact.identity);
        assert.equal(finalInventory.effectSources[0], sourceHolding.source);
        const mutableArtifact = {...sourceArtifact};
        const mutableComputation =
          await issueCompletedEffectfulComputationEvidence({
            ...captureOptions,
            effectSourceHoldings: [{...sourceHolding,
              artifact: mutableArtifact}],
          });
        mutableArtifact.identity = cid('9');
        assert.equal(prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation: mutableComputation, preview: admittedPreview,
        }).sourceArtifacts[0].identity, sourceArtifact.identity);
        assert.throws(() => prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation: {...computation}, preview: admittedPreview,
        }), {code: 'InvalidCompletedEffectfulRunOwner'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions, storedResults: {...storedResults},
        }), {code: 'InvalidCompletedEffectfulComputationOptions'});
        assert.equal(computation.manifest.name, 'result_manifest');
        assert.equal(computation.computationReceipt.name, 'run_receipt');
        assert.equal(computation.capturedRun.name, 'captured_run');
        const capturedBody = JSON.parse(computation.capturedRun.wire);
        assert.deepEqual(capturedBody.receipt,
          JSON.parse(computation.computationReceipt.wire));
        assert.equal(capturedBody.effect_context.effect_source_artifacts.save
          .result_artifact_cid, sourceArtifact.identity);
        assert.equal(capturedBody.effect_context.effect_source_artifacts.save
          .source_result,
          'rows');
        assert.equal(capturedBody.effect_context.effect_source_holding_cids.save,
          sourceHoldingCid);
        assert.deepEqual(Object.keys(capturedBody.effect_context
          .result_artifacts), ['answer']);
        const foreignArtifactPreview = effectInputPreview(
          prepared, evidence, definition, invocation, mappingCid, cid('9'));
        const foreignAdmittedPreview =
          control.admitEffectComputationPreview(
            foreignArtifactPreview.wire, runDefinitionContract,
            authoringContext, publicationLimits);
        assert.throws(() => prepareCompletedEffectfulPublication({
          execution, store, storedResults, control,
          computation, preview: foreignAdmittedPreview,
        }), {code: 'InvalidCompletedEffectfulRunOwner'});
        await assert.rejects(issueCompletedEffectfulComputationEvidence({
          ...captureOptions,
          preview: foreignAdmittedPreview, plans: [],
        }), {code: 'MoonBitHostFailure'});
        const previewLimits = moon.clientProgramEffectPreviewInputLimits(
          20000, 1000, 20, 1000, 100, 20000, 1000, 20,
          1, 2, 100, 100);
        assert.ok(previewLimits);
        const foreignPreview = effectInputPreview(
          prepared, evidence, definition, invocation, cid('9'),
          sourceArtifact.identity);
        assert.throws(() => checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, foreignPreview.wire,
            foreignPreview.authoringCid, previewLimits)),
        {code: 'MoonBitHostFailure'});
        previewInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, preview.wire,
            preview.authoringCid, previewLimits));
        assert.equal(moon.clientProgramEffectPreviewInputAt(
          previewInputs, 0), input);
        assert.equal(checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, 10, 100)).operation, 'update');
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, -1, 100)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 1, 10, 100)),
        {code: 'MoonBitHostFailure'});
        const previewRows = JSON.parse(preview.wire).effects[0].row_order;
        assert.doesNotThrow(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, previewRows, previewRows.map(() => cid('6')),
            2, 4)));
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [], 1, 2)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [cid('2')], 1, 2)),
        {code: 'MoonBitHostFailure'});
        const other = moon.clientProgramOpenSourceFreeLocalEffectHost(
          bound, registry, values, 1n, 0n, 0n, 0n);
        assert.ok(other);
        const otherExecution = await runCapturedEffectComputation(other);
        try {
          await assert.rejects(issueCompletedEffectfulComputationEvidence({
            ...captureOptions, execution: otherExecution,
          }), {code: 'InvalidCompletedEffectfulComputationOptions'});
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              other, inputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
        } finally {
          await otherExecution.close();
        }
        const limits = moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits));
        assert.ok(limits);
        assert.throws(() => checked(moon.clientProgramEffectInputExportStart(
          input, limits)), {code: 'MoonBitHostFailure'});
        const physical = execution.effectPhysicalSource(0);
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 1, limits,
          onChunk() { throw new Error('UnexpectedEffectChunk'); },
        }), {message: 'MissingEffectInput'});
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 0, limits,
          onChunk() { throw new Error('StoppedEffectConsumer'); },
        }), {message: 'StoppedEffectConsumer'});
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        const observed = {
          effectPhysicalSource(task) {
            assert.equal(task, 0);
            return {
              ...physical,
              withRows(...args) {
                limits.max_rows = 0;
                limits.values.max_nodes = 0;
                return physical.withRows(...args);
              },
            };
          },
        };
        const chunks = [];
        const exported = await exportPinnedEffectInput({
          moon, execution: observed, inputs, memberIndex: 0,
          task: 999,
          limits,
          onChunk: async chunk => { chunks.push(chunk); },
        });
        assert.deepEqual(JSON.parse(chunks.join('')),
          [{id: 1}, {id: 2}]);
        assert.deepEqual(exported.fields, ['id']);
        assert.match(exported.logicalCid, /^sha256:[0-9a-f]{64}$/);
        assert.match(exported.schemaCid, /^sha256:[0-9a-f]{64}$/);
        assert.equal(exported.rowCount, 2);
        assert.equal(sourcePayload.summary.logicalCid, exported.logicalCid);
        assert.equal(sourcePayload.summary.schemaCid, exported.schemaCid);
        assert.equal(sourcePayload.summary.rowCount, exported.rowCount);
        assert.equal(sourcePayload.physical.cid,
          `sha256:${createHash('sha256')
            .update(chunks.join('')).digest('hex')}`);
        const storedChunks = [];
        await store.consumePhysicalHolding(sourceHoldingCid, 0,
          chunk => storedChunks.push(Buffer.from(chunk)));
        assert.equal(Buffer.concat(storedChunks).toString('utf8'),
          chunks.join(''));
        const previewBody = JSON.parse(preview.wire);
        const applyPreview = effect.admitPreviewIdentity(
          preview.wire, previewBody.run_identity_cid,
          preview.authoringCid, requestScope, preview.keys,
          publicationLimits.maxWireBytes, publicationLimits.maxNodes,
          publicationLimits.maxDepth);
        const ledgerRoot = join(directory, 'effect-ledger');
        await mkdir(ledgerRoot);
        effectLedger = openEffectLedger({moon, root: ledgerRoot,
          authorityScopeCid: cid('e'),
          callerRequestId: 'effect-compute-request',
          maxEntryBytes: 4096});
        const rowOwners = [];
        let physicalSends = 0;
        for (const [rowIndex, change] of
          previewBody.effects[0].changes.entries()) {
          const correlation = canonicalJson(change.target_row_identity);
          const key = preview.keys[0][rowIndex];
          const locator = effect.logicalItemLocator(
            requestScope, 'program-1', 'node-1', 'save', correlation,
            64, 128, 8, 3);
          const requestWire = canonicalJson({operation: 'update',
            row: change.row_preview_cid});
          const canonicalRequestCid = `sha256:${createHash('sha256')
            .update(requestWire).digest('hex')}`;
          const basis = effect.ledgerBasis(
            requestScope, locator, key, cid('6'),
            previewBody.effects[0].effect_member_preview_cid,
            change.row_preview_cid, canonicalRequestCid, cid('0'),
            'unavailable', cid('1'), cid('2'));
          const claim = {scope: requestScope, locator, key, basis,
            intentFingerprintCid: change.row_preview_cid,
            canonicalRequestCid};
          const captured = await captureClaimedEffectResponse({
            ledger: effectLedger, claim, requestCid: canonicalRequestCid,
            execute: async () => {
              physicalSends++;
              return {observation: {useCid: cid('4'),
                statusCode: 204, body: Buffer.alloc(0)}};
            },
          });
          assert.equal(captured.claimed, true);
          const recorded = effectLedger.recordAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex: 0,
            previewRowIndex: rowIndex,
            outcomeWire: canonicalJson({result: {
              record_id: `row-${rowIndex + 1}`}, state: 'applied'}),
          });
          assert.equal(recorded.custody.created, true);
          assert.equal(effectLedger.commitAdmittedRowOutcome({
            claim, preview: applyPreview, memberIndex: 0,
            previewRowIndex: rowIndex,
          }).transition.created, true);
          rowOwners.push({claim});
        }
        assert.equal(physicalSends, 2);
        effectLedger.close();
        effectLedger = openEffectLedger({moon, root: ledgerRoot,
          authorityScopeCid: cid('e'),
          callerRequestId: 'effect-compute-request',
          maxEntryBytes: 4096});
        for (const {claim} of rowOwners) {
          const replay = await captureClaimedEffectResponse({
            ledger: effectLedger, claim,
            requestCid: claim.canonicalRequestCid,
            execute: async () => { throw new Error('EffectResent'); },
          });
          assert.equal(replay.claimed, false);
        }
        assert.equal(physicalSends, 2);
        await assert.rejects(issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: Object.freeze({}),
        }), /Foreign Effect computation Preview/u);
        await assert.rejects(issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: foreignAdmittedPreview,
        }), {code: 'MoonBitHostFailure'});
        const issuedSet = await issueAuthorizedEffectSetReceipt({
          ledger: effectLedger, members: [{rowOwners, replayed: true}],
          preview: applyPreview, commonMoon: moon,
          authorizeEvidenceRead: async () => true,
          limits: publicationLimits,
          publicationPreview: admittedPreview,
        });
        assert.equal(issuedSet.members.length, 1);
        const memberRows = JSON.parse(issuedSet.members[0].wire).rows;
        assert.equal(memberRows.length, 2);
        assert.deepEqual(memberRows.map(row => row.row_preview_cid),
          previewBody.effects[0].row_order);
        assert.equal(memberRows.every(row =>
          typeof row.outcome_receipt_cid === 'string'), true);
        const publicationOptions = {
          execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger: effectLedger, issuedSet,
          request: {
            namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
            publicationPolicyCid: cid('e'),
            publicationTargetCid: cid('f'),
            requestedAt: '2026-09-24T00:00:01.000Z',
          },
          attempt: {attemptId: 'effect-compute-attempt',
            fenceCid: cid('0'), externalIdempotencyKey: undefined,
            startedAt: '2026-09-24T00:00:02.000Z'},
          contractLimits: publicationLimits,
          now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
        };
        const published = await publishCompletedEffectfulRun(
          publicationOptions);
        assert.equal(published.publication.committed, true);
        assert.equal(published.publication.state, 'succeeded');
        const indexBody = JSON.parse(published.publication.index.wire);
        const finalReceipt = await store.readPublicationContract(
          indexBody.run_receipt_cid, 'run_receipt');
        assert.equal(JSON.parse(finalReceipt.wire)
          .effect_set_apply_receipt_cid, issuedSet.set.identity);
        committedPublicationKey = {
          namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
          runDefinitionCid: runDefinitionContract.identity,
        };
        assert.notEqual(await store.inspectCommittedIndex(
          committedPublicationKey), undefined);
        const replay = await publishCompletedEffectfulRun(
          publicationOptions);
        assert.equal(replay.publication.idempotent, true);
        assert.equal(physicalSends, 2);
      } finally {
        if (committedPublicationKey !== undefined) {
          assert.equal((await store.retireCommittedResult(
            committedPublicationKey,
            storedResults.definitions[0].identity,
          )).cleanup.status().pending, false);
          const retired = await store.retireCommittedPublicationMetadata(
            committedPublicationKey, '2026-09-24T00:00:04.000Z',
          );
          assert.equal(retired.deleted, true);
        } else if (sourceHoldingCid !== undefined) {
          assert.equal((await store.retirePhysicalHolding(
            sourceHoldingCid)).deleted, true);
        }
        if (sourcePayload?.prepared.status().pending === true) {
          await sourcePayload.prepared.release();
        }
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramEffectPreviewPlanTerminal(
          previewInputs, 0, 10, 100)),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramCheckEffectPreviewTargetGuards(
          previewInputs, [], [], 0, 1)),
      {code: 'MoonBitHostFailure'});
    } finally {
      effectLedger?.close();
      if (storedResults !== undefined) {
        await releaseCompletedRunPreparedPayloads(storedResults, control);
        if (committedPublicationKey !== undefined) {
          assert.equal(store.status().storedBytes, 0);
          assert.equal(store.status().objectCount, 0);
        }
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('owned update Plan matches approved rows and rejects altered intent',
  async t => {
    const memberIds = ['save', 'save_again'];
    const {document, environment, mappingCid} = await effectFixture({
      writeKind: 'update', memberIds,
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared),
      effectParametersCid(prepared),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = moon.clientProgramAdmitEffectPublication(
      prepared, ...evidence);
    assert.ok(admission);
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'namespace-a-scope', 'update-effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    const execution = await runCapturedEffectComputation(owned);
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'update-plan-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const localEvidenceContext = admittedLocalEffectEvidenceContext(
      control, prepared, evidence, definition, invocation, observation);
    const physicalStore = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
      privateEvidenceKey: Buffer.alloc(32, 4),
    }, control);
    let commitCount = 0;
    let shareCount = 0;
    let writerCount = 0;
    let releaseShare;
    const shareGate = new Promise(resolve => { releaseShare = resolve; });
    const lostShareReply = new Error('LostEffectSourceShareReply');
    const store = Object.freeze({...physicalStore,
      createPreparedObjectWriter(...args) {
        writerCount++;
        return physicalStore.createPreparedObjectWriter(...args);
      },
      async commitPhysicalHolding(...args) {
        commitCount++;
        return physicalStore.commitPhysicalHolding(...args);
      },
      async sharePhysicalHolding(...args) {
        shareCount++;
        const result = await physicalStore.sharePhysicalHolding(...args);
        if (shareCount === 1) {
          await shareGate;
          throw lostShareReply;
        }
        return result;
      },
    });
    let storedResults, inputs, privateHoldingCid;
    const sourcePayloads = [];
    const sourceHoldings = [];
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control,
        runDefinition: control.admit('run_definition',
          moon.strategyPublicationContractJson(definition),
          publicationLimits),
        invocation: control.admit('run_invocation',
          moon.strategyPublicationContractJson(invocation),
          publicationLimits),
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
      const invocationContract = control.admit('run_invocation',
        moon.strategyPublicationContractJson(invocation),
        publicationLimits);
      const sourceSet = await preparePinnedEffectSourceSet({
        moon, checkedOwner: prepared, execution, inputs,
        maxMembers: 2, maxGroupingWork: 3,
        limits: moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits)),
        store, maxBytes: outputLimits.maxWireBytes, control,
        invocation: invocationContract, retention,
        sourceBindingCid: cid('c'),
        contractLimits: publicationLimits,
        localEvidenceContext,
      });
      sourcePayloads.push(...sourceSet.payloads);
      assert.notEqual(sourcePayloads[0].summary.artifact.identity,
        storedResults.artifacts[0].identity);
      const requestScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'two-effect-request', 128));
      const previewFor = (values, targets = values.map((_, index) =>
        index + 1)) => effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        sourcePayloads[0].summary.artifact.identity, 'update', values,
        targets, memberIds, memberIds.map((_, index) =>
          cid(String(index))), requestScope);
      const preview = previewFor([1, 2]);
      const alternateScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'two-effect-request-alternate', 128));
      const alternatePreview = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        sourcePayloads[0].summary.artifact.identity, 'update', [1, 2],
        [1, 2], memberIds, memberIds.map((_, index) =>
          cid(String(index))), alternateScope);
      assert.equal(JSON.parse(preview.wire).effect_preview_cid,
        JSON.parse(alternatePreview.wire).effect_preview_cid);
      assert.notEqual(JSON.parse(preview.wire).effects[0].changes[0]
        .row_idempotency_key,
      JSON.parse(alternatePreview.wire).effects[0].changes[0]
        .row_idempotency_key);
      const runDefinitionContract = control.admit('run_definition',
        moon.strategyPublicationContractJson(definition),
        publicationLimits);
      const authoringContext = control.admitRunEvidence(
        'authoring_context',
        canonicalJson(JSON.parse(preview.wire).authoring_context),
        publicationLimits);
      const admittedPreview = control.admitEffectComputationPreview(
        preview.wire, runDefinitionContract, authoringContext,
        publicationLimits);
      privateHoldingCid = control.effectPrivateEvidenceBinding(
        admittedPreview, store.storeAuthorityCid).holdingCid;
      assert.throws(() => preparePinnedEffectSourceHoldings({
        sources: {...sourceSet}, store, control, preview: admittedPreview,
        invocation: invocationContract,
      }), {message: 'InvalidEffectSourceSetOwner'});
      assert.equal(commitCount + shareCount, 0);
      const holdingOwner = preparePinnedEffectSourceHoldings({
        sources: sourceSet, store, control, preview: admittedPreview,
        invocation: invocationContract,
      });
      sourceHoldings.push(...holdingOwner.holdings);
      assert.equal(commitCount + shareCount, 0);
      const firstCommit = holdingOwner.commit();
      const joinedCommit = holdingOwner.commit();
      assert.equal(firstCommit, joinedCommit);
      releaseShare();
      const settled = await Promise.allSettled([firstCommit, joinedCommit]);
      assert.ok(settled.every(value => value.status === 'rejected' &&
        value.reason === lostShareReply));
      assert.equal(commitCount, 1);
      assert.equal(shareCount, 1);
      for (const holding of sourceHoldings) {
        assert.deepEqual(await store.inspectPhysicalHolding(holding.holdingCid),
          holding.record);
      }
      const writersBeforeRetry = writerCount;
      const bytesBeforeRetry = store.status().storedBytes;
      assert.equal(await holdingOwner.commit(), holdingOwner.holdings);
      assert.equal(commitCount, 2);
      assert.equal(shareCount, 2);
      assert.equal(writerCount, writersBeforeRetry);
      assert.equal(store.status().storedBytes, bytesBeforeRetry);
      await assert.rejects(commitPinnedEffectSourceHolding({
        payload: sourcePayloads[0], store, control,
        preview: admittedPreview, memberIndex: 1,
        invocation: invocationContract, shareFromHoldingCid: cid('9'),
      }), {code: 'PublicationPhysicalHoldingUnavailable'});
      assert.notEqual(sourceHoldings[0].holdingCid,
        sourceHoldings[1].holdingCid);
      assert.equal(sourceHoldings[0].localManifest,
        sourceHoldings[1].localManifest);
      const duplicateIdentity = JSON.parse(preview.wire);
      duplicateIdentity.effects[1].effect_identity_cid =
        duplicateIdentity.effects[0].effect_identity_cid;
      assert.throws(() => checked(moon.strategyEffectPreviewIdentities(
        canonicalJson(duplicateIdentity), 20000, 1000, 20)),
      {code: 'MoonBitHostFailure'});
      const previewLimits = moon.clientProgramEffectPreviewInputLimits(
        20000, 1000, 20, 1000, 100, 20000, 1000, 20,
        2, 2, 100, 100);
      const foreignOwned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        bound, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(foreignOwned);
      const foreignExecution = await runCapturedEffectComputation(
        foreignOwned);
      try {
        assert.equal(foreignExecution.status, 'host-tasks-completed');
        const foreignInputs = checked(moon.clientProgramPinEffectSources(
          foreignOwned, 2));
        try {
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              owned, foreignInputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              foreignOwned, inputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
        } finally {
          assert.equal(moon.clientProgramReleaseEffectInputs(
            foreignInputs), true);
        }
      } finally {
        await foreignExecution.close();
        assert.equal(foreignExecution.cleanupPending(), false);
      }
      const conflicting = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        storedResults.artifacts[0].identity, 'update', [1, 2],
        [1, 2], memberIds, [cid('0'), cid('0')]);
      assert.throws(() => checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, conflicting.wire,
          conflicting.authoringCid, previewLimits)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0,
          canonicalJson(duplicateIdentity), preview.authoringCid,
          previewLimits)),
      {code: 'MoonBitHostFailure'});
      const previewInputs = checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, preview.wire,
          preview.authoringCid, previewLimits));
      const checkCurrent = ({sources = [cid('c'), cid('c')],
        contracts = [mappingCid, mappingCid],
        capabilities = [cid('d'), cid('d')],
        authorities = [cid('e'), cid('e')]} = {}) => checked(
        moon.clientProgramCheckEffectPreviewCurrentBindings(
          previewInputs, sources, contracts, capabilities, authorities,
          2, 8));
      assert.doesNotThrow(() => checkCurrent());
      const capability = (evidence = cid('d'), route = 0,
        reconciliation = 1) => checked(
        moon.clientProgramEffectApplyCapabilityFromCodes(
          evidence, route, 0, 0, true, true, 2, reconciliation));
      const selectedRoutes = [capability(), capability()];
      assert.equal(moon.clientProgramEffectApplyCapabilityIdempotencyMode(
        selectedRoutes[0]), 'unavailable');
      assert.equal(moon.clientProgramEffectApplyCapabilityReconciliationMode(
        selectedRoutes[0]), 'manual');
      const checkRoutes = routes => checked(
        moon.clientProgramCheckEffectPreviewCapabilities(
          previewInputs, routes, 2, 2));
      assert.doesNotThrow(() => checkRoutes(selectedRoutes));
      assert.throws(() => checkRoutes([selectedRoutes[0]]),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('f')),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('d'), 1),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes([capability(cid('d'), 0, 2),
        selectedRoutes[1]]), {code: 'MoonBitHostFailure'});
      const riskFor = (claims, previewCid =
        JSON.parse(preview.wire).effect_preview_cid) => {
        const body = {
          version: 'actql-effect-risk-acceptance/0.1',
          issuer_kind: 'policy', issuer_evidence_cid: cid('a'),
          policy_cid: cid('a'), decision: 'allow',
          effect_preview_cid: previewCid,
          review_projection_cid: cid('a'), authority_scope_cid: cid('e'),
          validity_evidence_cid: cid('a'), claims,
          authentication_evidence_cid: cid('a'),
        };
        return canonicalJson({...body,
          self_cid: `sha256:${createHash('sha256')
            .update(canonicalJson(body)).digest('hex')}`});
      };
      const admittedRisk = wire => checked(
        moon.clientProgramAdmitEffectRiskAcceptanceBody(
          wire, 8192, 256, 12));
      const risk = admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted']));
      const unsignedRisk = JSON.parse(riskFor(
        ['effect_scope_approved', 'partial_application_accepted']));
      delete unsignedRisk.self_cid;
      delete unsignedRisk.authentication_evidence_cid;
      assert.equal(moon.clientProgramEffectRiskUnsignedPayloadCid(risk),
        `sha256:${createHash('sha256')
          .update(canonicalJson(unsignedRisk)).digest('hex')}`);
      const checkRisk = (body, {
        projection = cid('a'), authority = cid('e'), policy = cid('a'),
        validity = cid('a'), issuer = cid('a'), authentication = cid('a'),
        issuerKind = 'policy', decision = 'allow',
        requirePartialApplication = false,
      } = {}) => checked(
        moon.clientProgramCheckEffectRiskAcceptanceBody(
          previewInputs, body, projection, authority,
          policy, validity, issuer, authentication,
          issuerKind, decision, requirePartialApplication));
      assert.doesNotThrow(() => checkRisk(risk));
      assert.doesNotThrow(() => checkRisk(risk,
        {requirePartialApplication: true}));
      // D2.multi-delegate-deferred: two members, [effect_scope_approved]
      // alone is admissible unless the Host policy requires the risk claim.
      const scopeOnlyRisk = admittedRisk(riskFor(['effect_scope_approved']));
      assert.doesNotThrow(() => checkRisk(scopeOnlyRisk));
      // D2.host-required-claim: the Host-declared requirement is enforced.
      assert.throws(() => checkRisk(scopeOnlyRisk,
        {requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(admittedRisk(riskFor(
        ['partial_application_accepted']))), {code: 'MoonBitHostFailure'});
      for (const field of ['projection', 'authority', 'policy', 'validity',
        'issuer', 'authentication']) {
        assert.throws(() => checkRisk(risk, {[field]: cid('f')}),
          {code: 'MoonBitHostFailure'});
      }
      assert.throws(() => checkRisk(risk, {issuerKind: 'human'}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(risk, {decision: 'approved'}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted'],
        cid('f')))), {code: 'MoonBitHostFailure'});
      assert.throws(() => admittedRisk(riskFor(
        ['effect_scope_approved', 'partial_application_accepted'])
        .replace('"decision":"allow"', '"decision":"approved"')),
      {code: 'MoonBitHostFailure'});
      const checkKeys = keys => checked(
        moon.clientProgramCheckEffectPreviewApplyKeys(
          previewInputs, requestScope, keys, 4, 10));
      assert.doesNotThrow(() => checkKeys(preview.keys));
      assert.throws(() => checked(
        moon.clientProgramCheckEffectPreviewApplyKeys(
          previewInputs, requestScope, preview.keys, 4, 5)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkKeys(preview.keys.slice(0, 1)),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkKeys(preview.keys.map(rows =>
        [rows[1], rows[0]])), {code: 'MoonBitHostFailure'});
      const foreignScope = checked(moon.strategyEffectLogicalRequestScope(
        cid('e'), 'foreign-request', 128));
      const foreignKey = checked(moon.strategyEffectDispatchKey(
        foreignScope, JSON.parse(preview.wire).effect_preview_cid,
        canonicalJson(1), 128, 8, 3));
      assert.throws(() => checkKeys([
        [foreignKey, preview.keys[0][1]], preview.keys[1],
      ]), {code: 'MoonBitHostFailure'});
      const progressRoot = join(directory, 'effect-ledger');
      await mkdir(progressRoot);
      const openProgress = () => openEffectLedger({moon,
        root: progressRoot, authorityScopeCid: cid('e'),
        callerRequestId: 'two-effect-request', maxEntryBytes: 4096});
      const effect = runtimeCore(moon).effectApplicationControl;
      const progressMembers = JSON.parse(preview.wire).effects.map(
        (member, memberIndex) => ({claims: member.changes.map(
          (change, rowIndex) => {
            const correlation = canonicalJson(change.target_row_identity);
            const key = preview.keys[memberIndex][rowIndex];
            const locator = effect.logicalItemLocator(
              requestScope, 'program-1', 'node-1', member.effect_id,
              correlation, 64, 128, 8, 3);
            const requestPath = `/effect/${member.effect_id}/${rowIndex}`;
            const requestBody = canonicalJson({
              row_preview_cid: change.row_preview_cid,
            });
            const canonicalRequestCid = `sha256:${createHash('sha256')
              .update(canonicalJson({method: 'PATCH', path: requestPath,
                body: requestBody})).digest('hex')}`;
            const intentFingerprintCid = change.row_preview_cid;
            const basis = effect.ledgerBasis(
              requestScope, locator, key, cid('6'),
              member.effect_member_preview_cid, intentFingerprintCid,
              canonicalRequestCid, cid('0'), 'unavailable', cid('1'), cid('2'));
            return {scope: requestScope, locator, key, basis,
              intentFingerprintCid, canonicalRequestCid,
              requestPath, requestBody};
          })}));
      const ready = ledger => {
        const frontier = ledger.frontierFromCapturedHeads(
          previewInputs, progressMembers, 64);
        return Array.from({length: effect.setFrontierReadyCount(frontier)},
          (_, index) => [effect.setFrontierReadyMember(frontier, index),
            effect.setFrontierReadyRow(frontier, index)]);
      };
      assert.throws(() => checkCurrent({capabilities: [cid('d')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({sources: [cid('c'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({contracts: [mappingCid, cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({capabilities: [cid('d'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({authorities: [cid('e'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const planLimits = {
        maxFields: 10, maxWork: 100, maxBytes: 20000,
        maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000,
      };
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0, limits,
        planLimits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.match(verified.logicalCid, /^sha256:[0-9a-f]{64}$/);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), true);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 1), false);
      const secondChunks = [];
      const second = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 1, limits,
        planLimits,
        onChunk: async chunk => { secondChunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(secondChunks.join('')),
        [{id: 1}, {id: 2}]);
      assert.notEqual(second.proof, verified.proof);
      assert.doesNotThrow(() => checked(
        moon.clientProgramCheckEffectPlanProofs(
          previewInputs, [second.proof, verified.proof], 2, 4)));
      const guardRows = JSON.parse(preview.wire).effects.flatMap(member =>
        member.changes.map(change => change.row_preview_cid));
      const preflight = ({proofs = [second.proof, verified.proof],
        sources = [cid('c'), cid('c')],
        contracts = [mappingCid, mappingCid],
        capabilities = [cid('d'), cid('d')],
        authorities = [cid('e'), cid('e')],
        observedRows = guardRows,
        guardVersions = guardRows.map(() => cid('6')),
        routes = selectedRoutes, riskBody = risk,
        requirePartialApplication = false,
        keys = preview.keys} = {}) => {
        const result = moon.clientProgramCheckEffectApplyPreflight(
          previewInputs, proofs, sources, contracts, capabilities,
          authorities, observedRows, guardVersions, routes,
          riskBody ?? undefined, requirePartialApplication,
          cid('a'), cid('e'), cid('a'), cid('a'), cid('a'), cid('a'),
          'policy', 'allow', requestScope, keys, 2, 4, 4, 100);
        return checked(result);
      };
      assert.doesNotThrow(() => preflight());
      const recoveryPreview = moon.clientProgramEffectPreviewLedgerIdentity(
        previewInputs);
      const recoveryRoot = join(directory, 'recovered-preflight-ledger');
      await mkdir(recoveryRoot);
      const recoveryLedger = openEffectLedger({moon, root: recoveryRoot,
        authorityScopeCid: cid('e'), callerRequestId: 'two-effect-request',
        maxEntryBytes: 4096});
      let recoveryGuards;
      try {
        // Missing durable row heads cannot waive target validation. Build
        // the proof from real prepared entries, without claiming or sending.
        assert.throws(() => recoveryLedger.recoveredTargetGuards(
          recoveryPreview, progressMembers, 64));
        recoveryLedger.prepareSetIntents(recoveryPreview, progressMembers, 64);
        recoveryGuards = recoveryLedger.recoveredTargetGuards(
          recoveryPreview, progressMembers, 64);
      } finally {
        recoveryLedger.close();
      }
      const recoveredPreflight = ({sources = [cid('c'), cid('c')],
        observedRows = guardRows,
        guardVersions = guardRows.map(() => cid('6')),
        keys = preview.keys} = {}) => checked(
        moon.clientProgramCheckRecoveredEffectApplySemantics(
          recoveryPreview, recoveryGuards,
          sources, [mappingCid, mappingCid], [cid('d'), cid('d')],
          [cid('e'), cid('e')], observedRows, guardVersions,
          selectedRoutes, risk ?? undefined, false,
          cid('a'), cid('e'), cid('a'), cid('a'),
          cid('a'), cid('a'), 'policy', 'allow', requestScope, keys,
          2, 4, 4, 100));
      assert.doesNotThrow(() => recoveredPreflight());
      assert.throws(() => recoveredPreflight({
        sources: [cid('c'), cid('f')],
      }), {code: 'MoonBitHostFailure'});
      assert.throws(() => recoveredPreflight({
        guardVersions: guardRows.map(() => cid('9')),
      }), {code: 'MoonBitHostFailure'});
      const runEvidence = evidence.slice(0, 3).map((value, index) =>
        control.admitRunEvidence(
          ['bound_invocation_template', 'prepared_invocation',
            'run_authorization'][index],
          moon.strategyRunEvidenceJson(value), publicationLimits));
      const compiledPlan = control.admit('compiled_plan',
        moon.strategyPublicationContractJson(evidence[3]),
        publicationLimits);
      const runAdmission = control.admitCheckedClientEffectRunPublication(
        prepared, ...runEvidence, compiledPlan);
      const normalizationJournal = control.sealRunEvidence(
        'normalization_journal', JSON.stringify({
          version: 'actql-normalization-journal/0.1',
          rule_catalog_cid: cid('1'), entries: [],
        }), publicationLimits);
      const computation = await issueCompletedEffectfulComputationEvidence({
        execution, store, storedResults, control, admission: runAdmission,
        runDefinition: runDefinitionContract,
        invocation: invocationContract,
        observation: control.admitRunEvidence('observation_set',
          moon.strategyRunEvidenceJson(observation), publicationLimits),
        normalizationJournal, authoringContext,
        receiptEvidence: {bindings: [], sourceEvidence: [],
          modelEvidence: [], barrierAttemptReceiptCids: []},
        captureEvidence: {pendingSourceStateAdvances: [],
          modelEvidence: []},
        preview: admittedPreview,
        plans: [{name: memberIds[0], wire: chunks.join('')},
          {name: memberIds[1], wire: secondChunks.join('')}],
        effectSourceHoldings: sourceHoldings,
        connectorRecovery: [],
        contractLimits: publicationLimits,
      });
      const captured = JSON.parse(computation.capturedRun.wire);
      assert.deepEqual(Object.keys(captured.effect_context
        .effect_source_holding_cids).sort(), memberIds);
      assert.deepEqual(Object.keys(captured.effect_context
        .result_artifacts), ['answer']);
      assert.deepEqual(memberIds.map(id => captured.effect_context
        .effect_source_artifacts[id].source_result), ['rows', 'rows']);
      assert.throws(() => preflight({proofs: [verified.proof]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({sources: [cid('c'), cid('f')]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({observedRows: [cid('1')]}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({routes: [selectedRoutes[0]]}),
        {code: 'MoonBitHostFailure'});
      // D2.multi-allow / D2.no-contract-floor: an account allow carries no
      // risk body and the two-member set passes whole-set preflight.
      // `null` means the Host holds no risk body (passed as absent).
      assert.doesNotThrow(() => preflight({riskBody: null}));
      assert.doesNotThrow(() => preflight({riskBody: scopeOnlyRisk}));
      // D2.host-required-claim: only a Host-declared policy requires it.
      assert.throws(() => preflight({riskBody: null,
        requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({riskBody: scopeOnlyRisk,
        requirePartialApplication: true}), {code: 'MoonBitHostFailure'});
      assert.doesNotThrow(() => preflight({requirePartialApplication: true}));
      assert.throws(() => preflight({riskBody: admittedRisk(riskFor(
        ['effect_scope_approved'], cid('f')))}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight({keys: preview.keys.slice(0, 1)}),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const altered = previewFor([1, 99]);
      const alteredInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, altered.wire,
        altered.authoringCid, previewLimits));
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, alteredInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        alteredInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const partial = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: alteredInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { partial.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(partial.length, 1);
      const swapped = previewFor([1, 2], [2, 1]);
      const swappedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, swapped.wire,
        swapped.authoringCid, previewLimits));
      const swappedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: swappedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { swappedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(swappedChunks, []);
      const omitted = previewFor([]);
      const omittedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, omitted.wire,
        omitted.authoringCid, previewLimits));
      const omittedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: omittedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { omittedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(omittedChunks, []);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
      // Explicit Host account for this Effect commit: allow the Effect
      // operation on the Host-derived connection/resource. No risk claim is
      // fabricated.
      const effectAuthorization = {
        gate: await fixtureAuthorization([accountEntry('crm-effect',
          'allow', {connection: 'crm', resource: 'Account',
            operation: 'effect'}),
        accountEntry('crm-target-read', 'allow', {connection: 'crm',
          resource: 'Account', operation: 'read'})]),
        scopes: [{connection: 'crm', resource: 'Account'},
          {connection: 'crm', resource: 'Account'}],
      };
      const applyOptions = {
        moon, capturedInputs: previewInputs, members: progressMembers,
        maxFrontierWork: 64,
        refreshPreflight: async ({preflight}) => preflight,
        authorization: effectAuthorization,
        preflight: {
          proofs: [second.proof, verified.proof],
          sources: [cid('c'), cid('c')],
          contracts: [mappingCid, mappingCid],
          capabilities: [cid('d'), cid('d')],
          authorities: [cid('e'), cid('e')],
          observedRows: guardRows,
          guardVersions: guardRows.map(() => cid('6')),
          routes: selectedRoutes, risk,
          reviewProjectionCid: cid('a'),
          authorityScopeCid: cid('e'), policyCid: cid('a'),
          validityCid: cid('a'), issuerCid: cid('a'),
          authenticationCid: cid('a'), issuerKind: 'policy',
          decision: 'allow', requestScope, keys: preview.keys,
          maxMembers: 2, maxRows: 4, maxFootprintWork: 4,
          maxWork: 100,
        },
      };
      const firstProgress = openProgress();
      try {
        assert.deepEqual(ready(firstProgress), [[0, 0], [1, 0]]);
        // Effect commit is protected: no Host gate, no dispatch.
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress, authorization: undefined,
          dispatchRow: () => assert.fail('unauthorized commit sent a row'),
        }), {code: 'EffectApplyAuthorizationRequired'});
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          authorization: {...effectAuthorization,
            gate: await fixtureAuthorization([accountEntry('read-only',
              'allow', {operation: 'read'})])},
          bindDispatch: () => assert.fail('no-match commit bound dispatch'),
        }), error => error.code === 'ExecutionAuthorizationDenied' &&
          error.authorization.boundary === 'effect_commit' &&
          error.authorization.tuple.operation === 'effect');
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          preflight: {...applyOptions.preflight,
            sources: [cid('c'), cid('f')]},
          bindDispatch: () => assert.fail('stale preflight bound dispatch'),
        }), {code: 'MoonBitHostFailure'});
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          dispatchRow: async () => {},
        }), {code: 'EffectApplyDidNotAdvance'});
        for (const member of progressMembers) {
          for (const claim of member.claims) {
            assert.equal(effect.ledgerEntryStateCode(
              firstProgress.currentAdmitted(
                effect.logicalItemLocatorCid(claim.locator))), 0);
          }
        }
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: firstProgress,
          dispatchRow: ({memberIndex, rowIndex, claim}) => {
            assert.deepEqual([memberIndex, rowIndex], [0, 0]);
            assert.equal(firstProgress.claimDispatch(claim).claimed, true);
            throw new Error('LostEffectResponse');
          },
        }), {message: 'LostEffectResponse'});
        assert.deepEqual(ready(firstProgress), [[1, 0]]);
      } finally {
        firstProgress.close();
      }
      const reopenedProgress = openProgress();
      try {
        assert.deepEqual(ready(reopenedProgress), [[1, 0]]);
        assert.equal(reopenedProgress.claimDispatch(
          progressMembers[0].claims[0]).claimed, false);
      } finally {
        reopenedProgress.close();
      }
      const applyPreview = effect.admitPreviewIdentity(
        preview.wire, JSON.parse(preview.wire).run_identity_cid,
        preview.authoringCid, requestScope, preview.keys,
        20000, 1000, 20);
      const seenRequests = [];
      const endpoint = createServer(async (request, response) => {
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        seenRequests.push({method: request.method, path: request.url,
          body: Buffer.concat(chunks).toString('utf8')});
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(canonicalJson({ok: true}));
      });
      await new Promise(resolve => endpoint.listen(0, '127.0.0.1', resolve));
      t.after(() => new Promise(resolve => endpoint.close(resolve)));
      const sendRow = (ledger, claim) => captureClaimedEffectResponse({
        ledger, claim, requestCid: claim.canonicalRequestCid,
        execute: async () => {
          const reply = await fetch(
            `http://127.0.0.1:${endpoint.address().port}` +
              claim.requestPath,
            {method: 'PATCH', body: claim.requestBody});
          return {observation: {useCid: cid('4'),
            statusCode: reply.status,
            body: Buffer.from(await reply.arrayBuffer())}};
        },
      });
      const beforeProjection = openProgress();
      try {
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: beforeProjection,
          dispatchRow: async ({memberIndex, rowIndex, claim}) => {
            assert.deepEqual([memberIndex, rowIndex], [1, 0]);
            assert.equal((await sendRow(beforeProjection, claim)).claimed,
              true);
            throw new Error('CrashAfterSavedEffectResponse');
          },
        }), {message: 'CrashAfterSavedEffectResponse'});
        assert.equal(seenRequests.length, 1);
      } finally {
        beforeProjection.close();
      }
      const resumedProgress = openProgress();
      try {
        const possible = progressMembers[0].claims[0];
        const replay = await captureClaimedEffectResponse({
          ledger: resumedProgress, claim: possible,
          requestCid: possible.canonicalRequestCid,
          execute: async () => { throw new Error('UnknownRowResent'); },
        });
        assert.equal(replay.claimed, false);
        const savedClaim = progressMembers[1].claims[0];
        const saved = resumedProgress.readClaimedResponse(savedClaim);
        assert.equal(saved.statusCode, 200);
        assert.equal(saved.responseBytes.toString('utf8'),
          canonicalJson({ok: true}));
        const savedReplay = await captureClaimedEffectResponse({
          ledger: resumedProgress, claim: savedClaim,
          requestCid: savedClaim.canonicalRequestCid,
          execute: async () => { throw new Error('SavedRowResent'); },
        });
        assert.equal(savedReplay.claimed, false);
        assert.deepEqual(ready(resumedProgress), []);
        resumedProgress.recordAdmittedRowOutcome({
          claim: savedClaim, preview: applyPreview, memberIndex: 1,
          previewRowIndex: 0,
          outcomeWire: canonicalJson({state: 'applied',
            result: {record_id: 'row-1'}}),
        });
        resumedProgress.commitAdmittedRowOutcome({
          claim: savedClaim, preview: applyPreview, memberIndex: 1,
          previewRowIndex: 0,
        });
        await assert.rejects(applyCapturedEffectSet({
          ...applyOptions, ledger: resumedProgress,
          bindDispatch: () => undefined,
        }), {code: 'InvalidEffectDispatchBinding'});
        assert.deepEqual(ready(resumedProgress), [[1, 1]]);
        let bindings = 0;
        const advanced = await applyCapturedEffectSet({
          ...applyOptions, ledger: resumedProgress,
          bindDispatch: ({members, subjectCid, decisions}) => {
            bindings++;
            assert.equal(subjectCid,
              JSON.parse(preview.wire).effect_preview_cid);
            assert.equal(Object.isFrozen(members), true);
            // This generation's commit decisions: dispatch for the sealed
            // Set, one per distinct Host tuple.
            assert.equal(Object.isFrozen(decisions), true);
            assert.ok(decisions.length > 0);
            for (const decision of decisions) {
              assert.equal(decision.action, 'dispatch');
              assert.equal(decision.boundary, 'effect_commit');
              assert.equal(decision.subjectCid, subjectCid);
              assert.equal(decision.tuple.operation, 'effect');
            }
            return async ({memberIndex, rowIndex, claim}) => {
              assert.equal(claim, members[memberIndex].claims[rowIndex]);
              assert.equal(memberIndex, 1);
              assert.deepEqual(ready(resumedProgress), [[1, rowIndex]]);
              const response = await sendRow(resumedProgress, claim);
              assert.equal(response.claimed, true);
              resumedProgress.recordAdmittedRowOutcome({
                claim, preview: applyPreview, memberIndex,
                previewRowIndex: rowIndex,
                outcomeWire: canonicalJson({state: 'applied',
                  result: {record_id: `row-${rowIndex + 1}`}}),
              });
              resumedProgress.commitAdmittedRowOutcome({
                claim, preview: applyPreview, memberIndex,
                previewRowIndex: rowIndex,
              });
            };
          },
        });
        assert.equal(bindings, 1);
        assert.equal(advanced.dispatched, 1);
        assert.deepEqual(ready(resumedProgress), []);
        assert.deepEqual(seenRequests, progressMembers[1].claims.map(
          claim => ({method: 'PATCH', path: claim.requestPath,
            body: claim.requestBody})));
        const settled = await applyCapturedEffectSet({
          ...applyOptions, ledger: resumedProgress,
          authorization: undefined, refreshPreflight: undefined,
          bindDispatch: () => assert.fail('settled rows bound a dispatcher'),
        });
        assert.equal(settled.status, 'applied');
        assert.equal(settled.dispatched, 0);
        const issued = await issueAuthorizedEffectSetReceipt({
          ledger: resumedProgress, preview: applyPreview,
          commonMoon: moon, authorizeEvidenceRead: async () => true,
          publicationPreview: admittedPreview,
          members: progressMembers.map(member => ({
            rowOwners: member.claims.map(claim => ({claim})),
            replayed: false,
          })),
          limits: publicationLimits,
        });
        assert.equal(JSON.parse(issued.set.wire).status,
          'unknown_outcome');
        assert.deepEqual(JSON.parse(issued.set.wire).effects.map(
          member => member.state), ['unknown', 'applied']);
        await assert.rejects(publishCompletedEffectfulRun({
          execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger: resumedProgress,
          issuedSet: issued,
          request: {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
            publicationPolicyCid: cid('e'),
            publicationTargetCid: cid('f'),
            requestedAt: '2026-09-24T00:00:01.000Z'},
          attempt: {attemptId: 'two-effect-attempt',
            fenceCid: cid('0'), externalIdempotencyKey: undefined,
            startedAt: '2026-09-24T00:00:02.000Z'},
          contractLimits: publicationLimits,
          now: () => '2026-09-24T00:00:03.000Z', signal: undefined,
        }), {code: 'EffectfulRunNeedsReconciliation'});
        assert.equal(await store.inspectCommittedIndex({namespaceId: 'namespace-a',
          authorityScopeCid: cid('a'),
          runDefinitionCid: runDefinitionContract.identity}), undefined);
        assert.ok(await store.inspectPhysicalHolding(privateHoldingCid));
        for (const holding of sourceHoldings) {
          assert.ok(await store.inspectPhysicalHolding(holding.holdingCid));
        }
      } finally {
        resumedProgress.close();
      }
      const releasedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => {
          releasedChunks.push(chunk);
          if (releasedChunks.length === 1) {
            assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
          }
        },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(releasedChunks.length, 1);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      const historicalProgress = openProgress();
      try {
        assert.deepEqual(ready(historicalProgress), []);
        assert.equal(historicalProgress.claimDispatch(
          progressMembers[1].claims[0]).claimed, false);
      } finally {
        historicalProgress.close();
      }
      assert.throws(() => checkKeys(preview.keys),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRoutes(selectedRoutes),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkRisk(risk),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent(),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => preflight(), {code: 'MoonBitHostFailure'});
    } finally {
      if (inputs !== undefined) {
        moon.clientProgramReleaseEffectInputs(inputs);
      }
      if (storedResults !== undefined) {
        await releaseCompletedRunPreparedPayloads(storedResults, control);
        if (privateHoldingCid !== undefined) {
          assert.equal((await store.retirePhysicalHolding(
            privateHoldingCid)).deleted, true);
        }
        for (const holding of sourceHoldings) {
          assert.equal((await store.retirePhysicalHolding(
            holding.holdingCid)).deleted, true);
        }
        for (const payload of sourcePayloads) {
          if (payload.prepared.status().pending) {
            await payload.prepared.release();
          }
        }
        assert.equal(store.status().storedBytes, 0);
        assert.equal(store.status().objectCount, 0);
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('Effect source set shares exact owners and retains failed cleanup',
  async t => {
    for (const distinctResults of [false, true]) {
      await t.test(distinctResults ? 'equal values, distinct Results' :
        'one Result, two members', async t => {
        const fixture = await effectFixture({writeKind: 'update',
          memberIds: ['first', 'second']});
        const document = JSON.parse(fixture.document);
        if (distinctResults) {
          document.stages[0].results.other = structuredClone(
            document.stages[0].results.rows);
          document.stages[0].effects.second.update.from.result = 'other';
        }
        const prepared = moon.clientProgramEffectPreparationReady(
          moon.clientProgramPrepareEffectComputationWithParameters(
            JSON.stringify(document), 'json', fixture.environment,
            undefined, []));
        assert.ok(prepared);
        const evidence = publicationEvidence(
          moon.clientProgramEffectDefinitionCid(prepared),
          effectParametersCid(prepared),
          moon.clientProgramEffectSemanticsCid(prepared),
          moon.clientProgramEffectEnvironmentCid(prepared));
        const admission = moon.clientProgramAdmitEffectPublication(
          prepared, ...evidence);
        const definition = checked(moon.strategyIssueRunDefinition(
          admission, 'namespace-a-scope', 'source-set-run', cid('c'),
          '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
          100000, 10000, 64));
        const observation = checked(moon.strategyRunEvidenceSeal(
          'observation_set', JSON.stringify({
            version: 'actql-observation-set/0.1',
            invocation_template_cid: moon.strategyRunEvidenceIdentity(
              evidence[0]), source_evidence_cids: [],
            captured_input_artifact_cids: [],
            consistency: 'no_external_sources', capture_started_at: null,
            capture_completed_at: null,
            replayability: {materialized: false,
              availability_evidence_cids: []}, data_policy_cid: cid('d'),
          }), 100000, 10000, 64));
        const invocation = checked(moon.strategyIssueRunInvocation(
          evidence[0], observation, 100000, 10000, 64));
        const bound = moon.clientProgramBindEffectRun(
          prepared, admission, definition);
        const registry = await readFile(new URL(
          '../../spec/dependencies/aoa-pipeline-registry.json',
          import.meta.url), 'utf8');
        const contract = JSON.parse(await readFile(new URL(
          '../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
        const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(bound,
          registry, JSON.stringify(contract.execution_contracts['REL.values']),
          1n, 0n, 0n, 0n);
        assert.ok(owned);
        const execution = await runCapturedEffectComputation(owned);
        const inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
        await mkdir(scratch, {recursive: true});
        const directory = await mkdtemp(join(scratch.pathname, 'source-set-'));
        t.after(() => rm(directory, {recursive: true, force: true}));
        const control = runtimeCore(moon).publicationControl;
        const physical = await openLocalPublicationStore({directory,
          storeAuthorityCid: cid('7'), capacityBytes: 1024 * 1024,
          maxObjectBytes: 100000, maxObjects: 10,
          maxContractNodes: 10000, maxContractDepth: 64,
        }, control);
        let writers = 0;
        let refuseRelease = false;
        const store = Object.freeze({...physical,
          createPreparedObjectWriter(...args) {
            writers++;
            const writer = physical.createPreparedObjectWriter(...args);
            return Object.freeze({...writer, async seal(...args) {
              const sealed = await writer.seal(...args);
              return Object.freeze({...sealed, prepared: Object.freeze({
                ...sealed.prepared,
                async release() {
                  if (refuseRelease) throw new Error('InjectedSourceRelease');
                  return sealed.prepared.release();
                },
              })});
            }});
          },
        });
        const retention = control.seal('result_retention_policy',
          JSON.stringify({version: 'actql-result-retention-policy/0.1',
            retention_contract_cid: cid('e'), effective_data_policy_cid: cid('d'),
            available_until: '2026-09-24T01:00:00.000Z',
            delete_by: '2026-09-24T02:00:00.000Z',
            extension_ceiling_at: '2026-09-24T03:00:00.000Z',
            metadata_retention_policy_cid: cid('f'),
            metadata_delete_by: '2026-09-24T04:00:00.000Z',
            clock_contract_cid: cid('0')}), publicationLimits);
        const issuedArguments = [];
        const issuerControl = Object.freeze({...control,
          issueSourceFreeLocalEffectResultArtifact(...args) {
            if (distinctResults && issuedArguments.length === 1) {
              // Equal Result values do not let the first preparation claim
              // the second Result's live export receipt.
              const foreign = [...issuedArguments[0]];
              foreign[6] = args[6];
              assert.throws(() => control
                .issueSourceFreeLocalEffectResultArtifact(...foreign),
              {code: 'MoonBitHostFailure'});
            }
            const issued = control.issueSourceFreeLocalEffectResultArtifact(
              ...args);
            issuedArguments.push(args);
            return issued;
          },
        });
        const options = {moon, checkedOwner: prepared, execution, inputs,
          maxMembers: 2, maxGroupingWork: 3,
          limits: moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits)),
          store, maxBytes: 100000, control: issuerControl,
          invocation: control.admit('run_invocation',
            moon.strategyPublicationContractJson(invocation), publicationLimits),
          retention, sourceBindingCid: cid('c'), contractLimits: publicationLimits,
          localEvidenceContext: admittedLocalEffectEvidenceContext(control,
            prepared, evidence, definition, invocation, observation),
        };
        try {
          await assert.rejects(preparePinnedEffectSourceSet({...options,
            maxGroupingWork: 0}), {message: 'EffectSourceGroupingLimit'});
          assert.equal(writers, 0);
          const sources = await preparePinnedEffectSourceSet(options);
          assert.equal(sources.payloads.length, distinctResults ? 2 : 1);
          assert.equal(issuedArguments.length, distinctResults ? 2 : 1);
          for (const args of issuedArguments) {
            // The receipt was released by exportPinnedEffectInput before
            // returning the prepared Store owner.
            assert.throws(() => control
              .issueSourceFreeLocalEffectResultArtifact(...args),
            {code: 'MoonBitHostFailure'});
          }
          assert.equal(writers, distinctResults ? 2 : 1);
          assert.equal(sources.members[0].payload.summary.logicalCid,
            sources.members[1].payload.summary.logicalCid);
          assert.equal(sources.members[0].payload ===
            sources.members[1].payload, !distinctResults);
          assert.equal(sources.members[0].payload.localManifest,
            sources.members[1].payload.localManifest);
          assert.deepEqual(Object.keys(JSON.parse(
            sources.members[0].payload.localManifest.wire).results),
          distinctResults ? ['other', 'rows'] : ['rows']);
          if (distinctResults) assert.notEqual(
            sources.members[0].payload.localResultDefinition.identity,
            sources.members[1].payload.localResultDefinition.identity);
          for (const payload of sources.payloads) await payload.prepared.release();
          if (distinctResults) {
            refuseRelease = true;
            let failure;
            try {
              await preparePinnedEffectSourceSet({...options,
                proposalLimits: {...previewPlanLimits, maxUtf16Units: 20000},
                onProposalRow(memberIndex) {
                  if (memberIndex === 1) throw new Error('SecondSourceFailed');
                }});
            } catch (error) { failure = error; }
            assert.equal(failure?.cleanupPending, true);
            assert.equal(failure.primaryFailure.message, 'SecondSourceFailed');
            assert.ok(physical.status().storedBytes > 0);
            const beforeRetry = writers;
            refuseRelease = false;
            assert.equal((await failure.cleanupHandle.retry()).pending, false);
            assert.equal(writers, beforeRetry);
          }
          assert.equal(physical.status().storedBytes, 0);
          assert.equal(physical.status().reservedBytes, 0);
        } finally {
          moon.clientProgramReleaseEffectInputs(inputs);
          await physical.close();
          await execution.close();
          assert.equal(execution.cleanupPending(), false);
        }
      });
    }
  });

async function verifySharedEffectSource({splitSource, expectedTask}) {
  const {document, environment} = await effectFixture({
    splitSource, splitEffectSource: 'middle',
  });
  const source = JSON.parse(document);
  const effectStage = source.stages[splitSource ? 1 : 0];
  effectStage.effects.save_again = structuredClone(effectStage.effects.save);
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(source), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
  const evidence = publicationEvidence(
    moon.clientProgramEffectDefinitionCid(prepared),
    effectParametersCid(prepared),
    moon.clientProgramEffectSemanticsCid(prepared),
    moon.clientProgramEffectEnvironmentCid(prepared));
  const admission = moon.clientProgramAdmitEffectPublication(
    prepared, ...evidence);
  assert.ok(admission);
  const definition = checked(moon.strategyIssueRunDefinition(
    admission, 'namespace-a-scope', 'two-effect-compute', cid('c'),
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
    100000, 10000, 64));
  const bound = moon.clientProgramBindEffectRun(
    prepared, admission, definition);
  assert.ok(bound);
  const [registry, contract] = await Promise.all([
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
      import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json',
      import.meta.url), 'utf8'),
  ]);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
    bound, registry, values, 1n, 0n, 0n, 0n);
  assert.ok(owned);
  assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 2);
  assert.throws(() => checked(moon.clientProgramPinEffectSources(
    owned, 2)), {code: 'MoonBitHostFailure'});
  const execution = await runCapturedInternalStrategy(
    moon.clientProgramLocalEffectHostRuntime(owned));
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.throws(() => checked(moon.clientProgramPinEffectSources(
      owned, 1)), {code: 'MoonBitHostFailure'});
    const expectedInventory = splitSource
      ? [[0, 'rows'], [1, 'rows'], [1, 'early']] : [[0, 'rows']];
    const inputs = checked(moon.clientProgramPinEffectSources(
      owned, Math.max(2, expectedInventory.length)));
    try {
      assert.deepEqual(Array.from({length:
        moon.clientProgramEffectLocalResultCount(inputs)}, (_, index) => {
        const result = moon.clientProgramEffectLocalResultAt(inputs, index);
        return [moon.clientProgramEffectLocalResultStage(result),
          moon.clientProgramEffectLocalResultName(result)];
      }), expectedInventory);
      assert.equal(moon.clientProgramEffectInputCount(inputs), 2);
      const first = moon.clientProgramEffectInputAt(inputs, 0);
      const second = moon.clientProgramEffectInputAt(inputs, 1);
      assert.ok(first);
      assert.ok(second);
      assert.notEqual(first, second);
      assert.equal(moon.clientProgramEffectInputsShareView(inputs, 0, 1),
        true);
      assert.equal(moon.clientProgramEffectInputTask(first), expectedTask);
      assert.equal(moon.clientProgramEffectInputTask(second), expectedTask);
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
      assert.equal(moon.clientProgramReleaseEffectInput(first), true);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), true);
      assert.equal(moon.clientProgramEffectInputsShareView(inputs, 0, 1),
        false);
      const chunks = [];
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const exported = await exportPinnedEffectInput({
        moon, execution, inputs, memberIndex: 1, limits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.deepEqual(exported.fields, ['id']);
      assert.equal(moon.clientProgramReleaseEffectInput(first), false);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 2)), {code: 'MoonBitHostFailure'});
    } finally {
      assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
    }
    assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), false);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
}

test('two Effect members hold one completed Result independently', async () => {
  await verifySharedEffectSource({splitSource: false, expectedTask: 0});
  await verifySharedEffectSource({splitSource: true, expectedTask: 4});
});

test('Effect sources retain exact physical producers across split Stages',
  async () => {
    for (const [splitEffectSource, expectedTask] of [
      ['consumer', 5], ['middle', 4], ['early', 3],
    ]) {
      const {document, environment} = await effectFixture({
        splitSource: true, splitEffectSource,
      });
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        document, 'json', environment, undefined, []);
      const prepared = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(prepared,
        `${splitEffectSource}: ${moon.clientProgramEffectPreparationIssueCode(outcome)}`);
      const evidence = publicationEvidence(
        moon.clientProgramEffectDefinitionCid(prepared),
        effectParametersCid(prepared),
        moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared));
      const admission = moon.clientProgramAdmitEffectPublication(
        prepared, ...evidence);
      assert.ok(admission);
      const definition = checked(moon.strategyIssueRunDefinition(
        admission, 'namespace-a-scope', 'split-effect-compute', cid('c'),
        '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
        100000, 10000, 64));
      const bound = moon.clientProgramBindEffectRun(
        prepared, admission, definition);
      assert.ok(bound);
      const [registry, contract] = await Promise.all([
        readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
          import.meta.url), 'utf8'),
        readFile(new URL('../../spec/contracts/actql-aoa.json',
          import.meta.url), 'utf8'),
      ]);
      const values = JSON.stringify(
        JSON.parse(contract).execution_contracts['REL.values']);
      const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        bound, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(owned);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 1)), {code: 'MoonBitHostFailure'});
      const execution = await runCapturedInternalStrategy(
        moon.clientProgramLocalEffectHostRuntime(owned));
      try {
        assert.equal(execution.status, 'host-tasks-completed',
          execution.failure?.stack);
        const expectedInventory = [[0, 'rows'], [1, 'rows'], [1, 'early'],
          ...(splitEffectSource === 'consumer' ? [[2, 'rows']] : [])];
        const pinned = moon.clientProgramPinEffectSources(
          owned, expectedInventory.length);
        assert.equal(pinned.$tag, 1,
          `${splitEffectSource}: ${pinned._0?.constructor?.name}`);
        const inputs = checked(pinned);
        try {
          assert.deepEqual(Array.from({length:
            moon.clientProgramEffectLocalResultCount(inputs)}, (_, index) => {
            const result = moon.clientProgramEffectLocalResultAt(inputs, index);
            return [moon.clientProgramEffectLocalResultStage(result),
              moon.clientProgramEffectLocalResultName(result)];
          }), expectedInventory);
          const input = moon.clientProgramEffectInputAt(inputs, 0);
          assert.ok(input);
          assert.equal(moon.clientProgramEffectInputTask(input), expectedTask);
          assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
          const chunks = [];
          const limits = moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits));
          for (let resultIndex = 0; resultIndex < expectedInventory.length;
            resultIndex++) {
            const dependencyChunks = [];
            await exportPinnedEffectLocalResult({
              moon, execution, inputs, resultIndex, limits,
              onChunk: async chunk => dependencyChunks.push(chunk),
            });
            assert.deepEqual(JSON.parse(dependencyChunks.join('')),
              [{id: 1}, {id: 2}],
              `retained dependency ${expectedInventory[resultIndex]}`);
          }
          const exported = await exportPinnedEffectInput({
            moon, execution, inputs, memberIndex: 0, limits,
            onChunk: async chunk => { chunks.push(chunk); },
          });
          assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
          assert.deepEqual(exported.fields, ['id']);
          assert.throws(() => checked(moon.clientProgramPinEffectSources(
            owned, 1)), {code: 'MoonBitHostFailure'});
        } finally {
          assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
        }
      } finally {
        await execution.close();
        assert.equal(execution.cleanupPending(), false);
      }
    }
  });

function admittedLocalEffectEvidenceContext(control, prepared, evidence,
  definition, invocation, observation) {
  const [template, preparedEvidence, authorization] = evidence
    .slice(0, 3).map((value, index) => control.admitRunEvidence(
      ['bound_invocation_template', 'prepared_invocation',
        'run_authorization'][index],
      moon.strategyRunEvidenceJson(value), publicationLimits));
  const plan = control.admit('compiled_plan',
    moon.strategyPublicationContractJson(evidence[3]), publicationLimits);
  return Object.freeze({
    admission: control.admitCheckedClientEffectRunPublication(
      prepared, template, preparedEvidence, authorization, plan),
    runDefinition: control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), publicationLimits),
    runInvocation: control.admit('run_invocation',
      moon.strategyPublicationContractJson(invocation), publicationLimits),
    observation: control.admitRunEvidence('observation_set',
      moon.strategyRunEvidenceJson(observation), publicationLimits),
  });
}

test('a supplied connector manifest is checked without any Mapping', async () => {
  const [document, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const base = JSON.parse(environmentBody);
  delete base.evidence_bundle_cid;
  const environment = changes => {
    const body = {...base, ...changes};
    const cid = machineCid(body);
    return moon.clientProgramCheckEnvironment(
      canonicalText({...body, evidence_bundle_cid: cid}), cid,
      false, false, true, false, false, false, false);
  };
  const withConnector = {};
  withFixtureConnector(withConnector, 'connector://crm/account');
  // A valid manifest, or none, still checks the Values Program.
  for (const changes of [{}, withConnector]) {
    const admitted = environment(changes);
    assert.ok(admitted);
    assert.ok(moon.clientProgramPrepareEffectFree(document, 'json', admitted));
  }
  // An invalid version, an entry without its Catalog and an unknown member
  // are refused at environment admission, before any Program is checked.
  const entry = withConnector.connector_manifest.connectors[0];
  for (const manifest of [
    {...withConnector.connector_manifest, version: 'definitely-invalid'},
    {connectors: [{...entry, connector_id: 'missing'}],
      version: 'actql-connectors/0.1'},
    {connectors: [{...entry, path: 'x'}], version: 'actql-connectors/0.1'},
  ]) {
    assert.equal(environment({...withConnector, connector_manifest: manifest}),
      undefined);
  }
});
