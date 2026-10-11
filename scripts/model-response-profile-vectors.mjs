import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {taskFixture} from './decision-vectors.mjs';

// Authored fixture objects and independent Node hashing. These fixture build
// and lock originals are not a verified SDK installation or shipped profile.
const hash = value => 'sha256:' + createHash('sha256')
  .update(canonicalText(value)).digest('hex');
const generation = {
  version: 'actql-model-response-profile/0.1',
  adapter: {builder_id: 'fixture/http-builder', builder_revision: '1',
    codec_id: 'fixture/chat-one', codec_revision: '1',
    build_artifact_cid: hash({fixture: 'http-builder-and-codec', revision: 1}),
    port_abi: 'model-physical-port/1', sdk: null},
  operation: {endpoint: 'https://fixture.invalid/v1/chat/completions',
    method: 'POST', streaming: false},
  task: {contract_cid: 'sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560',
    kind: 'structured_generate',
    input_schema_cid: 'sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7',
    output_schema_cid: 'sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3'},
  completion: {validator_id: 'fixture/chat-envelope', validator_revision: '1',
    validator_artifact_cid: hash({fixture: 'chat-envelope-validator', revision: 1}),
    basis: 'generation_finish', transport_eof: true, endpoint_envelope: true,
    output_contract: true},
  probability: null,
  observations: ['provider_request_id', 'provider_reported_model_id', 'finish_reason',
    'input_tokens', 'output_tokens', 'provider_metadata'],
  limits: {request_bytes: 1024, response_bytes: 2048, chunk_bytes: 512,
    chunks: 16, header_bytes: 256, metadata_bytes: 128, metadata_nodes: 16,
    metadata_depth: 4, parse_nodes: 256, parse_depth: 16, parse_work: 8192,
    adapter_holding_bytes: 4096, adapter_workspace_bytes: 2048,
    active_slots: 4, unsettled_slots: 4},
  controls: {model_requests: 1, retry: false, fallback: false, hedging: false,
    tools: false, repair: false, cache: false, media_fetch: false,
    workflow_restore: false, sdk_telemetry: false, redirect: false},
};
const decision = structuredClone(generation);
decision.adapter = {...decision.adapter, builder_id: 'fixture/sdk-builder',
  codec_id: 'fixture/native-decision',
  sdk: {package: '@ai-sdk/typesafe-ai', version: '3.0.13', interface: 'v4',
    lock_artifact_cid: hash({fixture: 'synthetic-lock-not-an-installed-sdk',
      packages: {'@ai-sdk/typesafe-ai': '3.0.13', '@ai-sdk/provider': '4.0.22',
        '@ai-sdk/provider-utils': '5.0.54'}})}};
decision.operation.endpoint = 'https://fixture.invalid/systemone';
decision.task = {contract_cid: taskFixture.contract_cid, kind: 'decision',
  input_schema_cid: taskFixture.input_schema_cid,
  output_schema_cid: taskFixture.output_schema_cid};
decision.completion = {...decision.completion, basis: 'native_decision'};
decision.probability = {source: 'native',
  validation_profile_cid: 'sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f'};
