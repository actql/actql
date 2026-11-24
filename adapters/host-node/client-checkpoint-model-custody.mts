// Model INPUT and original saved-state custody within one installed Checkpoint
// connection. All reads and writes use that Host's original Evidence and
// acquisition owners; a saved document is not a Resource or dispatch grant.
import {MAX_MODEL_INPUT_BYTES} from './installed-model-input-custody.mjs';
import {selectOriginalInferMetadataAcquisition,
  selectOriginalInferStoreBootstrapAcquisition,
  selectOriginalInferResourceCodecAcquisition} from './infer-operation.mjs';

import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {openContinuationEvidence} from './local-continuation-evidence.mjs';
import type {createModelResumeState} from './model-resume-state.mjs';
import type {snapshotInferOriginalCurrentStateCodec} from './infer-original-installation.mjs';

type Control = Pick<ReturnType<typeof runtimeCore>['publicationControl'],
  'runDefinitionRunId' | 'readModelOriginalResourceDocument' | 'modelOriginalResourceOriginField'>;
type Evidence = Pick<ReturnType<typeof openContinuationEvidence>,
  'observeOriginalModelStorageBinding' | 'observeOriginalModelStorageBindingSelected' |
  'originalModelStorageBindingEvidence' | 'originalModelStorageBindingEvidenceSelected' |
  'holdOriginalModelState' | 'openOriginalModelState' | 'hold' | 'open' | 'reference'>;
type StorageBinding = Awaited<ReturnType<Evidence['observeOriginalModelStorageBinding']>>;
type RunDefinition = Readonly<{identity: string}>;
type InputReceipt = Readonly<{ownerId: string; cid: string; runId: string; runDefinitionCid: string}>;
type StateReceipt = InputReceipt & Readonly<{storageBindingCid: string}>;
type StateInput = Readonly<{runDefinition: RunDefinition; storageBinding: StorageBinding}>;
type StateWrite = StateInput & Readonly<{bodyWire: string}>;
type StateRead = StateInput & Readonly<{receipt: StateReceipt}>;
type Verifier = NonNullable<Parameters<typeof createModelResumeState>[1]['verifier']>;
type SavedFacts = ReturnType<NonNullable<Verifier['originalStateSaved']>['inspect']>;
type StateObservation = Readonly<{kind: 'saved-original-model-state'}>;
type ConfirmState = StateRead & Readonly<{identity: SavedFacts['identity']}>;
type StateRecord = {
  observation: StateObservation; facts?: SavedFacts; storageBinding?: StorageBinding;
  runDefinition?: RunDefinition;
};
type LiveStateRecord = StateRecord & Readonly<{facts: SavedFacts; storageBinding: StorageBinding}>;
type StateData = Readonly<{
  resource_state_cid: string; resource_phase: SavedFacts['phase']; cut: SavedFacts['cut'];
}>;
type Ports = Readonly<{
  contractControl: Control; evidence: Evidence;
  closed: boolean; IDENTIFIER: RegExp;
  capturedValueWire(value: unknown): string;
  fail(code: string, detail?: unknown): never;
}>;

const freezeSavedData = <Value,>(value: Value): Value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeSavedData(child);
    Object.freeze(value);
  }
  return value;
};

