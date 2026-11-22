// Optional projection of existing, Store-confirmed INFER originals. This
// adapter never dispatches, restores, authorizes a call or changes Run state.
import {runtimeField, runtimeIsOkRequired} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';
// @ts-expect-error TS7016 until the authored Infer operation and its nominal receipts migrate.
import {inferCopyFundingOriginal, inferEvidenceCopyFunded} from './infer-operation.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// Results and non-scalar values stay opaque at the Common boundary.
type Runtime = Readonly<{
  clientProgramInferOccurrenceTargetName(occurrence: unknown): string | undefined;
  clientProgramReleaseInferEvidenceCopy(ledger: unknown, reservation: unknown): unknown;
  clientProgramReserveInferEvidenceCopy(maxBytes: number): unknown;
  clientProgramInferPreparedCallCount(value: unknown): number | undefined;
  clientProgramInferPreparedCallAt(value: unknown, slot: number): unknown;
  strategyRunEvidenceJson(value: unknown): string;
  clientProgramModelRequestInputFrameBounded(request: unknown, maxBytes: number): string | undefined;
  clientProgramInferTargetName(prepared: unknown, step: number): string | undefined;
  clientProgramModelRequestInputFrame(request: unknown): string | undefined;
  clientProgramDefinitionCid(prepared: unknown): string;
  clientProgramObserveOriginalInferUsageAction(value: unknown, action: unknown, observation: string): unknown;
  clientProgramStopOriginalInferUsagePublication(value: unknown): void;
  clientProgramOriginalInferUsageCompletion(value: unknown): string;
  clientProgramOriginalInferUsageItemCount(value: unknown): number;
  clientProgramOriginalInferUsageItem(value: unknown, index: number): unknown;
  clientProgramOriginalInferUsageItemAttempt(value: unknown, index: number): string | undefined;
  clientProgramNextOriginalInferUsageAction(value: unknown): unknown;
  clientProgramOriginalInferUsageActionKind(action: unknown): string | undefined;
  clientProgramOriginalInferUsageActionSlot(action: unknown): number | undefined;
  clientProgramOriginalInferUsageBindingMatches(value: unknown, action: unknown, slotCid: string, attemptCid: string): boolean;
  clientProgramOriginalInferUsageActionWire(action: unknown): string | undefined;
}>;

type Awaitable<Value> = Value | PromiseLike<Value>;
type EvidenceKind = 'typed-input' | 'usage';
type Subject = Readonly<{runDefinitionCid: string; authorityScopeCid: string}>;
type Origin = Readonly<{captureBundleCid?: string; modelCallSlotCid: string;
  semanticRequestCid?: string; modelTaskCid?: string}>;
type Authorization = Readonly<{subject: Subject; target: string | undefined;
  policy: unknown; destination: string; purpose: string; kind?: EvidenceKind;
  original?: Origin; attemptCid?: string}>;
type EvidenceReceipt = Readonly<Record<string, unknown> & {status?: string; reason?: string}>;
type Manifest = EvidenceReceipt & Readonly<{items?: readonly EvidenceReceipt[]; cleanupPending?: boolean}>;
type Sink = Readonly<{
  capture(handoff: Partial<Authorization> & Readonly<{wires: Readonly<Record<string, string | undefined>>}>):
    Awaitable<EvidenceReceipt>;
  record(receipt: Readonly<{subject: Subject | undefined; target: string | undefined; manifest: Manifest | undefined}>):
    Awaitable<unknown>;
}>;
type Configuration = Readonly<{authorize(binding: Authorization): Awaitable<boolean>;
  destination: string; kind?: EvidenceKind; maxBytes: number; sink: Sink; target: string | readonly string[]}>;
