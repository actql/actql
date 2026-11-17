import assert from 'node:assert/strict';
import {createPublicKey, verify} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {canonicalJson, bytesCid} from '../packages/sdk/checkpoints.mjs';
import {createCheckpointAnswerCodec} from '../packages/sdk/internal/checkpoint-answer-construction.generated.mjs';
import {checkpointAnswerContract} from './checkpoint-answer-wire.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const corpus = JSON.parse(await readFile(new URL('../portability/corpus/checkpoint-answer-candidates.json', import.meta.url), 'utf8'));
const limits = {maxWireBytes: 16384, maxNodes: 1000, maxDepth: 16};
const actor = value => ({keyId: value.keyId, reviewerId: value.actor,
  ...(value.authorityScopeCid === null ? {} : {authorityScopeCid: value.authorityScopeCid})});
const codec = () => createCheckpointAnswerCodec({canonicalJson, bytesCid});
const publicKey = createPublicKey({key: Buffer.from(corpus.publicKeySpkiHex, 'hex'), format: 'der', type: 'spki'});
async function finish(selected, value, selectedLimits = limits, summary = value.summary) {
  const prepared = await selected.prepareAnswerCandidate(summary, value.decision, actor(value), value.decidedAt, selectedLimits);
  const preimage = selected.answerCandidateApprovalPreimage(prepared);
  assert.equal(preimage, value.approvalPreimage ?? undefined);
  const resolution = await selected.prepareAnswerResolution(prepared, value.approvalSignature ?? undefined);
  assert.equal(selected.answerResolutionPreimage(resolution), value.resolutionPreimage);
  return selected.finishAnswerCandidate(resolution, value.resolutionSignature);
}
for (const value of corpus.vectors) test('generated candidate matches independent Common bytes and signed CID text: ' + value.name, async () => {
  const result = await finish(codec(), value);
  assert.deepEqual(result, {checkpointCid: value.summary.checkpointCid,
    resolutionWire: value.resolutionWire, approvalEvidenceWire: value.evidenceWire});
  for (const [preimage, signature] of [[value.approvalPreimage, value.approvalSignature],
    [value.resolutionPreimage, value.resolutionSignature]]) {
    if (preimage !== null) assert.equal(verify(null, Buffer.from(preimage, 'utf8'), publicKey,
      Buffer.from(signature, 'base64')), true);
  }
});

test('candidate captures data, key and primitive receivers before first asynchronous digest', async () => {
  const value = corpus.vectors[0], summary = structuredClone(value.summary), selectedActor = actor(value);
  let release, arrive, first = true;
  const entered = new Promise(resolve => {arrive = resolve;});
  const pending = new Promise(resolve => {release = resolve;});
  const primitives = {
    canonicalJson(body) {assert.equal(this, primitives); return canonicalJson(body);},
    async bytesCid(bytes) {
      assert.equal(this, primitives);
      if (first) {first = false; arrive(); await pending;}
      return bytesCid(bytes);
    },
  };
  const selected = createCheckpointAnswerCodec(primitives);
  const preparation = selected.prepareAnswerCandidate(summary, value.decision, selectedActor, value.decidedAt, limits);
  await entered;
  summary.checkpointCid = 'sha256:' + 'f'.repeat(64);
  summary.requiredArtifact.cid = 'sha256:' + 'e'.repeat(64);
  selectedActor.keyId = 'substituted-key';
  selectedActor.reviewerId = 'substituted-reviewer';
  primitives.bytesCid = primitives.canonicalJson = () => assert.fail('substituted primitive');
  release();
  const prepared = await preparation;
  assert.equal(selected.answerCandidateApprovalPreimage(prepared), value.approvalPreimage);
  const resolution = await selected.prepareAnswerResolution(prepared, value.approvalSignature);
  const result = await selected.finishAnswerCandidate(resolution, value.resolutionSignature);
  assert.equal(result.resolutionWire, value.resolutionWire);
  assert.equal(result.approvalEvidenceWire, value.evidenceWire);
  await assert.rejects(codec().prepareAnswerResolution(prepared, value.approvalSignature),
    cause => cause.code === 'InvalidShape');
});

