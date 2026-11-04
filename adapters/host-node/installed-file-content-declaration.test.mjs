import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {ledgerUsageSnapshot} from '../host-common/runtime-core.mjs';
import {ledgerUsageFieldsFor} from './fixtures/ledger-usage.mjs';
// Actual declaration/Checker, installed Source and public Client boundaries.
// Envelope-only cases are labelled separately from real Store-backed capture.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {inspect} from 'node:util';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {acquiredTaskRunAdmission, acquiredTaskPublicationPlan,
  acquiredKeyedTaskPublicationPlan, serializationTaskRunAdmission, inferTaskRunAdmission} from './local-values-plan.mjs';
import {rowSourceCheckEnvironment, createInstalledRowSource,
  installRowSourceAuthorization} from './installed-row-source.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {runCapturedInternalStrategy, runPublishedCapturedStrategy} from './entry.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {issueStoredCapturedContent} from './generated-content-holding.mjs';
import {retainCapturedContent} from './captured-content-holding.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {installLocalRetainedStore} from '../local-node/retained-store.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {mediaInstallation, generatedContentModelProviders} from './fixtures/generated-model-installation.fixture.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';
import {installCompletionObserver} from '../host-common/completion-observer.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {connect as connectRemote} from '../../packages/sdk/index.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';
import {runGeneratedContentPrefix, writeGeneratedContent, stopGeneratedContentPrefix,
  identifyGeneratedContentInput} from './generated-content-write.mjs';
import {localOutputLimits, localContractLimits} from './local-values-plan.mjs';
import {readGcsKeyedContent} from '../connectors/gcs/site/gcs-keyed-content.mjs';
import {canonical, cid, token, fileListingDeclaration, resource, item} from './fixtures/file-listing-source.fixture.mjs';

const baseWire = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
const correlation = {
  request_fields: ['resource', 'version'], response_fields: ['resource', 'version'],
  identity: ['resource', 'version'], cardinality: 'one',
};
// An opaque-value admission fixture only: this envelope does not assert that
// a physical content body has been captured or that GCS has been exercised.
const admittedContent = {$actql_ref: 'content', version: 'actql-content-ref/0.1',
  media_type: 'application/pdf', content_ref_cid: token('e'), metadata: {}};
// Preparation validates the entire declared Catalog through the existing
// SourceRequest Owner. Environment wire admission alone deliberately does not.
const checkProgram = JSON.stringify({version: 'actql/0.1', id: 'content-contract-check',
  stages: [{id: 'check', inputs: {}, steps: [{values: {
    schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'rows'}],
  results: {r: {from: 'rows', fields: ['id']}}}],
  results: {r: {from: {stage: 'check', result: 'r'}}}});
function fixture({authority = 'read_content', kind = 'fetch',
  roles = correlation, nullableVersion = false, conditionalContent = false,
  capacity = {}, profile = {}} = {}) {
  const content = {type: 'content_ref', media_type: 'application/pdf', nullable: false};
  const fields = {
    resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
    version: {type: 'string', nullable: nullableVersion},
    content: conditionalContent ? {contract: content, presence: 'conditional'} : content,
  };
  const spec = {resource: 'contents', resource_kind: 'file',
    schema_wire: canonical(fields), schema_cid: cid(fields),
    request_schema_wire: canonical({type: 'object', nullable: false,
      additional_properties: false, fields: {
        resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
        version: {type: 'string', nullable: false},
      }}), acquisition_wire: canonical({kind, authority, correlation: roles}), facts_wire: '{}'};
  const restore = expected => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'content-fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [spec]}), expected));
  const initial = JSON.parse(moon.clientProgramRowSourceDeclarationJson(restore(undefined)));
  spec.facts_wire = canonical({file_content: {
    version: 'actql-file-content/0.1', kind: 'file_content',
    admitted_scope_contract_cid: token('a'),
    content_schema_contract_cid: initial.views[0].carrier_schema_cid,
    version_capability: {contract_cid: token('b'), required_nonnull: true},
    representation: 'exact_stored_bytes', ...profile,
  }, lookup_capacity: {version: 'actql-lookup-capacity/0.1',
    completeness: 'complete_per_requested_key', max_rows_per_key: 1,
    max_pages_per_request: 2, max_response_bytes_per_page: 4096, ...capacity}});
  const declaration = restore(undefined);
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseWire.trimEnd(), declared);
  const admit = () => moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  const check = () => {
    const checkedEnvironment = admit();
    assert.ok(checkedEnvironment, 'wire environment is admitted before semantic checking');
    const preparation = moon.clientProgramPrepareEffectFreeWithParameters(checkProgram,
      'json', checkedEnvironment, undefined);
    return {ready: moon.clientProgramPreparationReady(preparation) !== undefined,
      issueCode: moon.clientProgramPreparationIssueCode(preparation)};
  };
  return {spec, declaration, declared, environment, check, restore};
}

test('compiled installed declaration binds keyed ContentRef roles to its real Request and Catalog', () => {
  const value = fixture();
  assert.deepEqual(value.check(), {ready: true, issueCode: undefined});
  const catalog = JSON.parse(value.declared.catalog);
  const acquisition = catalog.source_views[0].acquisition;
  assert.deepEqual(acquisition.correlation, correlation);
  assert.equal(acquisition.kind, 'fetch');
  assert.equal(acquisition.authority, 'read_content');
  assert.deepEqual(acquisition.modes, [{bounded: true, mode: 'snapshot'}]);
  const request = value.declared.contracts.map(JSON.parse)
    .find(envelope => envelope.kind === 'request_schema');
  assert.deepEqual(acquisition.request_schema,
    {id: request.id, version: request.version, cid: request.cid});
  const restored = JSON.parse(moon.clientProgramRowSourceDeclarationJson(
    value.restore(value.declared.catalog_cid)));
  assert.equal(restored.catalog, value.declared.catalog);
  assert.deepEqual(restored.contracts, value.declared.contracts);
  const reversed = fixture({roles: {request_fields: ['version', 'resource'],
    response_fields: ['version', 'resource'], identity: ['version', 'resource'], cardinality: 'one'}});
  assert.deepEqual(reversed.check(), {ready: true, issueCode: undefined});
  assert.notEqual(reversed.declared.catalog_cid, value.declared.catalog_cid);
  assert.deepEqual(JSON.parse(reversed.declared.catalog).source_views[0].acquisition.correlation.identity,
    ['version', 'resource']);
  assert.deepEqual(fixture({authority: 'read_binary'}).check(), {ready: true, issueCode: undefined});
});

test('real Program checking refuses metadata-only, weak or nullable ContentRef fetch contracts', () => {
  for (const options of [
    {authority: 'read_metadata'}, {kind: 'search'}, {nullableVersion: true},
    {conditionalContent: true}, {roles: {...correlation, cardinality: 'zero_or_one'}},
    {roles: {...correlation, identity: ['resource']}},
    {capacity: {max_rows_per_key: 2}}, {capacity: {completeness: 'partial'}},
    {profile: {content_schema_contract_cid: token('c')}},
    {profile: {representation: 'decoded_text'}},
    {profile: {version_capability: {contract_cid: token('b'), required_nonnull: false}}},
  ]) {
    const outcome = fixture(options).check();
    assert.equal(outcome.ready, false, JSON.stringify(options));
    assert.equal(outcome.issueCode, 'check_invalid_configuration', JSON.stringify(options));
  }
});

test('installed acquisition cannot supply a replacement Request reference or broaden finite modes', () => {
  const value = fixture();
  for (const extra of [
    {request_schema: {id: 'foreign', version: 'external', cid: token('f')}},
    {modes: [{mode: 'watch', bounded: false}]}, {default_mode: 'changes'},
  ]) {
    assert.throws(() => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
      'content-fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{...value.spec,
        acquisition_wire: canonical({kind: 'fetch', authority: 'read_content', correlation, ...extra}),
      }]}), undefined)), {code: 'MoonBitHostFailure'});
  }
});

function authoredListingJoin(format, {allFiles = false} = {}) {
  const listing = allFiles ? 'LIST_FILES(docs.listing)'
    : "LIST_FILES(docs.listing, paths => ['invoice.pdf'])";
  return format === 'sql'
    ? 'SELECT f.name AS name, c.content AS content ' +
      `FROM ${listing} AS f ` +
      'JOIN docs.contents AS c ON f.resource = c.resource AND f.version = c.version ' +
      "WHERE f.name = 'invoice.pdf'"
    : `FROM ${listing} AS f ` +
      "|> WHERE f.name = 'invoice.pdf' |> JOIN docs.contents AS c " +
      'ON f.resource = c.resource AND f.version = c.version ' +
      '|> SELECT f.name AS name, c.content AS content';
}

function listingContentProgram({maximum = 3, emptySelector = false,
  omitVersion = false, explicitEmptyRequest = false, expectReady = true,
  hostListingMaximum, decodedResponseMaximum = 32768,
  joinCount = 1, filterFirst = false, capturePrefix = false, allFiles = false,
  captureFilter, postJoinFilter, lookupPolicy = {}, reverseSourceInputs = false,
  sourceFormat = 'json', serialize = false, modelTask, hostCapacityPolicy, classification,
  authoredDocument, publicUnknownSource = false} = {}) {
  const listing = {...fileListingDeclaration(moon, baseWire.trimEnd()).spec};
  const content = {...fixture().spec};
  if (classification !== undefined) {
    listing.data_classification = classification;
    content.data_classification = classification;
  }
  const listingFacts = JSON.parse(listing.facts_wire);
  const contentFacts = JSON.parse(content.facts_wire);
  listing.facts_wire = '{}';
  content.facts_wire = '{}';
  const restore = () => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'content-fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [listing, content]}), undefined));
  const initial = JSON.parse(moon.clientProgramRowSourceDeclarationJson(restore()));
  listingFacts.file_listing.listing_schema_contract_cid = initial.views.find(v => v.resource === 'files')?.carrier_schema_cid;
  contentFacts.file_content.content_schema_contract_cid = initial.views.find(v => v.resource === 'contents')?.carrier_schema_cid;
  assert.match(listingFacts.file_listing.listing_schema_contract_cid ?? '', /^sha256:[0-9a-f]{64}$/u);
  assert.match(contentFacts.file_content.content_schema_contract_cid ?? '', /^sha256:[0-9a-f]{64}$/u);
  listingFacts.file_listing.max_listing_items = maximum;
  // This selected ordinary Source has the same carrier/Request schema, but
  // no LIST_FILES capability or numeric row fact. Runtime reader budgets stay
  // finite; they must not become a fabricated checked count.
  listing.facts_wire = publicUnknownSource ? '{}' : canonical(listingFacts);
  content.facts_wire = canonical(contentFacts);
  const declaration = restore();
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const base = JSON.parse(baseWire);
  delete base.evidence_bundle_cid;
  if (modelTask !== undefined) base.model_task_contracts = [modelTask];
  if (hostCapacityPolicy !== undefined) base.host_policy_profile.capacity = hostCapacityPolicy;
  if (hostListingMaximum !== undefined) {
    base.host_policy_profile.capacity.max_file_listing_items = hostListingMaximum;
  }
  base.host_policy_profile.lookup_execution = {version: 'actql-lookup-execution-policy/0.1',
    max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
    max_total_request_bytes: 32768, max_total_response_bytes: 32768,
    max_total_decoded_response_bytes: decodedResponseMaximum, max_total_duration_ms: 30000,
    ...lookupPolicy};
  const env = rowSourceCheckEnvironment(canonical({...base, evidence_bundle_cid: cid(base)}), declared);
  const environment = moon.clientProgramCheckEnvironment(env.wire, env.evidenceCid,
    false, false, true, false, false, false, false);
  const program = {version: 'actql/0.1', id: 'listed-versioned-content', stages: [{id: 's',
    inputs: {files: {connector: 'content-fixture', resource: 'files',
      request: {paths: emptySelector ? [] : allFiles ? null : ['invoice.pdf'], glob: null}},
    // Keyed JOIN supplies resource/version; an empty explicit Request is not
    // an admitted Source input declaration.
    contents: {connector: 'content-fixture', resource: 'contents',
      ...(explicitEmptyRequest ? {request: {}} : {})}},
    steps: [...(capturePrefix ? [{from: 'files', filter: captureFilter ?? (allFiles ? 'name IS NOT NULL' : "name = 'invoice.pdf'"), as: 'matched'},
      {from: 'matched', select: ['name', 'resource', 'version'], as: 'selected'}]
      : filterFirst ? [{from: 'files', filter: "name = 'invoice.pdf'", as: 'selected'}] : []),
    ...Array.from({length: joinCount}, (_, index) => ({
      join: {left: filterFirst || capturePrefix ? 'selected' : 'files', with: 'contents', kind: 'inner',
      on: [{left: 'resource', right: 'resource'},
        ...(omitVersion ? [] : [{left: 'version', right: 'version'}])],
      select: {name: 'left.name', content: 'right.content'}},
      as: index === joinCount - 1 ? 'captured' : `captured_${index}`})),
    ...(postJoinFilter === undefined ? [] : [{from: 'captured', filter: postJoinFilter, as: 'published'}])],
    results: {r: {from: postJoinFilter === undefined ? 'captured' : 'published', fields: ['name', 'content']}}}],
  results: {r: {from: {stage: 's', result: 'r'}}}};
  if (reverseSourceInputs) {
    const {files, contents} = program.stages[0].inputs;
    program.stages[0].inputs = {contents, files};
  }
  if (serialize) {
    program.stages[0].steps.push(
      {from: postJoinFilter === undefined ? 'captured' : 'published',
        assert_rows: {unique_by: ['name']}, as: 'ordered_input'},
      {from: 'ordered_input', serialize: {format: 'jsonl', fields: ['name', 'content'],
        name: 'captured.jsonl', order_by: [{name: 'asc'}]}, as: 'attachment'});
    program.stages[0].results.r = {from: 'attachment', fields: ['name', 'content']};
  }
  if (modelTask !== undefined) {
    program.stages[0].steps.push(
      {from: 'captured', assert_rows: {unique_by: ['name']}, as: 'unique_input'},
      {from: 'unique_input', infer: {contract: modelTask.task_id, key: 'name',
        input: {document: {field: 'content'}}}, as: 'inferred'});
    program.stages[0].results.r = {from: 'inferred', fields: ['name', 'outcome', 'value']};
  }
  const queryAliases = declared.views.map(view => ({
    name: view.resource === 'files' ? 'docs.listing' : 'docs.contents',
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
    schemaContractCid: view.carrier_schema_cid,
  }));
  const preparation = publicUnknownSource ? undefined : sourceFormat === 'json'
    ? moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program), 'json', environment, undefined)
    : installNodePublicSourcePreparation({moon, environment,
      publication: sourceAliasPublication(moon, environment, queryAliases)}).prepare({
      document: authoredDocument ?? authoredListingJoin(sourceFormat, {allFiles}), format: sourceFormat,
    }).outcome;
  if (expectReady && !publicUnknownSource) assert.ok(moon.clientProgramPreparationReady(preparation) !== undefined,
    inspect(moon.clientProgramPreparationIssue(preparation),
      {depth: 9, maxArrayLength: 6, maxStringLength: 400}));
  return {ready: preparation === undefined ? undefined : moon.clientProgramPreparationReady(preparation) !== undefined,
    issue: preparation === undefined ? undefined : moon.clientProgramPreparationIssueCode(preparation),
    preparation,
    preparedProgram: preparation === undefined ? undefined : moon.clientProgramPreparationReady(preparation),
    declaration, declared, program, environmentWire: env.wire,
    viewsWire: JSON.stringify({views: [listing, content]})};
}

function assertOriginalSerializationInput({control, plan, program, acquisition,
  foreignProgram, joinedInput}) {
  // A split task serializes the original captured predecessor. Its selected
  // fragment contains the internal sort, not a second execution of the JOIN.
  control.checkClientCompiledRunOwner(plan.compiled, program);
  control.checkClientCompiledRunDefinition(plan.compiled, plan.runDefinition);
  assert.equal(moon.clientProgramDefinitionCid(foreignProgram),
    moon.clientProgramDefinitionCid(program));
  assert.equal(moon.clientProgramKeyedAcquisitionMatchesProgram(acquisition, program), true);
  assert.equal(moon.clientProgramKeyedAcquisitionMatchesProgram(acquisition, foreignProgram), false);
  assert.throws(() => control.checkClientCompiledRunOwner(plan.compiled,
    foreignProgram), /Foreign Client compiled Run/u);
  assert.throws(() => control.checkClientCompiledRunOwner({...plan.compiled},
    program), /Foreign Client compiled Run/u);
  assert.throws(() => runtimeCore({...moon}).publicationControl.checkClientCompiledRunOwner(
    plan.compiled, program), /Foreign Client compiled Run/u);
  assert.throws(() => control.checkClientCompiledRunDefinition(plan.compiled,
    {...plan.runDefinition}), /Foreign/u);
  assert.deepEqual(control.compiledSerializationGraph(plan.compiled), plan.serializationGraph);
  const graph = JSON.parse(plan.serializationGraph.wire);
  const input = graph.nodes.find(node => node.node_id ===
    `task_${plan.serializationGraph.task}_before_serialize_${plan.serializationGraph.step}`);
  assert(input, 'The same original Content barrier must retain its typed input fragment');
  assert.deepEqual(Object.keys(input.input_contracts).sort(),
    joinedInput ? ['contents', 'files'] : ['input_0']);
  for (const cid of Object.values(input.input_contracts)) {
    assert.match(cid, /^sha256:[0-9a-f]{64}$/u);
  }
  assert.match(plan.serializationGraph.wire, /REL\.orderByStable/u);
  if (joinedInput) assert.match(plan.serializationGraph.wire, /REL\.join/u);
  else assert.doesNotMatch(plan.serializationGraph.wire, /REL\.join/u);
  assert.doesNotMatch(plan.serializationGraph.wire, /REL\.values/u);
}

test('keyed capture SERIALIZE checks and compiles both original Source obligations', () => {
  const value = listingContentProgram({capturePrefix: true, allFiles: true, serialize: true});
  const program = value.preparedProgram;
  const acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(program));
  assert.ok(acquisition, 'Content generation must retain its exact original keyed acquisition');
  const occurrences = moon.clientProgramSerializationOccurrences(program);
  assert.equal(occurrences.length, 1);
  const control = runtimeCore(moon).publicationControl;
  let plan;
  try {
    plan = serializationTaskRunAdmission({moon, control, preparedProgram: program,
      authorityScopeCid: token('a'), namespaceId: 'keyed-content-plan',
      now: () => '2026-10-10T00:00:00.000Z'});
  } catch (cause) {
    throw new Error(inspect({occurrences, tasks: moon.clientProgramTaskCount(program),
      acquisition: moon.clientProgramKeyedAcquisitionCoordinates(acquisition)}, {depth: 5}), {cause});
  }
  assert.equal(plan.kind, 'serialization');
  const body = JSON.parse(control.compiledSerializationPolicy(plan.compiled).wire);
  const policies = JSON.parse(value.environmentWire).schema_snapshots
    .map(view => view.source_data_policy_cid);
  assert.deepEqual(new Set(body.source_data_policy_cids), new Set(policies));
  assert.equal(control.compiledSourceFreeResultPolicy(plan.compiled), undefined);
  assertOriginalSerializationInput({control, plan, program, acquisition,
    foreignProgram: listingContentProgram({capturePrefix: true, allFiles: true,
      serialize: true}).preparedProgram, joinedInput: false});
  assert.throws(() => control.issueCheckedClientCompiledInvocation(plan.compiled,
    plan.runDefinition, {dataPolicyCid: control.compiledSerializationPolicy(plan.compiled).cid},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}), /RunHostInvocationRejected/u);
});

for (const syntax of ['aql', 'json']) test(`unfiltered ${syntax} file Content JOIN retains its acquired serialization graph`, () => {
  const options = {allFiles: true, serialize: true,
    sourceFormat: syntax,
    authoredDocument: 'FROM LIST_FILES(docs.listing) AS f ' +
      '|> JOIN docs.contents AS c ON f.resource = c.resource AND f.version = c.version ' +
      '|> SELECT f.name AS name, c.content AS document ' +
      '|> ASSERT UNIQUE BY (name) ' +
      "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'native-files.jsonl')"};
  const value = listingContentProgram(options);
  const program = value.preparedProgram;
  const acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(program));
  assert.ok(acquisition, 'The exact original keyed acquisition must be retained');
  const occurrences = moon.clientProgramSerializationOccurrences(program);
  assert.equal(occurrences.length, 1);
  const control = runtimeCore(moon).publicationControl;
  let plan;
  try {
    plan = serializationTaskRunAdmission({moon, control, preparedProgram: program,
      authorityScopeCid: token('a'), namespaceId: 'unfiltered-keyed-content-plan',
      now: () => '2026-10-10T00:00:00.000Z'});
  } catch (cause) {
    throw new Error(inspect({syntax, occurrences,
      tasks: moon.clientProgramTaskCount(program), acquisitions: moon.clientProgramAcquisitionCount(program),
      keyed: moon.clientProgramKeyedAcquisitionCoordinates(acquisition),
      direct: moon.clientProgramKeyedDirectAcquisitionCoordinates(acquisition)}, {depth: 5}), {cause});
  }
  assert.equal(plan.kind, 'serialization');
  const policy = JSON.parse(control.compiledSerializationPolicy(plan.compiled).wire);
  assert.deepEqual(new Set(policy.source_data_policy_cids), new Set(
    JSON.parse(value.environmentWire).schema_snapshots.map(view => view.source_data_policy_cid)));
  assert.equal(control.compiledSourceFreeResultPolicy(plan.compiled), undefined);
  assertOriginalSerializationInput({control, plan, program, acquisition,
    foreignProgram: listingContentProgram(options).preparedProgram,
    joinedInput: syntax === 'json'});
  assert.throws(() => control.issueCheckedClientCompiledInvocation(plan.compiled,
    plan.runDefinition, {dataPolicyCid: control.compiledSerializationPolicy(plan.compiled).cid},
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}), /RunHostInvocationRejected/u);
});

async function capturedListingForOriginalKeyedProgram({empty = false,
  stopCaptureAfterProgress = false, readKeyed,
  listedVersion = 'v1', listingItems, allFiles = false, captureFilter, postJoinFilter,
  lookupPolicy = {}, observeSend = true, ledgerFor, reverseSourceInputs = false, deferCapture = false,
  authorizeRead = async () => ({action: 'dispatch'}), sourceAuthorization,
  sourceFormat = 'json', captureContent, runCaptureContent = false, contentValidator, serialize = false,
  readOperation = 'read', issueReadGrant = () => ({}), modelTask, hostCapacityPolicy, classification,
  publicUnknownSource = false, sourceAccountConfiguration} = {}) {
  // The user Program itself contains the capture filter/projection and JOIN.
  // It is prepared once; no alternate Direct Program or fake completion exists.
  const value = listingContentProgram({capturePrefix: true, emptySelector: empty,
    allFiles, captureFilter, postJoinFilter, lookupPolicy, reverseSourceInputs, sourceFormat, serialize, modelTask,
    hostCapacityPolicy, classification, publicUnknownSource});
  const items = listingItems ?? [item('d', 'invoice.pdf', listedVersion)];
  const keyed = publicUnknownSource ? [] : [0, 1].map(input => ({input, outcome:
    moon.clientProgramPrepareKeyedAcquisition(value.preparedProgram, 0, input, 2)}))
    .filter(entry => entry.outcome.$tag === 1);
  if (!publicUnknownSource) assert.equal(keyed.length, 1);
  const acquisition = publicUnknownSource ? undefined : checked(keyed[0].outcome);
  const [registry, aoa, queryContract, evidenceContract] = await Promise.all([
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8').then(JSON.parse),
    readFile(new URL('../../spec/contracts/actql-query-acquisition.json', import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-query-process-evidence.json', import.meta.url), 'utf8'),
  ]);
  const requirementResult = publicUnknownSource ? undefined : moon.clientProgramPrepareLocalQueryRequirement(
    value.preparedProgram, 0, 1 - keyed[0].input, registry,
    JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
  if (!publicUnknownSource) assert.equal(requirementResult.$tag, 1, inspect(requirementResult.$tag === 0
    ? requirementResult._0 : 'ready', {depth: 5, maxArrayLength: 5, maxStringLength: 200}));
  const requirement = publicUnknownSource ? undefined : checked(requirementResult);
  if (!stopCaptureAfterProgress) {
    const issuer = moon.clientProgramRowReferenceIssuer((kind, wire) =>
      kind === 'file' && items.some(row => wire === canonical(row.resource)),
    (media, wire) => media === 'application/pdf' && (contentValidator === undefined
      ? wire === canonical(admittedContent) : contentValidator(wire)),
    () => true);
    let requests = 0;
    const adapterOptions = {moon,
      declaration: value.declaration, declared: value.declared,
      environmentWire: value.environmentWire, connectorId: 'content-fixture',
      connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
      bindingCid: token('c'), referenceIssuer: issuer, readOperation,
      captureContent: runCaptureContent ? undefined : captureContent,
      site: {connection: 'fixture:files', issueReadGrant, close() {}},
      authorization: sourceAuthorization ?? {authorize: authorizeRead,
        // The fixture Site is unprotected for Compute activation. Reads still
        // use the independent current authorization callback above.
        isProtectedSite: () => false, cover() {},
        accountConfiguration: '{}', context: {contextCid: token('b')}},
      physicalTarget: (resource, fields) => ({resource, fields}),
      limits: {maxPages: 4, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
      readPages: async options => {
        const {resource: target, requestWire, listing, chargePage} = options;
        if (target === 'contents') {
          assert.equal(typeof readKeyed, 'function');
          if (observeSend) await options.beginRequest(Buffer.from(requestWire, 'utf8'));
          return await readKeyed(options);
        }
        assert.equal(target, 'files');
        requests++;
        assert.deepEqual(JSON.parse(requestWire), {glob: null, paths: allFiles ? null : ['invoice.pdf']});
        if (publicUnknownSource) {
          assert.equal(listing, undefined, 'ordinary Source cannot borrow a LIST_FILES ceiling');
          const wire = JSON.stringify(items), body = Buffer.from(wire);
          await options.consumePageWire(wire, {charge: chargePage(body)});
          return;
        }
        await listing.beginRequest(undefined);
        const body = Buffer.from(JSON.stringify({request_token: null, next_token: null,
          items}));
        await listing.consumePage(body, {charge: chargePage(body)});
      }};
    // The public Host receives only declaration/driver originals. It alone
    // checks and compiles this Program and supplies every later preparation.
    if (publicUnknownSource) {
      assert.equal(deferCapture, true);
      assert.equal(value.preparation, undefined);
      const {moon: _moon, declaration: _declaration, declared: _declared,
        environmentWire: _environmentWire, connectorId: _connectorId,
        connectorRegistration: _registration, connectorRevision: _revision,
        site: _site, authorization: _authorization, ...readerOptions} = adapterOptions;
      return {...value, listingRequests: () => requests,
        async load({construction}) {
          assert.ok(construction);
          construction.prepareDeclaration(value.viewsWire, value.declared.catalog_cid);
          await construction.openSpecializedSite({accountConfiguration: sourceAccountConfiguration,
            authorizationConstructor: options => installRowSourceAuthorization({
              ...options, connectorRegistration: 'fixture'}),
            siteConstructor: (_argument, {authorization}) => Object.freeze({
              connection: 'fixture:files', issueReadGrant,
              close() {
                if (authorization.close() !== true) throw new Error('FixtureSourceAuthorizationCleanupPending');
              },
            })});
          return construction.createRowSource(readerOptions);
        }};
    }
    const adapter = await createInstalledRowSource(adapterOptions);
    const joinContracts = {registry, values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
    const occurrence = {stage: 0, input: 1 - keyed[0].input, task: 0};
    const preparedSource = await adapter.prepare({preparedProgram: value.preparedProgram,
      ...joinContracts, occurrence});
    const keyedContent = runCaptureContent ? Object.freeze({capture: captureContent,
      // The Run's Content holder has no Resource issuance authority. The
      // installed Source must preserve that independent domain at admission.
      referenceIssuer: moon.clientProgramRowReferenceIssuer(() => false,
        (media, wire) => media === 'application/pdf' && (contentValidator === undefined
          ? wire === canonical(admittedContent) : contentValidator(wire)), () => true)})
      : undefined;
    if (deferCapture) return {...value, acquisition, adapter, preparedSource, occurrence,
      keyedContent, joinContracts, listingRequests: () => requests};
    const ledger = ledgerFor === undefined ? undefined : await ledgerFor({adapter,
      preparedSource, keyedAcquisition: acquisition, preparedProgram: value.preparedProgram,
      joinContracts, expectedDirectInput: reverseSourceInputs ? 1 : 0});
    const capture = await adapter.openCapture({preparedProgram: value.preparedProgram,
      registry, values: JSON.stringify(aoa.execution_contracts['REL.values']),
      fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered']),
      occurrence, preparedSource, ledger});
    assert.equal(requests, empty ? 0 : 1);
    const source = capture.capture.source();
    const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition, source));
    return {...value, acquisition, source, left, adapter, captured: capture, close: capture.close,
      preparedSource, ledger, keyedContent, joinContracts, listingRequests: () => requests};
  }
  const row = checked(moon.clientProgramRowSourcePrepareAcquisition(
    value.declaration, requirement, queryContract, evidenceContract, undefined));
  const run = checked(moon.clientProgramRowSourceStart(row, 'original-listing-keyed', () => true));
  const issuer = moon.clientProgramResourceReferenceIssuer((kind, wire) =>
    kind === 'file' && wire === canonical(resource('d')), () => true);
  try {
    checked(moon.clientProgramRowSourceBegin(run, 8192, 3, 3, issuer));
    if (!empty) {
      const listing = rowListingCallbacks({moon, run, currentRead: async () => {}});
      await listing.beginRequest(undefined);
      const body = Buffer.from(JSON.stringify({request_token: null, next_token: null,
        items: [item('d', 'invoice.pdf', 'v1')]}));
      await listing.consumePage(body, {charge: checked(moon.clientProgramRowSourceChargePage(run, body))});
    }
    checked(moon.clientProgramRowSourceFinish(run));
    checked(moon.clientProgramRowSourceCaptureBegin(run));
    let complete = false;
    let work = 0n;
    for (let poll = 0; poll < 10000; poll++) {
      const outcome = moon.clientProgramRowSourceCaptureAdvance(run, 1);
      assert.equal(outcome.$tag, 1, inspect(outcome.$tag === 0 ? outcome._0 : 'ready',
        {depth: 5, maxArrayLength: 5, maxStringLength: 200}));
      const {_0: ready, _1: nextWork} = checked(outcome);
      assert.ok(nextWork >= work);
      work = nextWork;
      if (stopCaptureAfterProgress && nextWork > 0n && !ready) {
        return {...value, acquisition, run, work};
      }
      if (ready) { complete = true; break; }
    }
    assert.equal(complete, true);
    const capture = checked(moon.clientProgramRowSourceCapture(run));
    const source = checked(moon.clientProgramRowSourceCaptureSource(capture));
    const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition, source));
    return {...value, acquisition, run, source, left};
  } catch (error) {
    moon.clientProgramRowSourceClose(run);
    moon.clientProgramRowSourceCaptureCleanup(run);
    throw error;
  }
}

test('original Program captured left supplies the exact live version-fixed keyed Request', async t => {
  const value = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  const cursor = checked(moon.clientProgramKeyedRequestStart(value.left, 0, 100000, 10000));
  let request;
  let work = moon.clientProgramKeyedRequestWork(cursor);
  assert.ok(work > 0);
  for (let poll = 0; poll < 10000; poll++) {
    const {_0: status, _1: nextWork, _2: ready} = moon.clientProgramKeyedRequestAdvance(cursor);
    assert.ok(nextWork >= work && nextWork <= 100000);
    work = nextWork;
    assert.notEqual(status, 2);
    if (status === 1) { request = ready; break; }
  }
  assert.ok(request !== undefined);
  assert.deepEqual(JSON.parse(checked(moon.clientProgramKeyedRequestWire(request, 4096))),
    {resource: resource('d'), version: 'v1'});
  const rowAcquisition = checked(moon.clientProgramKeyedRowPrepareAcquisition(
    value.acquisition, request, value.declaration, 4096, 10000, 100000));
  assert.ok(rowAcquisition !== undefined);
  const other = listingContentProgram({capturePrefix: true});
  const input = moon.clientProgramKeyedAcquisitionCoordinates(value.acquisition)[1];
  const foreign = checked(moon.clientProgramPrepareKeyedAcquisition(other.preparedProgram, 0, input, 2));
  assert.equal(moon.clientProgramKeyedRowPrepareAcquisition(foreign, request,
    other.declaration, 4096, 10000, 100000).$tag, 0);
  assert.equal(moon.clientProgramKeyedCaptureLeftRead(foreign, value.source).$tag, 0);
  const pending = checked(moon.clientProgramKeyedRequestStart(value.left, 0, 100000, 10000));
  const before = moon.clientProgramKeyedRequestWork(pending);
  value.close();
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), undefined);
  assert.equal(moon.clientProgramKeyedRequestWire(request, 4096).$tag, 0);
  assert.equal(moon.clientProgramKeyedRowPrepareAcquisition(value.acquisition, request,
    value.declaration, 4096, 10000, 100000).$tag, 0);
  const {_0: status, _1: after, _2: ready} = moon.clientProgramKeyedRequestAdvance(pending);
  assert.equal(status, 2);
  assert.equal(after, before);
  assert.equal(ready, undefined);
});

