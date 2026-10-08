// Example envelope, not an ArtifactRef or an execution-completion receipt.
// Retrieval adapters retain each original reference's own authority contract.
import {createHash} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';

const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});

export const evidenceParts = Object.freeze(['typedInput', 'typedOutput',
  'renderedInput', 'contextManifest', 'validation']);
export const contentCid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
export const referenceCid = body => contentCid(canonicalJson(body));
const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);
const plain = value => value !== null && typeof value === 'object' &&
  Object.getPrototypeOf(value) === Object.prototype;
const keys = (value, expected) => plain(value) && Object.keys(value).sort().join(',') ===
  [...expected].sort().join(',');
const fail = code => {throw Object.assign(new Error(code), {code});};

export function checkEvidenceReference(ref, subject, attemptCid, at = Date.now()) {
  if (!keys(ref, ['version', 'kind', 'part', 'subject', 'attemptCid', 'original', 'policy',
    'content', 'evidenceRefCid']) || ref.version !== 'evaluation-evidence-reference/0.1' ||
    !evidenceParts.includes(ref.part) || !cid(attemptCid) || ref.attemptCid !== attemptCid ||
    !keys(ref.subject, ['runDefinitionCid', 'authorityScopeCid']) ||
    !cid(ref.subject.runDefinitionCid) || !cid(ref.subject.authorityScopeCid) ||
    ref.subject.runDefinitionCid !== subject?.runDefinitionCid ||
    ref.subject.authorityScopeCid !== subject?.authorityScopeCid) fail('EvidenceSubjectMismatch');
  if (!keys(ref.policy, ['kind', 'cid', 'wire']) || ref.policy.kind !== 'data_policy' ||
    !cid(ref.policy.cid) || typeof ref.policy.wire !== 'string' ||
    ref.policy.wire.length > 16384 || Buffer.byteLength(ref.policy.wire) > 16384 ||
    contentCid(ref.policy.wire) !== ref.policy.cid) fail('InvalidEvidencePolicy');
  let policy;
  try {policy = JSON.parse(ref.policy.wire);} catch {fail('InvalidEvidencePolicy');}
  if (policy.version !== 'actql-effective-data-policy/0.1' ||
    typeof policy.unknown_provenance !== 'boolean' ||
    !['public', 'internal', 'confidential', 'restricted', 'unknown'].includes(policy.classification)) {
    fail('InvalidEvidencePolicy');
  }
  if (!keys(ref.content, ['cid', 'sizeBytes', 'expiresAt', 'truncated']) ||
    !cid(ref.content.cid) || !Number.isSafeInteger(ref.content.sizeBytes) ||
    ref.content.sizeBytes < 1 || ref.content.sizeBytes > 1048576 ||
    ref.content.truncated !== false || !Number.isFinite(Date.parse(ref.content.expiresAt))) {
    fail('RequiredEvidenceUnavailable');
  }
  if (!Number.isFinite(at) || at >= Date.parse(ref.content.expiresAt)) fail('EvidenceExpired');
  switch (ref.kind) {
    case 'model_capture':
      if (!keys(ref.original, ['captureBundleCid', 'modelCallSlotCid', 'semanticRequestCid', 'modelTaskCid']) ||
        Object.values(ref.original).some(value => !cid(value))) fail('InvalidEvidenceReference');
      break;
    case 'result_delivery':
      if (!keys(ref.original, ['resultManifestCid', 'deliveryAttemptCid', 'readGrantCid']) ||
        Object.values(ref.original).some(value => !cid(value))) fail('InvalidEvidenceReference');
      break;
    case 'artifact': {
      const artifact = ref.original;
      if (artifact?.$actql_ref !== 'artifact' || artifact.version !== 'actql-artifact-ref/0.1' ||
        !cid(artifact.artifact_ref_cid) || artifact.metadata?.content_cid !== ref.content.cid ||
        artifact.metadata?.size_bytes !== ref.content.sizeBytes || artifact.metadata?.truncated !== false ||
        artifact.metadata?.expires_at !== ref.content.expiresAt ||
        artifact.metadata?.effective_data_policy_cid !== ref.policy.cid ||
        policy.unknown_provenance || artifact.metadata?.data_classification !== policy.classification) {
        fail('InvalidEvidenceReference');
      }
      // The Artifact adapter must still verify issuer, availability and lease
      // through its existing Store. This envelope issues none of those facts.
      break;
    }
    default: fail('InvalidEvidenceReference');
  }
  const {evidenceRefCid, ...body} = ref;
  if (!cid(evidenceRefCid) || referenceCid(body) !== evidenceRefCid) fail('InvalidEvidenceReference');
  return ref;
}

