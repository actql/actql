// Optional projection of existing, Store-confirmed INFER originals. This
// adapter never dispatches, restores, authorizes a call or changes Run state.
import {createHash} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';

// Evidence contains opaque data keys, not configuration member names.
const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});

const cid = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const missing = reason => Object.freeze({status: 'incomplete', reason});
const configurations = new WeakMap();

export function configureInferEvidence(configuration) {
  if (configuration === undefined) return undefined;
  if (configuration === null || typeof configuration !== 'object' ||
    Object.keys(configuration).sort().join(',') !== 'authorize,destination,maxBytes,sink,target' ||
    typeof configuration.target !== 'string' || !configuration.target ||
    configuration.target.length > 256 || typeof configuration.destination !== 'string' ||
    !configuration.destination || configuration.destination.length > 1024 ||
    !Number.isSafeInteger(configuration.maxBytes) || configuration.maxBytes < 1 ||
    configuration.maxBytes > 1048576 || typeof configuration.authorize !== 'function' ||
    typeof configuration.sink?.capture !== 'function' || typeof configuration.sink?.record !== 'function') {
    throw new TypeError('InvalidInferEvidenceConfiguration');
  }
  const token = Object.freeze({target: configuration.target, destination: configuration.destination,
    maxBytes: configuration.maxBytes});
  configurations.set(token, {...configuration, pending: false, sink: Object.freeze({
    capture: configuration.sink.capture.bind(configuration.sink),
    record: configuration.sink.record.bind(configuration.sink),
  })});
  return token;
}

export async function projectInferEvidence({configuration, moon, control, preparedProgram,
  plan, selected, operation, captureOwner, continuation, authorityScopeCid, retainCopy}) {
  if (configuration === undefined) return;
  const configured = configurations.get(configuration);
  if (configured === undefined) throw new TypeError('ForeignInferEvidenceConfiguration');
  const subject = Object.freeze({runDefinitionCid: plan.runDefinition.identity, authorityScopeCid});
  let manifest, copy, copying = true;
  const releaseCopy = () => {
    if (copy === undefined) return true;
    if (copying) return false;
    const released = moon.clientProgramReleaseInferEvidenceCopy(copy._0, copy._1);
    if (released.$tag !== 1) return false;
    copy = undefined; configured.pending = false; return true;
  };
  try {
    const target = moon.clientProgramInferTargetName(preparedProgram, selected.step);
    if (target !== configured.target) return;
    const bundle = captureOwner.evaluationBundle();
    if (bundle === undefined || bundle.count !== 1) manifest = missing('RequiredEvidenceUnavailable');
    else {
      if (configured.pending || bundle.wire.length > configured.maxBytes ||
          Buffer.byteLength(bundle.wire) > configured.maxBytes) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
      const reserved = moon.clientProgramReserveInferEvidenceCopy(configured.maxBytes);
      if (reserved.$tag !== 1) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
      copy = reserved._0; configured.pending = true;
      // The normal dispatch custody retains a failed release for retry. The
      // optional sink cannot make Model cleanup settle this live copy early.
      retainCopy({cleanupPending: () => copy !== undefined,
        close: async () => releaseCopy(), cleanup: async () => releaseCopy()});
      const record = JSON.parse(bundle.wire).captures[0];
      const physical = operation.evaluationRequest(0);
      const entry = continuation?.entry(0);
      const policy = control.compiledInferSourceFreeResultPolicy(plan.compiled);
      if (physical === undefined || entry === undefined || policy === undefined ||
        record?.evidence?.model_call_slot_cid !== entry.slotCid) {
        manifest = missing('RequiredEvidenceUnavailable');
      } else {
        const typedInput = moon.clientProgramModelRequestInputFrame(physical._0);
        const original = Object.freeze({captureBundleCid: bundle.cid,
          modelCallSlotCid: record.model_call_slot_cid,
          semanticRequestCid: record.semantic_request_cid,
          modelTaskCid: record.evidence.model_task_contract_cid});
        const binding = Object.freeze({subject, attemptCid: entry.attemptCid, original, policy,
          target, destination: configured.destination, purpose: 'capture'});
        const wires = {typedInput,
          typedOutput: canonicalJson({outcome: 'ok', value: record.structured_response,
            validatedOutputCid: record.evidence.validated_structured_output_cid}),
          renderedInput: physical._1, contextManifest: physical._2,
          validation: canonicalJson({outcome: 'accepted', evidence: record.evidence, captureBundleWire: bundle.wire})};
        if (Object.values(wires).some(wire => typeof wire !== 'string') ||
          Object.values(wires).reduce((sum, wire) => sum + Buffer.byteLength(wire), 0) > configured.maxBytes) {
          manifest = missing('EvaluationBudgetExceeded');
        } else if (await configured.authorize(binding) !== true) {
          manifest = missing('EvidenceReadDenied');
        } else {
          const captured = await configured.sink.capture({...binding, wires});
          manifest = Object.freeze({...captured, subject, target, attemptCid: entry.attemptCid,
            programCid: moon.clientProgramDefinitionCid(preparedProgram),
            modelTaskCid: original.modelTaskCid, providerBindingCid: selected.providerBinding.identity});
        }
      }
    }
  } catch (error) {manifest = missing(error.code ?? 'EvidenceSinkFailure');}
  finally {copying = false; if (!releaseCopy()) manifest = {...missing('EvidenceCopyCleanupPending'), cleanupPending: true};}
  // An optional evidence receipt records capture availability, not execution
  // completion. Sink errors cannot overwrite the already published Run.
  try {await configured.sink.record({subject, target: configured.target, manifest});}
  catch { /* The sink remains responsible for reporting its own unavailable receipt. */ }
}