type Configured = Omit<Configuration, 'target'> & Readonly<{targets: readonly string[]}> & {pending: boolean};
type CopyOwner = Readonly<{cleanupPending(): boolean; close(): Promise<boolean>; cleanup(): Promise<boolean>}>;
type RetainCopy = (copy: CopyOwner) => void;
type Plan = Readonly<{compiled: unknown; runDefinition: Readonly<{identity: string}>}>;
type Control = Readonly<{compiledInferEvaluationPolicy(compiled: unknown): unknown}>;
type Selected = Readonly<{occurrence?: unknown; step: number; providerBinding: Readonly<{identity: string}>}>;
type PreparedInput = Readonly<{callWire: string; typedInputWire: string; renderedInput: string; contextManifest: string}>;
type Entry = Readonly<{slotCid: string; attemptCid: string}>;
type Call = Readonly<{slotCid: string; callWire: string; outcome: string; entry?: Entry;
  captureBundleCid?: string; state?: string}>;
type CaptureBundle = Readonly<{cid?: string; count: number; calls: readonly Call[]; wire: string}>;
type Inventory = Pick<CaptureBundle, 'count' | 'calls'> & Readonly<{
  readBundle?(slot: number, count: (bytes: number) => void): Awaitable<CaptureBundle | undefined>;
}>;
type UsageInventory = Readonly<{cid?: string; count: number; calls: readonly Readonly<{slotCid: string}>[]}>;
type CaptureOwner = Readonly<{evaluationBundle(): CaptureBundle | undefined;
  usageInventory?(current: () => void): UsageInventory | undefined;
  beginUsage?(maxBytes: number, current: () => void): unknown}>;
type Continuation = Readonly<{evaluationInventory(): Inventory | undefined; entry(slot: number): Entry | undefined}>;
type CaptureRecord = Readonly<{model_call_slot_cid: string; semantic_request_cid: string;
  structured_response: unknown; evidence?: Readonly<{model_call_slot_cid: string;
    model_task_contract_cid: string; validated_structured_output_cid: string}>}>;
type CaptureBody = Readonly<{captures?: CaptureRecord[]}>;
type CallBody = Readonly<{fixed_request_cid: string; model_task_cid: string; input_key_cid?: string}>;
type Identity = {modelCallSlotCid: string; attemptCid?: string; inputKeyCid?: string; callState?: string};
type PreparedOptions<Result> = Readonly<{configuration?: object; moon: Runtime; control: Control;
  plan: Plan; selected: Pick<Selected, 'occurrence'>; preparedCallSet: unknown;
  operation: Readonly<{preparedPhysicalRequest(prepared: unknown, slot: number): unknown}>;
  authorityScopeCid: string; retainCopy: RetainCopy;
  consume(inputs: readonly PreparedInput[] | undefined): Awaitable<Result>}>;
type ProjectionOptions = Readonly<{configuration?: object; moon: Runtime; control: Control;
  preparedProgram: unknown; plan: Plan; selected: Selected; captureOwner: CaptureOwner;
  operation: Readonly<{evaluationRequest(slot: number): unknown;
    evaluationInput?(slot: number): Readonly<{request: unknown; callWire: string}> | undefined}>;
  continuation?: Continuation; authorityScopeCid: string; retainCopy: RetainCopy; partial?: boolean;
  copyFunding?(bundle: CaptureBundle, kind: 'typed-input' | undefined): object | undefined;
  current?: () => void; programDefinitionCid?: string; usageCurrent?: () => void}>;
type UsageOptions = Readonly<{configured: Configured; moon: Runtime; plan: Plan; captureOwner: CaptureOwner;
  continuation?: Continuation; authorityScopeCid: string; retainCopy: RetainCopy;
  current: () => void; target: string | undefined; policy: unknown; inventory: UsageInventory}>;

// Evidence contains opaque data keys, not configuration member names.
const canonicalJson = (value: unknown) => sdkCanonicalJson(value, {dataKeys: true});

const cid = (wire: string) => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const missing = (reason: string) => Object.freeze({status: 'incomplete', reason});
const configurations = new WeakMap<object, Configured>();

