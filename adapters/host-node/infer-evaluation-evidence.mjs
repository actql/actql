// Optional projection of existing, Store-confirmed INFER originals. This
// adapter never dispatches, restores, authorizes a call or changes Run state.
import {createHash} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';

// Evidence contains opaque data keys, not configuration member names.
const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});

const cid = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const missing = reason => Object.freeze({status: 'incomplete', reason});
const configurations = new WeakMap();

// Measure these fixed string fields before allocating their JSON copy. The
// existing canonicalizer remains the sole encoder and preserves original text.
function preparedEvidenceBytes(item, maxBytes) {
  let bytes = Buffer.byteLength(canonicalJson({callWire: '', typedInputWire: '',
    renderedInput: '', contextManifest: ''}));
  for (const value of Object.values(item)) {
    if (typeof value !== 'string') return undefined;
    for (let index = 0; index < value.length; index++) {
      const unit = value.charCodeAt(index);
      if (unit === 34 || unit === 92 || [8, 9, 10, 12, 13].includes(unit)) bytes += 2;
      else if (unit < 32) bytes += 6;
      else if (unit < 128) bytes++;
      else if (unit < 2048) bytes += 2;
      else if (unit >= 0xd800 && unit <= 0xdbff) {
        const next = value.charCodeAt(++index);
        if (!(next >= 0xdc00 && next <= 0xdfff)) return undefined;
        bytes += 4;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) return undefined;
      else bytes += 3;
      if (bytes > maxBytes) return undefined;
    }
  }
  return bytes <= maxBytes ? bytes : undefined;
}

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

// Optional bounded preservation before a send. The same private fixed-input
// receipt retains these originals; this creates no executable Model owner.
export async function withPreparedInferEvidence({configuration, moon, control, plan,
  selected, preparedCallSet, operation, authorityScopeCid, retainCopy, consume}) {
  const configured = configurations.get(configuration);
  const target = selected.occurrence === undefined ? undefined
    : moon.clientProgramInferOccurrenceTargetName(selected.occurrence);
  if (configured === undefined || !configured.targets.includes(target) || configured.pending ||
      typeof retainCopy !== 'function') return consume(undefined);
  let copy, copying = true, inputs;
  const release = () => {
    if (copy === undefined) return true;
    if (copying) return false;
    if (moon.clientProgramReleaseInferEvidenceCopy(copy._0, copy._1).$tag !== 1) return false;
    copy = undefined; configured.pending = false; return true;
  };
  try {
    const policy = control.compiledInferEvaluationPolicy(plan.compiled);
    if (policy === undefined || await configured.authorize({subject: {
      runDefinitionCid: plan.runDefinition.identity, authorityScopeCid}, target,
      policy, destination: configured.destination, purpose: 'capture'}) !== true) return consume(undefined);
    // Authorization can yield to another Run using this same capture sink.
    // Recheck the existing single-copy flight before acquiring reservation.
    if (configured.pending) return consume(undefined);
    const reserved = moon.clientProgramReserveInferEvidenceCopy(configured.maxBytes);
    if (reserved.$tag !== 1) return consume(undefined);
    copy = reserved._0; configured.pending = true;
    retainCopy({cleanupPending: () => copy !== undefined, close: async () => release(), cleanup: async () => release()});
    const count = moon.clientProgramInferPreparedCallCount(preparedCallSet);
    if (!Number.isSafeInteger(count) || count < 0 || count > 128) throw new Error('RequiredEvidenceUnavailable');
    const saved = [];
    let bytes = 2;
    for (let slot = 0; slot < count; slot++) {
      const physical = operation.preparedPhysicalRequest(preparedCallSet, slot);
      const call = moon.clientProgramInferPreparedCallAt(preparedCallSet, slot);
      if (physical === undefined || call === undefined) continue;
      const callWire = moon.strategyRunEvidenceJson(call);
      const remaining = configured.maxBytes - bytes;
      if (Buffer.byteLength(callWire) + Buffer.byteLength(physical._1) +
          Buffer.byteLength(physical._2) > remaining) throw new Error('EvaluationBudgetExceeded');
      const typedInputWire = moon.clientProgramModelRequestInputFrameBounded(physical._0, Math.min(65536, remaining));
      if (typedInputWire === undefined) throw new Error('EvaluationBudgetExceeded');
      const item = {callWire, typedInputWire,
        renderedInput: physical._1, contextManifest: physical._2};
      const amount = preparedEvidenceBytes(item, configured.maxBytes - bytes - (saved.length > 0 ? 1 : 0));
      if (amount === undefined) throw new Error('EvaluationBudgetExceeded');
      bytes += amount + (saved.length > 0 ? 1 : 0);
      saved.push(item);
    }
    inputs = saved;
  } catch { inputs = undefined; }
  try {return await consume(inputs);}
  finally {copying = false; release();}
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