export function createCheckpointModelCustody(ports: Ports) {
  const {contractControl, evidence, IDENTIFIER, capturedValueWire} = ports;
  const fail: Ports['fail'] = ports.fail;
  const originalStateSavedObservations = new WeakMap<object, StateRecord>();
  const originalStateSavedByBinding = new WeakMap<StorageBinding, Map<string, LiveStateRecord>>();
  async function originalModelStorageEvidence(handle: unknown, acquisition?: unknown, ownerId?: string, requestCid?: string) {
    if (ports.closed) fail('OriginalModelStateHostStopped');
    if (acquisition !== undefined) {
      selectOriginalInferMetadataAcquisition(acquisition, ownerId, requestCid);
      if (typeof evidence.originalModelStorageBindingEvidenceSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
    }
    const selected = await (acquisition === undefined
      ? evidence.originalModelStorageBindingEvidence(handle)
      : evidence.originalModelStorageBindingEvidenceSelected(handle, ownerId!, requestCid!, acquisition));
    if (ports.closed) fail('OriginalModelStateHostStopped');
    if (acquisition !== undefined) selectOriginalInferMetadataAcquisition(acquisition, ownerId, requestCid);
    return selected;
  }
  async function originalModelBootstrapEvidence(handle: unknown, acquisition?: unknown, ownerId?: string, requestCid?: string) {
    if (ports.closed) fail('OriginalModelStateHostStopped');
    selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
    if (typeof evidence.originalModelStorageBindingEvidenceSelected !== 'function') {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await evidence.originalModelStorageBindingEvidenceSelected(
      handle, ownerId!, requestCid!, acquisition);
    if (ports.closed) fail('OriginalModelStateHostStopped');
    selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
    return selected;
  }
  function originalModelDocumentLimits(acquisition: unknown, ownerId: string, requestCid: string) {
    if (acquisition === undefined) {
      return {maxWireBytes: MAX_MODEL_INPUT_BYTES, maxNodes: 10000, maxDepth: 64};
    }
    const codec = selectOriginalInferResourceCodecAcquisition(acquisition, ownerId, requestCid) as
      ReturnType<typeof snapshotInferOriginalCurrentStateCodec>;
    const parse = codec.decode.parse;
    // This is the original Writer/decoder ceiling, not new funding, a Store
    // grant or a replacement for the complete simultaneous read envelope.
    if (parse.max_input_bytes < 1 || parse.max_nodes < 1 || parse.max_depth < 1) {
      fail('InferOriginalStateCodecUnavailable');
    }
    return {maxWireBytes: Math.min(MAX_MODEL_INPUT_BYTES, parse.max_input_bytes),
      maxNodes: parse.max_nodes, maxDepth: parse.max_depth};
  }
  async function retainOriginalModelStateBytes({runDefinition, storageBinding, bodyWire}: StateWrite, acquisition: unknown) {
    const runId = contractControl.runDefinitionRunId(runDefinition);
    if (!IDENTIFIER.test(runId)) fail('InvalidOriginalModelStateCustody');
    const ownerId = `model-${runId}`;
    const runDefinitionCid = runDefinition.identity;
    const current = () => {
      if (ports.closed) fail('OriginalModelStateHostStopped');
      if (acquisition !== undefined) {
        selectOriginalInferMetadataAcquisition(acquisition, ownerId, runDefinitionCid);
      }
    };
    current();
    const documentLimits = originalModelDocumentLimits(acquisition, ownerId, runDefinitionCid);
    if (acquisition !== undefined &&
        (typeof evidence.holdOriginalModelState !== 'function' ||
          typeof evidence.openOriginalModelState !== 'function')) {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    const document = contractControl.readModelOriginalResourceDocument(bodyWire, documentLimits);
    if (contractControl.modelOriginalResourceOriginField(document, 'run_id') !== runId ||
        contractControl.modelOriginalResourceOriginField(document, 'run_definition_cid') !== runDefinitionCid ||
        contractControl.modelOriginalResourceOriginField(document, 'storage_binding_cid') !== selected.identity) {
      fail('OriginalModelStateBindingMismatch');
    }
    const cid = acquisition === undefined
      ? (await evidence.hold(ownerId, runDefinitionCid,
        [{name: 'original_model_state', wire: document.wire}]))[0]
      : await evidence.holdOriginalModelState(ownerId, runDefinitionCid, document.wire, acquisition);
    // An unavailable original after write never rewrites that write as unsaved.
    // The same continuation keeps its park, Store and cleanup responsibilities.
    current();
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    const held = await (acquisition === undefined ? evidence.open(ownerId)
      : evidence.openOriginalModelState(ownerId, acquisition));
    current();
    if (held.requestCid !== runDefinitionCid) fail('ModelContinuationRunMismatch');
    const saved = await held.bytes('original_model_state', cid,
      {maxBytes: Math.min(documentLimits.maxWireBytes, Buffer.byteLength(document.wire, 'utf8'))});
    current();
    if (!saved.equals(Buffer.from(document.wire, 'utf8'))) fail('OriginalModelStateBindingMismatch');
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    return Object.freeze({ownerId, cid, runId, runDefinitionCid,
      storageBindingCid: selected.identity});
  }
  async function readOriginalModelStateBytes({runDefinition, storageBinding, receipt}: StateRead, acquisition: unknown) {
    const runId = contractControl.runDefinitionRunId(runDefinition);
    const ownerId = `model-${runId}`;
    const current = () => {
      if (ports.closed) fail('OriginalModelStateHostStopped');
      if (acquisition !== undefined) {
        selectOriginalInferMetadataAcquisition(acquisition, ownerId, runDefinition.identity);
      }
    };
    current();
    const documentLimits = originalModelDocumentLimits(acquisition, ownerId, runDefinition.identity);
    // The selected path never silently delegates to the ordinary Evidence
    // reader. Its physical metadata/FD lifetime belongs to that same Owner.
    if (acquisition !== undefined && typeof evidence.openOriginalModelState !== 'function') {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    current();
    if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
        Object.keys(receipt).sort().join(',') !== 'cid,ownerId,runDefinitionCid,runId,storageBindingCid' ||
        !IDENTIFIER.test(runId) || receipt.ownerId !== ownerId ||
        receipt.runId !== runId || receipt.runDefinitionCid !== runDefinition.identity ||
        receipt.storageBindingCid !== selected.identity ||
        !/^sha256:[0-9a-f]{64}$/u.test(receipt.cid ?? '')) fail('InvalidOriginalModelStateCustody');
    const held = await (acquisition === undefined ? evidence.open(ownerId)
      : evidence.openOriginalModelState(ownerId, acquisition));
    current();
    if (held.requestCid !== runDefinition.identity) fail('ModelContinuationRunMismatch');
    const bytes = await held.bytes('original_model_state', receipt.cid, {maxBytes: documentLimits.maxWireBytes});
    current();
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    const document = contractControl.readModelOriginalResourceDocument(wire, documentLimits);
    if (contractControl.modelOriginalResourceOriginField(document, 'run_id') !== runId ||
        contractControl.modelOriginalResourceOriginField(document, 'run_definition_cid') !== runDefinition.identity ||
        contractControl.modelOriginalResourceOriginField(document, 'storage_binding_cid') !== selected.identity) {
      fail('OriginalModelStateBindingMismatch');
    }
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    current();
    return {document, storage: selected};
  }
  async function confirmOriginalModelStateSavedBytes(args: ConfirmState, acquisition: unknown) {
    const {runDefinition, storageBinding, receipt, identity} = args;
    const runId = contractControl.runDefinitionRunId(runDefinition);
    if (identity === null || typeof identity !== 'object' || Array.isArray(identity) ||
        Object.keys(identity).sort().join(',') !== 'inputArtifactCid,preparedInvocationCid,providerBindingCid,runDefinitionCid,runId,scopeCid,strategyRevision,taskIndex' ||
        identity.runId !== runId || identity.runDefinitionCid !== runDefinition.identity) {
      fail('InvalidOriginalModelStateCustody');
    }
    const {document, storage} = await readOriginalModelStateBytes(args, acquisition);
    if (acquisition !== undefined) {
      selectOriginalInferMetadataAcquisition(acquisition, `model-${runId}`, runDefinition.identity);
    }
    if (ports.closed) fail('OriginalModelStateHostStopped');
    if (contractControl.modelOriginalResourceOriginField(document, 'prepared_invocation_cid') !== identity.preparedInvocationCid) {
      fail('OriginalModelStateBindingMismatch');
    }
    const documentWire = document.wire;
    // Projection of the Common-admitted data only, not a Resource phase or
    // current journal decision. Preserve the original saved evidence issuer.
    const data = JSON.parse(documentWire) as StateData;
    if (data.cut?.scope_cid !== identity.scopeCid || data.cut.input_artifact_cid !== identity.inputArtifactCid) {
      fail('OriginalModelStateBindingMismatch');
    }
    const reference = evidence.reference(receipt.ownerId, 'original_model_state', documentWire);
    if (reference.semantic_cid !== receipt.cid) fail('OriginalModelStateBindingMismatch');
    let originals = originalStateSavedByBinding.get(storageBinding);
    if (originals === undefined) {
      originals = new Map(); originalStateSavedByBinding.set(storageBinding, originals);
    }
    const prior = originals.get(reference.holding_cid);
    if (prior !== undefined) {
      if (prior.facts.documentWire !== documentWire ||
          capturedValueWire(prior.facts.identity) !== capturedValueWire(identity)) fail('OriginalModelStateBindingMismatch');
      return prior.observation;
    }
    const observation: StateObservation = Object.freeze({kind: 'saved-original-model-state'});
    const facts = freezeSavedData({identity: {...identity}, documentCid: receipt.cid,
      holdingCid: reference.holding_cid, storageBindingCid: storage.identity,
      resourceStateCid: data.resource_state_cid, phase: data.resource_phase, cut: data.cut, documentWire});
    const original = {observation, facts, storageBinding, runDefinition};
    originalStateSavedObservations.set(observation, original);
    originals.set(reference.holding_cid, original);
    return observation;
  }
  function originalModelStateSavedRecord(observation: unknown) {
    const original = originalStateSavedObservations.get(observation as object);
    if (original === undefined) fail('ForeignOriginalModelStateSavedObservation');
    if (original.facts === undefined) fail('OriginalModelStateSavedObservationRetired');
    return original as StateRecord & Readonly<{facts: SavedFacts}>;
  }
  function retireOriginalModelStateSavedObservation(observation: unknown) {
    const original = originalStateSavedObservations.get(observation as object);
    if (original === undefined) fail('ForeignOriginalModelStateSavedObservation');
    if (original.facts === undefined) return;
    const originals = originalStateSavedByBinding.get(original.storageBinding!);
    if (originals?.get(original.facts.holdingCid) !== original) {
      fail('ForeignOriginalModelStateSavedObservation');
    }
    originals.delete(original.facts.holdingCid);
    if (originals.size === 0) originalStateSavedByBinding.delete(original.storageBinding!);
    // Keep only the original nominal shell for idempotent retirement. Neither
    // an escaped token nor the Store-wide binding may retain the Run graph.
    original.facts = undefined;
    original.storageBinding = undefined;
    original.runDefinition = undefined;
  }

  return Object.freeze({
    // Installation-only custody from this exact private Evidence port, not a
    // caller's CID or matching configuration. Reopening requires fresh nominal
    // custody even when the selected Store's canonical identity is unchanged.
    async observeModelOriginalStorageBinding() {
      if (ports.closed) fail('OriginalModelStateHostStopped');
      const handle = await evidence.observeOriginalModelStorageBinding();
      if (ports.closed) fail('OriginalModelStateHostStopped');
      return handle;
    },
    async observeModelOriginalStorageBindingSelected(args: Pick<StateInput, 'runDefinition'>, acquisition: unknown) {
      // Require the operation's original bootstrap role BEFORE reading DATA;
      // omission never falls back to the ordinary unselected Store path.
      selectOriginalInferStoreBootstrapAcquisition(acquisition);
      const {runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      const requestCid = runDefinition.identity;
      if (ports.closed) fail('OriginalModelStateHostStopped');
      selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
      if (typeof evidence.observeOriginalModelStorageBindingSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      const handle = await evidence.observeOriginalModelStorageBindingSelected(ownerId, requestCid, acquisition);
      if (ports.closed) fail('OriginalModelStateHostStopped');
      selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
      return handle;
    },
    async modelOriginalStorageBindingBootstrapSelected(args: StateInput, acquisition: unknown) {
      selectOriginalInferStoreBootstrapAcquisition(acquisition);
      const {storageBinding, runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      return originalModelBootstrapEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    },
    modelOriginalStorageBindingEvidence(handle: unknown) {
      return originalModelStorageEvidence(handle);
    },
    async modelOriginalStorageBindingEvidenceSelected(args: StateInput, acquisition: unknown) {
      selectOriginalInferMetadataAcquisition(acquisition);
      const {storageBinding, runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      return originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    },
    // A data-only Common document is saved under its dedicated private role.
    // This does not authenticate the other Origin fields, restore a current
    // resource cut, acknowledge a Model Entry or grant startup/send authority.
    retainOriginalModelState: (args: StateWrite) => retainOriginalModelStateBytes(args, undefined),
    async retainOriginalModelStateSelected(args: StateWrite, acquisition: unknown) {
      // Check nominal membership before even inspecting caller DATA. Missing
      // selected physical support must never fall back to the ordinary path.
      selectOriginalInferMetadataAcquisition(acquisition);
      return retainOriginalModelStateBytes(args, acquisition);
    },
    readOriginalModelState: async (args: StateRead) => (await readOriginalModelStateBytes(args, undefined)).document,
    async readOriginalModelStateSelected(args: StateRead, acquisition: unknown) {
      // Required nominal original; an omitted/forged handle cannot opt out to
      // a legacy read. This is current-cut only, not a prime/general restriction.
      selectOriginalInferMetadataAcquisition(acquisition);
      return (await readOriginalModelStateBytes(args, acquisition)).document;
    },
    // A same-installation saved-byte observation, not a restore/read/send
    // grant. The existing Store is actually reopened and verified first;
    // an imported receipt or matching configuration alone cannot issue it.
    confirmOriginalModelStateSaved: (args: ConfirmState) => confirmOriginalModelStateSavedBytes(args, undefined),
    async confirmOriginalModelStateSavedSelected(args: ConfirmState, acquisition: unknown) {
      selectOriginalInferMetadataAcquisition(acquisition);
      return confirmOriginalModelStateSavedBytes(args, acquisition);
    },
    // The original private caller must first finish all users and unresolved
    // cut/cleanup duties, then retire this view BEFORE returning its READ
    // reservation. This drops references only: no Store deletion, physical ACK,
    // Journal mutation, Resource settlement or send grant. Stop does not block
    // this cleanup-only path, and durable bytes still require a fresh read.
    retireOriginalModelStateSavedObservation,
    originalModelStateSavedFacts(observation: unknown) {
      if (ports.closed) fail('OriginalModelStateHostStopped');
      return originalModelStateSavedRecord(observation).facts;
    },
    originalModelStateSavedObservationCurrent(observation: unknown) {
      if (ports.closed) fail('OriginalModelStateHostStopped');
      originalModelStateSavedRecord(observation);
      // Currentness is nominal installation lifetime only. The saved fact is
      // historical; callers reconfirm bytes asynchronously before using it,
      // and separately validate current Resource/authorization/retention.
      return observation;
    },

    // Exact private pre-INFER completion bytes, held before either immediate
    // inventory registration or a deferred Checkpoint. This receipt names
    // custody; callers must reopen it and validate the original owner binding.
    async retainModelInput({runId, runDefinitionCid, bodyWire}: Readonly<{runId: string; runDefinitionCid: string; bodyWire: string}>) {
      if (!IDENTIFIER.test(runId ?? '') ||
          !/^sha256:[0-9a-f]{64}$/u.test(runDefinitionCid ?? '') ||
          typeof bodyWire !== 'string' || bodyWire.length === 0 ||
          Buffer.byteLength(bodyWire) > MAX_MODEL_INPUT_BYTES) {
        fail('InvalidModelInputCustody');
      }
      const ownerId = `model-${runId}`;
      const [cid] = await evidence.hold(ownerId, runDefinitionCid,
        [{name: 'captured_input', wire: bodyWire}]);
      return Object.freeze({ownerId, cid, runId, runDefinitionCid});
    },
    async readModelInput(receipt: InputReceipt) {
      if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
          Object.keys(receipt).sort().join(',') !== 'cid,ownerId,runDefinitionCid,runId' ||
          !IDENTIFIER.test(receipt.runId ?? '') || receipt.ownerId !== `model-${receipt.runId}` ||
          !/^sha256:[0-9a-f]{64}$/u.test(receipt.cid ?? '') ||
          !/^sha256:[0-9a-f]{64}$/u.test(receipt.runDefinitionCid ?? '')) {
        fail('InvalidModelInputCustody');
      }
      const held = await evidence.open(receipt.ownerId);
      if (held.requestCid !== receipt.runDefinitionCid) fail('ModelContinuationRunMismatch');
      return held.bytes('captured_input', receipt.cid, {maxBytes: MAX_MODEL_INPUT_BYTES});
    }
  });
}