// Measure these fixed string fields before allocating their JSON copy. The
// existing canonicalizer remains the sole encoder and preserves original text.
function preparedEvidenceBytes(item: PreparedInput, maxBytes: number) {
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

export function configureInferEvidence(configuration: Configuration | undefined) {
  if (configuration === undefined) return undefined;
  if (configuration === null || typeof configuration !== 'object' ||
    !['authorize,destination,maxBytes,sink,target', 'authorize,destination,kind,maxBytes,sink,target']
      .includes(Object.keys(configuration).sort().join(',')) ||
    configuration.kind !== undefined && !['typed-input', 'usage'].includes(configuration.kind) ||
    !(typeof configuration.target === 'string' || Array.isArray(configuration.target as unknown)) ||
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
export async function withPreparedInferEvidence<Result>({configuration, moon, control, plan,
  selected, preparedCallSet, operation, authorityScopeCid, retainCopy, consume}: PreparedOptions<Result>) {
  const configured = configurations.get(configuration!);
  const target = selected.occurrence === undefined ? undefined
    : moon.clientProgramInferOccurrenceTargetName(selected.occurrence);
  if (configured === undefined || ['typed-input', 'usage'].includes(configured.kind!) ||
      !configured.targets.includes(target!) || configured.pending ||
      typeof retainCopy !== 'function') return consume(undefined);
  let copy: unknown, copying = true, inputs: PreparedInput[] | undefined;
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
    if (!Number.isSafeInteger(count) || count! < 0 || count! > 128) throw new Error('RequiredEvidenceUnavailable');
    const saved = [];
    let bytes = 2;
    for (let slot = 0; slot < count!; slot++) {
      const physical = operation.preparedPhysicalRequest(preparedCallSet, slot);
      const call = moon.clientProgramInferPreparedCallAt(preparedCallSet, slot);
      if (physical === undefined || call === undefined) continue;
      const callWire = moon.strategyRunEvidenceJson(call);
      const remaining = configured.maxBytes - bytes;
      if (Buffer.byteLength(callWire) + Buffer.byteLength(runtimeField(physical, 1) as string) +
          Buffer.byteLength(runtimeField(physical, 2) as string) > remaining) throw new Error('EvaluationBudgetExceeded');
      const typedInputWire = moon.clientProgramModelRequestInputFrameBounded(runtimeField(physical, 0), Math.min(65536, remaining));
      if (typedInputWire === undefined) throw new Error('EvaluationBudgetExceeded');
      const item = {callWire, typedInputWire,
        renderedInput: runtimeField(physical, 1) as string, contextManifest: runtimeField(physical, 2) as string};
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
  copyFunding, current, programDefinitionCid, usageCurrent}: ProjectionOptions) {
  if (configuration === undefined) return;
  const configured = configurations.get(configuration);
  if (configured === undefined) throw new TypeError('ForeignInferEvidenceConfiguration');
  if (configured.kind === 'usage') {
    // Claim the existing flight before trusted current/admission callbacks can
    // reenter. Fund its fixed window before constructing the async copy input,
    // subject, items, authorization binding or retained cleanup child.
    if (configured.pending) return Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});
    configured.pending = true;
    try {
      const actualCurrent = usageCurrent ?? current;
      if (typeof actualCurrent !== 'function' || partial ||
          typeof captureOwner?.usageInventory !== 'function' ||
          typeof captureOwner?.beginUsage !== 'function' || typeof retainCopy !== 'function') {
        return Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});
      }
      actualCurrent();
      const target = selected.occurrence === undefined
        ? moon.clientProgramInferTargetName(preparedProgram, selected.step)
        : moon.clientProgramInferOccurrenceTargetName(selected.occurrence);
      if (!configured.targets.includes(target!)) return;
      const policy = control.compiledInferEvaluationPolicy(plan.compiled);
      actualCurrent();
      if (policy === undefined) return Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});
      const inventory = captureOwner.usageInventory(actualCurrent);
      actualCurrent();
      if (inventory === undefined || !Number.isSafeInteger(inventory.count) || inventory.count < 1 ||
          !Array.isArray(inventory.calls as unknown) || inventory.calls.length !== inventory.count) {
        return Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});
      }
      return await projectInferUsage({configured, moon, plan, captureOwner, continuation, authorityScopeCid,
        retainCopy, current: actualCurrent, target, policy, inventory});
    } catch {return Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});}
    finally {configured.pending = false;}
  }
  const typedInputOnly = configured.kind === 'typed-input';
  const subject = Object.freeze({runDefinitionCid: plan.runDefinition.identity, authorityScopeCid});
  let manifest: Manifest | undefined, copy: unknown, copying = true, target: string | undefined;
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
    if (!configured.targets.includes(target!)) return;
    if (typedInputOnly && typeof copyFunding !== 'function') throw Object.assign(new Error('RequiredEvidenceUnavailable'),
      {code: 'RequiredEvidenceUnavailable'});
    if (typedInputOnly && partial) throw Object.assign(new Error('RequiredEvidenceUnavailable'),
      {code: 'RequiredEvidenceUnavailable'});
    const bundle = partial ? undefined : captureOwner.evaluationBundle();
    const inventory = partial ? continuation?.evaluationInventory() : bundle;
    if (inventory === undefined || !Number.isSafeInteger(inventory.count) || inventory.count < 1 ||
        inventory.count > 2147483647 ||
        (inventory.count > 128 && (partial || !inferCopyFundingOriginal(copyFunding))) ||
        !Array.isArray(inventory.calls as unknown) || inventory.calls.length !== inventory.count) {
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
          const kind = typedInputOnly ? 'typed-input' : undefined;
          const receipt = copyFunding(bundle, kind);
          if (inventory.count > 128 && !inferEvidenceCopyFunded(receipt, bundle, kind)) {
            throw Object.assign(new Error('RequiredEvidenceUnavailable'), {code: 'RequiredEvidenceUnavailable'});
          }
          copy = Object.freeze({});
        } catch (cause) {configured.pending = false; throw cause;}
      }
      retainCopy({cleanupPending: () => copy !== undefined,
        close: async () => releaseCopy(), cleanup: async () => releaseCopy()});
      const records = bundle === undefined ? [] : (JSON.parse(bundle.wire) as CaptureBody).captures;
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
        const identity: Identity = {modelCallSlotCid: call.slotCid, attemptCid: entry?.attemptCid};
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
          const callBody = JSON.parse(call.callWire) as CallBody;
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
            originalBundle = await (inventory as Inventory).readBundle!(slot, physicalBytes => {
              // Include encrypted reading, decoding and private proof copies
              // in the same finite Evidence flight before allocation.
              const bytes = physicalBytes * 6;
              if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > configured.maxBytes - copiedBytes) {
                throw Object.assign(new Error('EvaluationBudgetExceeded'), {code: 'EvaluationBudgetExceeded'});
              }
              copiedBytes += bytes;
            });
            if (originalBundle === undefined) throw Object.assign(new Error('RequiredEvidenceUnavailable'), {code: 'RequiredEvidenceUnavailable'});
            const originals = (JSON.parse(originalBundle.wire) as CaptureBody).captures;
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
            const original = Object.freeze({captureBundleCid: originalBundle!.cid,
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
          const original = Object.freeze({captureBundleCid: originalBundle!.cid,
            modelCallSlotCid: record.model_call_slot_cid,
            semanticRequestCid: record.semantic_request_cid,
            modelTaskCid: record.evidence.model_task_contract_cid});
          const binding = Object.freeze({subject, attemptCid: entry.attemptCid, original, policy,
            target, destination: configured.destination, purpose: 'capture'});
          const wires = {typedInput,
            typedOutput: canonicalJson({outcome: 'ok', value: record.structured_response,
              validatedOutputCid: record.evidence.validated_structured_output_cid}),
            renderedInput: runtimeField(physical, 1) as string, contextManifest: runtimeField(physical, 2) as string,
            validation: canonicalJson({outcome: 'accepted', evidence: record.evidence,
              callWire: call.callWire, captureBundleWire: originalBundle!.wire})};
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
            ? 'RequiredEvidenceUnavailable' : (error as {code?: string}).code ?? 'EvidenceSinkFailure')}));
        }
      }
      const unavailable = items.find(item => item.status !== 'complete');
      manifest = Object.freeze({status: unavailable === undefined ? 'complete' : 'incomplete',
        ...(unavailable === undefined ? {} : {reason: unavailable.reason}), subject, target,
        programCid: programDefinitionCid ?? moon.clientProgramDefinitionCid(preparedProgram),
        modelTaskCid: (JSON.parse(inventory.calls[0].callWire) as CallBody).model_task_cid,
        ...(partial ? {policy} : {}),
        providerBindingCid: selected.providerBinding.identity, items: Object.freeze(items)});
    }
  } catch (error) {manifest = missing((error as {code?: string}).code ?? 'EvidenceSinkFailure');}
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

