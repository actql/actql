// Explicit real-Node boundary for one registered 100-row source. Both choices
// use the same checked requirement; Broad includes its original residual.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {inspect} from 'node:util';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as app from '../../_build/js/release/build/physical_strategy_example/physical_strategy_example.js';
import {retainedCase, workloads} from './fixtures.mjs';
import {benchmarkEnvironment} from './environment.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {canonicalJson, contentCid} from '../../adapters/host-node/local-account-config.mjs';
import {createNodeAuthorizationGate} from '../../adapters/host-node/authorization.mjs';
import {prepareCapturedDuckDBSource, openCapturedDuckDBSource} from
  '../../adapters/host-node/captured-duckdb-source.mjs';
import {checked} from '../../adapters/host-common/runtime-result.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const text = path => readFile(join(root, path), 'utf8');
const nativeCapability = 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8';
const broadCapability = 'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89';

test('Node Native/Broad selection retains equivalent 100-row acquisition and residual obligations',
  {timeout: 60000}, async () => {
    const fixture = retainedCase(workloads[0], 'narrow', 100);
    const directory = await mkdtemp(join(tmpdir(), 'actql-node-acquisition-'));
    let captured;
    try {
      const database = join(directory, 'source.duckdb');
      await promisify(execFile)(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root});
      const adoptedText = await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json');
      const adopted = JSON.parse(adoptedText);
      const configuration = managedCaseConfiguration(fixture, {adoptedText}, database, directory);
      const body = JSON.parse(benchmarkEnvironment(fixture).text);
      const view = body.source_views[0];
      body.connector_capabilities = [{source_ref: 'connector://crm/main/r#v',
        source_contract_cid: view.contract_cid, source_view_contract_cid: view.contract_cid,
        read_mode: 'snapshot', capability_contract_cids: [nativeCapability, broadCapability].sort()}];
      // The public source-evidence boundary requires an explicit schema
      // snapshot. Bind it to this fixture's declared source contracts.
      body.schema_snapshots = [{source_ref: 'connector://crm/main/r#v',
        source_contract_cid: view.contract_cid, source_view_contract_cid: view.contract_cid,
        read_mode: 'snapshot', output_carrier: 'relation',
        carrier_schema_contract_cid: view.output.schema.cid,
        source_data_policy_cid: view.output.data_policy.cid, data_classification: 'unknown'}];
      delete body.evidence_bundle_cid;
      body.evidence_bundle_cid = contentCid(body);
      const environment = moon.clientProgramCheckEnvironment(canonicalJson(body),
        body.evidence_bundle_cid, false, false, true, false, false, false, false);
      assert(environment, 'NodeDiagnosticEnvironmentRejected');
      const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
        configuration.input.programText, 'json', environment, configuration.input.parameterText);
      const preparedProgram = moon.clientProgramPreparationReady(outcome);
      assert(preparedProgram, String(moon.clientProgramPreparationIssueCode(outcome)));
      const authorization = await createNodeAuthorizationGate({
        configuration: configuration.input.accountConfiguration,
        context: {principal: 'benchmark-diagnostic', contextCid: 'sha256:' + 'c'.repeat(64)}});
      const l = fixture.limits;
      const options = {moon, preparedProgram, registry: JSON.stringify(adopted.registry),
        values: JSON.stringify(adopted.values), fragment: JSON.stringify(adopted.fragment),
        ordered: JSON.stringify(adopted.ordered ?? JSON.parse(await text('spec/contracts/actql-aoa.json'))
          .execution_contracts['REL.derive.ordered']),
        database, schema: 'main', table: 'records',
        sourceAccess: {authorization, sourceRef: 'connector://crm/main/r#v',
          connection: database, resource: 'main.records'},
        transportLimits: {maxRows: l.sourceRows + l.intermediateRows + 1,
          maxCells: (l.sourceRows + l.intermediateRows) * l.maxColumns + 1,
          maxTransportBytes: l.representationBytes * 3, maxSqlBytes: 10000,
          maxParameters: l.maxColumns * 128, maxColumns: l.maxColumns,
          memoryBytes: l.executionMemoryBytes / 2, threads: 1,
          maxChunkRows: 512, maxChunkBytes: Math.min(l.batchBytes, l.representationBytes)}};
      const records = [];
      const refusals = [];
      for (const candidate of ['nativeQuery', 'broadQuery']) {
        const selectedOptions = {...options, acquisitionPlanning: {policy: 'priority',
          priority: [candidate, candidate === 'nativeQuery' ? 'broadQuery' : 'nativeQuery']}};
        const preparedSource = await prepareCapturedDuckDBSource(selectedOptions);
        assert.equal(preparedSource.selection.selectedCandidate, candidate);
        assert.equal(preparedSource.selection.reason, 'HostPreferred');
        assert.equal(preparedSource.selection.candidates.length, 2);
        const ledger = checked(app.applicationBoundedLedger(configuration.limits));
        try {
          captured = await openCapturedDuckDBSource({...selectedOptions, preparedSource, ledger});
        } catch (error) {
          console.error('NODE_ACQUISITION_REFUSAL:' + candidate, inspect(error, {depth: 10}));
          refusals.push(error);
          continue;
        }
        const observation = JSON.parse(captured.capture.document());
        assert.equal(observation.output.rows_cid, fixture.identity().rowsCid);
        assert.equal(observation.output.row_count, fixture.cardinalities.capture);
        assert.deepEqual(captured.acquisition.selection, preparedSource.selection);
        const beforeClose = moon.clientProgramMultiCapturedLedgerUsage(ledger);
        assert(beforeClose[1] > 0n && beforeClose[2] > 0n && beforeClose[5] > 0n);
        await captured.close();
        const afterClose = moon.clientProgramMultiCapturedLedgerUsage(ledger);
        for (const index of [5, 6, 7, 8]) assert.equal(afterClose[index], 0n);
        await captured.close();
        assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), afterClose);
        records.push({host: 'node', candidate, selection: preparedSource.selection,
          observation, beforeClose, afterClose});
        console.log('NODE_ACQUISITION_ACCEPTED:' + candidate);
        captured = undefined;
      }
      if (refusals.length) throw new AggregateError(refusals, 'NodeAcquisitionAcceptanceIncomplete');
      assert.equal(records[0].selection.requirementCid, records[1].selection.requirementCid);
      assert.deepEqual(records[0].observation.output, records[1].observation.output);
      await assert.rejects(prepareCapturedDuckDBSource({...options,
        acquisitionPlanning: {policy: 'estimatedLatency', candidates: {}}}),
      {code: 'InstalledSourceSelectionDeferred'});
    } catch (error) {
      // Fixed local fixture only; preserve the actual nested runtime refusal
      // rather than replacing it with a generic acquisition error.
      console.error(inspect(error, {depth: 6}));
      throw error;
    } finally {
      await captured?.close();
      await rm(directory, {recursive: true, force: true});
    }
  });