async function originalKeyedRequest(value, row = 0) {
  const cursor = checked(moon.clientProgramKeyedRequestStart(value.left, row, 100000, 10000));
  for (let poll = 0; poll < 10000; poll++) {
    const {_0: status, _2: request, _3: issue} = moon.clientProgramKeyedRequestAdvance(cursor);
    assert.equal(issue, undefined);
    assert.notEqual(status, 2);
    if (status === 1) return request;
  }
  assert.fail('the original keyed request did not complete');
}

const lookupLedger = () => checked(moon.clientProgramAcquisitionLedger(
  8, 8, 131072n, 1048576n, 64000000n));

test('keyed INFER Source closure requires both original observations and rejects a foreign or closed lookup', async () => {
  // This exercises actual checked Source/lookup owners. Its Ref envelope is
  // explicitly a typed-value fixture, not evidence of physical byte custody.
  const taskSource = await readFile(new URL('../../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
  const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
  task.input_contract = {type: 'object', nullable: false, additional_properties: false,
    fields: {document: {type: 'content_ref', media_type: 'application/pdf', nullable: false}}};
  task.input_schema_cid = cid(task.input_contract);
  delete task.contract_cid;
  task.contract_cid = cid(task);
  for (const empty of [false, true]) {
    let gets = 0;
    const value = await capturedListingForOriginalKeyedProgram({empty, modelTask: task,
      ledgerFor: ({adapter, preparedSource, keyedAcquisition, preparedProgram, joinContracts}) => {
        const occurrences = checked(moon.clientProgramComposedInferOccurrences(preparedProgram));
        assert.equal(occurrences.length, 1);
        const direct = adapter.ledgerCapacity(preparedSource);
        const keyed = adapter.keyedLedgerCapacity(keyedAcquisition);
        const ledger = moon.clientProgramPrepareKeyedInferCapturedLedger(preparedProgram,
          occurrences[0], direct.capacity, keyedAcquisition, keyed.capacity,
          [direct.transferBytes, keyed.transferBytes], [direct.executionBytes, keyed.executionBytes],
          keyed.maxBytes, keyed.maxWork, joinContracts.registry, joinContracts.values,
          joinContracts.fragment, joinContracts.ordered, false);
        assert.ok(ledger !== undefined, 'derive the original whole keyed Model envelope before Source I/O');
        assert.equal(gets, 0, 'capacity selection must not acquire keyed input');
        return ledger;
      },
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
      }});
    let lookup, foreign, foreignLookup, inputOwner, modelOwner, composedOwner, root;
    try {
      const occurrences = checked(moon.clientProgramComposedInferOccurrences(value.preparedProgram));
      assert.equal(occurrences.length, 1);
      const occurrence = occurrences[0], at = '2026-10-10T00:00:00.000Z', scope = token('a');
      const directWire = await value.captured.issueSourceEvidence({authorityScopeCid: scope,
        effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid});
      lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
        keyedAcquisition: value.acquisition, left: value.left, ledger: value.ledger});
      const observed = await lookup.issueObservation({authorityScopeCid: scope, observedAt: at});
      const admit = keyed => moon.clientProgramAdmitComposedInferSources(occurrence,
        [value.captured.capture.source()], [value.captured.identity], [value.captured.requirement],
        [value.captured.logicalInput], [checked(moon.strategyRunEvidenceAdmit(
          'source_evidence', directWire, 100000, 10000, 100))], scope, at, at, keyed);
      assert.equal(admit(undefined).$tag, 0,
        'Direct evidence cannot omit the original keyed Source obligation');
      const admitted = admit(observed.observation);
      assert.equal(admitted.$tag, 1, inspect({
        reason: 'the original complete right observation joins the same Model Source closure',
        issue: admitted.$tag === 0 ? admitted._0 : undefined,
        occurrence: moon.clientProgramInferOccurrenceCoordinates(occurrence),
        keyed: moon.clientProgramKeyedAcquisitionCoordinates(value.acquisition),
        taskCount: moon.clientProgramTaskCount(value.preparedProgram),
      }, {depth: 6}));
      assert.equal(gets, empty ? 0 : 1);
      const {registry, values, fragment, ordered} = value.joinContracts;
      const segments = checked(moon.clientProgramPrepareComposedInferSegments(
        value.preparedProgram, occurrence, registry, values, fragment, ordered));
      assert.equal(moon.clientProgramStartComposedInferInput(occurrence,
        segments._0, [], undefined).$tag, 0,
      'input execution cannot bypass its original Source closure');
      inputOwner = checked(moon.clientProgramStartComposedInferInput(occurrence,
        segments._0, [], checked(admitted)));
      let rows, lastPoll;
      for (let poll = 0; poll < 10000; poll++) {
        lastPoll = checked(moon.clientProgramAdvanceInferInput(inputOwner, 1));
        rows = moon.clientProgramInferInputRows(lastPoll);
        if (rows !== undefined) break;
      }
      assert.ok(rows !== undefined, inspect(lastPoll, {depth: 6}));
      // This isolated mapper fixture has no physical attachment preflight.
      // The normal Model owner must reject that omission before any send;
      // typed input mapping alone is not physical byte-custody acceptance.
      const requests = [];
      const provider = moon.clientProgramInstallModelProvider(task.connector_id, request => {
        requests.push(JSON.parse(moon.clientProgramModelRequestInput(request, 'document')));
        return moon.clientProgramModelResponse(request, '{"reason":null,"risk":"high"}',
          'typed-content-fixture', 'fixture-request', 1n, 2n, at);
      });
      assert.ok(provider !== undefined);
      modelOwner = checked(moon.clientProgramStartModelExecution(rows, provider, token('b')));
      let capture, modelIssue;
      for (let poll = 0; poll < 10000; poll++) {
        const outcome = moon.clientProgramAdvanceModelExecution(modelOwner, 1);
        if (outcome.$tag === 0) { modelIssue = outcome._0; break; }
        const observation = checked(outcome);
        modelIssue = moon.clientProgramModelExecutionPollIssue(observation);
        if (modelIssue !== undefined) break;
        capture = moon.clientProgramModelCapture(observation);
        if (capture !== undefined) break;
      }
      assert.deepEqual(requests, [], 'no missing-preflight Content may reach a provider');
      if (empty) {
        assert.equal(modelIssue, undefined);
        assert.ok(capture !== undefined);
        assert.equal(JSON.parse(moon.clientProgramModelCaptureJson(capture)).captures.length, 0);
      } else {
        assert.equal(capture, undefined);
        assert.ok(modelIssue !== undefined, 'a terminal refusal must be observed');
        assert.equal(moon.clientProgramModelExecutionContentIssue(modelIssue), 'Role');
      }
      assert.equal(gets, empty ? 0 : 1, 'mapping never reacquires content');
      assert.equal(checked(moon.clientProgramCleanupModelExecution(modelOwner)), true);
      modelOwner = undefined;
      assert.equal(checked(moon.clientProgramCleanupInferInput(inputOwner)), true);
      inputOwner = undefined;
      // Exercise the actual composed Model input/identity owner as well as
      // the isolated mapper. These dependency CIDs are identity fixtures only;
      // no executable media policy or dispatch permission is fabricated.
      const executionBody = {version: 'actql-model-execution-contract/0.1',
        model_task_contract_cid: task.contract_cid,
        retry_classification_contract_cid: token('a'), backoff_contract_cid: token('a'),
        max_attempts_per_slot: 2, max_total_attempts: 4, max_total_cost_units: 0,
        max_total_duration_ms: 1000, max_total_token_reservation: 128,
        max_total_wire_bytes: 131072, media_input_contracts: {document: token('c')},
        default_publication: 'outcomes'};
      const execution = checked(moon.clientProgramReadComposedInferModelExecution(occurrence,
        canonical({...executionBody, self_cid: cid(executionBody)}), cid(executionBody)));
      const graph = checked(moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
      const control = runtimeCore(moon).publicationControl;
      const plan = inferTaskRunAdmission({moon, control, preparedProgram: value.preparedProgram,
        inferGraph: graph, authorityScopeCid: scope, namespaceId: 'keyed-model-scope', now: () => at});
      composedOwner = checked(moon.clientProgramStartComposedInferExecution(occurrence,
        graph, segments._0, [], provider, checked(admitted)));
      control.bindCheckedClientInferRun(plan.compiled, composedOwner, plan.runDefinition);
      let scopeWire;
      for (let poll = 0; poll < 10000; poll++) {
        const observation = checked(moon.clientProgramAdvanceInferExecution(composedOwner, 1));
        if (moon.clientProgramInferCallScopeUnitId(composedOwner) !== undefined) {
          scopeWire = checked(moon.clientProgramInferCallScopeSnapshot(composedOwner));
          break;
        }
        assert.equal(moon.clientProgramInferExecutionPollKind(observation), 'continue',
          inspect(moon.clientProgramInferExecutionPollIssue(observation), {depth: 6}));
      }
      assert.ok(scopeWire !== undefined, 'the original JOIN must reach its Model scope');
      const snapshot = JSON.parse(scopeWire);
      assert.deepEqual(snapshot.sources.map(source => source.name), ['files', 'contents']);
      assert.deepEqual(snapshot.sources.map(source => source.source_evidence_wire),
        [directWire, observed.sourceEvidenceWire]);
      assert.deepEqual(snapshot.sources.map(source => source.source_input_wire),
        [moon.strategyRunEvidenceJson(value.captured.logicalInput), observed.inputLogicalWire]);
      const inputArtifacts = JSON.parse(snapshot.effective_inputs_wire).input_artifacts;
      assert.deepEqual(inputArtifacts, {
        files: JSON.parse(moon.strategyRunEvidenceJson(value.captured.logicalInput)).input_logical_cid,
        contents: JSON.parse(observed.inputLogicalWire).input_logical_cid,
      });
      // This callback is an explicit custody fixture, not authentication or a
      // physical Store recovery. The common reader checks original bindings.
      const readScope = (wire, available = true) => control.readCheckedClientComposedInferSavedInputScope(
        plan.compiled, plan.runDefinition, occurrence, graph, wire, scope, () => available);
      assert.ok(readScope(scopeWire) !== undefined);
      assert.throws(() => readScope(scopeWire, false));
      assert.throws(() => readScope(canonical({...snapshot, sources: snapshot.sources.slice(0, 1)})));
      assert.throws(() => readScope(canonical({...snapshot, sources: [...snapshot.sources].reverse()})));
      assert.deepEqual(requests, [], 'Source scope issuance grants no Model send');
      moon.clientProgramCancelInferExecution(composedOwner);
      checked(moon.clientProgramAdvanceInferExecution(composedOwner, 1));
      assert.equal(checked(moon.clientProgramCleanupInferExecution(composedOwner)), true);
      composedOwner = undefined;
      // The installed root drives this same checked keyed input owner. It
      // cannot use a Local-bound component or fabricate a source-free prefix.
      root = openNodeInferOperation({moon, preparedProgram: value.preparedProgram,
        graph, provider, computeSuffix: segments._1, durableCalls: true,
        keyedInput: {occurrence, prefix: segments._0, sources: checked(admitted), ledger: value.ledger}});
      root.bindRun(control, plan);
      if (empty) {
        assert.ok(await root.run(), 'the original empty keyed root completes without a Model call');
      } else {
        // This fixture intentionally lacks a physical attachment owner. Do
        // not weaken that refusal to claim approval or byte-custody coverage.
        await assert.rejects(root.run(), error => error.code === 'MoonBitHostFailure' &&
          moon.clientProgramInferExecutionContentIssue(error.cause) === 'Role');
      }
      assert.deepEqual(requests, [], 'keyed root construction and waiting grant no Model send');
      assert.equal(gets, empty ? 0 : 1, 'keyed root must borrow, not reacquire, its original lookup');
      await root.close();
      assert.equal(root.cleanupPending(), false);
      root = undefined;
      foreign = await capturedListingForOriginalKeyedProgram({empty, modelTask: task,
        readKeyed: async ({requestWire, consumePage}) => {
          await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
        }});
      foreignLookup = await foreign.adapter.openKeyedLookup({preparedProgram: foreign.preparedProgram,
        keyedAcquisition: foreign.acquisition, left: foreign.left, ledger: lookupLedger()});
      const other = await foreignLookup.issueObservation({authorityScopeCid: scope, observedAt: at});
      assert.equal(admit(other.observation).$tag, 0,
        'equal source bytes from a separately prepared owner cannot substitute for this occurrence');
      await lookup.close();
      assert.equal(admit(observed.observation).$tag, 0,
        'closing the original lookup revokes this borrowed closure');
      assert.equal(moon.clientProgramStartComposedInferInput(occurrence,
        segments._0, [], checked(admitted)).$tag, 0,
      'a retained closure cannot reopen a closed lookup');
    } finally {
      await root?.close();
      if (composedOwner !== undefined) {
        moon.clientProgramCancelInferExecution(composedOwner);
        checked(moon.clientProgramAdvanceInferExecution(composedOwner, 1));
        checked(moon.clientProgramCleanupInferExecution(composedOwner));
      }
      if (modelOwner !== undefined) {
        moon.clientProgramCancelModelExecution(modelOwner);
        checked(moon.clientProgramCleanupModelExecution(modelOwner));
      }
      if (inputOwner !== undefined) {
        moon.clientProgramCancelInferInput(inputOwner);
        checked(moon.clientProgramCleanupInferInput(inputOwner));
      }
      await foreignLookup?.close();
      await foreign?.close();
      await lookup?.close();
      await value.close();
    }
  }
});

test('original keyed lookup supplies bounded SERIALIZE input without recapture or fabricated coverage', async t => {
  for (const empty of [false, true]) {
    let gets = 0;
    const core = runtimeCore(moon), publications = core.publicationControl;
    const control = core.contentGenerationControl;
    const limits = {maxRows: 3, maxWork: 100000, maxEntries: 1000,
      maxValueBytes: 4096, maxValueNodes: 1000, maxValueDepth: 16, maxFrames: 100};
    const now = () => '2026-10-10T00:00:00.000Z';
    const authorityScopeCid = token('a');
    let plan;
    const value = await capturedListingForOriginalKeyedProgram({empty, serialize: true,
      ledgerFor: ({adapter, preparedSource, keyedAcquisition, preparedProgram, joinContracts}) => {
        plan = serializationTaskRunAdmission({moon, control: publications, preparedProgram,
          authorityScopeCid, namespaceId: 'keyed-content-input', now});
        const direct = adapter.ledgerCapacity(preparedSource);
        const keyed = adapter.keyedLedgerCapacity(keyedAcquisition);
        const {task, step} = plan.serializationGraph;
        // Derive the admitted envelope before I/O from the actual Source and
        // prefix declarations, not sampled rows or a guessed generous budget.
        const prefix = control.prefixCapacity(preparedProgram, task, step,
          joinContracts, limits, undefined, true);
        const ledger = moon.clientProgramPrepareKeyedSerializationCapturedLedger(preparedProgram,
          direct.capacity, keyedAcquisition, keyed.capacity,
          [direct.transferBytes, keyed.transferBytes], [direct.executionBytes, keyed.executionBytes],
          keyed.maxBytes, keyed.maxWork, joinContracts.registry, joinContracts.values,
          joinContracts.fragment, joinContracts.ordered, task, step,
          prefix.retainedBytes, prefix.executionBytes, false);
        assert.ok(ledger !== undefined, 'the common owner sizes the complete original input custody');
        return ledger;
      },
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
      }}).catch(error => {
        t.diagnostic(inspect({boundary: 'original SERIALIZE source capture', error}, {depth: 8}));
        throw error;
      });
    let lookup, prefix, input;
    let work = 0;
    const remainingWork = () => limits.maxWork - work;
    const chargeWork = delta => (work += delta) <= limits.maxWork;
    try {
      lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
        keyedAcquisition: value.acquisition, left: value.left, ledger: value.ledger});
      const sourceEvidenceWire = await value.captured.issueSourceEvidence({authorityScopeCid,
        effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid});
      const keyedObservation = await lookup.issueObservation({authorityScopeCid, observedAt: now()});
      const observation = {sourceEvidenceWire, authorityScopeCid,
        captureStartedAt: now(), captureCompletedAt: now(), keyedObservation};
      assert.throws(() => publications.bindCheckedClientSerializationCapture(value.preparedProgram,
        plan.serializationGraph, value.captured, {...observation, keyedObservation: undefined}),
      {code: 'RunHostContentCaptureRejected'}, 'Direct evidence alone cannot discharge the keyed Source');
      const proof = publications.bindCheckedClientSerializationCapture(value.preparedProgram,
        plan.serializationGraph, value.captured, observation);
      const {task, step} = plan.serializationGraph;
      const capacity = control.prefixCapacity(value.preparedProgram, task, step,
        value.joinContracts, limits, undefined, value.source);
      assert.ok(capacity.retainedBytes > 0n && capacity.executionBytes > 0n);
      prefix = control.prefix(value.preparedProgram, task, step,
        value.joinContracts, limits, value.ledger, undefined, value.source,
        await lookup.borrowSerializationInput());
      const output = await runGeneratedContentPrefix({control, prefix,
        remainingWork, chargeWork, quantum: 7});
      const barrier = control.prepare(value.preparedProgram, task, step, 10000);
      const encoder = control.encoder(barrier, {maxRows: 3, maxBytes: 4096,
        maxValueNodes: 1000, maxValueDepth: 16, maxFrames: 100});
      input = control.bindInput(barrier, output, encoder);
      const identity = await identifyGeneratedContentInput({control, compiled: plan.compiled,
        input, limits: localOutputLimits, identityLimits: localContractLimits,
        maxWorkspaceSlots: 4 * localOutputLimits.maxWireNodes + 8 * localOutputLimits.maxColumns,
        remainingWork, chargeWork, captured: proof});
      assert.equal(JSON.parse(identity.wire).row_count, empty ? 0 : 1);
      const chunks = [];
      const generated = await writeGeneratedContent({control, input,
        writer: {async append(piece) { chunks.push(piece); }}, remainingWork, chargeWork, quantum: 7});
      // Opaque-envelope fixture only. The independently authored reference is
      // serialized canonically, not dereferenced or claimed as actual PDF bytes.
      const expected = empty ? '' : '{"name":"invoice.pdf","content":' + canonical(admittedContent) + '}\n';
      assert.equal(chunks.join(''), expected);
      assert.equal(generated.contentCid, `sha256:${createHash('sha256').update(expected).digest('hex')}`);
      assert.equal(generated.rowCount, empty ? 0 : 1);
      assert.equal(value.listingRequests(), empty ? 0 : 1);
      assert.equal(gets, empty ? 0 : 1, 'prefix, identity and byte generation never reacquire content');
      assert.ok(work > 0);
      assert.equal(stopGeneratedContentPrefix({control, prefix, chargeWork}), true);
      prefix = undefined;
      await lookup.close();
      assert.throws(() => publications.bindCheckedClientSerializationCapture(value.preparedProgram,
        plan.serializationGraph, value.captured, observation), {code: 'RunHostContentCaptureRejected'});
    } finally {
      if (input) control.inputCancel(input);
      if (prefix) assert.equal(stopGeneratedContentPrefix({control, prefix, chargeWork}), true);
      await lookup?.close();
      await value.close();
    }
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(value.ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),
      [0n, 0n, 0n, 0n]);
  }
});

function declaredKeyedRunLedger({adapter, preparedSource, keyedAcquisition,
  preparedProgram, joinContracts, expectedDirectInput}) {
  const direct = adapter.ledgerCapacity(preparedSource);
  const keyed = adapter.keyedLedgerCapacity(keyedAcquisition);
  const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
  assert.deepEqual([coordinates._0, coordinates._1, coordinates._2], [0, expectedDirectInput, 0],
    'the actual Direct root follows the declared source occurrence');
  const rowBytes = moon.clientProgramKeyedRowCapacityBytes(keyed.capacity);
  assert.deepEqual([rowBytes._0, rowBytes._1], [4096n, 16384n],
    'one exact keyed row reserves wire plus page/value/request workspace');
  const assembly = moon.clientProgramKeyedLookupCapacity(keyedAcquisition, keyed.maxBytes, keyed.maxWork);
  assert.deepEqual([assembly._0, assembly._1, assembly._2, assembly._3],
    [3n, 3n, 61632n, 32036864n],
    'declaration ceilings are independent of sampled or empty result rows');
  const ledger = moon.clientProgramPrepareKeyedCapturedLocalInstalledLedger(preparedProgram,
    direct.capacity, keyedAcquisition, keyed.capacity,
    [direct.transferBytes, keyed.transferBytes], [direct.executionBytes, keyed.executionBytes],
    keyed.maxBytes, keyed.maxWork,
    joinContracts.registry, joinContracts.values, joinContracts.fragment, joinContracts.ordered);
  assert.ok(ledger, 'one original Run Ledger is admitted before physical acquisition');
  return ledger;
}

function originalKeyedCompiledRun(preparedProgram) {
  const compilation = checked(moon.clientProgramCompileLocalTasks(preparedProgram));
  const run = checked(moon.clientProgramIssueTaskCompiledRun(preparedProgram, compilation,
    token('a'), token('b'), '2026-10-10T00:00:00.000Z'));
  const definition = checked(moon.clientProgramIssueCompiledRunDefinition(run,
    'fixture', 'original-keyed-run', '2026-10-09T00:00:00.000Z', '2026-10-10T00:00:00.000Z'));
  return {run, definition};
}

