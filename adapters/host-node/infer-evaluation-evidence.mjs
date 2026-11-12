// Optional projection of existing, Store-confirmed INFER originals. This
// adapter never dispatches, restores, authorizes a call or changes Run state.
import {runtimeField, runtimeIsOkRequired} from '../host-common/compiler-binding.generated.mjs';
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
    !['authorize,destination,maxBytes,sink,target', 'authorize,destination,kind,maxBytes,sink,target']
      .includes(Object.keys(configuration).sort().join(',')) ||
    configuration.kind !== undefined && configuration.kind !== 'typed-input' ||
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
  if (configured === undefined || configured.kind === 'typed-input' ||
      !configured.targets.includes(target) || configured.pending ||
      typeof retainCopy !== 'function') return consume(undefined);
  let copy, copying = true, inputs;
  const release = () => {
    if (copy === undefined) return true;
    if (copying) return false;
    if (!runtimeIsOkRequired(moon.clientProgramReleaseInferEvidenceCopy(runtimeField(copy, 0), runtimeField(copy, 1)))) return false;
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
    if (!runtimeIsOkRequired(reserved)) return consume(undefined);
    copy = runtimeField(reserved, 0); configured.pending = true;
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
      if (Buffer.byteLength(callWire) + Buffer.byteLength(runtimeField(physical, 1)) +
          Buffer.byteLength(runtimeField(physical, 2)) > remaining) throw new Error('EvaluationBudgetExceeded');
      const typedInputWire = moon.clientProgramModelRequestInputFrameBounded(runtimeField(physical, 0), Math.min(65536, remaining));
      if (typedInputWire === undefined) throw new Error('EvaluationBudgetExceeded');
      const item = {callWire, typedInputWire,
        renderedInput: runtimeField(physical, 1), contextManifest: runtimeField(physical, 2)};
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
  plan, selected, operation, captureOwner, continuation, authorityScopeCid, retainCopy, partial = false,
  copyFunding, current, programDefinitionCid}) {
  if (configuration === undefined) return;
  const configured = configurations.get(configuration);
  if (configured === undefined) throw new TypeError('ForeignInferEvidenceConfiguration');
  const typedInputOnly = configured.kind === 'typed-input';
  const subject = Object.freeze({runDefinitionCid: plan.runDefinition.identity, authorityScopeCid});
  let manifest, copy, copying = true, target;
  let currentUnavailable = false;
  const checkOriginalCurrent = () => {
    try {current?.();} catch (cause) {currentUnavailable = true; throw cause;}
  };
  const releaseCopy = () => {
    if (copy === undefined) return true;
    if (copying) return false;
    if (copyFunding === undefined) {
      const released = moon.clientProgramReleaseInferEvidenceCopy(runtimeField(copy, 0), runtimeField(copy, 1));
      if (!runtimeIsOkRequired(released)) return false;
    }
    copy = undefined; configured.pending = false; return true;
  };
  try {
    target = selected.occurrence === undefined
      ? moon.clientProgramInferTargetName(preparedProgram, selected.step)
      : moon.clientProgramInferOccurrenceTargetName(selected.occurrence);
    if (!configured.targets.includes(target)) return;
    if (typedInputOnly && typeof copyFunding !== 'function') throw Object.assign(new Error('RequiredEvidenceUnavailable'),
      {code: 'RequiredEvidenceUnavailable'});
    if (typedInputOnly && partial) throw Object.assign(new Error('RequiredEvidenceUnavailable'),
      {code: 'RequiredEvidenceUnavailable'});
    const bundle = partial ? undefined : captureOwner.evaluationBundle();
    const inventory = partial ? continuation?.evaluationInventory() : bundle;
    if (inventory === undefined || !Number.isSafeInteger(inventory.count) || inventory.count < 1 ||
        inventory.count > 128 || !Array.isArray(inventory.calls) || inventory.calls.length !== inventory.count) {
      manifest = missing('RequiredEvidenceUnavailable');
    } else {
      if (configured.pending || bundle !== undefined && (bundle.wire.length > configured.maxBytes ||
          Buffer.byteLength(bundle.wire) > configured.maxBytes)) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
      if (copyFunding === undefined) {
        const reserved = moon.clientProgramReserveInferEvidenceCopy(configured.maxBytes);
        if (!runtimeIsOkRequired(reserved)) throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
        copy = runtimeField(reserved, 0); configured.pending = true;
      } else {
        // The Effect child owns its actual Model publication funding already.
        // Reuse one bounded window, not a policy-sized new Ledger. Mark this
        // same flight before the original current callback can reenter it.
        configured.pending = true;
        try {
          if (partial || bundle === undefined) throw new Error('RequiredEvidenceUnavailable');
          if (typedInputOnly) copyFunding(bundle, 'typed-input');
          else copyFunding(bundle);
          copy = Object.freeze({});
        } catch (cause) {configured.pending = false; throw cause;}
      }
      retainCopy({cleanupPending: () => copy !== undefined,
        close: async () => releaseCopy(), cleanup: async () => releaseCopy()});
      const records = bundle === undefined ? [] : JSON.parse(bundle.wire).captures;
      if (!Array.isArray(records) || records.length > inventory.count ||
          new Set(inventory.calls.map(call => call.slotCid)).size !== inventory.count ||
          new Set(records.map(record => record.model_call_slot_cid)).size !== records.length ||
          records.some(record => !inventory.calls.some(call => call.slotCid === record.model_call_slot_cid))) {
        throw Object.assign(new Error('RequiredEvidenceUnavailable'), {code: 'RequiredEvidenceUnavailable'});
      }
      const bySlot = new Map(records.map(record => [record.model_call_slot_cid, record]));
      const policy = control.compiledInferEvaluationPolicy(plan.compiled);
      const items = [];
      let copiedBytes = 0;
      // The accepted common owner's inventory includes response-less calls.
      // Successful capture order and physical delivery order have no authority
      // to renumber logical slots or silently remove a required case.
      for (const [slot, call] of inventory.calls.entries()) {
        const entry = call.entry ?? continuation?.entry(slot);
        const identity = {modelCallSlotCid: call.slotCid, attemptCid: entry?.attemptCid};
        let record = bySlot.get(call.slotCid), originalBundle = bundle;
        if (currentUnavailable) {
          items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
          continue;
        }
        // Existing Effect-free callers retain their original eager lookup.
        // Only this Effect boundary defers lookup until its supplied current
        // fence succeeds; it must not inspect a later call after close.
        let physical = !typedInputOnly && current === undefined ? operation.evaluationRequest(slot) : undefined;
        if (policy === undefined || typeof call.callWire !== 'string' ||
            entry !== undefined && entry.slotCid !== call.slotCid) {
          items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
          continue;
        }
        try {
          checkOriginalCurrent();
          if (!typedInputOnly && current !== undefined) physical = operation.evaluationRequest(slot);
          const callBody = JSON.parse(call.callWire);
          if (partial) {
            const authorized = await configured.authorize({subject, attemptCid: entry?.attemptCid,
              original: {captureBundleCid: call.captureBundleCid,
                modelCallSlotCid: call.slotCid, semanticRequestCid: callBody.fixed_request_cid,
                modelTaskCid: callBody.model_task_cid}, policy, target,
              destination: configured.destination, purpose: 'capture'});
            checkOriginalCurrent();
            if (authorized !== true) throw Object.assign(new Error('EvidenceReadDenied'), {code: 'EvidenceReadDenied'});
            identity.inputKeyCid = callBody.input_key_cid;
            identity.callState = call.state;
            if (call.state === 'EnteredUnknown' || call.state === 'Unsent') {
              items.push(Object.freeze({...identity, ...missing(call.state === 'EnteredUnknown'
                ? 'ModelResultUnknown' : 'ModelCallUnsent')}));
              continue;
            }
            if (physical === undefined || entry === undefined || call.outcome !== 'ok') {
              items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
              continue;
            }
            originalBundle = await inventory.readBundle(slot, physicalBytes => {
              // Include encrypted reading, decoding and private proof copies
              // in the same finite Evidence flight before allocation.
              const bytes = physicalBytes * 6;
              if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > configured.maxBytes - copiedBytes) {
                throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
              }
              copiedBytes += bytes;
            });
            if (originalBundle === undefined) throw Object.assign(new Error('RequiredEvidenceUnavailable'), {code: 'RequiredEvidenceUnavailable'});
            const originals = JSON.parse(originalBundle.wire).captures;
            if (originalBundle.count !== 1 || !Array.isArray(originals) || originals.length !== 1 ||
                originals[0].model_call_slot_cid !== call.slotCid) throw Object.assign(new Error('EvidenceSubjectMismatch'), {code: 'EvidenceSubjectMismatch'});
            record = originals[0];
          }
          if (typedInputOnly) {
            const logical = operation.evaluationInput?.(slot);
            if (call.outcome !== 'ok' || entry === undefined || logical === undefined ||
                record?.evidence?.model_call_slot_cid !== call.slotCid || logical.callWire !== call.callWire) {
              items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
              continue;
            }
            const original = Object.freeze({captureBundleCid: originalBundle.cid,
              modelCallSlotCid: record.model_call_slot_cid,
              semanticRequestCid: record.semantic_request_cid,
              modelTaskCid: record.evidence.model_task_contract_cid});
            const binding = Object.freeze({kind: 'typed-input', subject, attemptCid: entry.attemptCid,
              original, policy, target, destination: configured.destination, purpose: 'capture'});
            const authorized = await configured.authorize(binding);
            checkOriginalCurrent();
            if (authorized !== true) {
              items.push(Object.freeze({...identity, ...missing('EvidenceReadDenied')}));
              continue;
            }
            const retained = operation.evaluationInput?.(slot);
            if (retained === undefined || retained.request !== logical.request || retained.callWire !== logical.callWire) {
              items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
              continue;
            }
            const typedInput = moon.clientProgramModelRequestInputFrameBounded(logical.request,
              Math.min(65536, configured.maxBytes - copiedBytes));
            if (typeof typedInput !== 'string' || Buffer.byteLength(typedInput) > configured.maxBytes - copiedBytes) {
              items.push(Object.freeze({...identity, ...missing('EvaluationBudgetExceeded')}));
              continue;
            }
            copiedBytes += Buffer.byteLength(typedInput);
            const captured = await configured.sink.capture({...binding, wires: {typedInput}});
            items.push(Object.freeze({...captured, ...identity}));
            try {checkOriginalCurrent();} catch { /* Keep the returned receipt; do not inspect a later call. */ }
            continue;
          }
          if (call.outcome !== 'ok' || physical === undefined || entry === undefined ||
              record?.evidence?.model_call_slot_cid !== call.slotCid) {
            items.push(Object.freeze({...identity, ...missing('RequiredEvidenceUnavailable')}));
            continue;
          }
          const typedInput = moon.clientProgramModelRequestInputFrame(runtimeField(physical, 0));
          const original = Object.freeze({captureBundleCid: originalBundle.cid,
            modelCallSlotCid: record.model_call_slot_cid,
            semanticRequestCid: record.semantic_request_cid,
            modelTaskCid: record.evidence.model_task_contract_cid});
          const binding = Object.freeze({subject, attemptCid: entry.attemptCid, original, policy,
            target, destination: configured.destination, purpose: 'capture'});
          const wires = {typedInput,
            typedOutput: canonicalJson({outcome: 'ok', value: record.structured_response,
              validatedOutputCid: record.evidence.validated_structured_output_cid}),
            renderedInput: runtimeField(physical, 1), contextManifest: runtimeField(physical, 2),
            validation: canonicalJson({outcome: 'accepted', evidence: record.evidence,
              callWire: call.callWire, captureBundleWire: originalBundle.wire})};
          const bytes = Object.values(wires).reduce((sum, wire) => sum +
            (typeof wire === 'string' ? Buffer.byteLength(wire) : configured.maxBytes + 1), 0);
          if (bytes > configured.maxBytes - copiedBytes) {
            items.push(Object.freeze({...identity, ...missing('EvaluationBudgetExceeded')}));
          } else {
            const authorized = await configured.authorize(binding);
            checkOriginalCurrent();
            if (authorized !== true) {
              items.push(Object.freeze({...identity, ...missing('EvidenceReadDenied')}));
              continue;
            }
            // Charge the entire handoff before copying, including failed sink
            // attempts. A later item cannot consume the same copy budget again.
            copiedBytes += bytes;
            const captured = await configured.sink.capture({...binding, wires});
            items.push(Object.freeze({...captured, ...identity}));
            // Keep the returned original receipt, even when this Sink closed
            // its Host. The next call must not start after that boundary.
            try {checkOriginalCurrent();} catch { /* The original group retains its current failure. */ }
          }
        } catch (error) {
          items.push(Object.freeze({...identity, ...missing(currentUnavailable
            ? 'RequiredEvidenceUnavailable' : error.code ?? 'EvidenceSinkFailure')}));
        }
      }
      const unavailable = items.find(item => item.status !== 'complete');
      manifest = Object.freeze({status: unavailable === undefined ? 'complete' : 'incomplete',
        ...(unavailable === undefined ? {} : {reason: unavailable.reason}), subject, target,
        programCid: programDefinitionCid ?? moon.clientProgramDefinitionCid(preparedProgram),
        modelTaskCid: JSON.parse(inventory.calls[0].callWire).model_task_cid,
        ...(partial ? {policy} : {}),
        providerBindingCid: selected.providerBinding.identity, items: Object.freeze(items)});
    }
  } catch (error) {manifest = missing(error.code ?? 'EvidenceSinkFailure');}
  finally {
    copying = false;
    if (!releaseCopy()) manifest = {...manifest, ...missing('EvidenceCopyCleanupPending'), cleanupPending: true};
  }
  // An optional evidence receipt records capture availability, not execution
  // completion. Sink errors cannot overwrite the already published Run.
  if (typedInputOnly) manifest = Object.freeze({...manifest, kind: 'typed-input'});
  try {await configured.sink.record({subject, target, manifest});}
  catch { /* The sink remains responsible for reporting its own unavailable receipt. */ }
}