test('identity domains reject noncanonical originals while display data and year zero stay valid', async () => {
  const value = corpus.vectors[0], run = corpus.vectors.find(item => item.summary.subject.kind === 'run_unit');
  for (const [fixture, path] of [[value, ['checkpointId']], [value, ['subject', 'prepareAttemptId']],
    [value, ['subject', 'requestId']], [run, ['subject', 'runId']]]) {
    const summary = structuredClone(fixture.summary);
    let parent = summary;
    for (const key of path.slice(0, -1)) parent = parent[key];
    parent[path.at(-1)] = 'e\u0301';
    await assert.rejects(codec().prepareAnswerCandidate(summary, fixture.decision, actor(fixture),
      fixture.decidedAt, limits), cause => cause.code === 'InvalidField' && cause.field === path.join('.'));
  }
  for (const display of ['', 'e\u0301\r\narbitrary display']) {
    const summary = {...value.summary, humanSummary: display};
    assert.equal((await finish(codec(), value, limits, summary)).resolutionWire, value.resolutionWire);
  }
  const summary = {...value.summary, createdAt: '0000-01-01T00:00:00.000Z', expiresAt: '0001-01-01T00:00:00.000Z'};
  const selected = codec(), stage = await selected.prepareAnswerCandidate(summary, value.decision, actor(value),
    '0000-06-01T00:00:00.000Z', limits);
  assert.match(selected.answerCandidateApprovalPreimage(stage), /^sha256:[0-9a-f]{64}$/u);
  for (const field of ['checkpointCid', 'reviewProjectionCid']) {
    await assert.rejects(codec().prepareAnswerCandidate({...value.summary, [field]: value.summary[field] + '\n'},
      value.decision, actor(value), value.decidedAt, limits), cause => ['InvalidShape', 'InvalidField'].includes(cause.code));
  }
});

test('candidate refuses missing signatures, profile substitutions and exact output overflow without partial evidence', async () => {
  const value = corpus.vectors[0], selected = codec();
  const prepared = await selected.prepareAnswerCandidate(value.summary, value.decision, actor(value), value.decidedAt, limits);
  await assert.rejects(selected.prepareAnswerResolution(prepared), cause => cause.code === 'InvalidField');
  for (const signature of ['', 'AAAA', 'A'.repeat(85) + 'B==', value.approvalSignature + '\n']) {
    await assert.rejects(selected.prepareAnswerResolution(prepared, signature), cause => cause.code === 'InvalidField');
  }
  const rejectedValue = corpus.vectors.find(item => item.decision === 'rejected');
  const rejected = await selected.prepareAnswerCandidate(rejectedValue.summary, rejectedValue.decision,
    actor(rejectedValue), rejectedValue.decidedAt, limits);
  assert.equal(selected.answerCandidateApprovalPreimage(rejected), undefined);
  await assert.rejects(selected.prepareAnswerResolution(rejected, value.approvalSignature),
    cause => cause.code === 'InvalidField');
  for (const summary of [{...value.summary, preparedInvocationCid: null},
    {...value.summary, requirements: ['invocation_scope_approved', 'invocation_scope_approved']}]) {
    await assert.rejects(selected.prepareAnswerCandidate(summary, value.decision, actor(value), value.decidedAt, limits));
  }
  for (const selectedLimits of [{...limits, maxNodes: 2}, {...limits, maxDepth: 1},
    {...limits, maxWireBytes: 1}]) {
    await assert.rejects(selected.prepareAnswerCandidate(value.summary, value.decision, actor(value), value.decidedAt, selectedLimits));
  }
  const expectedBound = Math.max(Buffer.byteLength(value.resolutionWire), Buffer.byteLength(value.evidenceWire));
  assert.equal(expectedBound, 930);
  assert.equal((await finish(codec(), value, {...limits, maxWireBytes: expectedBound})).resolutionWire, value.resolutionWire);
  await assert.rejects(finish(codec(), value, {...limits, maxWireBytes: expectedBound - 1}), cause => cause.code === 'Encoding');
});

test('candidate inventories derive from protocol and unknown construction expressions refuse generation', async () => {
  const registry = JSON.parse(await readFile(new URL('../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
  const protocol = JSON.parse(await readFile(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url), 'utf8'));
  const changed = structuredClone(protocol);
  changed.artifact_schemas.execution_checkpoint.oneOf[0].properties.required_artifact.properties.artifact_type.const = 'independent-artifact';
  const model = checkpointAnswerContract(registry, changed);
  assert.equal(model.candidates.find(item => item.name === 'preparation_run').artifactType, 'independent-artifact');
  assert.deepEqual(model.candidates.find(item => item.name === 'effect').requirements,
    [['effect_scope_approved'], ['effect_scope_approved', 'partial_application_accepted']]);
  const invalid = structuredClone(registry);
  invalid.checkpoint_answer_construction.documents.resolution.checkpoint_id = {source: 'summary.missing', transform: 'invented'};
  assert.throws(() => checkpointAnswerContract(invalid, protocol), /UnsupportedCheckpointAnswerConstruction/u);
});

test('actual Python Remote namespace and generated codec consume the same independent bytes without Local or Node fallback', () => {
  const output = execFileSync(process.env.ACTQL_PYTHON ?? 'python3',
    ['-I', '-B', 'scripts/fixtures/checkpoint-answer-codec.py', root],
    {cwd: root, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
  const row = output.split('\n').find(value => value.startsWith('PYTHON_CHECKPOINT_CODEC_SUMMARY '));
  assert.ok(row, output);
  const counts = JSON.parse(row.slice('PYTHON_CHECKPOINT_CODEC_SUMMARY '.length));
  assert.equal(counts.tests, 9);
  assert.equal(counts.failed, 0);
  assert.equal(counts.skipped, 0);
});