test('installed lookup uses one shared work allowance before content I/O', async t => {
  let sends = 0;
  const value = await capturedListingForOriginalKeyedProgram({readKeyed: async () => { sends++; }});
  t.after(value.close);
  const ledger = lookupLedger();
  // The request's authored canonical encoding alone consumes this allowance;
  // original extraction, role rechecks and assembly entry are not free.
  const maxWork = canonical({resource: resource('d'), version: 'v1'}).length;
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger, maxWork}),
  error => ['InstalledKeyedRequestFailed', 'MoonBitHostFailure'].includes(error.code)
    && error.outcome === 'not_started');
  assert.equal(sends, 0);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5), [0n, 0n, 0n, 0n, 0n]);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('original whole lookup refuses right-input sealing before every left occurrence is accepted', async t => {
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    listingItems: [item('d', 'first.pdf', 'v1'), item('e', 'second.pdf', 'v2')],
    readKeyed: async ({requestWire, consumePage}) => {
      await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
    }});
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  let right;
  t.after(async () => {
    moon.clientProgramKeyedLookupStop(lookup);
    await right?.close();
    let closed = false;
    for (let poll = 0; poll < 10000; poll++) {
      if (checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) { closed = true; break; }
    }
    assert.equal(closed, true);
  });
  assert.equal(moon.clientProgramKeyedLookupRead(lookup).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupIdentity(lookup), undefined);
  assert.equal(moon.clientProgramKeyedLookupIssueObservation(lookup,
    token('a'), '2026-10-09T00:00:00.000Z').$tag, 0,
  'an unfinished original key set cannot issue complete Source evidence');
  const {registry, values, fragment, ordered} = value.joinContracts;
  assert.equal(moon.clientProgramKeyedLookupJoinPrepare(value.preparedProgram,
    lookup, registry, values, fragment, ordered), undefined,
  'JOIN cannot be prepared from a partial key set');
  const foreign = listingContentProgram({capturePrefix: true, allFiles: true});
  assert.equal(moon.clientProgramKeyedLookupJoinPrepare(foreign.preparedProgram,
    lookup, registry, values, fragment, ordered), undefined,
  'equal Program wire does not replace original owner');
  const request = await originalKeyedRequest(value);
  right = await value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger});
  right.acceptLookup(lookup);
  assert.equal(moon.clientProgramKeyedLookupRead(lookup).$tag, 0, 'provisional row is not an input');
  let copied = false;
  for (let poll = 0; poll < 10000; poll++) {
    if (checked(moon.clientProgramKeyedLookupAdvance(lookup, 1))) { copied = true; break; }
  }
  assert.equal(copied, true);
  assert.equal(moon.clientProgramKeyedLookupRead(lookup).$tag, 0,
    'one complete key cannot settle a two-occurrence original lookup');
  assert.equal(moon.clientProgramKeyedLookupIdentity(lookup), undefined);
  assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger)).reservedRetentionBytes > 0n);
});

test('installed whole lookup assembles every original key before exposing its exact right input', async t => {
  const items = [item('e', 'second.pdf', 'v2'), item('d', 'first.pdf', 'v1')];
  const requests = [];
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    listingItems: items, readKeyed: async ({requestWire, consumePage}) => {
      const request = JSON.parse(requestWire);
      requests.push(request);
      await consumePage([{content: admittedContent, ...request}]);
    }});
  t.after(value.close);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2);
  const ledger = lookupLedger();
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger, quantum: 1});
  t.after(lookup.close);
  assert.deepEqual(requests, items.map(row => ({resource: row.resource, version: row.version})));
  assert.ok(lookup.capture.read());
  assert.equal(lookup.capture.read(), lookup.read, 're-read keeps the original opaque input binding');
  assert.equal(lookup.capture.identity(), cid(items.map(row => ({content: admittedContent,
    resource: row.resource, version: row.version}))));
  const work = lookup.work();
  assert.ok(work > 0n);
  assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger)).heldBytes > 0n);
  await lookup.close();
  assert.throws(lookup.capture.read, {code: 'InstalledSourceClosed'});
  assert.throws(lookup.capture.identity, {code: 'InstalledSourceClosed'});
  assert.equal(lookup.work(), work, 'cleanup preserves original cumulative work');
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  await lookup.close();
  assert.equal(requests.length, 2, 'close cannot reopen acquisition');
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2,
    'assembly cleanup does not close its borrowed original left');
});

// Private compiled provider diagnostic: the normal Host still has to reserve
// the prepared capacity and seal original Source/task evidence. It does not
// claim a packed public Run or final aggregate resource proof.
async function consumeOriginalJoin(prepared, quantum, {cancelAfterWork = false, dag} = {}) {
  const execution = checked(dag === undefined
    ? moon.clientProgramKeyedLookupJoinStart(prepared)
    : moon.clientProgramKeyedLookupDagJoinStart(prepared, dag));
  let stream;
  let stopped = false;
  try {
    let output;
    for (let poll = 0; poll < 100000; poll++) {
      const value = checked(moon.clientProgramKeyedLookupJoinAdvance(execution, quantum));
      if (cancelAfterWork && checked(moon.clientProgramKeyedLookupJoinWork(execution)) > 0n) {
        moon.clientProgramKeyedLookupJoinCancel(execution);
      }
      if (value.$tag === 3) { output = value._0; stopped = true; break; }
      if (value.$tag === 6) { stopped = true; break; }
      assert.equal(value.$tag, 0, inspect(value, {depth: 4}));
    }
    assert.equal(stopped, true, 'original managed JOIN reaches a terminal poll');
    const work = checked(moon.clientProgramKeyedLookupJoinWork(execution));
    assert.ok(work > 0n);
    if (cancelAfterWork) {
      assert.equal(output, undefined, 'cancelled JOIN exposes no partial completion');
      return {work};
    }
    assert.ok(output, 'existing JOIN, not acquisition prefix, issued the completion');
    stream = checked(moon.clientProgramKeyedJoinOutputExportBegin(output));
    const rows = [];
    for (let row = 0; row < 1000; row++) {
      const wire = checked(moon.clientProgramKeyedJoinOutputExportNext(stream));
      if (wire === undefined) break;
      // The common row-frame separator is not part of the canonical row.
      rows.push(JSON.parse(wire.slice(1)));
      assert.ok(row < 999, 'bounded common export must terminate');
    }
    const {_0: fields, _1: relationCid, _2: schemaCid} = checked(
      moon.clientProgramKeyedJoinOutputExportFinish(stream));
    return {rows, fields, relationCid, schemaCid, work};
  } finally {
    if (stream !== undefined) moon.clientProgramKeyedJoinOutputExportClose(stream);
    if (!stopped) {
      moon.clientProgramKeyedLookupJoinCancel(execution);
      for (let poll = 0; poll < 100000 && !stopped; poll++) {
        const value = checked(moon.clientProgramKeyedLookupJoinAdvance(execution, quantum));
        stopped = [3, 5, 6].includes(value.$tag);
      }
    }
    let reclaimed = false;
    for (let poll = 0; poll < 10000; poll++) {
      if (checked(moon.clientProgramKeyedLookupJoinCleanup(execution))) { reclaimed = true; break; }
    }
    assert.equal(reclaimed, true, 'same existing provider owns stop and cleanup');
  }
}

test('real assembled lookup feeds only the original managed JOIN with its actual filtered left', async t => {
  const totals = [];
  for (const quantum of [1, 7, 64]) {
    const items = [item('e', 'second.pdf', 'v2'), item('f', 'skip.pdf', 'v3'), item('d', 'first.pdf', 'v1')];
    const requested = [];
    const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
      captureFilter: "name <> 'skip.pdf'", listingItems: items,
      postJoinFilter: "name = 'first.pdf'",
      readKeyed: async ({requestWire, consumePage}) => {
        const request = JSON.parse(requestWire);
        requested.push(request);
        await consumePage([{content: admittedContent, ...request}]);
      }});
    t.after(value.close);
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger: lookupLedger(), quantum});
    t.after(lookup.close);
    const prepared = await lookup.prepareJoin(value.joinContracts);
    assert.ok(prepared);
    const capacity = moon.clientProgramKeyedLookupJoinCapacity(prepared);
    assert.ok(capacity[0] > 0n && capacity[1] >= capacity[0]);
    const result = await consumeOriginalJoin(prepared, quantum);
    // Schema export uses canonical UTF-16 field order. Authored public Result
    // field order is a separate publication contract, not this private schema.
    assert.deepEqual(result.fields, ['content', 'name']);
    assert.equal(result.schemaCid, cid({
      content: {type: 'content_ref', media_type: 'application/pdf', nullable: false},
      name: {type: 'string', nullable: false},
    }));
    const expected = [
      {name: 'second.pdf', content: admittedContent},
      {name: 'first.pdf', content: admittedContent},
    ];
    assert.deepEqual(result.rows, expected);
    assert.equal(result.rows.length, 2,
      'this child completes only JOIN; later WHERE and public Result remain pending');
    assert.equal(result.relationCid, cid({sort: 'relation', value: expected}));
    assert.deepEqual(requested, [
      {resource: resource('e'), version: 'v2'},
      {resource: resource('d'), version: 'v1'},
    ], 'WHERE placement excludes the third listed Resource before content I/O');
    totals.push(result.work);
    await lookup.close();
    assert.equal(moon.clientProgramKeyedLookupJoinStart(prepared).$tag, 0,
      'preparation cannot grant liveness after the original input closes');
    assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2,
      'JOIN cleanup does not collect the borrowed acquisition');
  }
  assert.equal(totals[0], totals[1]);
  assert.equal(totals[1], totals[2]);
});

test('checked capture prefix and keyed JOIN occupy distinct original task ports', () => {
  for (const emptySelector of [false, true]) {
    const value = listingContentProgram({capturePrefix: true, emptySelector,
      postJoinFilter: "name = 'invoice.pdf'"});
    assert.equal(moon.clientProgramTaskCount(value.preparedProgram), 3);
    const layout = moon.clientProgramKeyedLookupTaskLayout(value.preparedProgram)
      .map(value => [value._0, value._1, value._2, value._3]);
    assert.deepEqual(layout, [
      [0, undefined, 1, 2],
      [1, 2, undefined, 2],
      [2, 3, undefined, 1],
    ], 'schema/selection, not observed rows, fixes acquisition and consumer boundaries');
  }
});

test('normal captured DAG binds original filtered capture and sealed keyed input to JOIN ports', async t => {
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    listingItems: [item('e', 'second.pdf', 'v2'), item('f', 'skip.pdf', 'v3'), item('d', 'first.pdf', 'v1')],
    captureFilter: "name <> 'skip.pdf'", postJoinFilter: "name = 'first.pdf'",
    readKeyed: async ({requestWire, consumePage}) => {
      await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
    }});
  t.after(value.close);
  // A normal Host uses the same finite Run Ledger for acquisition, planning
  // and Compute; the acquisition-only fixture deliberately has no planning.
  const ledger = checked(moon.clientProgramAcquisitionLedger(
    8, 8, 8000000n, 268435456n, 536870912n, 100000));
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger});
  t.after(lookup.close);
  const prepared = await lookup.prepareJoin(value.joinContracts);
  const host = await lookup.openHost(value.joinContracts);
  t.after(() => moon.strategyHostStop(host));
  assert.equal(moon.strategyHostNextTask(host), 1,
    'the normal Host starts at JOIN, not capture or a later consumer');
  assert.equal(moon.strategyHostManagedInputCount(host), 2);
  const dag = await lookup.openDag();
  t.after(() => moon.clientProgramKeyedLookupDagStop(dag));
  assert.equal(moon.clientProgramKeyedLookupDagInputs(dag, 0).$tag, 0,
    'the capture is not the keyed consumer');
  assert.equal(moon.clientProgramKeyedLookupDagInputs(dag, 2).$tag, 0,
    'later WHERE cannot run before JOIN completes');
  const result = await consumeOriginalJoin(prepared, 7, {dag});
  assert.deepEqual(result.rows, [
    {name: 'second.pdf', content: admittedContent},
    {name: 'first.pdf', content: admittedContent},
  ]);
  assert.equal(moon.clientProgramKeyedLookupDagInputs(dag, 2).$tag, 0,
    'a private provider result alone cannot mark the normal task complete');
  moon.clientProgramKeyedLookupDagStop(dag);
  assert.equal(moon.clientProgramKeyedLookupDagInputs(dag, 1).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupDagJoinStart(prepared, dag).$tag, 0);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2,
    'stopping the DAG cannot close the borrowed physical capture');
  // Execute through the standard installed Host, not the private JOIN child.
  // Its next task applies the original post-JOIN WHERE before completion.
  const completedRows = [];
  let retainedRead;
  const observer = installCompletionObserver(async ({task, readRetained}) => {
    if (task !== 2) return;
    assert.equal(typeof readRetained, 'function');
    retainedRead = readRetained;
    await readRetained(wire => completedRows.push(JSON.parse(wire)));
  });
  const executed = await runCapturedInternalStrategy(host, {}, undefined, observer);
  t.after(() => executed.close());
  assert.equal(executed.status, 'host-tasks-completed', executed.failure?.stack);
  assert.equal(moon.strategyHostTaskCompleted(host, 1), true);
  assert.equal(moon.strategyHostTaskCompleted(host, 2), true);
  assert.deepEqual(completedRows, [{name: 'first.pdf', content: admittedContent}]);
  await executed.close();
  assert.equal(executed.cleanupPending(), false);
  await assert.rejects(retainedRead(() => {}), /RetainedUnavailable|ManagedInputUnavailable/);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2,
    'normal Host output cleanup cannot close the borrowed acquisition');
});

test('original Direct prefix issues only its own live Source observation before keyed I/O', async t => {
  let allowed = true;
  let gets = 0;
  const value = await capturedListingForOriginalKeyedProgram({
    authorizeRead: async () => ({action: allowed ? 'dispatch' : 'deny'}),
    readKeyed: async () => { gets++; },
  });
  t.after(value.close);
  assert.equal(value.captured.setup, undefined,
    'a sealed prefix cannot start a Host before its keyed input exists');
  const logical = JSON.parse(moon.strategyRunEvidenceJson(value.captured.logicalInput));
  const evidenceOptions = {authorityScopeCid: token('a'),
    effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid};
  const evidence = JSON.parse(await value.captured.issueSourceEvidence(evidenceOptions));
  assert.equal(logical.completeness, 'complete');
  assert.equal(evidence.completeness, 'complete');
  assert.equal(evidence.source_ref, value.declared.views.find(view => view.resource === 'files').source_ref);
  assert.equal(evidence.source_contract_cid, logical.source_contract_cid);
  const {input_logical_cid: logicalCid, ...logicalBody} = logical;
  assert.equal(logicalCid, cid(logicalBody),
    'logical evidence hashes its declared body, without its self CID');
  assert.equal(evidence.input_logical_cid, logicalCid);
  assert.equal(evidence.effective_data_policy_cid, evidenceOptions.effectiveDataPolicyCid);
  assert.equal(gets, 0, 'prefix evidence neither captures nor certifies keyed content');
  allowed = false;
  await assert.rejects(value.captured.issueSourceEvidence(evidenceOptions),
    {code: 'ExecutionAuthorizationDenied'});
  allowed = true;
  await value.close();
  await assert.rejects(value.captured.issueSourceEvidence(evidenceOptions));
  assert.equal(gets, 0, 'revocation and cleanup never acquire content to recreate proof');
});

test('complete keyed lookup issues its own logical input and live Source observation', async t => {
  for (const empty of [true, false]) {
    let gets = 0;
    let allowed = true;
    const value = await capturedListingForOriginalKeyedProgram({empty,
      authorizeRead: async () => ({action: allowed ? 'dispatch' : 'deny'}),
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
      }});
    t.after(value.close);
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger: lookupLedger()});
    t.after(lookup.close);
    const options = {authorityScopeCid: token('a'), observedAt: '2026-10-09T00:00:00.000Z'};
    await assert.rejects(lookup.issueObservation({...options, observedAt: '2026-10-09T00:00:00Z'}),
      {code: 'MoonBitHostFailure'}, 'the registered observation wire requires millisecond precision');
    const observed = await lookup.issueObservation(options);
    const input = JSON.parse(observed.inputLogicalWire);
    const evidence = JSON.parse(observed.sourceEvidenceWire);
    const expected = empty ? [] : [{resource: resource('d'), version: 'v1', content: admittedContent}];
    assert.equal(input.logical_relation_cid, cid({sort: 'relation', value: expected}));
    assert.equal(evidence.snapshot_ref, cid(expected),
      'physical ordered rows and logical Relation use distinct preimages');
    assert.equal(input.relation_schema_cid, cid({
      content: {type: 'content_ref', media_type: 'application/pdf', nullable: false},
      resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
      version: {type: 'string', nullable: false},
    }));
    assert.equal(evidence.source_ref, value.declared.views.find(view => view.resource === 'contents').source_ref);
    assert.equal(evidence.input_logical_cid, input.input_logical_cid);
    assert.equal(evidence.source_contract_cid, input.source_contract_cid);
    assert.equal(evidence.consistency_level, 'read_committed');
    assert.deepEqual(evidence.ordering_evidence, {stable: false, keys: []});
    assert.equal(evidence.authority_scope_cid, options.authorityScopeCid);
    assert.equal(evidence.completeness, 'complete');
    assert.equal(gets, empty ? 0 : 1);
    const compiled = originalKeyedCompiledRun(value.preparedProgram);
    const leftEvidenceWire = await value.captured.issueSourceEvidence({
      authorityScopeCid: options.authorityScopeCid,
      effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid});
    const leftLogicalWire = moon.strategyRunEvidenceJson(value.captured.logicalInput);
    const publicationPolicy = moon.clientProgramPublicationDataPolicyCid(value.preparedProgram);
    assert.equal(typeof publicationPolicy, 'string');
    assert.equal(moon.clientProgramIssueCompiledTaskInvocation(compiled.run, compiled.definition,
      leftEvidenceWire, leftLogicalWire, value.captured.checkedSource.sourceRef,
      value.captured.checkedSource.sourceContractCid, options.authorityScopeCid,
      value.captured.checkedSource.sourceDataPolicyCid,
      '2026-10-09T00:00:00.000Z', '2026-10-09T00:00:01.000Z', 100000, 10000, 100).$tag, 0,
    'one Direct observation cannot claim whole-Run coverage of a keyed Source');
    const issueInvocation = (run = compiled.run, definition = compiled.definition,
      scope = options.authorityScopeCid, policy = publicationPolicy) =>
      moon.clientProgramIssueCompiledKeyedTaskInvocation(run, definition,
        value.captured.capture.source(), value.captured.identity, value.captured.requirement,
        leftEvidenceWire, leftLogicalWire, observed.observation, scope, policy,
        '2026-10-09T00:00:00.000Z', '2026-10-09T00:00:01.000Z', 100000, 10000, 100);
    const issued = checked(issueInvocation());
    const wholeObservation = JSON.parse(moon.strategyRunEvidenceJson(issued._0));
    assert.deepEqual(wholeObservation.source_evidence_cids,
      [JSON.parse(leftEvidenceWire).source_evidence_cid, evidence.source_evidence_cid],
      'the original Run observes both Sources, not only its captured task prefix');
    assert.equal(wholeObservation.data_policy_cid, publicationPolicy);
    const foreign = originalKeyedCompiledRun(listingContentProgram({
      capturePrefix: true, emptySelector: empty}).preparedProgram);
    assert.equal(issueInvocation(foreign.run, foreign.definition).$tag, 0,
      'an independently prepared equal Program is not the original capture owner');
    assert.equal(issueInvocation(compiled.run, foreign.definition).$tag, 1,
      'equal admitted contract facts remain valid only with the original opaque compilation and capture');
    const different = originalKeyedCompiledRun(listingContentProgram({
      capturePrefix: true, emptySelector: empty, postJoinFilter: "name = 'different.pdf'"}).preparedProgram);
    assert.equal(issueInvocation(compiled.run, different.definition).$tag, 0,
      'a definition for a different compiled Program cannot bind the observation');
    assert.equal(issueInvocation(compiled.run, compiled.definition, token('c')).$tag, 0);
    assert.equal(issueInvocation(compiled.run, compiled.definition,
      options.authorityScopeCid, token('d')).$tag, 0);
    if (!empty) {
      allowed = false;
      await assert.rejects(lookup.issueObservation(options), {code: 'ExecutionAuthorizationDenied'});
      allowed = true;
      assert.deepEqual(await lookup.issueObservation(options), observed,
        'same bytes and observation inputs preserve wire identity, without another GET');
    }
    await lookup.close();
    assert.equal(moon.clientProgramKeyedLookupObservationWires(observed.observation), undefined);
    assert.equal(issueInvocation().$tag, 0,
      'a previously sealed wire does not restore closed physical capture custody');
    await assert.rejects(lookup.issueObservation(options), {code: 'InstalledSourceClosed'});
    assert.equal(gets, empty ? 0 : 1);
  }
});

test('actual Host publication plan retains both original keyed Source dependencies', async t => {
  for (const empty of [true, false]) {
    let gets = 0;
    const value = await capturedListingForOriginalKeyedProgram({empty, ledgerFor: declaredKeyedRunLedger,
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
      }});
    t.after(value.close);
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger: value.ledger});
    t.after(lookup.close);
    const now = () => '2026-10-09T00:00:00.000Z';
    const authorityScopeCid = token('a');
    const control = runtimeCore(moon).publicationControl;
    const acquired = acquiredTaskRunAdmission({moon, control, preparedProgram: value.preparedProgram,
      authorityScopeCid, namespaceId: 'keyed-publication', now});
    const sourceEvidenceWire = await value.captured.issueSourceEvidence({authorityScopeCid,
      effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid});
    const keyedObservation = await lookup.issueObservation({authorityScopeCid, observedAt: now()});
    const options = {moon, control, acquired, preparedProgram: value.preparedProgram,
      captured: value.captured, sourceEvidence: control.admitRunEvidence('source_evidence',
        sourceEvidenceWire, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
      keyedObservation, authorityScopeCid,
      effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(value.preparedProgram),
      captureStartedAt: now(), captureCompletedAt: '2026-10-09T00:00:01.000Z',
      namespaceId: 'keyed-publication', storeAuthorityCid: token('d'), now};
    const plan = acquiredKeyedTaskPublicationPlan(options);
    assert.equal(plan.admission, acquired.admission, 'the admission owner is reused, not reconstructed');
    assert.equal(plan.runDefinition, acquired.runDefinition);
    const rightRows = empty ? [] : [{resource: resource('d'), version: 'v1', content: admittedContent}];
    const leftRows = empty ? [] : [{name: 'invoice.pdf', resource: resource('d'), version: 'v1'}];
    const expectedDependencies = [...new Set([leftRows, rightRows].map(rows =>
      cid({sort: 'relation', value: rows})))];
    assert.deepEqual(plan.results[0].evidenceContext.inputRelationCids, expectedDependencies,
      'independent logical Relation preimages cover both Sources, including empty content');
    const sourceCids = [sourceEvidenceWire, keyedObservation.sourceEvidenceWire].map(wire =>
      JSON.parse(wire).source_evidence_cid);
    assert.deepEqual(plan.receiptEvidence.sourceEvidence.map(evidence => evidence.identity), sourceCids);
    const observation = JSON.parse(plan.observation.wire);
    assert.deepEqual(observation.source_evidence_cids, sourceCids);
    assert.deepEqual(observation.captured_input_artifact_cids, [],
      'physical Source capture is not relabeled as a replayable captured input Artifact');
    assert.equal(observation.data_policy_cid, options.effectiveDataPolicyCid);
    assert.equal(plan.results[0].evidenceContext.effectiveDataPolicyCid, options.effectiveDataPolicyCid);
    assert.equal(plan.results[0].evidenceContext.scopeCid, acquired.runDefinition.identity);
    assert.equal(plan.request.publicationTargetCid, token('d'));
    assert.ok(plan.results[0].transformation, 'the original compiled Result transformation is retained');
    assert.throws(() => acquiredTaskPublicationPlan(options),
      error => error.code === 'RunHostTaskInvocationRejected',
      'one Direct prefix cannot publish a keyed Run as complete');
    for (const replacement of [
      {sourceEvidence: {...options.sourceEvidence}},
      {sourceEvidence: control.admitRunEvidence('source_evidence', keyedObservation.sourceEvidenceWire,
        {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})},
      {effectiveDataPolicyCid: token('e')},
      {authorityScopeCid: token('e')},
      {acquired: {...acquired, compiled: {...acquired.compiled}}},
    ]) {
      // Empty logical inputs can coincide, but the full Source-specific
      // logical wire still differs by schema and Source contract.
      assert.throws(() => acquiredKeyedTaskPublicationPlan({...options, ...replacement}));
    }
    await lookup.close();
    assert.throws(() => acquiredKeyedTaskPublicationPlan(options), /InvalidAcquiredTaskPublication/,
      'retaining a plan input wire does not restore closed physical custody');
    assert.equal(gets, empty ? 0 : 1, 'plan issuance and failed substitution cannot re-fetch content');
  }
});

test('actual keyed Host executes and commits ordinary Named Result publication', async t => {
  const scratch = await createOwnedScratch({
    parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'keyed-publication-', label: 'keyed Host publication diagnostic'});
  const now = () => '2026-10-09T00:00:00.000Z';
  const control = runtimeCore(moon).publicationControl;
  const authorityScopeCid = token('a');
  const storeAuthorityCid = token('d');
  const store = await openLocalPublicationStore({directory: scratch.path,
    storeAuthorityCid, capacityBytes: 512 * 1024 * 1024,
    // Six independent publications each reserve nineteen bounded objects.
    maxObjectBytes: 10 * 1024 * 1024, maxObjects: 200,
    maxContractNodes: 10000, maxContractDepth: 64}, control);
  t.after(() => store.close());
  for (const {empty, reverseSourceInputs, sourceFormat = 'json'} of [
    {empty: true, reverseSourceInputs: false},
    {empty: false, reverseSourceInputs: false},
    {empty: true, reverseSourceInputs: true},
    {empty: false, reverseSourceInputs: true},
    {empty: false, reverseSourceInputs: false, sourceFormat: 'aql-text'},
    {empty: false, reverseSourceInputs: false, sourceFormat: 'sql'},
  ]) {
    const requests = [];
    const value = await capturedListingForOriginalKeyedProgram({empty, reverseSourceInputs, sourceFormat,
      ledgerFor: declaredKeyedRunLedger,
      readKeyed: async ({requestWire, consumePage}) => {
        const request = JSON.parse(requestWire);
        requests.push(request);
        await consumePage([{...request, content: admittedContent}]);
      }});
    t.after(value.close);
    const ledger = value.ledger;
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger});
    t.after(lookup.close);
    const acquired = acquiredTaskRunAdmission({moon, control,
      preparedProgram: value.preparedProgram, authorityScopeCid,
      namespaceId: 'keyed-publication', now});
    const plan = acquiredKeyedTaskPublicationPlan({moon, control, acquired,
      preparedProgram: value.preparedProgram, captured: value.captured,
      sourceEvidence: control.admitRunEvidence('source_evidence',
        await value.captured.issueSourceEvidence({authorityScopeCid,
          effectiveDataPolicyCid: value.captured.checkedSource.sourceDataPolicyCid}),
        {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
      keyedObservation: await lookup.issueObservation({authorityScopeCid, observedAt: now()}),
      authorityScopeCid, effectiveDataPolicyCid:
        moon.clientProgramPublicationDataPolicyCid(value.preparedProgram),
      captureStartedAt: now(), captureCompletedAt: '2026-10-09T00:00:01.000Z',
      namespaceId: 'keyed-publication', storeAuthorityCid, now});
    const host = await lookup.openHost({...value.joinContracts, retainedRelationOutput: true});
    let execution;
    t.after(async () => { if (execution !== undefined) await execution.close(); });
    const configuration = installLocalRetainedStore((_key, bytes, frame) =>
      createLocalRetainedStore({parentDirectory: scratch.path,
        capacityBytes: bytes, maxFrameBytes: frame, maxEntries: 1}));
    const published = await runPublishedCapturedStrategy(host, {store, plan}, {local: configuration},
      undefined, undefined, retained => { execution = retained; }).catch(error => {
      assert.fail(inspect({sourceFormat, code: error.code, cause: error.cause,
        failure: execution?.failure, status: execution?.status,
        completed: execution?.completed}, {depth: 10, maxStringLength: 2000}));
    });
    assert.equal(published.status, 'published');
    assert.equal(published.execution, execution);
    assert.equal(execution.status, 'host-tasks-completed', execution.failure?.stack);
    assert.equal(published.publication.publication.state, 'succeeded');
    assert.deepEqual(execution.completed.map(result => result.task),
      sourceFormat === 'sql' ? [1, 2, 3] : [1],
      'SQL retains its post-JOIN filter and final projection as separate checked tasks');
    const evidence = published.publication.evidence;
    assert.equal(evidence.definitions.length, 1);
    const result = published.publication.results[0];
    const expectedRows = empty ? [] : [{name: 'invoice.pdf', content: admittedContent}];
    assert.equal(JSON.parse(result.publication.durableBinding.wire).logical_result_cid,
      cid({sort: 'relation', value: expectedRows}));
    // Read through the committed Store boundary, not a completed task's live
    // output or an uncommitted prepared payload.
    const key = {namespaceId: 'keyed-publication', runDefinitionCid: plan.runDefinition.identity,
      authorityScopeCid};
    const chunks = [];
    const metadata = await store.consumeCommittedResult(key, evidence.definitions[0].identity,
      () => true, bytes => chunks.push(Buffer.from(bytes)));
    assert.equal(metadata.rowCount, expectedRows.length);
    assert.deepEqual(metadata.resultFields, ['name', 'content']);
    assert.equal(metadata.logicalResultCid, cid({sort: 'relation', value: expectedRows}));
    assert.equal(Buffer.concat(chunks).toString('utf8'), canonical(expectedRows),
      'committed payload bytes match the independent ordered-row fixture');
    await published.close();
    assert.equal(published.cleanupPending(), false);
    assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), empty ? 0 : 1,
      'Compute cleanup does not close borrowed acquisition custody');
    await lookup.close();
    await value.close();
    const retainedChunks = [];
    const reread = await store.consumeCommittedResult(key, evidence.definitions[0].identity,
      () => true, bytes => retainedChunks.push(Buffer.from(bytes)));
    assert.equal(reread.logicalResultCid, metadata.logicalResultCid,
      'ordinary Named Result retention outlives temporary acquisition/Compute cleanup');
    assert.equal(Buffer.concat(retainedChunks).toString('utf8'), canonical(expectedRows));
    assert.equal(requests.length, empty ? 0 : 1);
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),
      [0n, 0n, 0n, 0n]);
  }
  await store.close();
  scratch.passed();
});

