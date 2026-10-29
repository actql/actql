import {admitEffectPreviewIdentity, effectPreviewIdentityCid, issueEffectfulFinalRunReceipt,
  validateEffectfulPublicationCommit, type EffectPreviewIdentity,
  type EffectfulPublicationCommitEvidence, type PublicationContract,
  type PublicationRequestContract, type PublicationAttemptContract,
  type PublicIndexEntryContract} from '@actql/run-host-core';

declare const definition: PublicationContract;
declare const computation: PublicationContract;
declare const captured: PublicationContract;
declare const request: PublicationRequestContract;
declare const attempt: PublicationAttemptContract;
declare const index: PublicIndexEntryContract;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32};
const preview: EffectPreviewIdentity = admitEffectPreviewIdentity('wire', 'originalRun', 'context', limits);
const previewCid: string = effectPreviewIdentityCid(preview);
const receipt: PublicationContract = issueEffectfulFinalRunReceipt(definition,
  computation, captured, preview, 'set', ['member'], limits);
const evidence: EffectfulPublicationCommitEvidence = {runDefinition: definition,
  invocation: computation, definitions: [definition], artifacts: [definition],
  derivations: [definition], orderings: [definition], retentions: [definition],
  durableBindings: [definition], manifest: computation, computationReceipt: computation,
  capturedRun: captured, preview, setReceiptWire: 'set', memberReceiptWires: ['member'], finalReceipt: receipt};
validateEffectfulPublicationCommit(evidence, request, attempt, index, limits);
// @ts-expect-error A wire string is not an admitted original Preview.
issueEffectfulFinalRunReceipt(definition, computation, captured, 'wire', 'set', [], limits);
// @ts-expect-error A copied surface kind cannot construct the opaque original.
const copied: EffectPreviewIdentity = {kind: 'effect-preview-identity'};
// @ts-expect-error The complete Result-evidence inventory is required.
validateEffectfulPublicationCommit({runDefinition: definition}, request, attempt, index, limits);
// @ts-expect-error Historical wire DATA cannot replace a nominal contract.
issueEffectfulFinalRunReceipt('wire', computation, captured, preview, 'set', [], limits);
// @ts-expect-error A semantic identity string is not the admitted original.
effectPreviewIdentityCid(previewCid);