export function checkResolvedEvidence(job, resolvedEvidence, at = Date.now()) {
  let total = 0;
  const values = {};
  for (const name of evidenceParts) {
    const ref = checkEvidenceReference(job.evidence?.references?.[name], job.subject,
      job.evidence?.attemptCid, at);
    if (ref.part !== name) fail('EvidenceSubjectMismatch');
    const copy = resolvedEvidence?.[name];
    if (!keys(copy, ['refCid', 'base64']) || copy.refCid !== ref.evidenceRefCid ||
      typeof copy.base64 !== 'string' || copy.base64.length > 1398104 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(copy.base64)) {
      fail('RequiredEvidenceUnavailable');
    }
    const bytes = Buffer.from(copy.base64, 'base64');
    total += bytes.length;
    if (total > 1048576) fail('EvaluationBudgetExceeded');
    if (bytes.length !== ref.content.sizeBytes || contentCid(bytes) !== ref.content.cid) {
      fail('RequiredEvidenceUnavailable');
    }
    try {values[name] = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));}
    catch {fail('RequiredEvidenceUnavailable');}
  }
  return values;
}

// Verify correspondence to the original common capture. This is retrieval
// integrity, not a replacement Model checker or permission grant.
export function checkModelCaptureCorrespondence(job, values) {
  const refs = job.evidence.references;
  const original = refs.typedInput.original;
  if (evidenceParts.some(name => refs[name].kind !== 'model_capture' ||
      canonicalJson(refs[name].original) !== canonicalJson(original) ||
      canonicalJson(refs[name].policy) !== canonicalJson(refs.typedInput.policy))) fail('EvidenceSubjectMismatch');
  const {typedInput: input, typedOutput: output, validation, renderedInput: rendered, contextManifest: context} = values;
  let bundle;
  try {bundle = JSON.parse(validation.captureBundleWire);} catch {fail('RequiredEvidenceUnavailable');}
  const {bundle_cid: bundleCid, ...body} = bundle;
  if (validation.outcome !== 'accepted' || bundle.version !== 'actql-model-capture-bundle/0.1' ||
      bundleCid !== original.captureBundleCid || contentCid(canonicalJson(body)) !== bundleCid ||
      !Array.isArray(bundle.captures) || bundle.captures.length !== 1) fail('RequiredEvidenceUnavailable');
  const captured = bundle.captures[0], evidence = captured.evidence;
  if (canonicalJson(evidence) !== canonicalJson(validation.evidence) ||
      evidence?.version !== 'actql-model-invocation-evidence/0.1' ||
      evidence.model_task_contract_cid !== original.modelTaskCid ||
      captured.model_call_slot_cid !== original.modelCallSlotCid ||
      evidence.model_call_slot_cid !== original.modelCallSlotCid ||
      captured.semantic_request_cid !== original.semanticRequestCid ||
      evidence.semantic_request_cid !== original.semanticRequestCid ||
      input.model_task_contract_cid !== original.modelTaskCid ||
      input.model_call_slot_cid !== original.modelCallSlotCid ||
      input.semantic_request_cid !== original.semanticRequestCid ||
      (job.evidence.modelTaskCid !== undefined && job.evidence.modelTaskCid !== original.modelTaskCid) ||
      !input.input_contract || !input.output_contract || !Array.isArray(input.key) ||
      output.outcome !== 'ok' || canonicalJson(output.value) !== canonicalJson(captured.structured_response) ||
      output.validatedOutputCid !== evidence.validated_structured_output_cid ||
      contentCid(canonicalJson(output.value)) !== output.validatedOutputCid) fail('RequiredEvidenceUnavailable');
  // This fixture evaluator supports exactly one role and its known rendering.
  // Unknown provider internals remain unknown; no context is fetched here.
  if (typeof rendered.instructions !== 'string' || rendered.text !== input.inputs?.text ||
      context.providerHiddenContext !== 'unknown' ||
      canonicalJson(context.selectedFields) !== '["text"]' || context.retrievalPolicy !== 'none' ||
      (job.evidence.inputCid !== undefined && (!Array.isArray(input.key) || input.key.length !== 1 ||
        contentCid(canonicalJson({id: input.key[0], text: input.inputs.text})) !== job.evidence.inputCid)) ||
      (job.evidence.instructionCid !== undefined && contentCid(canonicalJson(rendered.instructions)) !== job.evidence.instructionCid)) {
    fail('EvidenceSubjectMismatch');
  }
  return values;
}