test('installed dispatch owns original keyed acquisition through committed Store cleanup', async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'keyed-dispatch-', label: 'installed keyed dispatch diagnostic'});
  const now = () => '2026-10-09T00:00:00.000Z';
  const control = runtimeCore(moon).publicationControl;
  const authorityScopeCid = token('a'), storeAuthorityCid = token('d');
  const namespaceId = 'keyed-dispatch';
  const store = await openLocalPublicationStore({directory: scratch.path,
    storeAuthorityCid, capacityBytes: 512 * 1024 * 1024,
    maxObjectBytes: 10 * 1024 * 1024, maxObjects: 200,
    maxContractNodes: 10000, maxContractDepth: 64}, control);
  t.after(() => store.close());
  for (const [index, {empty, reverseSourceInputs, missingCheckpointInventory = false,
    sourceFormat = 'json'}] of [
    {empty: true, reverseSourceInputs: false},
    {empty: false, reverseSourceInputs: false},
    {empty: false, reverseSourceInputs: true},
    {empty: false, reverseSourceInputs: false, missingCheckpointInventory: true},
    {empty: false, reverseSourceInputs: false, sourceFormat: 'aql-text'},
    {empty: false, reverseSourceInputs: false, sourceFormat: 'sql'},
  ].entries()) {
    let gets = 0, claims = 0;
    const value = await capturedListingForOriginalKeyedProgram({empty, reverseSourceInputs, sourceFormat,
      deferCapture: true, readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{...JSON.parse(requestWire), content: admittedContent}]);
      }});
    const plan = acquiredTaskRunAdmission({moon, control, preparedProgram: value.preparedProgram,
      authorityScopeCid, namespaceId, requestId: `keyed-dispatch-${index}`, now});
    const ref = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
    const events = [];
    const stops = [];
    let physicalCloseConfirmed = false;
    // The actual dispatch/acquisition/Compute/Store owners run here. This
    // journal fixture supplies one admitted claim, not public Client admission
    // or durable restart evidence.
    let publicationFailure;
    const owner = installNodeClientDispatchOwner({moon, control, store,
      runPublished: async (...args) => {
        try { return await runPublishedCapturedStrategy(...args); }
        catch (error) { publicationFailure = error; throw error; }
      },
      journal: {reservePhysicalStart() {
        assert.equal(value.listingRequests(), 0);
        assert.equal(gets, 0, 'all declaration-derived capacity precedes provider I/O');
        claims++;
        return true;
      }, lookupRunDefinition: () => ({runDefinition: plan.runDefinition, revision: 1,
        cancellationRequested: false, physicalCloseConfirmed}),
      lookupReconciliationState: () => undefined,
      markPhysicalClose(_ref, outcome) { physicalCloseConfirmed = true; stops.push(outcome); },
      markPreDispatchFailure() {
        assert.equal(missingCheckpointInventory, true,
          'a complete valid keyed dispatch must reserve its physical start');
      }},
      startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
      planFor: () => plan, sourceProfile: value.adapter, ...value.joinContracts,
      prepareAcquisition: (preparedProgram, sourceAccess, occurrence) => value.adapter.prepare({
        preparedProgram, sourceAccess, occurrence, ...value.joinContracts}),
      observed: (event, detail) => events.push({event, detail}),
      ...(missingCheckpointInventory ? {checkpoints: {
        heldOrigin: () => false,
        releaseAcquisition() {},
      }} : {}),
      namespaceId, authorityScopeCid, storeAuthorityCid, now, retainedRelationOutput: true});
    t.after(owner.drain);
    const held = {plan, preparedSource: value.preparedSource,
      preparedSourceAccess: value.adapter.sourceAccess};
    assert.equal(await owner.start({preparedProgram: value.preparedProgram, requestId: `keyed-dispatch-${index}`,
      principalId: 'fixture', connection: {}}, {}, {ref, runDefinition: plan.runDefinition}, held),
    missingCheckpointInventory ? 'not_started' : 'started');
    await owner.drain().catch(error => assert.fail(inspect(error,
      {depth: 6, maxArrayLength: 8, maxStringLength: 500})));
    const committed = await store.confirmCommittedIndex(ref);
    if (missingCheckpointInventory) {
      assert.equal(committed, undefined);
      assert.equal(claims, 0);
      assert.equal(gets, 0);
      assert.equal(value.listingRequests(), 0);
      assert.deepEqual(stops, []);
      assert.equal(events.find(event => event.event === 'dispatch_failed')?.detail.code,
        'InstalledKeyedSourceAdmissionInventoryUnavailable');
      continue;
    }
    assert.ok(committed, inspect({sourceFormat, failure: publicationFailure?.execution?.failure,
      code: publicationFailure?.code,
      events: events.filter(event => event.event === 'dispatch_failed')}, {depth: 10}));
    assert.equal(committed.durable_result_binding_cids.length, 1);
    const binding = await store.readJsonObject(committed.durable_result_binding_cids[0],
      'durable_result_binding');
    const chunks = [];
    const metadata = await store.consumeCommittedResult(ref, binding.result_definition_cid,
      () => true, bytes => chunks.push(Buffer.from(bytes)));
    const expected = empty ? [] : [{name: 'invoice.pdf', content: admittedContent}];
    assert.equal(Buffer.concat(chunks).toString('utf8'), canonical(expected));
    assert.equal(metadata.logicalResultCid, cid({sort: 'relation', value: expected}));
    assert.equal(claims, 1);
    assert.equal(value.listingRequests(), empty ? 0 : 1);
    assert.equal(gets, empty ? 0 : 1);
    assert.deepEqual(stops, [null]);
    const cleanup = events.find(event => event.event === 'dispatch_cleanup_completed');
    assert.ok(cleanup);
    for (const quantity of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']) {
      assert.equal(cleanup.detail.resourceUsage[quantity], '0', quantity);
    }
  }
  await store.close();
  scratch.passed();
});

for (const entrance of ['Local', 'HTTPS']) {
for (const verifyUnattestedRefusal of [false, true]) {
test(verifyUnattestedRefusal
  ? `public ${entrance} keyed captured INFER refuses unattested Request values before Source or Model I/O`
  : `public ${entrance} keyed captured INFER uses the original Model root and Store bytes`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'keyed-infer-public-', label: 'original keyed Content Model root'});
  const payload = Buffer.from('%PDF-1.7\nversion-fixed fixture\n');
  const {task, installation: modelInstallation, hostCapacityPolicy} = await mediaInstallation({
    requestBytes: 4096, contentBytes: payload.length, mediaType: 'application/pdf'});
  const account = canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'keyed-model-public', entries: [{entry_id: 'fixture-allow', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {all: true}, exclusions: []}]});
  const sourceAuthorization = await installRowSourceAuthorization({accountConfiguration: account,
    principalId: userInfo().username, root: join(scratch.path, 'host'), connectorRegistration: 'fixture'});
  t.after(() => sourceAuthorization.close());
  let gets = 0, calls = 0, physicalIssue, client, host, server, previousCertificates;
  const events = [];
  const value = await capturedListingForOriginalKeyedProgram({deferCapture: true,
    sourceAuthorization, modelTask: task, hostCapacityPolicy, classification: 'internal', runCaptureContent: true,
    captureFilter: 'name IS NOT NULL',
    readKeyed: async ({requestWire, consumePage, captureContent, chargePage}) => {
      gets++;
      const charge = chargePage(payload);
      const content = await captureContent({bytes: payload, mediaType: 'application/pdf',
        contentCid: `sha256:${createHash('sha256').update(payload).digest('hex')}`});
      await consumePage([{...JSON.parse(requestWire), content}], {charge});
    }});
  const profileVersion = 'actql-installed-content-fixture-source/0.1';
  const connectorTable = createInstalledConnectorTable([{name: 'fixture', registration: 'fixture',
    revision: 'fixture/0.1', source: {profileVersion, load: async () => ({
      check: profile => profile, identityParts: profile => [profile],
      load: async () => Object.freeze({...value.adapter, requiresRunContentCapture: true,
        async openKeyedLookup(options) {
          try { return await value.adapter.openKeyedLookup(options); }
          catch (error) { physicalIssue = error; throw error; }
        }}),
    })}}]);
  const sourceProfilePath = join(scratch.path, 'source-profile.json');
  await writeFile(sourceProfilePath, canonical({version: profileVersion,
    queryAliases: value.declared.views.map(view => ({
      name: view.resource === 'files' ? 'docs.listing' : 'docs.contents',
      sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
      schemaContractCid: view.carrier_schema_cid}))}));
  const keys = generateKeyPairSync('ed25519');
  const {evidence_bundle_cid: ignoredModelCid, ...modelEnvironment} = JSON.parse(modelInstallation.environmentWire);
  void ignoredModelCid;
  modelEnvironment.host_policy_profile = JSON.parse(value.environmentWire).host_policy_profile;
  modelInstallation.environmentWire = canonical({...modelEnvironment, evidence_bundle_cid: cid(modelEnvironment)});
  const installation = {directory: join(scratch.path, 'host'), sourceProfilePath, connectorTable,
    hostLookupExecutionPolicy: JSON.parse(value.environmentWire).host_policy_profile.lookup_execution,
    modelInstallation, hostCapacityPolicy,
    registerModelProviders: generatedContentModelProviders({root: scratch.path, task, expected: payload,
      onSend: () => calls++, onFailure: error => { physicalIssue = error; }}),
    authorization: {accountConfiguration: account,
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      observe: (event, detail) => events.push({event, detail})}};
  if (!verifyUnattestedRefusal) {
    const files = value.declared.views.find(view => view.resource === 'files');
    const declaredView = JSON.parse(value.environmentWire).source_views.find(
      view => view.contract_cid === files.view_cid);
    assert.ok(declaredView);
    installation.verifyRequestValuePolicy = async subject => {
      // Trusted fixture policy for this exact synthetic selector, not a
      // classification inferred from arbitrary values or the response policy.
      assert.equal(subject.source_ref, files.source_ref);
      assert.equal(subject.source_view_contract_cid, files.view_cid);
      assert.deepEqual(subject.request, {glob: null, paths: ['invoice.pdf']});
      assert.deepEqual(subject.origins, {glob: 'literal', paths: 'literal'});
      assert.ok(Object.isFrozen(subject.request.paths));
      return declaredView.output.data_policy.cid;
    };
  }
  t.after(async () => {
    await client?.close();
    if (server !== undefined) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
    if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
  });
  try {
  if (entrance === 'Local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  } else {
    const {key, cert, ca} = await fixtureCertificates(scratch.path);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer keyed-model' ? userInfo().username : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'keyed-model', durability: 'durable'});
  }
  } catch (error) { assert.fail(inspect(error, {depth: 10, maxStringLength: 2000})); }
  const submission = client.startSource(JSON.stringify(value.program), {format: 'json',
    submissionRef: client.newSubmission({nonce: 'original-keyed-model'})});
  if (verifyUnattestedRefusal) {
    // This separate regression proves the existing fail-closed boundary; it
    // cannot substitute for the original Program's successful chain above.
    await assert.rejects(submission, error => error.code === 'SubmissionPreparationFailed' &&
      error.outcome?.problem?.code === 'ClientProgramUnsupported');
    const admission = events.find(value => value.event === 'infer_preparation_rejected');
    assert.equal(admission?.detail.boundary, 'model_admission');
    assert.equal(admission?.detail.code, 'MoonBitHostFailure');
    // The pinned primitive enum representation maps 2 to UnknownClassification.
    assert.equal(admission?.detail.cause, 2);
    assert.equal(value.listingRequests(), 0);
    assert.equal(gets, 0);
    assert.equal(calls, 0);
    assert.equal(physicalIssue, undefined);
    scratch.passed();
    return;
  }
  const run = await submission.catch(error =>
    assert.fail(inspect({error, events, listingRequests: value.listingRequests(),
      contentRequests: gets, modelCalls: calls, physicalIssue},
    {depth: 10, maxStringLength: 2000})));
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(state.status, 'succeeded', inspect({state, events, physicalIssue}, {depth: 10}));
  const expected = [{name: 'invoice.pdf', outcome: 'ok', value: {reason: null, risk: 'high'}}];
  assert.deepEqual(await run.result('r').all(), expected);
  assert.deepEqual(await (await client.attach(run.ref)).result('r').all(), expected);
  assert.equal(value.listingRequests(), 1);
  assert.equal(gets, 1);
  assert.equal(calls, 1);
  const cleanup = events.find(({event}) => event === 'dispatch_cleanup_completed');
  assert.ok(cleanup, 'the root settles before its original acquired children');
  for (const quantity of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']) {
    assert.equal(cleanup.detail.resourceUsage[quantity], '0', quantity);
  }
  scratch.passed();
});
}
}

test('keyed read preparation binds the original Program, port and exact declared response', async () => {
  for (const reverseSourceInputs of [false, true]) {
    const value = await capturedListingForOriginalKeyedProgram({deferCapture: true, reverseSourceInputs});
    const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
      token('a'), 'keyed-read-selection', moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(requestIdentity);
    const selected = await value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, requestIdentity});
    assert.deepEqual(selected.occurrence, {stage: 0, input: reverseSourceInputs ? 0 : 1, task: 1});
    assert.deepEqual(selected.prepared.physicalBinding, {resource: 'contents', fields: ['content', 'resource', 'version']});
    assert.equal(selected.prepared.checkedSource.requirementCid, undefined);
    const selection = {version: 'actql-installed-keyed-selection/0.1',
      programCid: moon.clientRequestProgramCid(requestIdentity),
      parametersCid: moon.clientRequestParametersCid(requestIdentity),
      // The original Program has filter step 0, select step 1, JOIN step 2.
      coordinates: [0, reverseSourceInputs ? 0 : 1, 1, 2], sourceFacts: checked(
        moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(value.acquisition))};
    assert.equal(selected.prepared.checkedSource.selectionCid, cid(selection));
    assert.equal(value.listingRequests(), 0);
    const other = listingContentProgram({emptySelector: true, capturePrefix: true});
    const foreignRequest = moon.clientProgramRequestIdentity(other.preparedProgram,
      token('a'), 'keyed-read-selection', moon.clientProgramSourceFreeInputIntentCid());
    await assert.rejects(value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, requestIdentity: foreignRequest}),
    {code: 'InstalledSourceProgramMismatch'});
    await value.adapter.close();
  }
});

test('retained keyed read checks its original preparation and current authority without source I/O', async () => {
  let action = 'dispatch', checks = 0, onAuthorize;
  const value = await capturedListingForOriginalKeyedProgram({deferCapture: true,
    authorizeRead: async () => { checks++; onAuthorize?.(); return {action}; }});
  try {
    const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
      token('a'), 'retained-keyed-read', moon.clientProgramSourceFreeInputIntentCid());
    const selected = await value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, requestIdentity});
    const options = {preparedProgram: value.preparedProgram, keyedAcquisition: value.acquisition,
      preparedKeyed: selected.prepared};
    const before = checks;
    await assert.rejects(value.adapter.verifyKeyedRead({...options,
      preparedKeyed: {...selected.prepared}}), {code: 'InstalledSourcePreparationMismatch'});
    const other = listingContentProgram({emptySelector: true, capturePrefix: true});
    await assert.rejects(value.adapter.verifyKeyedRead({...options,
      preparedProgram: other.preparedProgram}), {code: 'InstalledSourcePreparationMismatch'});
    assert.equal(checks, before, 'copied/foreign input cannot even enter current read authorization');
    assert.equal((await value.adapter.verifyKeyedRead(options)).action, 'dispatch');
    action = 'deny';
    await assert.rejects(value.adapter.verifyKeyedRead(options), {code: 'ExecutionAuthorizationDenied'});
    action = 'dispatch';
    const cancellation = new AbortController();
    onAuthorize = () => cancellation.abort();
    await assert.rejects(value.adapter.verifyKeyedRead({...options, signal: cancellation.signal}),
      {name: 'AbortError'});
    onAuthorize = () => { selected.prepared.physicalBinding.fields.push('changed-after-read'); };
    await assert.rejects(value.adapter.verifyKeyedRead(options), {code: 'InstalledSourcePreparationMismatch'});
    assert.equal(value.listingRequests(), 0, 'rechecking authority does not list or acquire input');
  } finally { await value.adapter.close(); }
});

