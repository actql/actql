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
    !(typeof configuration.target === 'string' || Array.isArray(configuration.target)) ||
    typeof configuration.destination !== 'string' ||
    !configuration.destination || configuration.destination.length > 1024 ||
    !Number.isSafeInteger(configuration.maxBytes) || configuration.maxBytes < 1 ||
    configuration.maxBytes > 1048576 || typeof configuration.authorize !== 'function' ||
    typeof configuration.sink?.capture !== 'function' || typeof configuration.sink?.record !== 'function') {
    throw new TypeError('InvalidInferEvidenceConfiguration');
  }
  const targets = typeof configuration.target === 'string' ? [configuration.target] : [...configuration.target];
  if (targets.length < 1 || targets.length > 128 || new Set(targets).size !== targets.length ||
      targets.some(target => typeof target !== 'string' || !target || target.length > 256)) {
    throw new TypeError('InvalidInferEvidenceConfiguration');
  }
  const token = Object.freeze({target: Object.freeze(targets), destination: configuration.destination,
    maxBytes: configuration.maxBytes});
  configurations.set(token, {...configuration, targets: token.target, pending: false, sink: Object.freeze({
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
  let manifest, copy, copying = true, target;
  const releaseCopy = () => {
    if (copy === undefined) return true;
    if (copying) return false;
    const released = moon.clientProgramReleaseInferEvidenceCopy(copy._0, copy._1);
    if (released.$tag !== 1) return false;
    copy = undefined; configured.pending = false; return true;
  };
  try {
    target = selected.occurrence === undefined
      ? moon.clientProgramInferTargetName(preparedProgram, selected.step)
      : moon.clientProgramInferOccurrenceTargetName(selected.occurrence);
    if (!configured.targets.includes(target)) return;
    const bundle = captureOwner.evaluationBundle();
    if (bundle === undefined || !Number.isSafeInteger(bundle.count) || bundle.count < 1 ||
        bundle.count > 128 || !Array.isArray(bundle.calls) || bundle.calls.length !== bundle.count) {
      manifest = missing('RequiredEvidenceUnavailable');
    } else {
      if (configured.pending || bundle.wire.length > configured.maxBytes ||
          Buffer.byteLength(bundle.wire) > configured.maxBytes) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
      const reserved = moon.clientProgramReserveInferEvidenceCopy(configured.maxBytes);
      if (reserved.$tag !== 1) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
      copy = reserved._0; configured.pending = true;
      retainCopy({cleanupPending: () => copy !== undefined,
        close: async () => releaseCopy(), cleanup: async () => releaseCopy()});
      const records = JSON.parse(bundle.wire).captures;
      if (!Array.isArray(records) || records.length > bundle.count ||
          new Set(bundle.calls.map(call => call.slotCid)).size !== bundle.count ||
          new Set(records.map(record => record.model_call_slot_cid)).size !== records.length ||
          records.some(record => !bundle.calls.some(call => call.slotCid === record.model_call_slot_cid))) {
        throw Object.assign(new Error('RequiredEvidenceUnavailable'), {code: 'RequiredEvidenceUnavailable'});
      }
      const bySlot = new Map(records.map(record => [record.model_call_slot_cid, record]));
      const policy = control.compiledInferEvaluationPolicy(plan.compiled);
      const items = [];
      let copiedBytes = 0;
      // The accepted common owner's inventory includes response-less calls.
      // Successful capture order and physical delivery order have no authority
      // to renumber logical slots or silently remove a required case.
      for (const [slot, call] of bundle.calls.entries()) {
        const entry = continuation?.entry(slot);
        const identity = {modelCallSlotCid: call.slotCid, attemptCid: entry?.attemptCid};
        const record = bySlot.get(call.slotCid);
        const physical = operation.evaluationRequest(slot);
        if (call.outcome !== 'ok' || physical === undefined || entry === undefined || policy === undefined ||
            entry.slotCid !== call.slotCid || typeof call.callWire !== 'string' ||
            record?.evidence?.model_call_slot_cid !== call.slotCid) {
          items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
          continue;
        }
        try {
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
            validation: canonicalJson({outcome: 'accepted', evidence: record.evidence,
              callWire: call.callWire, captureBundleWire: bundle.wire})};
          const bytes = Object.values(wires).reduce((sum, wire) => sum +
            (typeof wire === 'string' ? Buffer.byteLength(wire) : configured.maxBytes + 1), 0);
          if (bytes > configured.maxBytes - copiedBytes) {
            items.push(Object.freeze({...identity, ...missing('EvaluationBudgetExceeded')}));
          } else if (await configured.authorize(binding) !== true) {
            items.push(Object.freeze({...identity, ...missing('EvidenceReadDenied')}));
          } else {
            // Charge the entire handoff before copying, including failed sink
            // attempts. A later item cannot consume the same copy budget again.
            copiedBytes += bytes;
            const captured = await configured.sink.capture({...binding, wires});
            items.push(Object.freeze({...captured, ...identity}));
          }
        } catch (error) {
          items.push(Object.freeze({...identity, ...missing(error.code ?? 'EvidenceSinkFailure')}));
        }
      }
      const unavailable = items.find(item => item.status !== 'complete');
      manifest = Object.freeze({status: unavailable === undefined ? 'complete' : 'incomplete',
        ...(unavailable === undefined ? {} : {reason: unavailable.reason}), subject, target,
        programCid: moon.clientProgramDefinitionCid(preparedProgram),
        modelTaskCid: JSON.parse(bundle.calls[0].callWire).model_task_cid,
        providerBindingCid: selected.providerBinding.identity, items: Object.freeze(items)});
    }
  } catch (error) {manifest = missing(error.code ?? 'EvidenceSinkFailure');}
  finally {copying = false; if (!releaseCopy()) manifest = {...missing('EvidenceCopyCleanupPending'), cleanupPending: true};}
  // An optional evidence receipt records capture availability, not execution
  // completion. Sink errors cannot overwrite the already published Run.
  try {await configured.sink.record({subject, target, manifest});}
  catch { /* The sink remains responsible for reporting its own unavailable receipt. */ }
}
