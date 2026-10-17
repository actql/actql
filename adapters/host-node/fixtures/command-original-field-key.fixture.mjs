// Independent legacy field-target counter: the target is issued by the same
// actual RowRun ReferenceIssuer and retained source. No Ref appears in the
// authored Program, and no published target or Mapping is synthesized.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import {checked} from '../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../installed-row-source.mjs';
import {runCapturedEffectComputation} from '../entry.mjs';
import {canonical, cid, resource} from './file-listing-source.fixture.mjs';
import {moon, publicationEvidence} from './command-original-key.fixture.mjs';

export async function originalFieldCommandKeyFixture({duplicate = false, inputKey = true} = {}) {
  const read = path => readFile(new URL(`../../../${path}`, import.meta.url), 'utf8');
  const original = await read('src/query_integration/published_store_capture_wbtest.mbt');
  const literals = [...original.matchAll(/^\s*#\|(.+)$/gmu)].map(match => JSON.parse(match[1]));
  const commandEnvironment = literals.find(value => Array.isArray(value.command_contracts));
  assert(commandEnvironment);
  const base = JSON.parse(await read('spec/local-check-environment.json'));
  commandEnvironment.host_policy_profile = base.host_policy_profile;
  const schema = {id: {type: 'string', nullable: false}, value: {type: 'string', nullable: false},
    resource: {type: 'resource_ref', resource_kind: 'file', nullable: false}};
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'field-target-source', 'fixture', 'fixture/0.1', canonical({views: [{resource: 'rows', resource_kind: 'file',
      schema_wire: canonical(schema), schema_cid: cid(schema), facts_wire: '{}'}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const supplied = rowSourceCheckEnvironment(canonical(base), declared);
  const {evidence_bundle_cid: _old, ...body} = JSON.parse(supplied.wire);
  // A new independent field-target Program has one actual Source Catalog and
  // the original Command Catalog/role bodies. No published Mapping is needed.
  body.connector_catalogs.push(...commandEnvironment.connector_catalogs);
  body.connector_manifest.connectors.push(...commandEnvironment.connector_manifest.connectors);
  body.command_contracts = commandEnvironment.command_contracts;
  body.contract_registry.push(...commandEnvironment.contract_registry);
  // Each original top-level evidence inventory is ordered by its complete
  // body identity; internal Catalog member order and all body bytes stay put.
  for (const name of ['schema_snapshots', 'connector_capabilities', 'source_views',
    'contract_registry', 'connector_catalogs', 'mapping_contracts', 'model_task_contracts', 'command_contracts']) {
    body[name].sort((left, right) => cid(left).localeCompare(cid(right)));
  }
  body.connector_manifest.connectors.sort((left, right) => cid(left).localeCompare(cid(right)));
  const environmentCid = cid(body);
  const environment = moon.clientProgramCheckEnvironment(canonical({...body, evidence_bundle_cid: environmentCid}), environmentCid,
    false, false, true, false, false, false, false);
  assert(environment, 'original command Catalog plus actual Source declaration');
  const program = {version: 'actql/0.1', id: 'original-field-command-key', stages: [{id: 'capture',
    inputs: {original: {connector: 'field-target-source', resource: 'rows', view: 'records'}},
    steps: [{from: 'original', filter: "id = 'one'", as: 'matching'},
      {from: 'matching', select: ['resource', 'id', 'value'], as: 'selected'}],
    results: {out: {from: 'selected', fields: ['resource', 'id', 'value']}},
  }, {id: 'save', inputs: {original: {result: {stage: 'capture', result: 'out'}}},
    steps: [{from: 'original', select: ['resource', 'id', 'value'], as: 'selected'}],
    results: {out: {from: 'selected', fields: ['resource', 'id', 'value']}},
    effects: {save: {command: {contract: 'command:fixture.upload.v1', target: {field: 'resource'},
      from: {result: 'out'}, input: {id: {field: 'id'}, value: {field: 'value'}},
      ...(inputKey ? {input_key: 'id'} : {})}}},
  }], results: {published: {from: {stage: 'save', result: 'out'}}}};
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    canonical(program), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert(prepared, inspect(moon.clientProgramEffectPreparationIssue(outcome), {depth: 12}));
  const evidence = publicationEvidence(prepared);
  const admission = moon.clientProgramAdmitEffectPublication(prepared, ...evidence);
  assert(admission);
  const definition = checked(moon.strategyIssueRunDefinition(admission, 'key-fixture-scope',
    'key-fixture', `sha256:${'c'.repeat(64)}`, '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z', 100000, 10000, 64));
  const bound = moon.clientProgramBindEffectRun(prepared, admission, definition);
  assert(bound);
  const registry = await read('spec/dependencies/aoa-pipeline-registry.json');
  const contracts = JSON.parse(await read('spec/contracts/actql-aoa.json')).execution_contracts;
  const values = JSON.stringify(contracts['REL.values']);
  const fragment = JSON.stringify(contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(contracts['REL.derive.ordered']);
  const requirement = checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
    prepared, 0, 0, registry, values, fragment, ordered));
  const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(declaration,
    requirement, await read('spec/contracts/actql-query-acquisition.json'),
    await read('spec/contracts/actql-query-process-evidence.json'), undefined));
  const rows = [{id: 'one', value: 'original', resource: resource('d')},
    ...(duplicate ? [{id: 'one', value: 'duplicate', resource: resource('e')}] : [])];
  let current = true, physical, execution, inputs;
  const issuer = moon.clientProgramResourceReferenceIssuer((kind, wire) =>
    current && kind === 'file' && rows.some(row => canonical(row.resource) === wire), () => current);
  try {
    physical = checked(moon.clientProgramRowSourceStart(acquisition, 'original-field-target', () => current));
    checked(moon.clientProgramRowSourceBegin(physical, 8192, 10, 10, issuer));
    assert.equal(checked(moon.clientProgramRowSourceAcceptPage(physical, Buffer.from(canonical(rows)))), rows.length);
    checked(moon.clientProgramRowSourceFinish(physical));
    const captured = checked(moon.clientProgramRowSourceCapture(physical));
    const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
    const owned = moon.clientProgramOpenCapturedLocalEffectHost(bound, source, registry, values,
      1n, 0n, 0n, 0n, fragment, ordered);
    assert(owned, 'same captured source feeds the original checked Effect Host');
    execution = await runCapturedEffectComputation(owned);
    assert.equal(execution.status, 'host-tasks-completed');
    inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
    const limits = moon.clientProgramEffectInputExportLimits(
      10, 1000, 10000, 100, 100, 10000, 100000, 64, 100000,
      100000, 10000, 64, 10, 10000, 100000, 10003, 66, 10, 100000, 10000, 64, 4096);
    assert(limits);
    return {prepared, owned, execution, inputs, limits, rows, revoke() { current = false; },
      publicationContext(control) {
        // Publication consumes the same original acquisition and capture. The
        // fixture's policy remains explicit and is not an installed grant.
        const bounds = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
        const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
        const identity = checked(moon.clientProgramIdentifyCapturedEffectSourceRelation(source));
        const logicalInput = checked(moon.clientProgramEffectIssueCapturedSourceLogical(
          prepared, source, identity, requirement));
        const dataPolicyCid = declared.views[0].data_policy_cid;
        const sourceEvidenceWire = checked(moon.clientProgramRowSourceIssueSourceEvidence(
          acquisition, captured, identity, logicalInput, authorityScopeCid,
          dataPolicyCid, '2026-09-24T00:00:00.000Z'));
        const sourceEvidence = control.admitRunEvidence('source_evidence', sourceEvidenceWire, bounds);
        const retentionDependencies = Object.freeze([
          ['retention_contract', 'key-fixture-retention'],
          ['metadata_retention_policy', 'key-fixture-metadata'],
          ['clock_contract', 'key-fixture-clock'],
        ].map(([kind, name]) => {
          const wire = canonical({name, version: 'actql-installed-local-policy/0.1'});
          return Object.freeze({kind, wire, cid: cid(JSON.parse(wire))});
        }));
        const retention = control.seal('result_retention_policy', canonical({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: retentionDependencies[0].cid,
          effective_data_policy_cid: dataPolicyCid,
          available_until: '2027-01-01T00:00:00.000Z',
          delete_by: '2027-01-02T00:00:00.000Z',
          extension_ceiling_at: '2027-01-03T00:00:00.000Z',
          metadata_retention_policy_cid: retentionDependencies[1].cid,
          metadata_delete_by: '2027-01-04T00:00:00.000Z',
          clock_contract_cid: retentionDependencies[2].cid,
        }), bounds);
        const [template, preparedEvidence, authorization] = evidence.slice(0, 3)
          .map((value, index) => control.admitRunEvidence(
            ['bound_invocation_template', 'prepared_invocation', 'run_authorization'][index],
            moon.strategyRunEvidenceJson(value), bounds));
        const compiledPlan = control.admit('compiled_plan',
          moon.strategyPublicationContractJson(evidence[3]), bounds);
        const observation = control.sealRunEvidence('observation_set', canonical({
          version: 'actql-observation-set/0.1', invocation_template_cid: template.identity,
          source_evidence_cids: [sourceEvidence.identity], captured_input_artifact_cids: [],
          consistency: 'independent_snapshots', capture_started_at: '2026-09-24T00:00:00.000Z',
          capture_completed_at: '2026-09-24T00:00:00.000Z',
          replayability: {materialized: false, availability_evidence_cids: []},
          data_policy_cid: dataPolicyCid,
        }), bounds);
        const invocation = control.issueRunInvocation(template, observation, bounds);
        const acquiredEvidence = control.issueCheckedAcquiredEffectEvidence(prepared,
          source, identity, requirement, logicalInput, sourceEvidence,
          authorityScopeCid, dataPolicyCid, retention, bounds);
        return {invocation, retention, sourceBindingCid: moon.clientProgramCapturedSourceLogicalCid(identity),
          localEvidenceContext: Object.freeze({
            admission: control.admitCheckedClientEffectRunPublication(prepared,
              template, preparedEvidence, authorization, compiledPlan),
            runDefinition: control.admit('run_definition',
              moon.strategyPublicationContractJson(definition), bounds),
            runInvocation: invocation, observation, acquiredEvidence, retentionDependencies,
          })};
      },
      async close() {
        moon.clientProgramReleaseEffectInputs(inputs);
        await execution.close();
        moon.clientProgramRowSourceClose(physical);
        current = false;
        assert.equal(execution.cleanupPending(), false);
      }};
  } catch (error) {
    if (inputs !== undefined) moon.clientProgramReleaseEffectInputs(inputs);
    if (execution !== undefined) await execution.close();
    if (physical !== undefined) moon.clientProgramRowSourceClose(physical);
    current = false;
    throw error;
  }
}