for (const entrance of ['Local', 'HTTPS']) {
for (const retainedRelationOutput of [false, true]) {
for (const byteBacked of [false, true]) {
for (const serializing of byteBacked && !retainedRelationOutput ? [false, true] : [false]) {
for (const {empty, cancel} of serializing ? [{empty: false, cancel: false},
  {empty: true, cancel: false}, {empty: false, cancel: true}] : [{empty: false, cancel: false}]) {
for (const publicUnknownSource of entrance === 'Local' && !retainedRelationOutput && byteBacked && !serializing
  ? [false, true] : [false]) {
test(`public ${entrance} Client ${retainedRelationOutput ? 'retained-file' : 'managed'} ${serializing ? `SERIALIZE ${empty ? 'empty ' : cancel ? 'cancelled ' : ''}` : ''}${byteBacked ? 'byte-backed capture' : 'envelope fixture'} retains the complete keyed inventory and original JOIN custody${publicUnknownSource ? ' without numeric row facts' : ''}`, async t => {
  const formats = [
    {format: 'json', reverseSourceInputs: false},
    {format: 'json', reverseSourceInputs: true},
    {format: 'aql-text', reverseSourceInputs: false},
    {format: 'sql', reverseSourceInputs: false},
  ];
  // Text JOIN must capture real Store-backed bytes, not only admit an opaque
  // envelope. Generated text SERIALIZE is a separate composed boundary below.
  for (const {format, reverseSourceInputs} of serializing || publicUnknownSource ? formats.slice(0, 1) : formats) {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: 'keyed-public-', label: `public keyed ${entrance} Client`});
    const account = canonical({version: 'actql-execution-account-config/0.1',
      account_id: 'keyed-public', entries: [{entry_id: 'read-write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: serializing ? {all: true} : {any_of: ['read', 'write']}, exclusions: []}]});
    const sourceAuthorization = publicUnknownSource ? undefined : await installRowSourceAuthorization({accountConfiguration: account,
      principalId: userInfo().username, root: join(scratch.path, 'host'), connectorRegistration: 'fixture'});
    t.after(() => sourceAuthorization?.close());
    const contentControl = runtimeCore(moon).contentCaptureControl;
    const contentLimits = {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096};
    const contentStore = !byteBacked ? undefined : await openLocalPublicationStore({
      directory: join(scratch.path, 'captured-bytes'), storeAuthorityCid: token('1'),
      capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
      maxContractNodes: 1000, maxContractDepth: 32}, runtimeCore(moon).publicationControl);
    const preparedObjects = [], writers = [], holdings = [], issuedWires = new Set();
    let contentStoreClosed = false;
    let expectedContent = admittedContent;
    const payload = Buffer.from('%PDF-1.7\nversion-fixed fixture\n', 'utf8');
    const contentCid = `sha256:${createHash('sha256').update(payload).digest('hex')}`;
    const captureContent = !byteBacked ? undefined : async ({bytes, mediaType,
      keyedAcquisition, request, readSubjectCid, verifyRead, signal}) => {
      assert.deepEqual(bytes, payload);
      assert.equal(mediaType, 'application/pdf');
      await verifyRead();
      signal.throwIfAborted();
      const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      const binding = {content_store_id: 'fixture', content_store_cid: token('1'),
        workspace_scope_cid: token('2'), storage_scope: 'workspace',
        retention_class: 'fixture', availability_evidence_cid: token('3'),
        effective_data_policy_cid: facts[3], data_classification: facts[4],
        issuer_contract_cid: token('5'), capture_authority_cid: readSubjectCid};
      const allocationsBeforeRefusal = writers.length;
      for (const [wrongBinding, wrongMedia] of [
        [{...binding, effective_data_policy_cid: token('9')}, mediaType],
        [binding, 'text/plain'],
      ]) assert.throws(() => contentControl.candidate(keyedAcquisition, request, wrongBinding,
        {mediaType: wrongMedia, contentCid, sizeBytes: bytes.length}, contentLimits),
      {code: 'MoonBitHostFailure'});
      assert.equal(writers.length, allocationsBeforeRefusal,
        'policy/MIME refusal allocates no new Store writer, including after an earlier capture');
      const candidate = contentControl.candidate(keyedAcquisition, request, binding,
        {mediaType, contentCid, sizeBytes: bytes.length}, contentLimits);
      const description = contentControl.inspect(candidate);
      // Expected bodies are authored from physical facts, not product output.
      const issuerBody = {version: 'actql-content-issuer-evidence/0.1',
        issuer_kind: 'connector_capture', issuer_contract_cid: token('5'),
        content_store_cid: token('1'), workspace_scope_cid: token('2'),
        content_cid: contentCid, effective_data_policy_cid: facts[3],
        capture_authority_cid: readSubjectCid, reported_media_type: mediaType};
      const refBody = {$actql_ref: 'content', version: 'actql-content-ref/0.1',
        media_type: mediaType, metadata: {content_store_id: 'fixture', content_cid: contentCid,
          media_type: mediaType, storage_scope: 'workspace', retention_class: 'fixture',
          availability_evidence_cid: token('3'), capture_authority: 'read_content',
          data_classification: facts[4], effective_data_policy_cid: facts[3],
          size_bytes: bytes.length, truncated: false,
          issuer_evidence: {...issuerBody, evidence_cid: cid(issuerBody)}}};
      const expectedCapturedContent = {...refBody, content_ref_cid: cid(refBody)};
      assert.equal(description.wire, canonical(expectedCapturedContent));
      const originalRequest = JSON.parse(checked(moon.clientProgramKeyedRequestWire(request, 4096)));
      if (canonical(originalRequest.resource) === canonical(resource('d'))) {
        expectedContent = expectedCapturedContent;
      }
      const holdingCid = cid({capture: readSubjectCid, content: description.identity});
      const issue = (overrides = {}) => issueStoredCapturedContent({store: contentStore,
        control: contentControl, candidate, holdingCid,
        workspaceScopeCid: token('2'), effectiveDataPolicyCid: facts[3],
        available: () => !signal.aborted,
        authorize: () => !signal.aborted, limits: contentLimits, ...overrides});
      await assert.rejects(issue(), {code: 'CapturedContentHoldingMismatch'});
      const retained = await retainCapturedContent({store: contentStore,
        control: contentControl, candidate, bytes, holdingCid,
        workspaceScopeCid: token('2'), effectiveDataPolicyCid: facts[3],
        available: () => !signal.aborted, authorize: () => !signal.aborted,
        limits: contentLimits, signal,
        retainCustody: ({writer, prepared, holding}) => {
          if (writer) writers.push(writer);
          if (prepared) preparedObjects.push(prepared);
          if (holding) holdings.push(holding);
        }});
      assert.equal(retained.wire, description.wire);
      await verifyRead();
      signal.throwIfAborted();
      await issue();
      await assert.rejects(issue({workspaceScopeCid: token('9')}),
        {code: 'CapturedContentBindingMismatch'});
      await assert.rejects(issue({authorize: () => false}), {code: 'MoonBitHostFailure'});
      issuedWires.add(description.wire);
      return JSON.parse(description.wire);
    };
    t.after(async () => {
      if (!contentStore || contentStoreClosed) return;
      for (const holding of holdings) await contentStore.retirePhysicalHolding(holding.holding_cid);
      for (const prepared of preparedObjects) await prepared.retry();
      for (const writer of writers) await writer.cancel();
      await contentStore.close();
      contentStoreClosed = true;
    });
    let gets = 0, captureError;
    const value = await capturedListingForOriginalKeyedProgram({deferCapture: true,
      reverseSourceInputs, sourceAuthorization, sourceAccountConfiguration: account,
      serialize: serializing, publicUnknownSource,
      ...(empty ? {allFiles: true, listingItems: []} : {}),
      ...(format === 'json' ? {} : {allFiles: true,
        listingItems: [item('d', 'invoice.pdf', 'v1'), item('f', 'skip.pdf', 'v2')]}),
      captureContent, contentValidator: byteBacked ? wire => issuedWires.has(wire) : undefined,
      readKeyed: async ({requestWire, consumePage, captureContent: capture, chargePage}) => {
        try {
          gets++;
          const charge = byteBacked ? chargePage(payload) : undefined;
          const content = !byteBacked ? admittedContent : await capture({bytes: payload,
            mediaType: 'application/pdf'});
          await consumePage([{...JSON.parse(requestWire), content}], {charge});
        } catch (error) { captureError = error; throw error; }
      }});
    if (publicUnknownSource) {
      assert.equal(value.preparation, undefined, 'no fixture-only Program check or compile');
      const declaration = value.declared.views.find(view => view.resource === 'files');
      assert.ok(declaration);
      const facts = value.declared.contracts.map(JSON.parse)
        .filter(envelope => envelope.kind === 'carrier_facts').map(envelope => envelope.body);
      assert.ok(facts.some(body => Object.keys(body).length === 0),
        'the direct Source carries no numeric row-count fact');
      assert.ok(facts.every(body => body.file_listing === undefined));
      const right = facts.find(body => body.file_content !== undefined);
      assert.equal(right.file_content.version_capability.required_nonnull, true);
      assert.equal(right.lookup_capacity.max_rows_per_key, 1);
      assert.equal(format, 'json');
    }
    const profileVersion = 'actql-installed-content-fixture-source/0.1';
    const connectorTable = createInstalledConnectorTable([{name: 'fixture', registration: 'fixture',
      revision: 'fixture/0.1', source: {profileVersion, load: async () => ({
        check: profile => publicUnknownSource ? {...profile, connectorId: 'content-fixture'} : profile,
        identityParts: profile => [profile],
        load: async (_profile, options) => publicUnknownSource ? value.load(options) : ({...value.adapter, async openCapture(options) {
          try { return await value.adapter.openCapture(options); }
          catch (error) { captureError = error; throw error; }
        }}),
      })}}]);
    const sourceProfilePath = join(scratch.path, 'source-profile.json');
    const queryAliases = value.declared.views.map(view => ({
      name: view.resource === 'files' ? 'docs.listing' : 'docs.contents',
      sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
      schemaContractCid: view.carrier_schema_cid,
    }));
    await writeFile(sourceProfilePath, canonical({version: profileVersion, queryAliases}));
    const keys = generateKeyPairSync('ed25519');
    const events = [];
    let inputIdentified;
    const identified = new Promise(resolve => { inputIdentified = resolve; });
    const installation = {directory: join(scratch.path, 'host'), sourceProfilePath, connectorTable,
      hostLookupExecutionPolicy: JSON.parse(value.environmentWire).host_policy_profile.lookup_execution,
      retainedRelationOutput, authorization: {accountConfiguration: account,
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        observe: (event, detail) => events.push({event, detail}),
        faultInjection: async (step, detail) => {
          if (!cancel || step !== 'content_input_identified') return;
          assert.ok(detail.work > 0n);
          inputIdentified();
          if (!detail.signal.aborted) await new Promise(resolve => {
            detail.signal.addEventListener('abort', resolve, {once: true});
          });
          detail.signal.throwIfAborted();
        }}};
    let server, host, previousCertificates;
    let closed = false;
    const close = async () => {
      if (closed) return;
      closed = true;
      await client?.close();
      if (server !== undefined) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
      if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
    };
    let client;
    t.after(close);
    try {
      if (entrance === 'Local') {
        client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
      } else {
        const {key, cert, ca} = await fixtureCertificates(scratch.path);
        previousCertificates = getCACertificates('default');
        setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
        host = await openInstalledRemoteHttpHost({...installation,
          authenticate: header => header === 'Bearer keyed-fixture' ? userInfo().username : undefined});
        server = createServer({key, cert}, host.handler);
        await new Promise((resolve, reject) => {
          server.once('error', reject);
          server.listen(0, '127.0.0.1', resolve);
        });
        client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
          token: 'keyed-fixture', durability: 'durable'});
      }
    } catch (error) {
      assert.fail(inspect(error, {depth: 6, maxArrayLength: 12, maxStringLength: 1000}));
    }
    const submissionRef = client.newSubmission({nonce: 'keyed-public'});
    const source = format === 'json' ? JSON.stringify(value.program)
      : authoredListingJoin(format, {allFiles: true});
    if (format !== 'json') {
      const environment = moon.clientProgramCheckEnvironment(value.environmentWire,
        JSON.parse(value.environmentWire).evidence_bundle_cid,
        false, false, true, false, false, false, false);
      const publication = sourceAliasPublication(moon, environment, queryAliases);
      const preparedText = moon.clientProgramPrepareSourceWithParameters(source, format,
        environment, JSON.stringify(publication), undefined, undefined);
      assert.ok(moon.clientProgramPreparationReady(preparedText), inspect({format,
        issue: moon.clientProgramPreparationIssue(preparedText)}, {depth: 8, maxStringLength: 2000}));
      const preparedProgram = moon.clientProgramPreparationReady(preparedText);
      let acquisition;
      try { acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)); }
      catch (error) {
        assert.fail(inspect({format, cause: error.cause,
          program: moon.clientProgramSemanticDocumentJson(preparedProgram)},
        {depth: 10, maxStringLength: 20000}));
      }
      assert.ok(acquisition, 'the text JOIN selects its actual keyed acquisition');
      const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(acquisition);
      const {registry, values, fragment, ordered} = value.joinContracts;
      const requirement = moon.clientProgramPrepareLocalQueryRequirement(preparedProgram,
        coordinates._0, coordinates._1, registry, values, fragment, ordered);
      assert.equal(requirement.$tag, 1, inspect({format, issue: requirement._0,
        program: moon.clientProgramSemanticDocumentJson(preparedProgram)}, {depth: 8}));
      const checkedText = await client.check(source, {kind: 'text', scope: 'bound_input', format})
        .catch(error => assert.fail(inspect(error, {depth: 7, maxStringLength: 2000})));
      assert.equal(checkedText.report?.verdict, 'verified', inspect(checkedText,
        {depth: 8, maxArrayLength: 12, maxStringLength: 1000}));
      assert.equal(value.listingRequests(), 0);
      assert.equal(gets, 0);
    }
    const execution = await client.startSource(source, {format, submissionRef})
      .catch(error => assert.fail(inspect({error, events}, {depth: 8, maxArrayLength: 12,
        maxStringLength: 1000})));
    const timeout = AbortSignal.timeout(10000);
    if (cancel) {
      await Promise.race([identified, new Promise((_, reject) => {
        timeout.addEventListener('abort', () => reject(timeout.reason), {once: true});
      })]);
      await execution.cancel();
    }
    const state = await execution.wait({signal: timeout});
    assert.equal(state.status, cancel ? 'cancelled' : 'succeeded',
      inspect({state, events, captureError}, {depth: 8, maxArrayLength: 12}));
    if (publicUnknownSource) {
      // This reads the accepted Run's stored original map. It does not invoke
      // client.plan(source), another Check, or another compiler preparation.
      const plan = await execution.plan();
      assert.deepEqual(plan.run_ref, execution.ref);
      assert.match(plan.plan_view.compiled_plan_cid, /^sha256:[0-9a-f]{64}$/u);
    }
    const resultName = format === 'json' ? 'r' : 'answer';
    const resultRows = cancel ? undefined : await execution.result(resultName).all();
    if (cancel) {
      assert.equal(state.result_availability[resultName].state, 'unavailable');
      assert.equal(state.result_availability[resultName].reason, 'not_published');
      const cleanup = events.find(({event}) => event === 'dispatch_cleanup_completed');
      assert.ok(cleanup, 'cancellation confirms dependent cleanup before Source reclamation');
      // Direct capture, lookup assembly and one keyed capture each create a
      // holding. Creations are cumulative, not live/refundable reservations.
      assert.equal(cleanup.detail.resourceUsage.holdings, '3');
      for (const quantity of ['heldBytes', 'reservedTransferBytes',
        'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
        assert.equal(cleanup.detail.resourceUsage[quantity], '0', quantity);
      }
      const generated = Buffer.from('{"name":"invoice.pdf","content":' + canonical(expectedContent) + '}\n');
      const generatedCid = createHash('sha256').update(generated).digest('hex');
      await assert.rejects(readFile(join(installation.directory, 'publication', 'objects', generatedCid)),
        {code: 'ENOENT'});
    } else {
    if (!serializing) {
      assert.deepEqual(resultRows, [{name: 'invoice.pdf', content: expectedContent}]);
    } else {
      assert.equal(resultRows.length, 1);
      assert.equal(resultRows[0].name, 'captured.jsonl');
      const expectedBytes = Buffer.from(empty ? ''
        : '{"name":"invoice.pdf","content":' + canonical(expectedContent) + '}\n');
      const expectedCid = `sha256:${createHash('sha256').update(expectedBytes).digest('hex')}`;
      assert.equal(resultRows[0].content.metadata.content_cid, expectedCid);
      assert.equal(resultRows[0].content.metadata.size_bytes, expectedBytes.length);
      assert.deepEqual(await readFile(join(installation.directory, 'publication', 'objects',
        expectedCid.slice('sha256:'.length))), expectedBytes);
    }
    }
    assert.equal(value.listingRequests(), 1);
    const expectedGets = empty ? 0 : format === 'sql' ? 2 : 1;
    assert.equal(gets, expectedGets,
      'Pipe filters before content acquisition; SQL WHERE remains after the JOIN');
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.admission.ref, execution.ref);
    if (!cancel) assert.deepEqual(await (await client.attach(lookup.admission.ref)).result(resultName).all(),
      resultRows);
    assert.equal(gets, expectedGets, 'attach never starts the original keyed acquisition again');
    await close();
    if (serializing) {
      const journal = new DatabaseSync(join(installation.directory, 'requests',
        'client-requests.sqlite3'), {readOnly: true});
      try {
        const rows = journal.prepare('SELECT run_admission_evidence_json FROM client_requests').all();
        assert.equal(rows.length, 1);
        const inventory = JSON.parse(JSON.parse(rows[0].run_admission_evidence_json).sourceInventory);
        assert.equal(inventory.version, 'actql-client-keyed-source-inventory/0.1');
        assert.deepEqual(inventory.acquisitions.map(({stage, input, task}) => ({stage, input, task})),
          [{stage: 0, input: 0, task: 0}, {stage: 0, input: 1, task: 0}]);
        assert.notEqual(inventory.acquisitions[0].checkedSource.sourceRef,
          inventory.acquisitions[1].checkedSource.sourceRef);
      } finally { journal.close(); }
    }
    if (byteBacked) {
      // Closing the producing Run/Host does not replace or discard byte custody.
      const chunks = [];
      if (empty) assert.equal(holdings.length, 0, 'empty input never captures physical content');
      else {
        await contentStore.consumePhysicalHolding(holdings[0].holding_cid, 0,
          chunk => chunks.push(Buffer.from(chunk)));
        assert.deepEqual(Buffer.concat(chunks), payload);
      }
      for (const holding of holdings) await contentStore.retirePhysicalHolding(holding.holding_cid);
      for (const prepared of preparedObjects) await prepared.retry();
      for (const writer of writers) await writer.cancel();
      await contentStore.close();
      contentStoreClosed = true;
    }
    await sourceAuthorization?.close();
    scratch.passed();
  }
});
}
}
}
}
}
}

test('installed keyed dispatch retains left custody while unknown child cleanup is pending', async t => {
  let stopped = false, gets = 0, physicalCleanups = 0;
  const value = await capturedListingForOriginalKeyedProgram({deferCapture: true, allFiles: true,
    listingItems: [item('d', 'first.pdf', 'v1'), item('e', 'second.pdf', 'v2')],
    readKeyed: async ({requestWire, consumePage}) => {
      gets++;
      const request = JSON.parse(requestWire);
      if (gets === 1) return await consumePage([{...request, content: admittedContent}]);
      try { await consumePage([{...request, content: admittedContent, version: 'wrong'}]); }
      catch (error) {
        throw acquisitionFailure(error, 'unknown', {close() {},
          cleanup() { physicalCleanups++; return stopped; }, cleanupPending: () => !stopped});
      }
    }});
  const now = () => '2026-10-09T00:00:00.000Z';
  const control = runtimeCore(moon).publicationControl;
  const authorityScopeCid = token('a'), storeAuthorityCid = token('d'), namespaceId = 'keyed-stop';
  const plan = acquiredTaskRunAdmission({moon, control, preparedProgram: value.preparedProgram,
    authorityScopeCid, namespaceId, now});
  const ref = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
  let captured, closed = false, directCloses = 0;
  const adapter = {...value.adapter, async openCapture(options) {
    captured = await value.adapter.openCapture(options);
    return {...captured, async close() { directCloses++; await captured.close(); }};
  }};
  const events = [], stops = [];
  const owner = installNodeClientDispatchOwner({moon, control,
    store: {confirmCommittedIndex: async () => undefined},
    journal: {reservePhysicalStart: () => true,
      lookupRunDefinition: () => ({runDefinition: plan.runDefinition, revision: 1,
        cancellationRequested: false, physicalCloseConfirmed: closed}),
      lookupReconciliationState: () => undefined,
      markPhysicalClose(_ref, outcome) { closed = true; stops.push(outcome); },
      markPreDispatchFailure() { assert.fail('valid capacity is admitted'); }},
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    planFor: () => plan, sourceProfile: adapter, ...value.joinContracts,
    prepareAcquisition: (preparedProgram, sourceAccess, occurrence) => adapter.prepare({
      preparedProgram, sourceAccess, occurrence, ...value.joinContracts}),
    runPublished() { assert.fail('incomplete keyed response cannot dispatch Compute or publish'); },
    observed: (event, detail) => events.push({event, detail}),
    namespaceId, authorityScopeCid, storeAuthorityCid, now, retainedRelationOutput: true});
  t.after(async () => { stopped = true; await owner.drain(); });
  const submission = {preparedProgram: value.preparedProgram, principalId: 'fixture', connection: {},
    requestId: 'keyed-stop'};
  const held = {plan, preparedSource: value.preparedSource, preparedSourceAccess: adapter.sourceAccess};
  const accepted = {ref, runDefinition: plan.runDefinition};
  assert.equal(await owner.start(submission, {}, accepted, held), 'started');
  await owner.operation(ref);
  await assert.rejects(owner.drain(), error => {
    assert.equal(error.code, 'ClientDispatchCleanupPending');
    assert.equal(error.failures[0].primary.outcome, 'unknown');
    return true;
  });
  assert.equal(gets, 2);
  assert.equal(directCloses, 0, 'the left capture remains borrowed by unresolved lookup cleanup');
  const left = checked(moon.clientProgramKeyedCaptureLeftRead(value.acquisition, captured.capture.source()));
  assert.equal(moon.clientProgramKeyedLeftReadRows(left), 2);
  assert.deepEqual(stops, [], 'unknown stop cannot become a terminal observation');
  assert.equal(await owner.start(submission, {}, accepted, held), 'not_started');
  stopped = true;
  await owner.drain();
  assert.equal(directCloses, 1);
  assert.equal(gets, 2, 'cleanup never repeats content I/O');
  assert.deepEqual(stops, ['failed']);
  const cleanups = physicalCleanups;
  await owner.drain();
  assert.equal(physicalCleanups, cleanups);
  assert.equal(directCloses, 1, 'successfully reclaimed children close once');
  const cleanup = events.find(event => event.event === 'dispatch_cleanup_completed');
  assert.ok(cleanup);
  for (const quantity of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']) {
    assert.equal(cleanup.detail.resourceUsage[quantity], '0', quantity);
  }
});

test('keyed Host preflight distinguishes absent keyed input, original owner and unsupported inventory', async () => {
  const value = await capturedListingForOriginalKeyedProgram({deferCapture: true});
  const acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(value.preparedProgram));
  assert.ok(acquisition);
  assert.deepEqual(moon.clientProgramKeyedAcquisitionCoordinates(acquisition),
    moon.clientProgramKeyedAcquisitionCoordinates(value.acquisition));
  const duplicated = listingContentProgram({capturePrefix: true, joinCount: 2});
  assert.equal(moon.clientProgramSelectSingleKeyedAcquisition(duplicated.preparedProgram).$tag, 0,
    'multiple original keyed occurrences never silently select the first');
  const pure = moon.clientProgramPrepareEffectFreeWithParameters(checkProgram, 'json',
    moon.clientProgramCheckEnvironment(value.environmentWire, JSON.parse(value.environmentWire).evidence_bundle_cid,
      false, false, true, false, false, false, false), undefined);
  assert.equal(checked(moon.clientProgramSelectSingleKeyedAcquisition(
    moon.clientProgramPreparationReady(pure))), undefined);
  const direct = value.adapter.ledgerCapacity(value.preparedSource);
  const capacity = value.adapter.keyedLedgerCapacity(acquisition);
  const foreign = checked(moon.clientProgramSelectSingleKeyedAcquisition(
    listingContentProgram({capturePrefix: true}).preparedProgram));
  const {registry, values, fragment, ordered} = value.joinContracts;
  const ledger = (keyed, transfers = [direct.transferBytes, capacity.transferBytes]) =>
    moon.clientProgramPrepareKeyedCapturedLocalInstalledLedger(value.preparedProgram,
      direct.capacity, keyed, capacity.capacity, transfers,
      [direct.executionBytes, capacity.executionBytes], capacity.maxBytes, capacity.maxWork,
      registry, values, fragment, ordered);
  assert.ok(ledger(acquisition));
  assert.equal(ledger(foreign), undefined, 'equivalent wire is not the original checked owner');
  assert.equal(ledger(acquisition, [-1n, 0n]), undefined);
  assert.equal(ledger(acquisition, [9223372036854775807n, 9223372036854775807n]), undefined);
  assert.equal(ledger(acquisition, [0n]), undefined);
  assert.equal(value.listingRequests(), 0, 'preflight never enters a provider');
});

test('normal keyed Host cannot bypass the original Run planning allowance', async t => {
  let gets = 0;
  const value = await capturedListingForOriginalKeyedProgram({readKeyed: async ({requestWire, consumePage}) => {
    gets++;
    await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
  }});
  t.after(value.close);
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger: lookupLedger()});
  t.after(lookup.close);
  await assert.rejects(lookup.openHost(value.joinContracts), {code: 'InstalledKeyedHostPreparation'});
  assert.equal(gets, 1, 'planning refusal cannot acquire a new physical key');
  assert.ok(lookup.read !== undefined);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1,
    'failed Host planning cannot collect the borrowed acquisition');
});

test('normal keyed Host preserves empty capture and cancels before the post-JOIN consumer', async t => {
  for (const empty of [true, false]) {
    let gets = 0;
    const value = await capturedListingForOriginalKeyedProgram({empty,
      postJoinFilter: "name = 'invoice.pdf'",
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
      }});
    t.after(value.close);
    const ledger = checked(moon.clientProgramAcquisitionLedger(
      8, 8, 8000000n, 268435456n, 536870912n, 100000));
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger});
    t.after(lookup.close);
    const host = await lookup.openHost(value.joinContracts);
    const rows = [];
    const controller = new AbortController();
    const stopped = new Error('StopAfterOriginalJoin');
    const observer = installCompletionObserver(async ({task, readRetained}) => {
      assert.ok(task === 1 || (empty && task === 2));
      if (task !== 1) return;
      await readRetained(wire => rows.push(JSON.parse(wire)));
      // A successful observer owns no failed release. Cancel through the
      // original driver instead of inventing an unknown observer cleanup.
      if (!empty) controller.abort(stopped);
    });
    const executed = await runCapturedInternalStrategy(host, {}, controller.signal, observer);
    t.after(() => executed.close());
    assert.equal(executed.status, empty ? 'host-tasks-completed' : 'host-tasks-failed');
    if (empty) assert.deepEqual(rows, []);
    else {
      assert.equal(executed.failure, stopped);
      assert.deepEqual(rows, [{name: 'invoice.pdf', content: admittedContent}]);
    }
    assert.deepEqual(executed.completed.map(entry => entry.task), empty ? [1, 2] : [1]);
    assert.equal(moon.strategyHostTaskCompleted(host, 2), empty,
      'cancellation after real JOIN work prevents the original later WHERE');
    assert.equal(gets, empty ? 0 : 1);
    await executed.close();
    assert.equal(executed.cleanupPending(), false);
    await lookup.close();
    assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), empty ? 0 : 1);
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]),
      [0n, 0n, 0n, 0n], 'same Run Ledger retains no keyed/Compute reservation after cleanup');
  }
});

test('original managed JOIN preserves typed empty lookup and cancels after positive work', async t => {
  for (const empty of [true, false]) {
    let gets = 0;
    const value = await capturedListingForOriginalKeyedProgram({empty,
      readKeyed: async ({requestWire, consumePage}) => {
        gets++;
        await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
      }});
    t.after(value.close);
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger: lookupLedger()});
    t.after(lookup.close);
    const prepared = await lookup.prepareJoin(value.joinContracts);
    const result = await consumeOriginalJoin(prepared, 1, {cancelAfterWork: !empty});
    assert.equal(gets, empty ? 0 : 1);
    if (empty) {
      assert.deepEqual(result.fields, ['content', 'name']);
      assert.equal(result.schemaCid, cid({
        content: {type: 'content_ref', media_type: 'application/pdf', nullable: false},
        name: {type: 'string', nullable: false},
      }));
      assert.deepEqual(result.rows, []);
      assert.equal(result.relationCid, cid({sort: 'relation', value: []}));
    }
    assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), empty ? 0 : 1);
  }
});

test('complete original JOIN preparation refuses a separately checked equal Program owner', async t => {
  const value = await capturedListingForOriginalKeyedProgram({readKeyed: async ({requestWire, consumePage}) => {
    await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
  }});
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  const request = await originalKeyedRequest(value);
  const right = await value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger});
  t.after(async () => {
    moon.clientProgramKeyedLookupStop(lookup);
    await right.close();
    let done = false;
    for (let poll = 0; poll < 10000; poll++) {
      if (checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) { done = true; break; }
    }
    assert.equal(done, true);
  });
  right.acceptLookup(lookup);
  let done = false;
  for (let poll = 0; poll < 10000; poll++) {
    if (checked(moon.clientProgramKeyedLookupAdvance(lookup, 64))) { done = true; break; }
  }
  assert.equal(done, true);
  checked(moon.clientProgramKeyedLookupRead(lookup));
  const {registry, values, fragment, ordered} = value.joinContracts;
  assert.ok(moon.clientProgramKeyedLookupJoinPrepare(value.preparedProgram,
    lookup, registry, values, fragment, ordered));
  const foreign = listingContentProgram({capturePrefix: true});
  assert.equal(moon.clientProgramKeyedLookupJoinPrepare(foreign.preparedProgram,
    lookup, registry, values, fragment, ordered), undefined);
  assert.equal(moon.clientProgramKeyedLookupOpenDag(foreign.preparedProgram,
    lookup, ledger).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupOpenDag(value.preparedProgram,
    lookup, lookupLedger()).$tag, 0);
});

test('installed JOIN preparation rechecks current authority before returning original inputs', async t => {
  let allowed = true;
  let gets = 0;
  const value = await capturedListingForOriginalKeyedProgram({
    authorizeRead: async () => ({action: allowed ? 'dispatch' : 'deny'}),
    readKeyed: async ({requestWire, consumePage}) => {
      gets++;
      await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
    }});
  t.after(value.close);
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger: lookupLedger()});
  t.after(lookup.close);
  allowed = false;
  await assert.rejects(lookup.prepareJoin(value.joinContracts), {code: 'ExecutionAuthorizationDenied'});
  await assert.rejects(lookup.openDag(), {code: 'ExecutionAuthorizationDenied'});
  await assert.rejects(lookup.openHost(value.joinContracts), {code: 'ExecutionAuthorizationDenied'});
  assert.equal(gets, 1, 'refused preparation cannot recapture or resend');
  allowed = true;
  assert.ok(await lookup.prepareJoin(value.joinContracts));
});

test('installed lookup retains the same rows identity and logical work across quanta', async t => {
  const totals = [];
  const expected = [{content: admittedContent, resource: resource('d'), version: 'v1'}];
  for (const quantum of [1, 7, 64]) {
    const value = await capturedListingForOriginalKeyedProgram({readKeyed: async ({consumePage}) => {
      await consumePage(expected);
    }});
    t.after(value.close);
    const ledger = lookupLedger();
    const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, left: value.left, ledger, quantum});
    t.after(lookup.close);
    assert.equal(lookup.capture.identity(), cid(expected));
    totals.push(lookup.work());
    await lookup.close();
    assert.equal(lookup.work(), totals.at(-1));
    assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  }
  assert.ok(totals[0] > 0n);
  assert.deepEqual(totals, [totals[0], totals[0], totals[0]], 'quantum is not logical work');
});

test('installed lookup refuses cancellation after positive physical work without publishing partial input', async t => {
  let sends = 0;
  const abort = new AbortController();
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    listingItems: [item('d', 'first.pdf', 'v1'), item('e', 'second.pdf', 'v2')],
    readKeyed: async ({requestWire, consumePage}) => {
      sends++;
      await consumePage([{content: admittedContent, ...JSON.parse(requestWire)}]);
      if (sends === 2) abort.abort(new Error('StoppedOriginalLookup'));
    }});
  t.after(value.close);
  const ledger = lookupLedger();
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger, signal: abort.signal}),
  error => error.code === 'StoppedOriginalLookup' && error.outcome === 'stopped');
  assert.equal(sends, 2);
  assert.ok(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes > 0n,
    'cancellation never refunds observed physical bytes');
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2);
});

test('installed empty original lookup makes zero GETs and seals a typed empty right input', async t => {
  let sends = 0;
  const value = await capturedListingForOriginalKeyedProgram({empty: true,
    readKeyed: async () => { sends++; assert.fail('empty left cannot send'); }});
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger});
  t.after(lookup.close);
  assert.equal(sends, 0);
  assert.equal(lookup.capture.identity(), cid([]));
  assert.ok(lookup.capture.read());
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5), [0n, 0n, 0n, 0n, 0n]);
  await lookup.close();
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('installed middle-key uncertainty retains assembly and original physical recovery without resend', async t => {
  let sends = 0;
  let stopped = false;
  let physicalCleanups = 0;
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    listingItems: [item('d', 'first.pdf', 'v1'), item('e', 'second.pdf', 'v2')],
    readKeyed: async ({requestWire, consumePage}) => {
      sends++;
      const request = JSON.parse(requestWire);
      if (sends === 1) { await consumePage([{content: admittedContent, ...request}]); return; }
      try { await consumePage([{content: admittedContent, ...request, version: 'wrong'}]); }
      catch (error) {
        throw acquisitionFailure(error, 'unknown', {close() {},
          cleanup() { physicalCleanups++; return stopped; }, cleanupPending: () => !stopped});
      }
    }});
  t.after(value.close);
  const ledger = lookupLedger();
  let failure;
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger}), error => {
    failure = error;
    return error.code === 'MoonBitHostFailure' && error.outcome === 'unknown';
  });
  assert.equal(sends, 2);
  assert.equal(failure.recovery.cleanupPending(), true);
  const retained = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.ok(ledgerUsageSnapshot(retained).transferredBytes > 0n && ledgerUsageSnapshot(retained).reservedRetentionBytes > 0n && ledgerUsageSnapshot(retained).reservedExecutionBytes > 0n);
  assert.equal(await failure.recovery.cleanup(), false);
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), retained,
    'unconfirmed child stop cannot return the assembly reservation');
  stopped = true;
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(failure.recovery.cleanupPending(), false);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  const calls = physicalCleanups;
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(physicalCleanups, calls, 'successful physical cleanup is not repeated');
  assert.equal(sends, 2, 'same failed lookup is cleaned up, never resent');
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 2);
});

test('installed lookup checks its original owner and reserves assembly before provider I/O', async t => {
  let sends = 0;
  const value = await capturedListingForOriginalKeyedProgram({readKeyed: async () => { sends++; }});
  const foreign = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  t.after(foreign.close);
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: foreign.left, ledger: lookupLedger()}),
  {code: 'InstalledSourceProgramMismatch'});
  const tiny = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 1n, 1n));
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger: tiny}),
  {code: 'MoonBitHostFailure'});
  assert.equal(sends, 0);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(tiny), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('installed original keyed acquisition retains its right port and charges the physical page once', async t => {
  let requests = 0;
  let bodyBytes;
  const value = await capturedListingForOriginalKeyedProgram({readKeyed:
    async ({columns, requestWire, chargePage, consumePage}) => {
      requests++;
      assert.deepEqual(columns, ['content', 'resource', 'version']);
      assert.deepEqual(JSON.parse(requestWire), {resource: resource('d'), version: 'v1'});
      const rows = [{content: admittedContent, resource: resource('d'), version: 'v1'}];
      const body = Buffer.from(JSON.stringify(rows));
      bodyBytes = BigInt(body.length);
      assert.equal(await consumePage(rows, {charge: chargePage(body)}), 1);
    }});
  t.after(value.close);
  const request = await originalKeyedRequest(value);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  const acquired = await value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger});
  t.after(acquired.close);
  assert.equal(requests, 1);
  assert.ok(acquired.capture.read());
  // The acquisition law hashes the ordered canonical row array, not provider
  // arrival bytes or the logical Relation envelope. Authored rows fix this
  // expectation independently of the product's retained representation.
  assert.equal(acquired.capture.identity(), cid([
    {content: admittedContent, resource: resource('d'), version: 'v1'},
  ]));
  const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.equal(ledgerUsageSnapshot(usage).transferredBytes, bodyBytes, 'the charged body is not charged again during admission');
  assert.equal(ledgerUsageSnapshot(usage).holdings, 1n);
  assert.ok(ledgerUsageSnapshot(usage).heldBytes > 0n);
  assert.deepEqual(ledgerUsageFieldsFor(usage, ["reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n]);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5),
    [1n, 1n, BigInt(Buffer.byteLength(canonical({resource: resource('d'), version: 'v1'}))),
      bodyBytes, bodyBytes]);
  acquired.close();
  assert.throws(acquired.capture.read, {code: 'MoonBitHostFailure'});
  assert.throws(acquired.capture.identity, {code: 'MoonBitHostFailure'});
  const released = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.deepEqual(ledgerUsageFieldsFor(released, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  acquired.close();
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), released);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1,
    'right cleanup does not release its borrowed original left');
});