// Select one own DATA field without enumerating or retaining callback-owned
// payloads. The emitted completion is closed; extra input fields are ignored.
function usagePhysicalCompletion(value: unknown) {
  if (value === null || typeof value !== 'object' || types.isProxy(value) || Array.isArray(value)) {
    return 'incomplete';
  }
  const status = Object.getOwnPropertyDescriptor(value, 'status');
  return status?.enumerable && Object.hasOwn(status, 'value') && status.value === 'complete'
    ? 'captured' : 'incomplete';
}

async function projectInferUsage({configured, moon, plan, captureOwner, continuation, authorityScopeCid,
  retainCopy, current, target, policy, inventory}: UsageOptions) {
  let usage: unknown, action: unknown, retirement: unknown, copying = true,
    manifest: Manifest | undefined, subject: Subject | undefined, binding: Authorization | undefined;
  let currentUnavailable = false, finished = false;
  const observe = (original: unknown, outcome: string) =>
    checked(moon.clientProgramObserveOriginalInferUsageAction(usage, original, outcome));
  const check = () => {
    if (currentUnavailable) throw new Error('RequiredEvidenceUnavailable');
    try {
      if (typeof current !== 'function') throw new Error('RequiredEvidenceUnavailable');
      current();
    } catch (cause) {
      currentUnavailable = true;
      if (usage !== undefined) moon.clientProgramStopOriginalInferUsagePublication(usage);
      throw cause;
    }
  };
  const snapshot = () => {
    const completion = moon.clientProgramOriginalInferUsageCompletion(usage);
    const items = [];
    const count = moon.clientProgramOriginalInferUsageItemCount(usage);
    for (let index = 0; index < count; index++) {
      const item = moon.clientProgramOriginalInferUsageItem(usage, index);
      const slot = runtimeField(item, 0) as number, outcome = runtimeField(item, 1) as string;
      const call = inventory.calls[slot];
      const attemptCid = moon.clientProgramOriginalInferUsageItemAttempt(usage, index);
      items.push(Object.freeze({modelCallSlotCid: call.slotCid,
        ...(attemptCid === undefined ? {} : {attemptCid}),
        ...(outcome === 'complete' ? {status: 'complete'} : missing(outcome))}));
    }
    return Object.freeze({kind: 'usage',
      ...(completion === 'complete' ? {status: 'complete'} : missing(completion)),
      subject, target, items: Object.freeze(items)});
  };
  // This exact retained child reports only its own settled local work. A
  // parent cleanup during an await returns pending, never an inferred ACK.
  const cleanup = async () => {
    if (copying || usage === undefined) return false;
    try {
      if (retirement === undefined) {
        moon.clientProgramStopOriginalInferUsagePublication(usage);
        retirement = checked(moon.clientProgramNextOriginalInferUsageAction(usage));
      }
      if (retirement === undefined) {finished = true; return true;}
      if (moon.clientProgramOriginalInferUsageActionKind(retirement) !== 'retire') return false;
      observe(retirement, 'cleaned'); retirement = undefined;
      finished = true;
      return true;
    } catch {return false;}
  };
  try {
    check();
    usage = captureOwner.beginUsage!(configured.maxBytes, check);
    subject = Object.freeze({runDefinitionCid: plan.runDefinition.identity, authorityScopeCid});
    const child = {cleanupPending: () => copying || !finished,
      cleanup, close: cleanup};
    for (;;) {
      action = checked(moon.clientProgramNextOriginalInferUsageAction(usage));
      if (action === undefined) return manifest;
      const kind = moon.clientProgramOriginalInferUsageActionKind(action);
      if (kind === 'retire') {
        if (manifest === undefined) manifest = snapshot();
        else {
          const completion = moon.clientProgramOriginalInferUsageCompletion(usage);
          if ((manifest.reason ?? manifest.status) !== completion) {
            // Common completion can only move from complete to incomplete.
            // Keep the recorded items/subject, without rebuilding another
            // inventory or touching an original after current loss. This
            // outer carrier and getter alias were prefunded with the child.
            manifest = Object.freeze({kind: 'usage', status: 'incomplete',
              reason: completion, subject, target, items: manifest.items});
          }
        }
        retirement = action; action = undefined;
        copying = false;
        if (!await cleanup()) return Object.freeze({...manifest, cleanupPending: true});
        return manifest;
      }
      try {
        check();
        if (kind === 'retain') {
          try {retainCopy(child);} catch {
            observe(action, 'refused'); action = undefined; continue;
          }
          observe(action, 'retained');
        } else if (kind === 'authorize') {
          const slot = moon.clientProgramOriginalInferUsageActionSlot(action);
          const entry = continuation?.entry(slot!);
          check();
          if (typeof entry?.slotCid !== 'string' || typeof entry?.attemptCid !== 'string' ||
              !moon.clientProgramOriginalInferUsageBindingMatches(usage, action, entry.slotCid, entry.attemptCid)) {
            observe(action, 'unavailable'); action = undefined; continue;
          }
          binding = Object.freeze({subject, attemptCid: entry.attemptCid,
            original: Object.freeze({captureBundleCid: inventory.cid, modelCallSlotCid: entry.slotCid}),
            policy, target, destination: configured.destination, purpose: 'capture', kind: 'usage'});
          const authorized = await configured.authorize(binding);
          observe(action, authorized === true ? 'authorized' : 'denied');
        } else if (kind === 'capture') {
          const wire = moon.clientProgramOriginalInferUsageActionWire(action);
          const captured = await configured.sink.capture({...binding, wires: Object.freeze({usage: wire})});
          observe(action, usagePhysicalCompletion(captured));
        } else if (kind === 'record') {
          manifest = snapshot();
          check();
          await configured.sink.record({subject, target, manifest});
          observe(action, 'recorded');
        } else {
          throw Error('RequiredEvidenceUnavailable');
        }
        action = undefined;
        check();
      } catch {
        if (action !== undefined) {
          observe(action, kind === 'retain' ? 'refused' : 'failed');
          action = undefined;
        }
      }
    }
  } catch { /* Optional disclosure failure cannot replace or resend the Model. */ }
  finally {
    // Local await settlement is observed separately from Common retirement.
    // A refused cleanup remains attached to the actual retained child.
    copying = false;
    if (usage !== undefined) {
      if (manifest === undefined) {try {manifest = snapshot();} catch { /* no forged manifest */ }}
      await cleanup();
    }
  }
  return manifest ?? Object.freeze({kind: 'usage', ...missing('RequiredEvidenceUnavailable')});
}
