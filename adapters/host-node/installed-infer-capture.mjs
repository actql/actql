// Reopen private evidence only for the already admitted Run. This reader has
// no provider port: absent or invalid custody never falls back to dispatch.
import {checked} from '../host-common/runtime-result.mjs';

const limits = Object.freeze({maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});

export async function readInstalledInferCapture({moon, control, store,
  compiled, runDefinition, storeAuthorityCid, signal}) {
  const read = async (name, slot) => {
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
    await store.confirmPrivateEvidence({name, semanticCid, holdingCid, wire});
    signal?.throwIfAborted();
    return {wire, semanticCid};
  };
  const observed = await read('observation_set', -1);
  const observation = control.admitRunEvidence('observation_set', observed.wire,
    limits);
  // The common reader admits this closed canonical body first. Its inventory
  // bounds physical reads; the common replay owner verifies all slot bindings.
  const slots = JSON.parse(observation.wire).model_slot_capture_cids;
  if (!Array.isArray(slots) || slots.length > 128) {
    throw new Error('InstalledInferCaptureInventoryUnavailable');
  }
  const records = [];
  const proofs = [];
  for (let slot = 0; slot < slots.length; slot++) {
    const adopted = await read('model_slot_capture', slot);
    records.push(checked(moon.strategyRunEvidenceAdmit('model_slot_capture',
      adopted.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    const leaves = [];
    for (const name of ['model_call_attempt', 'model_attempt_accounting',
      'model_attempt_outcome', 'model_dispatch_authority']) {
      const body = await read(name, slot);
      leaves.push(checked(moon.strategyRunEvidenceAdmit(name, body.wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    }
    proofs.push(moon.clientProgramInferAttemptRecords(...leaves));
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