test('per-Run keyed capture refuses invalid or ambiguous custody before reservation and I/O', async t => {
  let sends = 0;
  const captureContent = async () => assert.fail('Invalid custody cannot capture bytes');
  const issuer = moon.clientProgramRowReferenceIssuer(() => false, () => false, () => false);
  for (const empty of [false, true]) {
    const value = await capturedListingForOriginalKeyedProgram({empty,
      runCaptureContent: true, captureContent, readKeyed: async () => { sends++; }});
    t.after(value.close);
    for (const keyedContent of [null, {}, {capture: captureContent},
      {capture: false, referenceIssuer: issuer}]) {
      const ledger = lookupLedger();
      await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
        keyedAcquisition: value.acquisition, left: value.left, ledger, keyedContent}),
      {code: 'InvalidInstalledContentCapture'});
      assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), Array(ledgerUsageFields.length).fill(0n));
    }
  }
  const installed = await capturedListingForOriginalKeyedProgram({captureContent,
    readKeyed: async () => { sends++; }});
  t.after(installed.close);
  const ledger = lookupLedger();
  await assert.rejects(installed.adapter.openKeyedLookup({preparedProgram: installed.preparedProgram,
    keyedAcquisition: installed.acquisition, left: installed.left, ledger,
    keyedContent: {capture: captureContent, referenceIssuer: issuer}}),
  {code: 'InvalidInstalledContentCapture'});
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), Array(ledgerUsageFields.length).fill(0n));
  assert.equal(sends, 0);
});

for (const runCaptureContent of [false, true]) {
for (const storedEncoding of ['identity', 'gzip']) {
test(`GCS physical keyed read uses the original RowRun and real Store-backed Content custody (${runCaptureContent ? 'per-Run capture' : 'installed fixture capture'}, stored ${storedEncoding})`, async t => {
  const gcsMoon = await import('../../_build/js/release/build/connectors/gcs/host_node/host_node.js');
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'gcs-rowrun-', label: 'GCS keyed RowRun and Store fixture'});
  const control = runtimeCore(moon).contentCaptureControl;
  const contentLimits = {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxTextUnits: 4096};
  const store = await openLocalPublicationStore({directory: join(scratch.path, 'store'),
    storeAuthorityCid: token('1'), capacityBytes: 65536, maxObjectBytes: 4096,
    maxObjects: 8, maxContractNodes: 1000, maxContractDepth: 32}, runtimeCore(moon).publicationControl);
  const writers = [], preparations = [], holdings = [], issued = new Set();
  const payload = storedEncoding === 'identity' ? Buffer.from('123456789')
    : Buffer.from('1f8b080000000000001333343236313533b7b004002639f4cb09000000', 'hex');
  const contentCid = storedEncoding === 'identity'
    ? 'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225'
    : 'sha256:50362a01a8d29d0eaceb7640872bab3f6d7f980e33804a57e21c79a18fe25cb8';
  const generation = '9007199254740993';
  const meta = {bucket: 'actql-fixture', name: 'test/invoice.pdf', generation,
    metageneration: '9007199254740995', size: String(payload.length), contentType: 'application/pdf',
    crc32c: storedEncoding === 'identity' ? '4waSgw==' : 'zCyQIQ==',
    ...(storedEncoding === 'gzip' ? {contentEncoding: 'gzip'} : {})};
  const metadataBody = Buffer.from(JSON.stringify(meta));
  const scope = {operation: 'gcs:file:read', resourceOrigin: 'https://storage.googleapis.com',
    siteGeneration: 1, connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1'};
  // Only physical credential exchange is injected. Program preparation,
  // original lookup, RowRun, Ledger, issuer and Store are real owners. MIME
  // evidence is not a PDF decoder; these fixed bytes intentionally prove that.
  let calls = 0, captured = 0, verifiedBytes = 0;
  const operations = [];
  const readOperations = {files: 'gcs:file:list', contents: 'gcs:file:read'};
  let expectedRef;
  let lookup, value, selectedCapture;
  let disposed = false;
  const dispose = async () => {
    if (disposed) return;
    await lookup?.close();
    await value?.close();
    for (const holding of holdings) await store.retirePhysicalHolding(holding.holding_cid);
    for (const prepared of preparations) await prepared.retry();
    for (const writer of writers) await writer.cancel();
    await store.close();
    disposed = true;
  };
  t.after(dispose);
  value = await capturedListingForOriginalKeyedProgram({listedVersion: generation,
    runCaptureContent,
    authorizeRead: async () => {
      if (selectedCapture !== undefined) {
        selectedCapture.capture = () => assert.fail('Run capture was replaced after selection');
        selectedCapture.referenceIssuer = {};
      }
      return {action: 'dispatch'};
    },
    allFiles: true, listingItems: [{...item('d', 'invoice.pdf', generation), path: meta.name}],
    observeSend: false, contentValidator: wire => issued.has(wire),
    readOperation: readOperations,
    issueReadGrant: ({operation, resource}) => {
      operations.push([resource, operation]);
      return {grant: {}, scope: {...scope, operation}};
    },
    captureContent: async ({bytes, mediaType, keyedAcquisition, request, readSubjectCid,
      verifyRead, signal}) => {
      captured++;
      assert.deepEqual(bytes, payload);
      assert.equal(mediaType, 'application/pdf');
      await verifyRead();
      const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      const binding = {content_store_id: 'fixture', content_store_cid: token('1'),
        workspace_scope_cid: token('2'), storage_scope: 'workspace', retention_class: 'fixture',
        availability_evidence_cid: token('3'), effective_data_policy_cid: facts[3],
        data_classification: facts[4], issuer_contract_cid: token('5'), capture_authority_cid: readSubjectCid};
      const candidate = control.candidate(keyedAcquisition, request, binding,
        {mediaType, contentCid, sizeBytes: payload.length}, contentLimits);
      const description = control.inspect(candidate);
      const issuerBody = {version: 'actql-content-issuer-evidence/0.1', issuer_kind: 'connector_capture',
        issuer_contract_cid: token('5'), content_store_cid: token('1'), workspace_scope_cid: token('2'),
        content_cid: contentCid, effective_data_policy_cid: facts[3], capture_authority_cid: readSubjectCid,
        reported_media_type: mediaType};
      const refBody = {$actql_ref: 'content', version: 'actql-content-ref/0.1', media_type: mediaType,
        metadata: {content_store_id: 'fixture', content_cid: contentCid, media_type: mediaType,
          storage_scope: 'workspace', retention_class: 'fixture', availability_evidence_cid: token('3'),
          capture_authority: 'read_content', data_classification: facts[4], effective_data_policy_cid: facts[3],
          size_bytes: payload.length, truncated: false, issuer_evidence: {...issuerBody, evidence_cid: cid(issuerBody)}}};
      expectedRef = {...refBody, content_ref_cid: cid(refBody)};
      assert.equal(description.wire, canonical(expectedRef));
      const retained = await retainCapturedContent({store, control, candidate, bytes,
        holdingCid: cid({capture: readSubjectCid, content: description.identity}),
        workspaceScopeCid: token('2'), effectiveDataPolicyCid: facts[3],
        available: () => !signal.aborted, authorize: () => !signal.aborted, limits: contentLimits, signal,
        retainCustody: ({writer, prepared, holding}) => {
          if (writer) writers.push(writer);
          if (prepared) preparations.push(prepared);
          if (holding) holdings.push(holding);
        }});
      issued.add(retained.wire);
      return JSON.parse(retained.wire);
    },
    readKeyed: async options => {
      const charge = options.chargeVerification;
      return await readGcsKeyedContent({...options, moon: gcsMoon,
        credential: {journal: {fixture: true}},
        resolveResource: async ref => {
          assert.deepEqual(ref, resource('d'));
          const objectName = await options.capturedResourcePath();
          assert.equal(objectName, 'test/invoice.pdf');
          return {bucket: meta.bucket, objectName, prefix: 'test/'};
        },
        limits: {maxMetadataBytes: 4096, maxContentBytes: payload.length, maxRequestBytes: 4096,
          maxAttempts: 2, maxTimeMs: 5000},
        chargeVerification: async bytes => { await charge(bytes); verifiedBytes += bytes; },
        callResource: async call => {
          const media = ++calls === 2;
          assert.deepEqual(call.operations.get('gcs:file:read').headers,
            [['accept-encoding', media ? storedEncoding : 'identity'],
              ...(media && storedEncoding === 'gzip' ? [['range', 'bytes=0-28']] : [])]);
          return {accepted: true, statusCode: media && storedEncoding === 'gzip' ? 206 : 200,
            headers: media && storedEncoding === 'gzip'
              ? [['content-encoding', 'gzip'], ['content-range', 'bytes 0-28/29']] : [],
            body: media ? payload : metadataBody};
        }});
    }});
  readOperations.contents = 'gcs:file:list';
  const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
    token('a'), 'gcs-original-keyed-rowrun', moon.clientProgramSourceFreeInputIntentCid());
  assert.ok(requestIdentity);
  const selectedRead = await value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, requestIdentity});
  selectedCapture = value.keyedContent === undefined ? undefined : {...value.keyedContent};
  const ledger = lookupLedger();
  lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger, originalCapture: value.captured.capture,
    keyedContent: selectedCapture, preparedKeyed: selectedRead.prepared});
  assert.equal(calls, 2); assert.equal(captured, 1); assert.equal(verifiedBytes, payload.length);
  assert.deepEqual(operations, [['files', 'gcs:file:list'], ['contents', 'gcs:file:read']],
    'metadata and content use separate immutable registered credential operations');
  assert.equal(lookup.capture.identity(), cid([{resource: resource('d'), version: generation,
    content: expectedRef}]));
  assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes, BigInt(metadataBody.length + payload.length));
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 2), [1n, 2n]);
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[3], BigInt(metadataBody.length + payload.length));
  assert.ok(await store.inspectPhysicalHolding(holdings[0].holding_cid));
  const storedChunks = [];
  await store.consumePhysicalHolding(holdings[0].holding_cid, 0,
    bytes => storedChunks.push(Buffer.from(bytes)));
  assert.deepEqual(Buffer.concat(storedChunks), payload,
    'the encrypted Store retains exact compressed or identity bytes, not a transparently decoded payload');
  await lookup.close();
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1,
    'closing the right lookup never closes its borrowed original listing');
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  await dispose();
  scratch.passed();
});
}
}

for (const missingKeyedPreparation of [false, true]) {
test(missingKeyedPreparation
  ? 'original dispatch refuses absent captured Content read preparation before Source I/O'
  : 'original dispatch supplies Run-bound Content custody and preserves committed bytes after Source cleanup', async t => {
  const gcsMoon = await import('../../_build/js/release/build/connectors/gcs/host_node/host_node.js');
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'run-keyed-content-', label: 'original dispatch Content capture fixture'});
  const core = runtimeCore(moon), control = core.publicationControl;
  const namespaceId = 'run-content', authorityScopeCid = token('a'), storeAuthorityCid = token('d');
  const now = () => '2026-10-10T00:00:00.000Z';
  const payload = Buffer.from('123456789');
  const contentCid = 'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225';
  const generation = '9007199254740993';
  const metadata = {bucket: 'actql-fixture', name: 'test/invoice.pdf', generation,
    metageneration: '9007199254740995', size: '9', contentType: 'application/pdf', crc32c: '4waSgw=='};
  const metadataBody = Buffer.from(JSON.stringify(metadata));
  let gets = 0, claims = 0, preDispatchFailures = 0, content, readSubjectCid;
  const value = await capturedListingForOriginalKeyedProgram({deferCapture: true,
    allFiles: true, observeSend: false, listedVersion: generation,
    listingItems: [{...item('d', 'invoice.pdf', generation), path: metadata.name}],
    contentValidator: () => false,
    readOperation: {files: 'gcs:file:list', contents: 'gcs:file:read'},
    issueReadGrant: ({operation}) => ({grant: {}, scope: {operation,
      resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
      connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1'}}),
    readKeyed: options => readGcsKeyedContent({...options, moon: gcsMoon,
      credential: {journal: {fixture: true}},
      limits: {maxMetadataBytes: 4096, maxContentBytes: 9, maxRequestBytes: 4096,
        maxAttempts: 2, maxTimeMs: 5000},
      resolveResource: async ref => {
        assert.deepEqual(ref, resource('d'));
        assert.equal(await options.capturedResourcePath(), metadata.name);
        return {bucket: metadata.bucket, objectName: metadata.name, prefix: 'test/'};
      },
      callResource: async () => ({accepted: true, statusCode: 200, headers: [],
        body: ++gets === 1 ? metadataBody : payload}),
      captureContent: async facts => {
        assert.equal(typeof options.captureContent, 'function', 'the original dispatcher must supply capture');
        content = await options.captureContent(facts);
        return content;
      }}),
  });
  const checkOriginalCandidate = async facts => {
        assert.ok(facts.keyedAcquisition !== undefined && facts.request !== undefined);
        const binding = {content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
          workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace',
          retention_class: 'local-content', expires_at: expiresAt,
          availability_evidence_cid: availabilityCid, effective_data_policy_cid: sourceFacts[3],
          data_classification: sourceFacts[4], issuer_contract_cid: issuerContractCid,
          capture_authority_cid: facts.readSubjectCid};
        const limits = {maxBytes: 4096, maxNodes: 256, maxDepth: 32, maxTextUnits: 4096};
        const byteFacts = {mediaType: facts.mediaType, contentCid: facts.contentCid, sizeBytes: 9};
        // These refuse before retaining any bytes. Use the actual original
        // request after physical verification, not a fabricated request token.
        for (const expires_at of [undefined, '2099-01-01T00:00:00.000Z']) {
          assert.throws(() => core.contentCaptureControl.candidateForRun(plan.compiled,
            plan.runDefinition, facts.keyedAcquisition, facts.request,
            {...binding, expires_at}, byteFacts, limits), {code: 'MoonBitHostFailure'});
        }
        assert.throws(() => core.contentCaptureControl.candidateForRun(plan.compiled,
          plan.runDefinition, facts.keyedAcquisition, facts.request,
          {...binding, effective_data_policy_cid: token('f')}, byteFacts, limits), {code: 'MoonBitHostFailure'});
        assert.throws(() => core.contentCaptureControl.candidateForRun(plan.compiled,
          plan.runDefinition, facts.keyedAcquisition, facts.request,
          binding, {...byteFacts, mediaType: 'text/plain'}, limits), {code: 'MoonBitHostFailure'});
        assert.throws(() => core.contentCaptureControl.candidateForRun(foreignPlan.compiled,
          foreignPlan.runDefinition, facts.keyedAcquisition, facts.request,
          binding, byteFacts, limits), {code: 'MoonBitHostFailure'},
          'an independently prepared equal Program is not this capture owner');
        const generic = core.contentCaptureControl.candidate(facts.keyedAcquisition,
          facts.request, binding, byteFacts, limits);
        assert.throws(() => core.contentCaptureControl.holdingCid(generic),
          /requires original Run custody/u);
        assert.equal(await store.inspectPhysicalHolding(holdingCid), undefined);
  };
  const plan = acquiredTaskRunAdmission({moon, control, preparedProgram: value.preparedProgram,
    authorityScopeCid, namespaceId, requestId: 'original-content', now});
  const independentlyPrepared = listingContentProgram({capturePrefix: true, allFiles: true});
  const foreignPlan = acquiredTaskRunAdmission({moon, control,
    preparedProgram: independentlyPrepared.preparedProgram,
    authorityScopeCid, namespaceId, requestId: 'original-content', now});
  const ref = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
  const sourceFacts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(value.acquisition));
  readSubjectCid = cid({version: 'actql-keyed-row-source-read/0.1', sourceFacts,
    occurrence: [...moon.clientProgramKeyedAcquisitionCoordinates(value.acquisition)],
    request: {resource: resource('d'), version: generation},
    physicalBinding: {resource: 'contents', fields: ['content', 'resource', 'version']},
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1', bindingCid: token('c')});
  const expiresAt = JSON.parse(plan.runDefinition.wire).valid_until;
  const availabilityCid = cid({version: 'actql-installed-local-policy/0.1', name: 'content-availability',
    storeAuthorityCid, runDefinitionCid: plan.runDefinition.identity, expiresAt});
  const issuerContractCid = cid({version: 'actql-installed-local-policy/0.1', name: 'content-issuer',
    storeAuthorityCid, authorityScopeCid});
  const issuerBody = {version: 'actql-content-issuer-evidence/0.1', issuer_kind: 'connector_capture',
    issuer_contract_cid: issuerContractCid, content_store_cid: storeAuthorityCid,
    workspace_scope_cid: authorityScopeCid, content_cid: contentCid,
    effective_data_policy_cid: sourceFacts[3], capture_authority_cid: readSubjectCid,
    reported_media_type: 'application/pdf'};
  const refBody = {$actql_ref: 'content', version: 'actql-content-ref/0.1', media_type: 'application/pdf',
    metadata: {content_store_id: namespaceId, content_cid: contentCid, media_type: 'application/pdf',
      storage_scope: 'workspace', retention_class: 'local-content', expires_at: expiresAt,
      availability_evidence_cid: availabilityCid, capture_authority: 'read_content',
      data_classification: sourceFacts[4], effective_data_policy_cid: sourceFacts[3], size_bytes: 9,
      truncated: false, issuer_evidence: {...issuerBody, evidence_cid: cid(issuerBody)}}};
  const expected = {...refBody, content_ref_cid: cid(refBody)};
  const holdingCid = cid({capture_authority_cid: readSubjectCid, content_ref_cid: expected.content_ref_cid,
    role: 'captured_content_bytes', run_definition_cid: plan.runDefinition.identity,
    store_authority_cid: storeAuthorityCid, version: 'actql-content-private-holding/0.1'});
  const store = await openLocalPublicationStore({directory: join(scratch.path, 'store'), storeAuthorityCid,
    capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 10 * 1024 * 1024, maxObjects: 200,
    maxContractNodes: 10000, maxContractDepth: 64}, control);
  const originalContentRun = installNodeContentRun({moon, core, ...value.joinContracts,
    namespaceId, authorityScopeCid, storeAuthorityCid, ownerPrincipal: 'fixture', now, authorize: () => true});
  const runContent = Object.freeze(Object.assign(options => originalContentRun(options),
    {...originalContentRun, captureKeyed: options => {
    const original = originalContentRun.captureKeyed(options);
    return Object.freeze({...original, capture: async facts => {
      await checkOriginalCandidate(facts);
      return await original.capture(facts);
    }});
  }}));
  const adapter = Object.freeze({...value.adapter, requiresRunContentCapture: true});
  const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
    authorityScopeCid, 'original-content', moon.clientProgramSourceFreeInputIntentCid());
  const selectedRead = missingKeyedPreparation ? undefined : await adapter.prepareKeyed({
    preparedProgram: value.preparedProgram, keyedAcquisition: value.acquisition, requestIdentity});
  const events = [], stops = [];
  let physicalCloseConfirmed = false;
  const owner = installNodeClientDispatchOwner({moon, control, store, runContent,
    journal: {reservePhysicalStart() { claims++; assert.equal(gets, 0); return true; },
      lookupRunDefinition: () => ({runDefinition: plan.runDefinition, revision: 1,
        cancellationRequested: false, physicalCloseConfirmed}),
      lookupReconciliationState: () => undefined,
      markPhysicalClose(_ref, outcome) { physicalCloseConfirmed = true; stops.push(outcome); },
      markPreDispatchFailure() {
        assert.equal(missingKeyedPreparation, true, 'original declaration and capture capacity are available');
        preDispatchFailures++;
      }},
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    planFor: () => plan, sourceProfile: adapter, ...value.joinContracts,
    prepareAcquisition: (preparedProgram, sourceAccess, occurrence) => adapter.prepare({
      preparedProgram, sourceAccess, occurrence, ...value.joinContracts}),
    observed: (event, detail) => events.push({event, detail}),
    namespaceId, authorityScopeCid, storeAuthorityCid, now, retainedRelationOutput: true});
  let disposed = false;
  const dispose = async () => {
    if (disposed) return;
    await owner.drain();
    await adapter.close();
    await store.close();
    disposed = true;
  };
  t.after(dispose);
  assert.equal(await owner.start({preparedProgram: value.preparedProgram, requestId: 'original-content',
    principalId: 'fixture', connection: {}}, requestIdentity, {ref, runDefinition: plan.runDefinition},
  {plan, preparedSource: value.preparedSource, preparedSourceAccess: adapter.sourceAccess,
    ...(selectedRead === undefined ? {} : {keyedSource: {...selectedRead,
      adapter, sourceAccess: adapter.sourceAccess, acquisition: value.acquisition, requestIdentity}})}),
  missingKeyedPreparation ? 'not_started' : 'started');
  await owner.drain().catch(error => assert.fail(inspect(error, {depth: 8, maxStringLength: 500})));
  if (missingKeyedPreparation) {
    assert.equal(content, undefined);
    assert.equal(value.listingRequests(), 0);
    assert.equal(gets, 0);
    assert.equal(claims, 0);
    assert.equal(preDispatchFailures, 1);
    assert.deepEqual(stops, []);
    assert.equal(events.find(event => event.event === 'dispatch_failed')?.detail.code,
      'InstalledSourcePreparationMismatch');
    assert.equal(await store.confirmCommittedIndex(ref), undefined);
    await dispose();
    scratch.passed();
    return;
  }
  assert.equal(events.find(event => event.event === 'dispatch_failed'), undefined);
  assert.deepEqual(content, expected);
  assert.equal(gets, 2); assert.equal(claims, 1); assert.deepEqual(stops, [null]);
  const committed = await store.confirmCommittedIndex(ref);
  assert.ok(committed, 'ordinary execution and publication complete, not capture alone');
  const binding = await store.readJsonObject(committed.durable_result_binding_cids[0], 'durable_result_binding');
  const chunks = [];
  await store.consumeCommittedResult(ref, binding.result_definition_cid, () => true,
    bytes => chunks.push(Buffer.from(bytes)));
  assert.equal(Buffer.concat(chunks).toString('utf8'), canonical([{name: 'invoice.pdf', content: expected}]));
  const held = await store.inspectPhysicalHolding(holdingCid);
  assert.deepEqual(held, {version: 'actql-local-physical-holding/0.1', namespace: 'content',
    holding_cid: holdingCid, manifest_cid: expected.content_ref_cid,
    objects: [{cid: contentCid, byte_count: 9}]});
  const cleanup = events.find(event => event.event === 'dispatch_cleanup_completed');
  assert.ok(cleanup);
  for (const quantity of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes', 'reservedExecutionBytes']) {
    assert.equal(cleanup.detail.resourceUsage[quantity], '0', quantity);
  }
  const actualBytes = [];
  await store.consumePhysicalHolding(holdingCid, 0, bytes => actualBytes.push(Buffer.from(bytes)));
  assert.deepEqual(Buffer.concat(actualBytes), payload, 'temporary Source cleanup does not reclaim held content');
  await dispose();
  // Reopen the real physical Store and reconstruct an equivalent original
  // checked owner. This isolated receiving boundary uses a trusted fixture
  // original; durable journal inventory/public process restart are separate.
  const reopenedStore = await openLocalPublicationStore({directory: join(scratch.path, 'store'), storeAuthorityCid,
    capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 10 * 1024 * 1024, maxObjects: 200,
    maxContractNodes: 10000, maxContractDepth: 64}, control);
  t.after(() => reopenedStore.close());
  const restoredPlan = acquiredTaskRunAdmission({moon, control,
    preparedProgram: independentlyPrepared.preparedProgram,
    authorityScopeCid, namespaceId, now, retainedDefinitionWire: plan.runDefinition.wire});
  assert.equal(restoredPlan.runDefinition.identity, plan.runDefinition.identity,
    'restoration keeps the original definition/lifetime rather than issuing a new Run');
  const restoredAcquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(independentlyPrepared.preparedProgram));
  const restoredLedger = lookupLedger();
  let cleanupOwner, authorized = true, recoveringNow = now(), authorizationChecks = 0;
  const recovered = installRunKeyedContentCapture({moon, publications: control,
    control: core.contentCaptureControl, preparedProgram: independentlyPrepared.preparedProgram,
    plan: restoredPlan, acquisition: restoredAcquisition, ledger: restoredLedger, maxBytes: 4096,
    store: reopenedStore, namespaceId, authorityScopeCid, storeAuthorityCid,
    principalId: 'fixture', ownerPrincipal: 'fixture', now: () => recoveringNow,
    authorize: () => authorized, retainExecution: owner => { cleanupOwner = owner; }});
  t.after(() => cleanupOwner.close());
  const originalEntry = {referenceWire: canonical(expected), captureAuthorityCid: readSubjectCid};
  const recoveryOptions = {...originalEntry, keyedAcquisition: restoredAcquisition,
    verifyRead: async () => { authorizationChecks++; assert.ok(authorized, 'current Source access required'); }};
  assert.deepEqual(await recovered.recover(recoveryOptions), expected);
  assert.deepEqual(recovered.recovery(), originalEntry);
  assert.equal(gets, 2, 'recovery never repeats either metadata or byte GET');
  assert.equal(authorizationChecks, 2, 'current read authority is rechecked around Store awaits');
  const bindingFacts = {content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
    workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace', retention_class: 'local-content',
    expires_at: expiresAt, availability_evidence_cid: availabilityCid,
    effective_data_policy_cid: sourceFacts[3], data_classification: sourceFacts[4],
    issuer_contract_cid: issuerContractCid, capture_authority_cid: readSubjectCid};
  const referenceLimits = {maxBytes: 4096, maxNodes: 256, maxDepth: 32, maxTextUnits: 4096};
  for (const changed of [{...bindingFacts, expires_at: '2099-01-01T00:00:00.000Z'},
    {...bindingFacts, effective_data_policy_cid: token('f')}]) {
    assert.throws(() => core.contentCaptureControl.recoveryCandidateForRun(restoredPlan.compiled,
      restoredPlan.runDefinition, restoredAcquisition, originalEntry.referenceWire, changed, referenceLimits),
    {code: 'MoonBitHostFailure'});
  }
  assert.throws(() => core.contentCaptureControl.recoveryCandidateForRun(restoredPlan.compiled,
    restoredPlan.runDefinition, value.acquisition, originalEntry.referenceWire, bindingFacts, referenceLimits),
  {code: 'MoonBitHostFailure'}, 'a foreign checked Source port is not restored by wire coincidence');
  let raceChecks = 0;
  await assert.rejects(recovered.recover({...recoveryOptions, verifyRead: async () => {
    if (++raceChecks === 2) {
      authorized = false;
      throw Object.assign(new Error('FixtureCurrentSourceReadDenied'), {code: 'FixtureCurrentSourceReadDenied'});
    }
  }}), {code: 'FixtureCurrentSourceReadDenied'});
  assert.equal(recovered.recovery(), undefined, 'authority lost across Store await publishes no reference');
  assert.equal(gets, 2);
  authorized = true;
  assert.deepEqual(await recovered.recover(recoveryOptions), expected,
    'current authorization retries only exact saved custody, not acquisition');
  authorized = false;
  assert.equal(recovered.recovery(), undefined, 'revoked custody cannot export recovery metadata');
  await assert.rejects(recovered.recover({...recoveryOptions, verifyRead: async () => {}}),
    /InstalledContentAuthorityUnavailable/u);
  authorized = true;
  recoveringNow = expiresAt;
  await assert.rejects(recovered.recover(recoveryOptions), /InstalledContentAuthorityUnavailable/u);
  recoveringNow = now();
  await reopenedStore.retirePhysicalHolding(holdingCid);
  await assert.rejects(recovered.recover(recoveryOptions), {code: 'CapturedContentHoldingMismatch'});
  assert.equal(gets, 2, 'missing custody is a refusal, never recapture');
  assert.equal(await cleanupOwner.close(), true);
  assert.equal(await cleanupOwner.close(), true);
  for (const quantity of ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(restoredLedger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"])) {
    assert.equal(quantity, 0n, 'the same receiving frame releases all live capacity');
  }
  await reopenedStore.close();
  scratch.passed();
});
}

test('captured Content inventory restores every original holding before enabling its shared issuer', async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'capture-inventory-', label: 'multiple original captured Content holdings'});
  const core = runtimeCore(moon), control = core.contentCaptureControl;
  const items = [item('d', 'invoice.pdf', 'v1'), item('e', 'invoice.pdf', 'v2')];
  let readChecks = 0, denyReadAt, modelInputLive = true;
  const value = await capturedListingForOriginalKeyedProgram({listingItems: items,
    authorizeRead: async () => ({action: ++readChecks === denyReadAt ? 'deny' : 'dispatch'})});
  const namespaceId = 'capture-inventory', authorityScopeCid = token('a'), storeAuthorityCid = token('d');
  const now = () => '2026-10-10T00:00:00.000Z';
  const plan = acquiredTaskRunAdmission({moon, control: core.publicationControl,
    preparedProgram: value.preparedProgram, namespaceId, authorityScopeCid, requestId: 'inventory', now});
  const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
    authorityScopeCid, 'inventory', moon.clientProgramSourceFreeInputIntentCid());
  const selectedRead = await value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, requestIdentity});
  const sourceBinding = value.adapter.keyedRecoveryBinding(selectedRead.prepared);
  const storeOptions = {directory: join(scratch.path, 'store'), storeAuthorityCid,
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 1000, maxContractDepth: 32};
  let store = await openLocalPublicationStore(storeOptions, core.publicationControl);
  const children = [];
  let evidence, evidenceKey;
  let disposed = false;
  const dispose = async () => {
    if (disposed) return;
    for (const child of children) await child.cleanup();
    await value.close();
    await store.close();
    await evidence?.close();
    evidenceKey?.key.fill(0);
    disposed = true;
  };
  t.after(dispose);
  const cancellation = new AbortController();
  const frameOptions = {moon, publications: core.publicationControl, control,
    preparedProgram: value.preparedProgram, plan, acquisition: value.acquisition,
    sourceBinding,
    maxBytes: 4096, namespaceId, authorityScopeCid, storeAuthorityCid,
    principalId: 'fixture', ownerPrincipal: 'fixture', now, authorize: () => true,
    signal: cancellation.signal,
    retainExecution: child => children.push(child)};
  const ledger = () => checked(moon.clientProgramAcquisitionLedger(1, 0, 0n, 199936n, 203776n));
  let writes = 0;
  const physical = {...store, createPreparedObjectWriter(size) {
    writes++;
    return store.createPreparedObjectWriter(size);
  }};
  const frame = installRunKeyedContentCapture({...frameOptions, store: physical, ledger: ledger()});
  const refs = [];
  for (let index = 0; index < 2; index++) {
    const request = await originalKeyedRequest(value, index);
    checked(moon.clientProgramKeyedRequestObserveAttempt(request, 1n, 0n));
    refs.push(await frame.capture({keyedAcquisition: value.acquisition, request,
      verifyRead: async () => {}, readSubjectCid: token(index === 0 ? 'b' : 'c'),
      mediaType: 'application/pdf',
      contentCid: 'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225',
      bytes: Buffer.from('123456789')}));
  }
  assert.equal(writes, 2);
  assert.notEqual(refs[0].content_ref_cid, refs[1].content_ref_cid,
    'equal bytes under different original capture authorities are different references');
  const original = frame.recoveryInventory();
  assert.deepEqual(original, {version: 'actql-installed-captured-content-inventory/0.1',
    runDefinitionCid: plan.runDefinition.identity, entries: [
      {referenceWire: canonical(refs[0]), captureAuthorityCid: token('b')},
      {referenceWire: canonical(refs[1]), captureAuthorityCid: token('c')},
    ]});
  // Use the same encrypted captured_input holding as Model fixed-input
  // persistence. The waiting-journal fixture is not public process recovery.
  const stateDirectory = join(scratch.path, 'continuation');
  await createPrivateEvidenceKey(stateDirectory);
  evidenceKey = await loadPrivateEvidenceKey(stateDirectory);
  const openEvidence = () => openContinuationEvidence({stateDirectory,
    ...evidenceKey, contractControl: core.publicationControl,
    preparation: () => ({status: 'waiting_checkpoint'}), isTerminalRunOutcome: () => false});
  evidence = openEvidence();
  const originalRunId = JSON.parse(plan.runDefinition.wire).run_id;
  const savedInputWire = canonical({version: 'actql-installed-model-input/0.1', capturedContent: original,
    capturedContentBinding: frame.sourceBinding});
  const [inputCid] = await evidence.hold(`model-${originalRunId}`, plan.runDefinition.identity,
    [{name: 'captured_input', wire: savedInputWire}]);
  assert.equal(inputCid, `sha256:${createHash('sha256').update(savedInputWire).digest('hex')}`,
    'the original transport bytes, not regenerated references, identify input custody');
  const source = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(value.acquisition));
  const expiry = JSON.parse(plan.runDefinition.wire).valid_until;
  const limits = {maxBytes: 4096, maxNodes: 256, maxDepth: 32, maxTextUnits: 4096};
  const candidateFor = entry => control.recoveryCandidateForRun(plan.compiled,
    plan.runDefinition, value.acquisition, entry.referenceWire, {
      content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
      workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace', retention_class: 'local-content',
      expires_at: expiry, availability_evidence_cid: cid({version: 'actql-installed-local-policy/0.1',
        name: 'content-availability', storeAuthorityCid, runDefinitionCid: plan.runDefinition.identity, expiresAt: expiry}),
      effective_data_policy_cid: source[3], data_classification: source[4],
      issuer_contract_cid: cid({version: 'actql-installed-local-policy/0.1',
        name: 'content-issuer', storeAuthorityCid, authorityScopeCid}),
      capture_authority_cid: entry.captureAuthorityCid,
    }, limits);
  const candidates = original.entries.map(candidateFor);
  const reissue = (owner, candidate) => moon.clientProgramIssueCapturedContent(candidate,
    owner.referenceIssuer, 4096, 256, 32, 4096);
  for (const candidate of candidates) assert.equal(reissue(frame, candidate).$tag, 1,
    'the second capture cannot make the first reference unreadable');
  await children[0].cleanup();
  for (const candidate of candidates) assert.equal(reissue(frame, candidate).$tag, 0);
  await store.close();
  await evidence.close();
  evidenceKey.key.fill(0);
  evidenceKey = await loadPrivateEvidenceKey(stateDirectory);
  evidence = openEvidence();
  const savedInput = await evidence.open(`model-${originalRunId}`);
  assert.equal(savedInput.requestCid, plan.runDefinition.identity);
  const savedInputBytes = await savedInput.bytes('captured_input', inputCid, {maxBytes: 16384});
  assert.equal(savedInputBytes.toString('utf8'), savedInputWire);
  const restoredInventory = JSON.parse(savedInputBytes).capturedContent;
  const restoredBinding = JSON.parse(savedInputBytes).capturedContentBinding;
  assert.deepEqual(restoredBinding, sourceBinding);
  assert.deepEqual(restoredInventory, original);
  store = await openLocalPublicationStore(storeOptions, core.publicationControl);
  let inspections = 0;
  const recoveryStore = {...store,
    createPreparedObjectWriter() { assert.fail('saved inventory never recaptures bytes'); },
    async inspectPhysicalHolding(holding) { inspections++; return store.inspectPhysicalHolding(holding); },
  };
  const restoredLedger = ledger();
  const keyedSource = {adapter: value.adapter, acquisition: value.acquisition,
    prepared: selectedRead.prepared, sourceAccess: value.adapter.sourceAccess};
  // The real encrypted transport and physical Store are exercised here. The
  // Model lease port is an explicit trusted-boundary fixture; real Model lease
  // authentication/foreign-token rejection have separate controller tests.
  const inputToken = Object.freeze({});
  const modelController = {capturedContent(actual, runDefinitionCid) {
    assert.equal(actual, inputToken);
    assert.equal(runDefinitionCid, plan.runDefinition.identity);
    if (!modelInputLive) throw new Error('FixtureModelInputUnavailable');
    return restoredInventory;
  }, capturedContentBinding: () => restoredBinding};
  const runContent = installNodeContentRun({moon, core, ...value.joinContracts,
    namespaceId, authorityScopeCid, storeAuthorityCid, ownerPrincipal: 'fixture', now, authorize: () => true});
  const receiving = {...frameOptions, store: recoveryStore, ledger: restoredLedger,
    modelController, inputToken, keyedSource};
  for (const field of ['bindingCid', 'connectorRevision', 'physicalBindingCid', 'connection']) {
    await assert.rejects(runContent.recoverKeyed({...receiving, modelController: {...modelController,
      capturedContentBinding: () => ({...restoredBinding, [field]: 'changed'})}}),
    /InstalledCapturedContentBindingMismatch/u);
    assert.equal(inspections, 0, 'a changed installed target cannot inspect original bytes');
    assert.equal(children.length, 1, 'binding refusal precedes another reservation or receiver');
  }
  // Fail after a confirmed first holding. The retained frame, not a fresh
  // receiver or payload writer, owns the retry and original reservation.
  denyReadAt = readChecks + 4;
  await assert.rejects(runContent.recoverKeyed(receiving), {code: 'ExecutionAuthorizationDenied'});
  assert.equal(inspections, 1);
  assert.equal(children.length, 2);
  const restored = children[1].recoveryFrame;
  assert.ok(restored, 'the existing owner retains the exact failed receiving frame');
  assert.throws(() => restored.recoverInventory({keyedAcquisition: value.acquisition,
    inventory: {...restoredInventory, runDefinitionCid: token('f')}, verifyRead: async () => {}}),
  /InstalledKeyedContentInventoryMismatch/u);
  assert.equal(inspections, 1, 'a foreign inventory cannot inspect another holding');
  assert.equal(restored.recoveryInventory(), undefined);
  assert.throws(() => restored.capture({}), /InstalledKeyedContentCaptureMismatch/u,
    'failed recovery cannot switch to acquisition of new bytes');
  for (const candidate of candidates) assert.equal(reissue(restored, candidate).$tag, 0);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(restoredLedger), ["reservedRetentionBytes","reservedExecutionBytes"]), [199936n, 203776n]);
  await children[1].retryRecovery();
  assert.deepEqual(restored.recoveryInventory(), original);
  for (const candidate of candidates) assert.equal(reissue(restored, candidate).$tag, 1);
  assert.equal(writes, 2, 'restoration cannot allocate another payload writer');
  modelInputLive = false;
  for (const candidate of candidates) assert.equal(reissue(restored, candidate).$tag, 0,
    'release of the original Model input lease revokes already restored references');
  assert.equal(restored.recoveryInventory(), undefined);
  cancellation.abort();
  for (const candidate of candidates) assert.equal(reissue(restored, candidate).$tag, 0,
    'cancellation revokes authority before asynchronous cleanup');
  await children[1].cleanup();
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(restoredLedger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  await dispose();
  scratch.passed();
});

