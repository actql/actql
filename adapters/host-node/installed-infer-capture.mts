// Reopen private evidence only for the already admitted Run. This reader has
// no provider port: absent or invalid custody never falls back to dispatch.
import {checked} from '../host-common/runtime-result.mjs';

type EvidenceName = 'observation_set' | 'source_evidence' | 'model_slot_capture' | 'model_call_attempt' |
  'model_attempt_accounting' | 'model_attempt_outcome' | 'model_dispatch_authority' |
  'model_attachment_admission' | 'model_capture_bundle';
type RunEvidence = Readonly<{name: string; wire: string}>;
type ContractLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ReplayLimits = Readonly<{maxSlots: number; maxSlotWireUnits: number}>;
type Awaitable<Value> = Value | PromiseLike<Value>;
type EncodedEvidence = NonNullable<Parameters<TextDecoder['decode']>[0]>;
type Store = Readonly<{
  inspectPhysicalHolding(holdingCid: string): Awaitable<Readonly<{manifest_cid: string}> | undefined>;
  readPrivateEvidence(name: EvidenceName, semanticCid: string, holdingCid: string): Awaitable<EncodedEvidence>;
  confirmPrivateEvidence(value: Readonly<{name: EvidenceName; semanticCid: string; holdingCid: string; wire: string}>): Awaitable<unknown>;
}>;
type Control<Replay> = Readonly<{
  modelPrivateHoldingCid(definition: unknown, authorityCid: string, name: EvidenceName, slot: number): string;
  admitRunEvidence(name: EvidenceName, wire: string, limits: ContractLimits): RunEvidence;
  readCheckedClientInferSlotReplay(compiled: unknown, definition: unknown, observation: RunEvidence,
    records: readonly unknown[], bundle: unknown, proofs: readonly unknown[], limits: ReplayLimits): Replay;
}>;
type AttemptLeaves = [attempt: unknown, accounting: unknown, outcome: unknown, authority: unknown];
type Runtime = Readonly<{
  strategyRunEvidenceAdmit(name: EvidenceName, wire: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramVerifyInferAttachmentAdmission(capture: unknown, authority: unknown, admission: unknown): unknown;
  clientProgramInferAttemptRecords(...leaves: AttemptLeaves): unknown;
  clientProgramReadInferCaptureBundle(wire: string, semanticCid: string): unknown;
  clientProgramReleaseInferCaptureBundle(bundle: unknown): unknown;
}>;
type CaptureOptions<Replay> = Readonly<{
  moon: Runtime; control: Control<Replay>; store: Store; compiled: unknown; runDefinition: unknown;
  storeAuthorityCid: string; signal?: AbortSignal;
  restoreSource?(source: RunEvidence, observation: RunEvidence): Awaitable<unknown>;
}>;

const limits = Object.freeze({maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});

export async function readInstalledInferCapture<Replay>({moon, control, store,
  compiled, runDefinition, storeAuthorityCid, signal, restoreSource}: CaptureOptions<Replay>) {
  const read = async (name: EvidenceName, slot: number) => {
    signal?.throwIfAborted();
    const holdingCid = control.modelPrivateHoldingCid(runDefinition,
      storeAuthorityCid, name, slot);
    const holding = await store.inspectPhysicalHolding(holdingCid);
    if (holding === undefined) {
      throw Object.assign(new Error('InstalledInferCaptureUnavailable'),
        {code: 'InstalledInferCaptureUnavailable'});
    }
    const semanticCid = holding.manifest_cid;
    const bytes = await store.readPrivateEvidence(name, semanticCid, holdingCid);
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    if (await store.confirmPrivateEvidence({name, semanticCid, holdingCid, wire}) === undefined) {
      throw Object.assign(new Error('InstalledInferCaptureUnavailable'),
        {code: 'InstalledInferCaptureUnavailable'});
    }
    signal?.throwIfAborted();
    return {wire, semanticCid};
  };
  const observed = await read('observation_set', -1);
  const observation = control.admitRunEvidence('observation_set', observed.wire,
    limits);
  if (restoreSource !== undefined) {
    const saved = await read('source_evidence', 0);
    const source = control.admitRunEvidence('source_evidence', saved.wire,
      {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100});
    await restoreSource(source, observation);
  }
  // The common reader admits this closed canonical body first. Its inventory
  // bounds physical reads; the common replay owner verifies all slot bindings.
  const slots = JSON.parse(observation.wire).model_slot_capture_cids;
  if (!Array.isArray(slots) || slots.length > 128) {
    throw new Error('InstalledInferCaptureInventoryUnavailable');
  }
  const records: unknown[] = [];
  const proofs: unknown[] = [];
  for (let slot = 0; slot < slots.length; slot++) {
    const adopted = await read('model_slot_capture', slot);
    records.push(checked(moon.strategyRunEvidenceAdmit('model_slot_capture',
      adopted.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    const leaves: unknown[] = [];
    for (const name of ['model_call_attempt', 'model_attempt_accounting',
      'model_attempt_outcome', 'model_dispatch_authority'] as const) {
      const body = await read(name, slot);
      leaves.push(checked(moon.strategyRunEvidenceAdmit(name, body.wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    }
    const attachmentCids = JSON.parse(adopted.wire).attachment_admission_cids;
    let attachment: unknown;
    if (attachmentCids.length !== 0) {
      const body = await read('model_attachment_admission', slot);
      attachment = checked(moon.strategyRunEvidenceAdmit('model_attachment_admission',
        body.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    }
    checked(moon.clientProgramVerifyInferAttachmentAdmission(records.at(-1), leaves[3], attachment));
    proofs.push(moon.clientProgramInferAttemptRecords(...leaves as AttemptLeaves));
  }
  const captured = await read('model_capture_bundle', -1);
  const bundle = checked(moon.clientProgramReadInferCaptureBundle(captured.wire,
    captured.semanticCid));
  try {
    signal?.throwIfAborted();
    return control.readCheckedClientInferSlotReplay(compiled, runDefinition,
      observation, records, bundle, proofs,
      {maxSlots: 128, maxSlotWireUnits: limits.maxWireBytes});
  } finally {
    moon.clientProgramReleaseInferCaptureBundle(bundle);
  }
}