const mutate = (base, change) => {const value = structuredClone(base); change(value); return value;};
const authored = [
  ['non-SDK generation', generation, true],
  ['SDK native Decision', decision, true],
  ['no raw fields promised', mutate(generation, b => {b.observations = [];}), true],
  ['estimated declaration is not native Task support', mutate(decision, b => {
    b.completion.basis = 'generation_finish'; b.probability.source = 'estimated';}), true],
  ['original revision strings', mutate(generation, b => {
    b.adapter.codec_revision = 'e\u0301\r\ncodec';}), true],
  ['unknown root member', {...generation, extra: null}, false],
  ['unknown version', {...generation, version: 'actql-model-response-profile/invalid'}, false],
  ['missing SDK discriminator', mutate(generation, b => {delete b.adapter.sdk;}), false],
  ['SDK lock absent', mutate(decision, b => {delete b.adapter.sdk.lock_artifact_cid;}), false],
  ['SDK interface mismatch', mutate(decision, b => {b.adapter.sdk.interface = 'v3';}), false],
  ['unknown adapter field', mutate(generation, b => {b.adapter.authorized = true;}), false],
  ['ABI mismatch', mutate(generation, b => {b.adapter.port_abi = 'model-physical-port/invalid';}), false],
  ['streaming not supported', mutate(generation, b => {b.operation.streaming = true;}), false],
  ['operation mismatch', mutate(generation, b => {b.operation.method = 'GET';}), false],
  ['missing completion basis', mutate(generation, b => {delete b.completion.basis;}), false],
  ['metadata cannot replace endpoint validation', mutate(generation, b => {b.completion.endpoint_envelope = false;}), false],
  ['incomplete transport', mutate(generation, b => {b.completion.transport_eof = false;}), false],
  ['unchecked output', mutate(generation, b => {b.completion.output_contract = false;}), false],
  ['generation with probabilities', mutate(generation, b => {b.probability = decision.probability;}), false],
  ['Decision with missing probabilities', mutate(decision, b => {b.probability = null;}), false],
  ['native codec with estimated probabilities', mutate(decision, b => {b.probability.source = 'estimated';}), false],
  ['generation using native completion', mutate(generation, b => {b.completion.basis = 'native_decision';}), false],
  ['observations duplicated', mutate(generation, b => {b.observations.push('provider_metadata');}), false],
  ['observations order changed', mutate(generation, b => {b.observations.reverse();}), false],
  ['unknown observation', mutate(generation, b => {b.observations = ['sdk_model_default'];}), false],
  ['zero body bound', mutate(generation, b => {b.limits.response_bytes = 0;}), false],
  ['fractional parse bound', mutate(generation, b => {b.limits.parse_work = 0.5;}), false],
  ['unbounded parse', mutate(generation, b => {b.limits.parse_nodes = 2147483648;}), false],
  ['overflowing holding minimum', mutate(generation, b => {
    b.limits.response_bytes = 2147483647; b.limits.chunk_bytes = 2147483647;
    b.limits.adapter_holding_bytes = 2147483647;}), false],
  ['unfunded backing minimum', mutate(generation, b => {b.limits.adapter_holding_bytes = 2815;}), false],
  ['exact backing minimum', mutate(generation, b => {b.limits.adapter_holding_bytes = 2816;}), true],
  ['fifth active slot', mutate(generation, b => {b.limits.active_slots = 5;}), false],
  ['fifth unsettled slot', mutate(generation, b => {b.limits.unsettled_slots = 5;}), false],
  ['second model request', mutate(generation, b => {b.controls.model_requests = 2;}), false],
  ...Object.keys(generation.controls).filter(name => name !== 'model_requests')
    .map(name => [`hidden ${name}`, mutate(generation, b => {b.controls[name] = true;}), false]),
];
const nodes = value => 1 + (value !== null && typeof value === 'object'
  ? Object.values(value).reduce((sum, child) => sum + nodes(child), 0) : 0);
const structuralWork = value => {
  if (value === null) return 0;
  if (typeof value === 'string') return value.length;
  if (typeof value !== 'object') return 1;
  if (Array.isArray(value)) return value.length * 9 +
    value.reduce((sum, child) => sum + structuralWork(child), 0);
  return Object.keys(value).length + Object.entries(value).reduce((sum, [key, child]) =>
    sum + key.length + structuralWork(child), 0);
};
const installationLiteral = body => {
  const a = body.adapter, c = body.completion;
  const sdk = a.sdk === null ? 'None' : 'Some({' +
    Object.entries({...a.sdk, package_name: a.sdk.package})
      .filter(([key]) => key !== 'package')
      .map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join(', ') + '})';
  return '{' + Object.entries({builder_id: a.builder_id,
    builder_revision: a.builder_revision, codec_id: a.codec_id,
    codec_revision: a.codec_revision, build_artifact_cid: a.build_artifact_cid,
    endpoint: body.operation.endpoint, validator_id: c.validator_id,
    validator_revision: c.validator_revision,
    validator_artifact_cid: c.validator_artifact_cid, completion_basis: c.basis})
    .map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join(', ') +
    ', sdk: ' + sdk + ', http_method: "POST", streaming: false}';
};