for (const failure of ['factory', 'close']) {
test(`Run-bound capture preserves original workspace and retry handles after Store ${failure} failure`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'capture-cleanup-', label: `Run capture ${failure} cleanup composition fixture`});
  const core = runtimeCore(moon), control = core.contentCaptureControl;
  const value = await capturedListingForOriginalKeyedProgram();
  const plan = acquiredTaskRunAdmission({moon, control: core.publicationControl,
    preparedProgram: value.preparedProgram, namespaceId: 'capture-cleanup', authorityScopeCid: token('a'),
    requestId: failure, now: () => '2026-10-10T00:00:00.000Z'});
  const store = await openLocalPublicationStore({directory: join(scratch.path, 'store'),
    storeAuthorityCid: token('d'), capacityBytes: 65536, maxObjectBytes: 4096,
    maxObjects: 8, maxContractNodes: 1000, maxContractDepth: 32}, core.publicationControl);
  // This isolated composition uses a real original Request and real Store;
  // only the selected Store failure is injected. It is not public GCS I/O.
  const request = await originalKeyedRequest(value);
  checked(moon.clientProgramKeyedRequestObserveAttempt(request, 1n, 0n));
  // Three declared distinct keys, not the one observed row, reserve the
  // receiving inventory: frame + 3 * (8*4096 + 256*64 + 1024).
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 0, 0n, 199936n, 203776n));
  let child, closeAllowed = false, allocations = 0, closeAttempts = 0;
  const physical = Object.freeze({...store, createPreparedObjectWriter(size) {
    allocations++;
    if (failure === 'factory') throw Object.assign(new Error('FixtureFactoryBeforeAllocation'),
      {code: 'FixtureFactoryBeforeAllocation'});
    const writer = store.createPreparedObjectWriter(size);
    return Object.freeze({...writer, async cancel() {
      closeAttempts++;
      if (!closeAllowed) throw Object.assign(new Error('FixtureWriterClosePending'),
        {code: 'FixtureWriterClosePending'});
      return await writer.cancel();
    }});
  }});
  const frame = installRunKeyedContentCapture({moon, publications: core.publicationControl, control,
    preparedProgram: value.preparedProgram, plan, acquisition: value.acquisition,
    ledger, maxBytes: 4096, store: physical, namespaceId: 'capture-cleanup',
    authorityScopeCid: token('a'), storeAuthorityCid: token('d'), principalId: 'fixture',
    ownerPrincipal: 'fixture', now: () => '2026-10-10T00:00:00.000Z', authorize: () => true,
    retainExecution: owner => { assert.equal(child, undefined); child = owner; }});
  let disposed = false;
  const dispose = async () => {
    if (disposed) return;
    closeAllowed = true;
    await child.cleanup();
    await value.close();
    await store.close();
    disposed = true;
  };
  t.after(dispose);
  await assert.rejects(frame.capture({keyedAcquisition: value.acquisition, request,
    verifyRead: async () => {}, readSubjectCid: token('b'), mediaType: 'application/pdf',
    contentCid: 'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225',
    bytes: Buffer.from('123456789')}),
  {code: failure === 'factory' ? 'FixtureFactoryBeforeAllocation' : 'FixtureWriterClosePending'});
  assert.equal(allocations, 1);
  assert.equal(child.cleanupPending(), true);
  const pending = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.deepEqual(ledgerUsageFieldsFor(pending, ["reservedRetentionBytes","reservedExecutionBytes"]), [199936n, 203776n]);
  if (failure === 'close') {
    await assert.rejects(child.cleanup(), {code: 'FixtureWriterClosePending'});
    assert.equal(child.cleanupPending(), true);
    assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), pending);
  }
  closeAllowed = true;
  assert.equal(await child.cleanup(), true);
  assert.equal(child.cleanupPending(), false);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  const finished = moon.clientProgramMultiCapturedLedgerUsage(ledger), finishedCloses = closeAttempts;
  assert.equal(await child.cleanup(), true);
  assert.equal(closeAttempts, finishedCloses);
  assert.equal(allocations, 1, 'cleanup does not recapture or create another Store writer');
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), finished);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1,
    'frame cleanup never reclaims its borrowed original Source');
  await assert.rejects(async () => frame.capture({}), /CaptureMismatch/u);
  await dispose();
  scratch.passed();
});
}

test('captured file locator borrows original metadata after WHERE and path projection', async t => {
  let paths = [], gets = 0;
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    observeSend: false, captureFilter: "name = 'invoice.pdf'",
    listingItems: [item('f', 'test/skipped.pdf', 'v9'),
      {...item('d', 'invoice.pdf', 'v1'), path: 'test/e\u0301%2F.pdf'},
      item('e', 'test/other.pdf', 'v2')],
    readKeyed: async options => {
      paths.push(await options.capturedResourcePath());
      await options.beginRequest(Buffer.from(options.requestWire));
      gets++;
      await options.consumePage([{...JSON.parse(options.requestWire), content: admittedContent}]);
      await assert.rejects(options.capturedResourcePath(), {code: 'InstalledFileLocatorAfterSend'});
    }});
  t.after(value.close);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1,
    'WHERE removes other occurrences, but the original captured listing still owns metadata');
  const ledger = lookupLedger();
  const lookup = await value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger, quantum: 1, originalCapture: value.captured.capture});
  t.after(lookup.close);
  assert.deepEqual(paths, ['test/e\u0301%2F.pdf']);
  assert.equal(gets, 1);
  await lookup.close();
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('retained original file metadata restores its checked locator after Source closure without relisting', async t => {
  const scratch = await createOwnedScratch({
    parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'original-file-custody-', label: 'original input continuation diagnostic'});
  const items = [item('f', 'test/skipped.pdf', 'v9'),
    {...item('d', 'invoice.pdf', 'v1'), path: 'test/e\u0301%2F.pdf'},
    item('e', 'test/other.pdf', 'v2')];
  const options = {allFiles: true, captureFilter: "name = 'invoice.pdf'", listingItems: items};
  const original = await capturedListingForOriginalKeyedProgram(options);
  t.after(original.close);
  const control = runtimeCore(moon).publicationControl;
  const admitted = acquiredTaskRunAdmission({moon, control,
    preparedProgram: original.preparedProgram, authorityScopeCid: token('a'),
    namespaceId: 'original-file-custody', now: () => '2026-10-10T00:00:00.000Z'});
  const runId = control.runDefinitionRunId(admitted.runDefinition);
  await createPrivateEvidenceKey(scratch.path);
  const key = await loadPrivateEvidenceKey(scratch.path);
  // The continuation's real encrypted Store is reopened below. The journal
  // fixture keeps this isolated Run nonterminal; this is not public restart.
  const openEvidence = () => openContinuationEvidence({stateDirectory: scratch.path,
    ...key, contractControl: control, preparation: () => ({status: 'waiting_checkpoint'}),
    isTerminalRunOutcome: () => false});
  let evidence = openEvidence();
  t.after(() => evidence.close());
  const checkpoints = {
    async retainComputationSource(id, definition, wire) {
      assert.equal(id, runId);
      return (await evidence.hold(`effect-${id}`, definition,
        [{name: 'source_capture', wire}]))[0];
    },
    async computationSourceReferences(view) {
      const held = await evidence.open(`effect-${view.runId}`);
      assert.equal(held.requestCid, view.runDefinitionCid);
      return held.held('source_capture');
    },
    async readComputationSource(view, captureCid, maxBytes) {
      const held = await evidence.open(`effect-${view.runId}`);
      assert.equal(held.requestCid, view.runDefinitionCid);
      return held.bytes('source_capture', captureCid, {maxBytes});
    },
    async retireComputationSources() { await evidence.settle(); },
  };
  const sourceFor = value => ({adapter: value.adapter, preparedSource: value.preparedSource,
    occurrence: value.preparedSource.occurrence});
  let receivingOwner;
  const receivingMoon = Object.freeze({...moon,
    clientProgramRestoreSourceCapture(...args) {
      const result = moon.clientProgramRestoreSourceCapture(...args);
      if (result.$tag === 1) receivingOwner = result._0;
      return result;
    },
    clientProgramCloseSourceCapture(owner) { return moon.clientProgramCloseSourceCapture(owner, 1); },
  });
  const makeContinuation = (value, restore) => {
    const continuation = acquiredEffectContinuation({moon: receivingMoon, checkpoints,
      acquired: {...admitted, control, kind: 'infer', prepared: value.preparedProgram},
      submission: {requestId: 'original-file-custody'}, declaredResults: ['r'],
      principalId: 'owner', unitId: 'original-file-unit', restore});
    continuation.accessFor({authorization: {authorize: async () => ({action: 'dispatch'})}}, sourceFor(value).occurrence);
    return continuation;
  };
  const first = makeContinuation(original);
  await first.prepared([sourceFor(original)]);
  await first.captured(sourceFor(original), original.captured,
    await original.captured.issueSourceEvidence({authorityScopeCid: token('a'),
      effectiveDataPolicyCid: original.captured.checkedSource.sourceDataPolicyCid}),
    '2026-10-10T00:00:00.000Z', '2026-10-10T00:00:01.000Z');
  const continuation = await first.retainAll();
  const view = {runId, runDefinitionCid: admitted.runDefinition.identity};
  const [savedCid] = await checkpoints.computationSourceReferences(view);
  const saved = JSON.parse((await checkpoints.readComputationSource(view, savedCid, 2_000_000)).toString('utf8'));
  assert.deepEqual(saved.original_input.rows, items.map(canonical),
    'original seven-field rows include filtered-out metadata in original input order');
  assert.equal(saved.original_input.rows_cid, cid(items));
  assert.equal(saved.rows.length, 1, 'residual capture has only the selected occurrence');
  assert.deepEqual(Object.keys(JSON.parse(saved.rows[0])).sort(), ['name', 'resource', 'version']);
  const oldRead = original.captured.capture.originalRead();
  await original.close();
  assert.throws(() => checked(moon.clientProgramExportSourceOriginalRead(oldRead)), {code: 'MoonBitHostFailure'});
  await first.close();
  await evidence.close();
  evidence = openEvidence();
  let gets = 0;
  const recovered = await capturedListingForOriginalKeyedProgram({...options, deferCapture: true,
    observeSend: false, readKeyed: async read => {
      assert.equal(await read.capturedResourcePath(), 'test/e\u0301%2F.pdf');
      await read.beginRequest(Buffer.from(read.requestWire));
      gets++;
      await read.consumePage([{...JSON.parse(read.requestWire), content: admittedContent}]);
    }});
  assert.equal(recovered.listingRequests(), 0);
  const second = makeContinuation(recovered, {continuation, view});
  await second.prepared([sourceFor(recovered)]);
  t.after(async () => {
    for (let attempt = 0; attempt < 100; attempt++) {
      try { await second.close(); return; }
      catch (error) { if (error.code !== 'SourceCaptureCleanupPending') throw error; }
    }
    assert.fail('original Source cleanup never completed');
  });
  const restored = second.restore(sourceFor(recovered), saved, undefined).captured;
  const again = checked(moon.clientProgramExportSourceOriginalRead(restored.capture.originalRead()));
  assert.deepEqual([again._0, again._1, again._2],
    [saved.original_input.schema_cid, cid(items), items.map(canonical)]);
  const originalBinding = recovered.adapter.retainedCapture(recovered.preparedSource);
  for (const [schema, rows, wires, issuer, available] of [
    [token('f'), cid(items), items.map(canonical), originalBinding.referenceIssuer, () => true],
    [again._0, token('f'), items.map(canonical), originalBinding.referenceIssuer, () => true],
    [again._0, cid(items), items.map((row, i) => canonical(i === 1 ? {...row, path: 'other'} : row)), originalBinding.referenceIssuer, () => true],
    [again._0, cid(items), items.map(canonical), undefined, () => true],
    [again._0, cid(items), items.map(canonical), originalBinding.referenceIssuer, () => false],
  ]) assert.throws(() => checked(moon.clientProgramRestoreSourceCapture(
    originalBinding.requirement, saved.requirement_cid, saved.binding, saved.binding,
    saved.descriptor, saved.rows, undefined, originalBinding.capacity, available, issuer,
    {_0: schema, _1: rows, _2: wires})), {code: 'MoonBitHostFailure'});
  // Four million existing capture units plus 22,404,096 original-input units.
  // One short refuses before creating the receiving buffer.
  const insufficient = checked(moon.clientProgramAcquisitionLedger(1, 1, 0n, 26404095n, 64000000n));
  const tooSmall = moon.clientProgramRestoreSourceCapture(originalBinding.requirement,
    saved.requirement_cid, saved.binding, saved.binding, saved.descriptor, saved.rows,
    insufficient, originalBinding.capacity, () => true, originalBinding.referenceIssuer,
    {_0: again._0, _1: cid(items), _2: items.map(canonical)});
  assert.equal(tooSmall.$tag, 0);
  assert.match(inspect(tooSmall._0), /ClientSourceCaptureIssue.*Physical/u);
  assert.equal(tooSmall._0._0, 5, 'compiled LedgerIssue.RetentionLimit');
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(insufficient), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.deepEqual(moon.clientProgramSourceCaptureUsage(receivingOwner), [26404096n, 0n, 0n]);
  const left = checked(moon.clientProgramKeyedCaptureLeftRead(recovered.acquisition, restored.capture.source()));
  const ledger = lookupLedger();
  const lookup = await recovered.adapter.openKeyedLookup({preparedProgram: recovered.preparedProgram,
    keyedAcquisition: recovered.acquisition, left, ledger, quantum: 1,
    originalCapture: restored.capture});
  t.after(lookup.close);
  assert.equal(gets, 1);
  assert.equal(recovered.listingRequests(), 0, 'saved metadata is never repaired by provider relisting');
  await lookup.close();
  const restoredRead = restored.capture.originalRead();
  await assert.rejects(restored.close(), {code: 'SourceCaptureCleanupPending'});
  assert.throws(() => checked(moon.clientProgramExportSourceOriginalRead(restoredRead)), {code: 'MoonBitHostFailure'});
  assert.equal(moon.clientProgramSourceCaptureCleanupPending(receivingOwner), true);
  assert.deepEqual(moon.clientProgramSourceCaptureUsage(receivingOwner), [26404096n, 0n, 0n],
    'logical revocation does not return the live original-input allocation');
  let cleaned = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { await restored.close(); cleaned = true; break; }
    catch (error) { assert.equal(error.code, 'SourceCaptureCleanupPending'); }
  }
  assert.equal(cleaned, true);
  assert.deepEqual(moon.clientProgramSourceCaptureUsage(receivingOwner), [0n, 0n, 0n]);
  await restored.close();
  await second.close();
  await evidence.close();
  scratch.passed();
});

test('captured file locator consumes an independent bounded original lookup allowance', async t => {
  const value = await capturedListingForOriginalKeyedProgram({allFiles: true,
    captureFilter: "name = 'invoice.pdf'",
    listingItems: [item('f', 'test/skipped.pdf', 'v9'),
      {...item('d', 'invoice.pdf', 'v1'), path: 'test/invoice.pdf'},
      item('e', 'test/other.pdf', 'v2')]});
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  t.after(() => {
    moon.clientProgramKeyedLookupStop(lookup);
    while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  });
  const preparation = checked(moon.clientProgramKeyedLookupRequestStart(lookup, 0));
  let request;
  while (request === undefined) {
    const poll = moon.clientProgramKeyedLookupRequestAdvance(lookup, preparation);
    assert.notEqual(poll._0, 2);
    if (poll._0 === 1) request = poll._2;
  }
  assert.equal(checked(moon.clientProgramKeyedLookupFind(lookup, request)), -1);
  const before = moon.clientProgramKeyedLookupWork(lookup);
  const locator = checked(moon.clientProgramKeyedFileLocatorStart(lookup, request,
    value.captured.capture.source(), value.captured.capture.originalRead()));
  let path;
  while (path === undefined) path = checked(moon.clientProgramKeyedFileLocatorAdvance(locator));
  assert.equal(path, 'test/invoice.pdf');
  // Start 1 + seven metadata columns + three resource rows + two version
  // units + version completion 1 + path borrow 1 + final completion 1.
  assert.equal(moon.clientProgramKeyedLookupWork(lookup) - before, 16n);
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[1], 0n);
  moon.clientProgramKeyedFileLocatorCancel(locator);
  moon.clientProgramKeyedLookupStop(lookup);
  const work = moon.clientProgramKeyedLookupWork(lookup);
  assert.equal(moon.clientProgramKeyedFileLocatorAdvance(locator).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), work);
});

