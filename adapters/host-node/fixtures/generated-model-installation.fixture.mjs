// Shared deterministic installation and real byte preflight for generated
// Content Model acceptance. This fixture never invokes a paid Model provider.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {checked} from '../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {providerBindingOriginals} from '../../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {canonical, cid, token} from './file-listing-source.fixture.mjs';

export async function mediaInstallation({requestBytes = 1466, contentBytes = 32,
  mediaType = 'text/csv'} = {}) {
  const base = JSON.parse(await readFile(new URL('../../../spec/local-check-environment.json', import.meta.url)));
  // The original opaque input envelope is 1466 bytes, independently measured
  // by its consuming tests. These are installed finite ceilings, not grants.
  const hostCapacityPolicy = {...base.host_policy_profile.capacity,
    max_model_request_bytes_per_item: requestBytes};
  base.host_policy_profile.capacity = hostCapacityPolicy;
  const taskSource = await readFile(new URL('../../../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
  const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
  const seal = body => ({...body, self_cid: cid(body)});
  const prompt = seal({version: 'actql-model-prompt/0.1',
    payload: {format: 'fixture-content/0.1', instructions: 'Inspect the exact CSV attachment.'}});
  const retry = seal({version: 'actql-model-retry-policy/0.1', retryable_failures: []});
  const backoff = seal({version: 'actql-model-backoff/0.1', delays_ms: []});
  const media = seal({version: 'actql-model-media-input/0.1', payload: {
    media_type: mediaType, max_bytes: contentBytes, max_pages: null, max_frames: null,
    complete: true, transfer_method: 'inline_bytes', classifications: ['internal'],
    regions: ['fixture-region'], egress_scope_cid: token('a'),
  }});
  task.input_contract = {type: 'object', nullable: false, additional_properties: false,
    fields: {document: {type: 'content_ref', media_type: mediaType, nullable: false}}};
  task.input_schema_cid = cid(task.input_contract);
  task.prompt_template_cid = prompt.self_cid;
  delete task.contract_cid;
  task.contract_cid = cid(task);
  const {evidence_bundle_cid: _, ...environment} = base;
  environment.model_task_contracts = [task];
  const execution = seal({version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: retry.self_cid,
    backoff_contract_cid: backoff.self_cid,
    max_attempts_per_slot: 1, max_total_attempts: 1, max_total_cost_units: 0,
    max_total_duration_ms: 500, max_total_wire_bytes: requestBytes + 65536,
    max_total_token_reservation: 33,
    media_input_contracts: {document: media.self_cid}, default_publication: 'outcomes'});
  return {task, hostCapacityPolicy, installation: {
    environmentWire: canonical({...environment, evidence_bundle_cid: cid(environment)}),
    executionContracts: [{modelTaskCid: task.contract_cid,
      cid: execution.self_cid, bodyWire: canonical(execution)}],
    dependencyBodies: [prompt, retry, backoff, media].map(body =>
      ({cid: body.self_cid, bodyWire: canonical(body)})),
  }};
}

export function generatedContentInferProgram() {
  return {version: 'actql/0.1', id: 'acquired-generated-content-model',
    stages: [{id: 'main', inputs: {
      transfers: {connector: 'content-fixture', resource: 'transfers', view: 'records'}},
    steps: [
      {from: 'transfers', filter: 'name IS NOT NULL', as: 'scan'},
      {select: ['name'], as: 'captured'},
      {assert_rows: {unique_by: ['name']}, as: 'unique_input'},
      {serialize: {format: 'csv', fields: ['name'], name: 'out.csv',
        header: true, null_marker: '\\N', order_by: [{name: 'asc'}],
        bounds: {max_rows: 1, max_bytes: 32}}, as: 'attachment'},
      {assert_rows: {unique_by: ['name']}, as: 'unique_attachment'},
      {infer: {contract: 'model-task:risk-score.v1', key: 'name',
        input: {document: {field: 'content'}}}, as: 'inferred'},
    ], results: {answer: {from: 'inferred', fields: ['name', 'outcome', 'value']}}}],
    results: {answer: {from: {stage: 'main', result: 'answer'}}}};
}

export function generatedContentModelProviders({root, task, expected, sourceWire,
  onPrepare = () => {}, onSend = () => {}, onFailure = () => {}}) {
  const expectedCid = `sha256:${createHash('sha256').update(expected).digest('hex')}`;
  return moon => {
    const vector = JSON.parse(readFileSync(new URL('../../../portability/corpus/model-response-profiles.json',
      import.meta.url), 'utf8')).cases[0].body;
    const {self_cid: _, ...body} = vector;
    const profileBody = {...body,
      task: {contract_cid: task.contract_cid, kind: body.task.kind,
        input_schema_cid: task.input_schema_cid, output_schema_cid: task.output_schema_cid},
      limits: {...body.limits, request_bytes: 4096}};
    const profileWire = canonical({...profileBody, self_cid: cid(profileBody)});
    const profile = runtimeCore(moon).publicationControl.readInstalledModelResponseProfile(
      profileWire, cid(profileBody), {maxWireBytes: 16384, maxNodes: 1000,
        maxDepth: 30, maxMembers: 1000, maxWork: 100000});
    const installation = {...profileBody.adapter,
      endpoint: profileBody.operation.endpoint, http_method: profileBody.operation.method,
      streaming: false, validator_id: profileBody.completion.validator_id,
      validator_revision: profileBody.completion.validator_revision,
      validator_artifact_cid: profileBody.completion.validator_artifact_cid,
      completion_basis: profileBody.completion.basis};
    delete installation.port_abi;
    // Retain ALL declared Task rows, including masked/unexecuted rows. This
    // fixture's transport is serial; Profile limits do not enable parallel I/O.
    // Keep the native Graph's complete nine amounts; these are ADDITIONAL
    // Node controls and bounded request/response/chunk/header/metadata overlap.
    // Four byte representations cover UTF-8, UTF-16 and a simultaneous copy.
    // The conservative 256-byte per parsed value covers the failed decoder's
    // Source/index/value controls; it is not a general runtime heap tariff.
    const controls = 14464n, limits = profileBody.limits, rows = BigInt(task.max_items);
    const buffers = BigInt(limits.request_bytes + limits.response_bytes + limits.chunk_bytes +
      limits.header_bytes + limits.metadata_bytes + expected.length);
    const read = rows * (controls + 4n * buffers + 256n * BigInt(limits.parse_nodes + limits.metadata_nodes));
    const runtimeArtifactCid = cid({adapter: profileBody.adapter, completion: profileBody.completion});
    const layoutArtifactCid = cid({profile: cid(profileBody), preparedRows: task.max_items,
      fixedControls: String(controls), nodeRetained: String(read), nodeExecution: String(read)});
    const originalReadRecipe = {
      bootstrap: {bootstrapRetainedBytes: controls, bootstrapExecutionBytes: controls,
        maxReservations: 12, maxHoldings: 8, maxDelegations: 4},
      modelRetainedBytes: controls, modelExecutionBytes: controls,
      currentStateCodec: {quantum: 64, comparisonWork: 26, decode: {maxWork: 100000,
        parse: {max_input_bytes: 65536, max_nodes: 8192, max_depth: 64},
        tree: {max_nodes: 8192, max_depth: 64, max_string_bytes: 65536, max_total_string_bytes: 65536}}},
      storeBootstrap: {maxWireBytes: 65536, maxDirectoryEntries: 128},
      metadataAcquisition: {metadata: {maxWireBytes: 65536, maxLedgerEntries: 16},
        directory: {maxWireBytes: 65536, maxDirectoryEntries: 128}, retainedBytes: read, workspaceBytes: read},
      publicationCapacity: {retainedBytes: read, workspaceBytes: read},
      nodeInstallation: {layout: {response_profile: profile,
        runtime_artifact_cid: runtimeArtifactCid, layout_artifact_cid: layoutArtifactCid,
        prepared_rows: rows, retained_bytes: read, execution_bytes: read},
      installation, runtimeArtifactCid, layoutArtifactCid, probability: undefined}};
    return [{providerId: 'models/fixture', originalReadRecipe,
    bindingOriginals: providerBindingOriginals('models/fixture', {selector: 'fixture-risk-model'}),
    invoke() { throw new Error('UnpreparedGeneratedContentCall'); },
    validatePrompt: (taskCid, selector, wire) => taskCid === task.contract_cid &&
      selector === task.authored_model_selector && JSON.parse(wire).format === 'fixture-content/0.1',
    quantityCapacity: {limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: 'internal', _1: 'fixture-region', _2: false, _3: false}),
    physicalPreflight(request, ioNotification, rawCaptureBinder, admittedProvider) {
      try {
        onPrepare();
        const input = checked(moon.clientProgramModelContentInput(admittedProvider, request, 'document', -1));
        const description = moon.clientProgramModelContentInputDescription(input);
        assert.equal(description._1, task.input_contract.fields.document.media_type);
        assert.equal(description._2, expectedCid);
        assert.equal(description._3, BigInt(expected.length));
        if (sourceWire !== undefined) {
          assert.notEqual(description._0, sourceWire, 'consume generated, not acquired input Content');
        }
        let checker, pending, bytes, issue, admission, offset = 0, closed = false;
        const progress = (ready, plan, work = 1) => ({_0: {$tag: 1, _0: {_0: ready, _1: plan}}, _1: work});
        return moon.clientProgramModelContentRequestPreflight(quantum => {
          if (checker === undefined) {
            checker = checked(moon.clientProgramStartModelContentBytes(input, 'fixture-region', token('a'),
              undefined, undefined, () => !closed));
            // The existing common byte checker consumes the exact original
            // immutable Store object, not a URI or another Source request.
            pending = readFile(join(root, 'host', 'publication', 'objects',
              expectedCid.slice('sha256:'.length))).then(value => { bytes = value; }, error => { issue = error; });
            return progress(false, undefined);
          }
          if (issue !== undefined) throw issue;
          if (bytes === undefined) return progress(false, undefined);
          if (offset < bytes.length) {
            const chunk = bytes.subarray(offset, offset + Math.min(quantum, 256));
            const work = checked(moon.clientProgramUpdateModelContentBytes(checker, chunk));
            assert.equal(work, chunk.length);
            offset += chunk.length;
            return progress(false, undefined, work);
          }
          admission ??= checked(moon.clientProgramFinishModelContentBytes(checker));
          const plan = checked(moon.clientProgramModelMediaPhysicalRequestPlan(request,
            4096n, 33n, 0n, 500n, [admission], () => {
              assert.deepEqual(bytes, expected);
              onSend();
              return moon.clientProgramModelResponse(request, '{"reason":null,"risk":"high"}',
                'fixture-risk-model', 'generated-content-request', 1n, 2n, new Date().toISOString());
            }));
          return progress(true, plan);
        }, () => {
          if (pending !== undefined && bytes === undefined && issue === undefined) return false;
          closed = true;
          bytes = undefined;
          return true;
        });
      } catch (error) { onFailure(error); throw error; }
    }}];
  };
}