export function responseProfileVectors() {
  const cases = authored.map(([id, body, accepted]) => {
    const expected_cid = hash(body);
    const wire = canonicalText({...body, self_cid: expected_cid});
    return {id, body, accepted, expected_cid, wire,
      expected_canonical_bytes: canonicalText(body),
      expected_nodes: nodes({...body, self_cid: expected_cid}),
      expected_work: accepted ? 3 * Buffer.byteLength(wire) +
        structuralWork({...body, self_cid: expected_cid}) : null};
  });
  const corpus = {version: 'actql-model-response-profile-vectors/0.1', cases};
  const crossBindings = [
    ['foreign Task CID', b => {b.task.contract_cid = hash({fixture: 'another-task'});}, 'ReferenceMismatch'],
    ['foreign input schema', b => {b.task.input_schema_cid = hash({fixture: 'another-input'});}, 'InputSchemaMismatch'],
    ['foreign output schema', b => {b.task.output_schema_cid = hash({fixture: 'another-output'});}, 'OutputSchemaMismatch'],
  ].map(([id, change, issue]) => {
    const body = mutate(generation, change), expected_cid = hash(body);
    return {id, body, expected_cid, issue,
      wire: canonicalText({...body, self_cid: expected_cid})};
  });
  corpus.cross_bindings = crossBindings;
  let moon = '// Generated from independently authored physical profile bodies.\n';
  for (const c of cases) {
    moon += `\n///|\ntest ${JSON.stringify('Response profile: ' + c.id)} {\n` +
      ` let wire = ${JSON.stringify(c.wire)}\n let cid = ${JSON.stringify(c.expected_cid)}\n` +
      ' let limits : Limits = {max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 10}\n' +
      ' let value = read_model_response_profile(@utf8.encode(wire), cid, limits, 100000)\n';
    if (c.accepted) {
      moon += ` let admitted = value.unwrap()\n assert_eq(model_response_profile_identity(admitted), cid)\n` +
        ` assert_eq(model_response_profile_usage(admitted), (${Buffer.byteLength(c.wire)}, ${c.expected_nodes}, ${c.expected_work}))\n` +
        ` let exact : Limits = {..limits, max_bytes: ${Buffer.byteLength(c.wire)}, max_nodes: ${c.expected_nodes}}\n` +
        ` assert_true(read_model_response_profile(@utf8.encode(wire), cid, exact, ${c.expected_work}) is Ok(_))\n` +
        ` assert_true(read_model_response_profile(@utf8.encode(wire), cid, exact, ${c.expected_work - 1}) is Err({kind: WorkLimit, ..}))\n` +
        ` assert_true(read_model_response_profile(@utf8.encode(wire), cid, {..exact, max_bytes: exact.max_bytes - 1}, 100000) is Err({kind: BodyLimit, ..}))\n` +
        ` assert_true(read_model_response_profile(@utf8.encode(wire), cid, {..exact, max_nodes: exact.max_nodes - 1}, 100000) is Err({kind: BodyLimit, ..}))\n`;
    } else moon += ' assert_true(value is Err(_))\n';
    moon += '}\n';
  }
  const valid = cases[0], native = cases[1];
  moon += `\n///|\nfn response_profile_fixture(wire : String, cid : String) -> ModelResponseProfile {\n` +
    ' read_model_response_profile(@utf8.encode(wire), cid, model_limits().bodies, 100000).unwrap()\n}\n';
  moon += '\n///|\nfn response_profile_generation_installation() -> ModelResponseProfileInstallation {\n' +
    installationLiteral(generation) + '\n}\n';
  moon += '\n///|\nfn response_profile_native_installation() -> ModelResponseProfileInstallation {\n' +
    installationLiteral(decision) + '\n}\n';
  moon += `\n///|\ntest "Response profile binds checked Task and exact installation facts without execution" {\n` +
    ` let generation = response_profile_fixture(${JSON.stringify(valid.wire)}, ${JSON.stringify(valid.expected_cid)})\n` +
    ' let tasks = check_model_tasks(model_wire([sealed_fixture(model_core(), "contract_cid")]), model_limits()).unwrap()\n' +
    ' let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()\n' +
    ' let installation = response_profile_generation_installation()\n' +
    ' assert_eq(check_model_response_profile_binding(generation, task, installation, None), Ok(()))\n' +
    ' assert_eq(check_model_response_profile_binding(generation, decision_fixture_task(), installation, None), Err(ReferenceMismatch))\n' +
    ' assert_eq(check_model_response_profile_binding(generation, task, {..installation, endpoint: "https://foreign.invalid/"}, None), Err(ReferenceMismatch))\n' +
    ' assert_eq(check_model_response_profile_binding(generation, task, {..installation, http_method: "GET"}, None), Err(ReferenceMismatch))\n' +
    ' assert_eq(check_model_response_profile_binding(generation, task, {..installation, streaming: true}, None), Err(ReferenceMismatch))\n' +
    ' assert_eq(check_model_response_profile_binding(generation, task, {..installation, build_artifact_cid: "sha256:" + "f".repeat(64)}, None), Err(ReferenceMismatch))\n' +
    ' for changed in [{..installation, builder_id: "foreign"}, {..installation, builder_revision: "foreign"}, {..installation, codec_id: "foreign"}, {..installation, codec_revision: "foreign"}, {..installation, validator_id: "foreign"}, {..installation, validator_revision: "foreign"}, {..installation, validator_artifact_cid: "sha256:" + "f".repeat(64)}, {..installation, completion_basis: "native_decision"}] {\n' +
    '   assert_eq(check_model_response_profile_binding(generation, task, changed, None), Err(ReferenceMismatch))\n }\n' +
    ` let native = response_profile_fixture(${JSON.stringify(native.wire)}, ${JSON.stringify(native.expected_cid)})\n` +
    ' let native_installation = response_profile_native_installation()\n' +
    ' let task = decision_fixture_task()\n' +
    ' assert_eq(check_model_response_profile_binding(native, task, native_installation, Some(initial_jev_decision_profile())), Ok(()))\n' +
    ' assert_eq(check_model_response_profile_binding(native, task, native_installation, None), Err(ReferenceMismatch))\n' +
    ' let sdk = native_installation.sdk.unwrap()\n' +
    ' assert_eq(check_model_response_profile_binding(native, task, {..native_installation, sdk: Some({..sdk, lock_artifact_cid: "sha256:" + "f".repeat(64)})}, Some(initial_jev_decision_profile())), Err(ReferenceMismatch))\n' +
    ' for changed in [None, Some({..sdk, package_name: "foreign"}), Some({..sdk, version: "foreign"}), Some({..sdk, interface: "foreign"})] {\n' +
    '   assert_eq(check_model_response_profile_binding(native, task, {..native_installation, sdk: changed}, Some(initial_jev_decision_profile())), Err(ReferenceMismatch))\n }\n' +
    ` let estimated = response_profile_fixture(${JSON.stringify(cases[3].wire)}, ${JSON.stringify(cases[3].expected_cid)})\n` +
    ' assert_eq(check_model_response_profile_binding(estimated, task, {..native_installation, completion_basis: "generation_finish"}, Some(initial_jev_decision_profile())), Err(ReferenceMismatch))\n' +
    ' assert_eq(model_response_profile_observation_count(generation), 6)\n' +
    ' assert_eq(model_response_profile_observation_at(generation, 5), Some("provider_metadata"))\n' +
    ' assert_eq(model_response_profile_observation_at(generation, 6), None)\n}\n';
  for (const c of crossBindings) {
    moon += `\n///|\ntest ${JSON.stringify('Response profile binding: ' + c.id)} {\n` +
      ` let profile = response_profile_fixture(${JSON.stringify(c.wire)}, ${JSON.stringify(c.expected_cid)})\n` +
      ' let tasks = check_model_tasks(model_wire([sealed_fixture(model_core(), "contract_cid")]), model_limits()).unwrap()\n' +
      ' let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()\n' +
      ` assert_eq(check_model_response_profile_binding(profile, task, response_profile_generation_installation(), None), Err(${c.issue}))\n}\n`;
  }
  moon += `\n///|\ntest "Response profile rejects changed reference, self, body and noncanonical bytes" {\n` +
    ` let wire = ${JSON.stringify(valid.wire)}\n let cid = ${JSON.stringify(valid.expected_cid)}\n` +
    ' let limits = model_limits().bodies\n' +
    ' assert_true(read_model_response_profile(@utf8.encode(wire), "sha256:" + "f".repeat(64), limits, 100000) is Err({kind: IdentityMismatch, ..}))\n' +
    ' let foreign = "sha256:" + "f".repeat(64)\n' +
    ' assert_true(read_model_response_profile(@utf8.encode(wire.replace(old=cid, new=foreign)), foreign, limits, 100000) is Err({kind: IdentityMismatch, ..}))\n' +
    ' assert_true(read_model_response_profile(@utf8.encode(wire.replace(old="chat-one", new="chat-two")), cid, limits, 100000) is Err({kind: IdentityMismatch, ..}))\n' +
    ' assert_true(read_model_response_profile(@utf8.encode(" " + wire), cid, limits, 100000) is Err({kind: InvalidBody, ..}))\n' +
    ' assert_true(read_model_response_profile(@utf8.encode(wire), cid, {..limits, max_depth: 1}, 100000) is Err({kind: BodyLimit, ..}))\n}\n';
  moon = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
    : 'moonfmt', ['-'], {input: moon, encoding: 'utf8'});
  let publication = '// Generated independent profile artifact caller fixtures.\n';
  for (const c of cases.filter(c => ['non-SDK generation', 'SDK native Decision',
    'no raw fields promised', 'original revision strings'].includes(c.id))) {
    publication += `\n///|\ntest ${JSON.stringify('Profile artifact: ' + c.id)} {\n` +
      ` let body = ${JSON.stringify(c.expected_canonical_bytes)}\n` +
      ` let wire = ${JSON.stringify(c.wire)}\n` +
      ` let cid = ${JSON.stringify(c.expected_cid)}\n` +
      ' let issued = seal_run_evidence_value("model_response_profile", body, 16384, 1024, 20).unwrap()\n' +
      ' assert_eq(run_evidence_value_identity(issued), cid)\n' +
      ' assert_eq(run_evidence_value_json(issued), wire)\n' +
      ' let restored = admit_run_evidence_value("model_response_profile", wire, 16384, 1024, 20).unwrap()\n' +
      ' assert_eq(run_evidence_value_json(restored), wire)\n' +
      ' assert_true(admit_run_evidence_value("model_response_profile", " " + wire, 16384, 1024, 20) is Err(RunEvidenceInvalidWire))\n' +
      ' assert_true(admit_run_evidence_value("model_response_profile", wire.replace(old="codec_revision", new="unregistered_revision"), 16384, 1024, 20) is Err(RunEvidenceInvalidShape))\n' +
      ' assert_true(admit_run_evidence_value("model_response_profile", wire.replace(old="fixture", new="foreign"), 16384, 1024, 20) is Err(RunEvidenceIdentityMismatch))\n}\n';
  }
  publication = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
    : 'moonfmt', ['-'], {input: publication, encoding: 'utf8'});
  return {corpus, moon, publication};
}

export function checkResponseProfileVectors(write = false) {
  const {corpus, moon, publication} = responseProfileVectors();
  const corpusPath = 'portability/corpus/model-response-profiles.json';
  const moonPath = 'src/check_environment/model_response_profile.generated_test.mbt';
  const publicationPath = 'src/run_publication/model_response_profile.generated_test.mbt';
  if (write) {
    writeFileSync(corpusPath, JSON.stringify(corpus, null, 2) + '\n');
    writeFileSync(moonPath, moon);
    writeFileSync(publicationPath, publication);
  }
  assert.deepEqual(JSON.parse(readFileSync(corpusPath, 'utf8')), corpus);
  assert.equal(readFileSync(moonPath, 'utf8'), moon);
  assert.equal(readFileSync(publicationPath, 'utf8'), publication);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  checkResponseProfileVectors(process.argv.includes('--write'));
}