test('captured file locator refuses missing metadata before provider I/O and recovers original capacity', async t => {
  let gets = 0;
  const value = await capturedListingForOriginalKeyedProgram({observeSend: false,
    allFiles: true,
    listingItems: [{...item('d', 'invoice.pdf', 'v1'), path: null}],
    readKeyed: async options => {
      await options.capturedResourcePath();
      gets++;
    }});
  t.after(value.close);
  const ledger = lookupLedger();
  await assert.rejects(value.adapter.openKeyedLookup({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, left: value.left, ledger,
    originalCapture: value.captured.capture}), error => {
      assert.match(inspect(error, {depth: 6}), /file_locator_unavailable/u);
      return true;
    });
  assert.equal(gets, 0);
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[1], 0n);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('captured file locator refuses equivalent foreign capture and observes original closure', async t => {
  const value = await capturedListingForOriginalKeyedProgram();
  const foreign = await capturedListingForOriginalKeyedProgram();
  t.after(value.close); t.after(foreign.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  t.after(() => {
    moon.clientProgramKeyedLookupStop(lookup);
    while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  });
  const request = await originalKeyedRequest(value);
  checked(moon.clientProgramKeyedLookupFind(lookup, request));
  const before = moon.clientProgramKeyedLookupWork(lookup);
  const refused = moon.clientProgramKeyedFileLocatorStart(lookup, request,
    foreign.captured.capture.source(), foreign.captured.capture.originalRead());
  assert.equal(refused.$tag, 0);
  assert.match(inspect(refused._0), /invalid_file_locator_request/u);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), before,
    'identical data is not the original capture or another budget allowance');
  const locator = checked(moon.clientProgramKeyedFileLocatorStart(lookup, request,
    value.captured.capture.source(), value.captured.capture.originalRead()));
  assert.equal(checked(moon.clientProgramKeyedFileLocatorAdvance(locator)), undefined);
  await value.close();
  const used = moon.clientProgramKeyedLookupWork(lookup);
  assert.equal(moon.clientProgramKeyedFileLocatorAdvance(locator).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), used);
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[1], 0n);
  moon.clientProgramKeyedFileLocatorCancel(locator);
  moon.clientProgramKeyedLookupStop(lookup);
  while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('physical keyed verification debits only the original active lookup allowance', async t => {
  const value = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  t.after(() => {
    moon.clientProgramKeyedLookupStop(lookup);
    while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  });
  const request = await originalKeyedRequest(value);
  const before = moon.clientProgramKeyedLookupWork(lookup);
  assert.equal(moon.clientProgramKeyedLookupChargeVerification(lookup, request, 9).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), before, 'pre-send rejection consumes no scan work');
  checked(moon.clientProgramKeyedLookupFind(lookup, request));
  checked(moon.clientProgramKeyedRequestObserveAttempt(request, 1n, 1n));
  const baseline = moon.clientProgramKeyedLookupWork(lookup);
  checked(moon.clientProgramKeyedLookupChargeVerification(lookup, request, 9));
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), baseline + 9n,
    'the independent nine-byte checksum scan costs nine logical units');
  const foreign = await originalKeyedRequest(value);
  for (const [observed, bytes] of [[foreign, 1], [request, 0], [request, -1]]) {
    assert.equal(moon.clientProgramKeyedLookupChargeVerification(lookup, observed, bytes).$tag, 0);
    assert.equal(moon.clientProgramKeyedLookupWork(lookup), baseline + 9n);
  }
  checked(moon.clientProgramKeyedRequestFinishIO(request, 2n));
  assert.equal(moon.clientProgramKeyedLookupChargeVerification(lookup, request, 1).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), baseline + 9n);
});

test('physical keyed verification work refusal preserves consumed work and original cleanup', async t => {
  const value = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  const ledger = lookupLedger();
  const lookup = checked(moon.clientProgramKeyedLookupStart(value.left, ledger, 4096, 1000000));
  const request = await originalKeyedRequest(value);
  t.after(() => {
    moon.clientProgramKeyedLookupStop(lookup);
    while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  });
  checked(moon.clientProgramKeyedLookupFind(lookup, request));
  checked(moon.clientProgramKeyedRequestObserveAttempt(request, 1n, 1n));
  const baseline = moon.clientProgramKeyedLookupWork(lookup);
  checked(moon.clientProgramKeyedLookupChargeVerification(lookup, request, 9));
  const refused = moon.clientProgramKeyedLookupChargeVerification(lookup, request, 1000000);
  assert.equal(refused.$tag, 0);
  assert.match(inspect(refused._0), /LookupLimit.*work/su);
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), baseline + 9n);
  assert.equal(moon.clientProgramKeyedLookupRead(lookup).$tag, 0);
  assert.equal(moon.clientProgramKeyedLookupIdentity(lookup), undefined);
  assert.equal(moon.clientProgramKeyedRequestFinishIO(request, 2n).$tag, 0,
    'work failure cannot turn into completed request evidence');
  moon.clientProgramKeyedLookupStop(lookup);
  while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, 64))) {}
  assert.equal(moon.clientProgramKeyedLookupWork(lookup), baseline + 9n,
    'cleanup does not refund already consumed verification work');
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('installed keyed response refusal recovers physical stop without successful evidence', async t => {
  let requests = 0;
  let stopped = false;
  let stopRequests = 0;
  let cleanupCalls = 0;
  const value = await capturedListingForOriginalKeyedProgram({readKeyed:
    async ({consumePage}) => {
      requests++;
      try {
        await consumePage([{content: admittedContent, resource: resource('d'), version: 'v2'}]);
      } catch (error) {
        throw acquisitionFailure(error, 'unknown', {
          close() { stopRequests++; },
          async cleanup() { cleanupCalls++; return stopped; },
          cleanupPending: () => !stopped,
        });
      }
    }});
  t.after(value.close);
  const request = await originalKeyedRequest(value);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  let failure;
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger}), error => {
    failure = error;
    return error.code === 'MoonBitHostFailure' && error.outcome === 'unknown';
  });
  assert.equal(requests, 1);
  assert.ok(failure.recovery?.cleanupPending());
  assert.equal(await failure.recovery.cleanup(), false,
    'an unobserved transport end cannot return reserved capacity');
  const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.ok(ledgerUsageSnapshot(usage).transferredBytes > 0n);
  assert.equal(ledgerUsageSnapshot(usage).heldBytes, 0n);
  assert.ok(ledgerUsageSnapshot(usage).reservedRetentionBytes > 0n && ledgerUsageSnapshot(usage).reservedExecutionBytes > 0n);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  assert.equal(stopRequests, 1);
  stopped = true;
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(failure.recovery.cleanupPending(), false);
  const released = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.deepEqual(ledgerUsageFieldsFor(released, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(cleanupCalls, 2, 'successful physical cleanup is not invoked twice');
  assert.equal(requests, 1, 'cleanup does not resend the failed keyed request');
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
});

test('installed keyed preparation rejects a foreign Program and current content denial before I/O', async t => {
  let requests = 0;
  let contentChecks = 0;
  const value = await capturedListingForOriginalKeyedProgram({
    authorizeRead: async (boundary, tuple, {subjectCid}) => {
      assert.equal(boundary, 'acquisition');
      assert.match(subjectCid, /^sha256:[0-9a-f]{64}$/u);
      if (tuple.resource === 'contents') {
        contentChecks++;
        return {action: 'deny'};
      }
      assert.equal(tuple.resource, 'files');
      return {action: 'dispatch'};
    }, readKeyed: async () => { requests++; assert.fail('denied content was dispatched'); }});
  t.after(value.close);
  const request = await originalKeyedRequest(value);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  const before = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  const foreign = listingContentProgram({capturePrefix: true});
  await assert.rejects(value.adapter.openKeyed({preparedProgram: foreign.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger}), error =>
    error.code === 'InstalledSourceProgramMismatch' && error.outcome === 'not_started');
  assert.equal(contentChecks, 0);
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), before);
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request, ledger}), error =>
    error.code === 'ExecutionAuthorizationDenied' && error.outcome === 'not_started');
  assert.equal(contentChecks, 1);
  assert.equal(requests, 0);
  const after = moon.clientProgramMultiCapturedLedgerUsage(ledger);
  assert.equal(ledgerUsageSnapshot(after).transferredBytes, 0n);
  assert.deepEqual(ledgerUsageFieldsFor(after, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
});

test('installed keyed authority keeps canonically equivalent version data distinct', async t => {
  const subjects = [];
  for (const version of ['é', 'é']) {
    const ownSubjects = new Set();
    const value = await capturedListingForOriginalKeyedProgram({listedVersion: version,
      authorizeRead: async (_, tuple, {subjectCid}) => {
        if (tuple.resource === 'contents') ownSubjects.add(subjectCid);
        return {action: 'dispatch'};
      }, readKeyed: async ({requestWire, consumePage}) => {
        assert.equal(JSON.parse(requestWire).version, version);
        await consumePage([{content: admittedContent, resource: resource('d'), version}]);
      }});
    t.after(value.close);
    const requestIdentity = moon.clientProgramRequestIdentity(value.preparedProgram,
      token('a'), 'exact-keyed-version', moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(requestIdentity);
    const selectedRead = await value.adapter.prepareKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, requestIdentity});
    // Preparation checks the static selected port. The per-request physical
    // subject below additionally includes its original captured version.
    ownSubjects.clear();
    const request = await originalKeyedRequest(value);
    const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
    const acquired = await value.adapter.openKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, request, ledger, preparedKeyed: selectedRead.prepared});
    t.after(acquired.close);
    assert.equal(ownSubjects.size, 1, 'each resume checks the same exact request subject');
    assert.equal(acquired.capture.identity(), cid([
      {content: admittedContent, resource: resource('d'), version},
    ]));
    subjects.push([...ownSubjects][0]);
  }
  assert.notEqual(subjects[0], subjects[1], 'NFC is not keyed version equality');
});

test('installed keyed requests share their original left lookup byte budget across captures', async t => {
  const requestBytes = BigInt(Buffer.byteLength(canonical({resource: resource('d'), version: 'v1'})));
  const rows = [{content: admittedContent, resource: resource('d'), version: 'v1'}];
  const responseBytes = BigInt(Buffer.byteLength(JSON.stringify(rows)));
  let sends = 0;
  const value = await capturedListingForOriginalKeyedProgram({
    lookupPolicy: {max_total_request_bytes: Number(requestBytes * 2n)},
    readKeyed: async ({consumePage}) => { sends++; await consumePage(rows); },
  });
  t.after(value.close);
  const ledger = checked(moon.clientProgramAcquisitionLedger(4, 4, 65536n, 16384n, 400000n));
  for (let i = 0; i < 2; i++) {
    const request = await originalKeyedRequest(value);
    const acquired = await value.adapter.openKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, request, ledger});
    assert.ok(acquired.capture.read());
    acquired.close();
  }
  assert.equal(sends, 2);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5),
    [2n, 2n, requestBytes * 2n, responseBytes * 2n, responseBytes * 2n]);
  const third = await originalKeyedRequest(value);
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: third, ledger}), error =>
    error.code === 'MoonBitHostFailure' && error.outcome === 'not_started');
  const after = moon.clientProgramKeyedLookupUsage(value.left);
  assert.deepEqual(after.slice(0, 5),
    [3n, 3n, requestBytes * 3n, responseBytes * 2n, responseBytes * 2n]);
  assert.equal(sends, 2, 'the over-limit request is not sent');
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  value.close();
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left), after,
    'cleanup and producer closure do not erase acquisition accounting');
});

test('installed keyed wire limit retains the received physical charge and forbids further sends', async t => {
  const rows = [{content: admittedContent, resource: resource('d'), version: 'v1'}];
  const body = Buffer.from(JSON.stringify(rows));
  let sends = 0;
  const value = await capturedListingForOriginalKeyedProgram({
    lookupPolicy: {max_total_response_bytes: body.length - 1},
    readKeyed: async ({chargePage, consumePage}) => {
      sends++;
      try { await consumePage(rows, {charge: chargePage(body)}); }
      catch (error) { throw acquisitionFailure(error, 'stopped'); }
    },
  });
  t.after(value.close);
  const ledger = checked(moon.clientProgramAcquisitionLedger(2, 2, 32768n, 8192n, 200000n));
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: await originalKeyedRequest(value), ledger}),
    error => error.code === 'MoonBitHostFailure' && error.outcome === 'stopped');
  assert.equal(sends, 1);
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[3], BigInt(body.length));
  assert.equal(moon.clientProgramKeyedLookupUsage(value.left)[4], 0n,
    'wire refusal precedes decoded admission');
  assert.equal(ledgerUsageSnapshot(moon.clientProgramMultiCapturedLedgerUsage(ledger)).transferredBytes, BigInt(body.length));
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: await originalKeyedRequest(value), ledger}),
    error => error.code === 'MoonBitHostFailure' && error.outcome === 'not_started');
  assert.equal(sends, 1, 'a new per-key RowRun does not reset a failed lookup budget');
});

test('installed keyed driver return without a physical send observation is not capture success', async t => {
  const value = await capturedListingForOriginalKeyedProgram({observeSend: false,
    readKeyed: async () => {}});
  t.after(value.close);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: await originalKeyedRequest(value), ledger}),
    error => error.code === 'MoonBitHostFailure' && error.outcome === 'not_started');
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5), [0n, 0n, 0n, 0n, 0n]);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('installed keyed network attempts consume the same request allowance without automatic retry', async t => {
  let sends = 1; // The fixture observes its first physical send before this driver.
  const value = await capturedListingForOriginalKeyedProgram({readKeyed:
    async ({beginRequest, requestWire}) => {
      try {
        for (let index = 1; index < 4; index++) {
          await beginRequest(Buffer.from(requestWire, 'utf8'));
          sends++;
        }
      } catch (error) { throw acquisitionFailure(error, 'stopped'); }
    }});
  t.after(value.close);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: await originalKeyedRequest(value), ledger}),
    error => error.code === 'MoonBitHostFailure' && error.outcome === 'stopped');
  assert.equal(sends, 3);
  const requestBytes = BigInt(Buffer.byteLength(canonical({resource: resource('d'), version: 'v1'})));
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left).slice(0, 5),
    [1n, 4n, requestBytes * 4n, 0n, 0n]);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('original checked lookup duration has an inclusive boundary and cannot reset on a new request', async t => {
  // A deterministic Host clock diagnostic, not real process restart or I/O.
  const value = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  const request = await originalKeyedRequest(value);
  checked(moon.clientProgramKeyedRequestObserveAttempt(request, 7n, 100n));
  assert.equal(checked(moon.clientProgramKeyedRequestRemainingMs(request, 30100n)), 0n);
  assert.equal(moon.clientProgramKeyedRequestRemainingMs(request, 30101n).$tag, 0);
  const after = [...moon.clientProgramKeyedLookupUsage(value.left)];
  assert.deepEqual(after, [1n, 1n, 7n, 0n, 0n, 30001n]);
  const next = await originalKeyedRequest(value);
  assert.equal(moon.clientProgramKeyedRequestObserveAttempt(next, 7n, 30102n).$tag, 0);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left), after);
});

test('installed keyed lookup deadline requests stop without turning timeout into successful evidence', async t => {
  let observedStop = false;
  const value = await capturedListingForOriginalKeyedProgram({lookupPolicy: {max_total_duration_ms: 20},
    readKeyed: async ({signal}) => {
      try {
        await new Promise((resolve, reject) => {
          const fallback = setTimeout(resolve, 1000);
          const stop = () => { clearTimeout(fallback); reject(signal.reason); };
          if (signal.aborted) stop();
          else signal.addEventListener('abort', stop, {once: true});
        });
        assert.fail('the policy deadline did not reach the physical reader');
      } catch (error) {
        observedStop = true;
        throw acquisitionFailure(error, 'stopped');
      }
    }});
  t.after(value.close);
  const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
  await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
    keyedAcquisition: value.acquisition, request: await originalKeyedRequest(value), ledger}),
    error => error.code === 'KeyedLookupDurationExceeded' && error.outcome === 'stopped');
  assert.equal(observedStop, true);
  const usage = moon.clientProgramKeyedLookupUsage(value.left);
  assert.equal(usage[1], 1n);
  assert.ok(usage[5] > 20n);
  assert.deepEqual(ledgerUsageFieldsFor(moon.clientProgramMultiCapturedLedgerUsage(ledger), ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
});

test('original checked lookup distinguishes wire and decoded ceilings and preserves overflow refusal', async t => {
  const value = await capturedListingForOriginalKeyedProgram();
  t.after(value.close);
  const request = await originalKeyedRequest(value);
  checked(moon.clientProgramKeyedRequestObserveAttempt(request, 7n, 100n));
  checked(moon.clientProgramKeyedResponseObserve(request, 32768n, 32768n, 101n));
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left), [1n, 1n, 7n, 32768n, 32768n, 1n]);
  assert.equal(moon.clientProgramKeyedResponseObserve(request, 0n, 1n, 102n).$tag, 0);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(value.left), [1n, 1n, 7n, 32768n, 32769n, 2n]);
  assert.equal(moon.clientProgramKeyedRequestFinishIO(request, 103n).$tag, 0);
  const overflow = await capturedListingForOriginalKeyedProgram();
  t.after(overflow.close);
  const invalid = await originalKeyedRequest(overflow);
  assert.equal(moon.clientProgramKeyedRequestObserveAttempt(invalid, 9007199254740992n, 100n).$tag, 0);
  assert.equal(moon.clientProgramKeyedRequestObserveAttempt(invalid, 1n, 100n).$tag, 0);
  assert.deepEqual(moon.clientProgramKeyedLookupUsage(overflow.left), [0n, 0n, 0n, 0n, 0n, 0n]);
});

for (const [name, rows] of [
  ['zero responses', []],
  ['two responses', Array.from({length: 2}, () =>
    ({content: admittedContent, resource: resource('d'), version: 'v1'}))],
  ['unissued content', [{content: {...admittedContent, content_ref_cid: token('f')},
    resource: resource('d'), version: 'v1'}]],
]) {
  test(`installed keyed ${name} refuses without retaining an output or losing confirmed cleanup`, async t => {
    let requests = 0;
    const value = await capturedListingForOriginalKeyedProgram({readKeyed:
      async ({chargePage, consumePage}) => {
        requests++;
        const body = Buffer.from(JSON.stringify(rows));
        try { await consumePage(rows, {charge: chargePage(body)}); }
        catch (error) { throw acquisitionFailure(error, 'stopped'); }
      }});
    t.after(value.close);
    const request = await originalKeyedRequest(value);
    const ledger = checked(moon.clientProgramAcquisitionLedger(1, 1, 16384n, 4096n, 100000n));
    await assert.rejects(value.adapter.openKeyed({preparedProgram: value.preparedProgram,
      keyedAcquisition: value.acquisition, request, ledger}), error =>
      error.code === 'MoonBitHostFailure' && error.outcome === 'stopped' &&
      error.recovery === undefined);
    assert.equal(requests, 1);
    const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    assert.equal(ledgerUsageSnapshot(usage).transferredBytes, BigInt(Buffer.byteLength(JSON.stringify(rows))));
    assert.equal(ledgerUsageSnapshot(usage).holdings, 0n);
    assert.deepEqual(ledgerUsageFieldsFor(usage, ["reservedTransferBytes","heldBytes","reservedRetentionBytes","reservedExecutionBytes"]), [0n, 0n, 0n, 0n]);
    assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 1);
  });
}

test('original acquisition prefix preserves positive work and cleanup until cancelled child stops', async () => {
  const value = await capturedListingForOriginalKeyedProgram({stopCaptureAfterProgress: true});
  assert.ok(value.work > 0n);
  assert.equal(moon.clientProgramRowSourceCapture(value.run).$tag, 0,
    'positive work is not a successful captured Source');
  moon.clientProgramRowSourceClose(value.run);
  assert.equal(checked(moon.clientProgramRowSourceCaptureCleanup(value.run)), false,
    'physical reader stop does not confirm the Local child stop');
  assert.equal(moon.clientProgramRowSourceCaptureBegin(value.run).$tag, 0);
  let cleaned = false;
  for (let poll = 0; poll < 10000; poll++) {
    const outcome = moon.clientProgramRowSourceCaptureAdvance(value.run, 1);
    assert.equal(outcome.$tag, 0, 'cancelled prefix never returns successful completion');
    assert.equal(moon.clientProgramRowSourceCapture(value.run).$tag, 0);
    if (checked(moon.clientProgramRowSourceCaptureCleanup(value.run))) {
      cleaned = true;
      break;
    }
  }
  assert.equal(cleaned, true);
  assert.equal(checked(moon.clientProgramRowSourceCaptureCleanup(value.run)), true);
  assert.equal(moon.clientProgramRowSourceCapture(value.run).$tag, 0);
});

test('typed empty original listing has no keyed Request occurrence', async t => {
  const value = await capturedListingForOriginalKeyedProgram({empty: true});
  t.after(value.close);
  assert.equal(moon.clientProgramKeyedLeftReadRows(value.left), 0);
  assert.equal(moon.clientProgramKeyedRequestStart(value.left, 0, 100000, 10000).$tag, 0);
});

test('actual Program preparation binds LIST_FILES to version-fixed keyed ContentRef input bounds', () => {
  const ordinary = listingContentProgram();
  assert.equal(ordinary.ready, true);
  assert.equal(ordinary.issue, undefined);
  // No observed rows or empty selector can create or remove the static bound.
  const empty = listingContentProgram({emptySelector: true});
  assert.equal(empty.ready, true);
  assert.equal(empty.issue, undefined);
});

test('installed keyed selection retains the original checked Program JOIN and Catalog', () => {
  const original = listingContentProgram();
  const selections = [];
  const outcomes = [];
  // Select by the actual original input occurrence, not assumed object/map
  // insertion order. Exactly one of these declared inputs is keyed.
  for (const input of [0, 1]) {
    const outcome = moon.clientProgramPrepareKeyedAcquisition(
      original.preparedProgram, 0, input, undefined);
    outcomes.push(outcome);
    if (outcome.$tag === 1) selections.push({input, acquisition: checked(outcome)});
  }
  assert.equal(selections.length, 1, inspect(outcomes, {depth: 5}));
  const {input, acquisition} = selections[0];
  assert.deepEqual([...moon.clientProgramKeyedAcquisitionCoordinates(acquisition)],
    [0, input, 0]);
  const expected = original.declared.views.find(view => view.resource === 'contents');
  const facts = [...checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition))];
  assert.equal(facts.length, 6);
  assert.deepEqual(facts, [expected.source_ref, expected.view_cid,
    expected.carrier_schema_cid, expected.data_policy_cid,
    'unknown', expected.view_cid]);
  assert.equal(moon.clientProgramKeyedAcquisitionMatchesProgram(acquisition,
    original.preparedProgram), true);
  // Equal source bytes and names are not the same checked invocation owner.
  const other = listingContentProgram();
  assert.equal(moon.clientProgramKeyedAcquisitionMatchesProgram(acquisition,
    other.preparedProgram), false);
  const explicit = checked(moon.clientProgramPrepareKeyedAcquisition(
    original.preparedProgram, 0, input, 0));
  assert.deepEqual([...moon.clientProgramKeyedAcquisitionCoordinates(explicit)],
    [0, input, 0]);
  for (const [stage, source, step] of [[1, input, undefined],
    [0, 99, undefined], [0, input, 99], [0, 1 - input, undefined]]) {
    assert.throws(() => checked(moon.clientProgramPrepareKeyedAcquisition(
      original.preparedProgram, stage, source, step)), {code: 'MoonBitHostFailure'});
  }
  // An empty selector still has the same declaration-derived keyed contract;
  // observed row counts cannot replace or remove its acquisition obligations.
  const empty = listingContentProgram({emptySelector: true});
  const emptyAcquisition = checked(moon.clientProgramPrepareKeyedAcquisition(
    empty.preparedProgram, 0, input, 0));
  assert.deepEqual([...checked(
    moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(emptyAcquisition))], facts);
});

test('checked keyed selection preserves WHERE placement and refuses ambiguous shared input', () => {
  const filtered = listingContentProgram({filterFirst: true});
  const selections = [0, 1].map(input => ({input,
    result: moon.clientProgramPrepareKeyedAcquisition(filtered.preparedProgram,
      0, input, 1)})).filter(entry => entry.result.$tag === 1);
  assert.equal(selections.length, 1, inspect(selections, {depth: 4}));
  const {input, result} = selections[0];
  assert.deepEqual([...moon.clientProgramKeyedAcquisitionCoordinates(checked(result))],
    [0, input, 1]);
  // Selecting the scan/WHERE position cannot move acquisition before WHERE.
  assert.throws(() => checked(moon.clientProgramPrepareKeyedAcquisition(
    filtered.preparedProgram, 0, input, 0)), {code: 'MoonBitHostFailure'});

  const shared = listingContentProgram({joinCount: 2, decodedResponseMaximum: 65536});
  assert.throws(() => checked(moon.clientProgramPrepareKeyedAcquisition(
    shared.preparedProgram, 0, input, undefined)), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 5);
  for (const step of [0, 1]) {
    const selected = checked(moon.clientProgramPrepareKeyedAcquisition(
      shared.preparedProgram, 0, input, step));
    assert.deepEqual([...moon.clientProgramKeyedAcquisitionCoordinates(selected)],
      [0, input, step]);
    assert.equal(moon.clientProgramKeyedAcquisitionMatchesProgram(selected,
      shared.preparedProgram), true);
  }
});

test('listed keyed ContentRef input cannot omit its version role or invent an empty Request', () => {
  const missingVersion = listingContentProgram({omitVersion: true, expectReady: false});
  assert.equal(missingVersion.ready, false);
  assert.match(inspect(moon.clientProgramPreparationIssue(missingVersion.preparation),
    {depth: 10, maxArrayLength: 0, maxStringLength: 100}), /MissingResponseField/u);
  const emptyRequest = listingContentProgram({explicitEmptyRequest: true, expectReady: false});
  assert.equal(emptyRequest.ready, false);
  assert.match(inspect(moon.clientProgramPreparationIssue(emptyRequest.preparation),
    {depth: 10, maxArrayLength: 0, maxStringLength: 100}), /InvalidValue/u);
});

test('actual keyed Program uses the Catalog and Host listing minimum, never observed empty rows', () => {
  // Three input rows, two response pages and 4096 bytes/page require 24576
  // decoded bytes. A Host ceiling of two lowers this to 16384, not zero.
  const insufficient = listingContentProgram({decodedResponseMaximum: 16384,
    emptySelector: true, expectReady: false});
  assert.equal(insufficient.ready, false);
  assert.match(inspect(moon.clientProgramPreparationIssue(insufficient.preparation),
    {depth: 12, maxArrayLength: 0, maxStringLength: 100}), /DecodedResponseLimit/u);
  const limited = listingContentProgram({hostListingMaximum: 2,
    decodedResponseMaximum: 16384, emptySelector: true});
  assert.equal(limited.ready, true);
  assert.equal(limited.issue, undefined);
  const oneShort = listingContentProgram({hostListingMaximum: 2,
    decodedResponseMaximum: 16383, emptySelector: true, expectReady: false});
  assert.equal(oneShort.ready, false);
  assert.match(inspect(moon.clientProgramPreparationIssue(oneShort.preparation),
    {depth: 12, maxArrayLength: 0, maxStringLength: 100}), /DecodedResponseLimit/u);
});
