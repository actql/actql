import {issueStoredGeneratedContent} from './generated-content-holding.mjs';

import type {retainGeneratedContentEvidence} from './generated-content-holding.mjs';
import type {contentGenerationControl} from '../host-common/content-generation-control.mjs';
import type {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';

type Issue = Parameters<typeof issueStoredGeneratedContent>[0];
type StoredOriginal = Parameters<NonNullable<Issue['retainOriginal']>>[0];
type Retention = Parameters<typeof retainGeneratedContentEvidence>[0];
type EvidenceBinding = Awaited<ReturnType<typeof retainGeneratedContentEvidence>>['bindings'][number];
type Generation = ReturnType<typeof contentGenerationControl>;
type CaptureSetup = Parameters<typeof installRunKeyedContentCapture>[0];
type RunDefinition = CaptureSetup['plan']['runDefinition'];
type RunPlan = Readonly<{
  kind: string;
  compiled: unknown;
  runDefinition: RunDefinition;
  serializationGraph?: unknown;
  inferGraph?: unknown;
}>;
type RetainedCompletion = Readonly<{binding: string; descriptorWire: string; rows: readonly string[]}>;
type SavedGeneration = Readonly<{
  referenceWire: string;
  binding: Readonly<Record<string, unknown>>;
  byteHoldingCid: string;
  bindings: readonly EvidenceBinding[];
  completion?: RetainedCompletion;
}>;
type Publications = Retention['publications'] & Pick<CaptureSetup['publications'], 'checkClientCompiledRunOwner'> & Readonly<{
  checkedClientCompiledEffectProgram(compiled: unknown, prepared: unknown): unknown;
  checkedClientSerializationByteHoldingCid(compiled: unknown, definition: RunDefinition, storeAuthorityCid: string): string;
  admitRunEvidence(name: EvidenceBinding['name'], wire: string,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): Readonly<{identity: string}>;
  prepareCheckedClientRetainedContentOutput(compiled: unknown, definition: RunDefinition,
    generation: ReturnType<Generation['recover']>, storeAuthorityCid: string,
    completion: RetainedCompletion, live: () => boolean): unknown;
}>;
type RecoveryPorts = Readonly<{
  publications: Publications;
  control: Pick<Generation, 'recoveryCandidate' | 'recover' | 'inspect' | 'issuer' | 'issue'>;
  ownerPrincipal: string;
  storeAuthorityCid: string;
  authorityScopeCid: string;
  now(): string;
  authorize: CaptureSetup['authorize'];
  installedBinding(plan: RunPlan): Readonly<{
    graphPolicy: Readonly<{cid: string}>;
    binding: Readonly<Record<string, unknown>>;
  }>;
  referenceLimits: Parameters<Generation['recoveryCandidate']>[2];
  faultInjection?: (step: 'effect_content_generation_recovered', facts: Readonly<{holdingCid: string}>) => unknown;
}>;
type RecoveryInput = Readonly<{
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  plan: RunPlan;
  store: Issue['store'] & Required<Pick<Retention['store'], 'confirmPrivateEvidence'>>;
  principalId: string;
  signal?: AbortSignal;
  restoredInput?: Readonly<{
    savedScope?: unknown;
    token: Readonly<{available: boolean}>;
    snapshot: Readonly<{contentGeneration?: SavedGeneration}>;
    capturedContent?: unknown;
    capturedContentBinding?: CaptureSetup['sourceBinding'];
  }>;
  retainExecution: CaptureSetup['retainExecution'];
}>;

// Reopen only authenticated original Model-input custody. These handles
// borrow durable holdings; they cannot regenerate, recapture or retire bytes.
export function createGeneratedContentRunRecovery({publications, control, ownerPrincipal, storeAuthorityCid,
  authorityScopeCid, now, authorize, installedBinding, referenceLimits, faultInjection}: RecoveryPorts) {
  return async ({preparedProgram, preparedEffect, plan, store, principalId, signal,
    restoredInput, retainExecution}: RecoveryInput) => {
    if (preparedEffect !== undefined) {
      preparedProgram = publications.checkedClientCompiledEffectProgram(plan.compiled, preparedEffect);
    }
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if ((plan.kind !== 'infer' && !(plan.kind === 'effect' && preparedEffect !== undefined)) ||
        plan.serializationGraph === undefined ||
        principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
        typeof retainExecution !== 'function' || restoredInput?.savedScope === undefined) {
      throw new TypeError('InvalidInstalledContentRecovery');
    }
    let retired = false;
    const definition = JSON.parse(plan.runDefinition.wire) as Readonly<{valid_until: string}>;
    const live = () => !retired && restoredInput.token.available === true &&
      store.status().closed === false && Date.parse(now()) < Date.parse(definition.valid_until) &&
      authorize(principalId) === true;
    retainExecution(Object.freeze({cleanupPending: () => !retired,
      async close() { retired = true; return true; },
      async cleanup() { retired = true; return true; }}));
    const recheck = () => {
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
    };
    recheck();
    const original = restoredInput.snapshot.contentGeneration;
    const closed = <Value,>(value: Value, fields: readonly string[]): value is NonNullable<Value> => value !== null && typeof value === 'object' &&
      !Array.isArray(value) && Object.keys(value).sort().join(',') === fields.slice().sort().join(',');
    const {graphPolicy, binding} = installedBinding(plan);
    const fields = ['referenceWire', 'binding', 'byteHoldingCid', 'bindings'];
    if (preparedEffect !== undefined) fields.push('completion');
    if (!closed(original, fields) ||
        preparedEffect !== undefined && (!closed(original.completion, ['binding', 'descriptorWire', 'rows']) ||
          typeof original.completion.binding !== 'string' ||
          typeof original.completion.descriptorWire !== 'string' ||
          !Array.isArray(original.completion.rows) || original.completion.rows.length !== 1 ||
          original.completion.rows.some(row => typeof row !== 'string')) ||
        typeof original.referenceWire !== 'string' ||
        !closed(original.binding, Object.keys(binding)) ||
        Object.keys(binding).some(name => original.binding[name] !== binding[name]) ||
        original.byteHoldingCid !== publications.checkedClientSerializationByteHoldingCid(
          plan.compiled, plan.runDefinition, storeAuthorityCid) ||
        !Array.isArray(original.bindings) || original.bindings.length !== 3 ||
        original.bindings.some((value, index) =>
          !closed(value, ['name', 'semanticCid', 'wire', 'holdingCid']) ||
          value.name !== ['content_input_artifact', 'content_evidence', 'content_generation'][index])) {
      throw new TypeError('InstalledContentRecoveryBindingMismatch');
    }
    const evidence: ReturnType<Publications['admitRunEvidence']>[] = [];
    for (const value of original.bindings) {
      recheck();
      if (await store.confirmPrivateEvidence(value) === undefined) {
        throw new Error('InstalledContentRecoveryEvidenceUnavailable');
      }
      recheck();
      evidence.push(publications.admitRunEvidence(value.name, value.wire,
        {maxWireBytes: 16384, maxNodes: 256, maxDepth: 16}));
      if (evidence.at(-1)!.identity !== value.semanticCid) {
        throw new TypeError('InstalledContentRecoveryEvidenceMismatch');
      }
    }
    const candidate = control.recoveryCandidate(original.referenceWire, binding, referenceLimits);
    let storedOriginal: StoredOriginal | undefined;
    const content = await issueStoredGeneratedContent({store, control, candidate,
      holdingCid: original.byteHoldingCid, workspaceScopeCid: authorityScopeCid,
      effectiveDataPolicyCid: graphPolicy.cid, available: live,
      authorize: () => live(), limits: referenceLimits,
      retainOriginal: value => { storedOriginal = value; }});
    recheck();
    const generation = control.recover(plan.compiled, plan.runDefinition, plan.inferGraph,
      restoredInput.savedScope, original.bindings[2].semanticCid,
      {input: evidence[0], derivation: evidence[1], generation: evidence[2]}, candidate, content);
    const current = publications.checkedClientSerializationRecoveryBindings(
      plan.compiled, generation, storeAuthorityCid);
    if (current.length !== original.bindings.length || current.some((value, index) =>
      (['name', 'semanticCid', 'wire', 'holdingCid'] as const).some(name => value[name] !== original.bindings[index][name]))) {
      throw new TypeError('InstalledContentRecoveryEvidenceMismatch');
    }
    recheck();
    const completion = preparedEffect === undefined ? undefined
      : publications.prepareCheckedClientRetainedContentOutput(plan.compiled, plan.runDefinition,
        generation, storeAuthorityCid, original.completion!, live);
    await faultInjection?.('effect_content_generation_recovered', {
      holdingCid: original.byteHoldingCid,
    });
    recheck();
    return Object.freeze({generation, recovery: original, completion, storedOriginal,
      capturedContentRecovery: restoredInput.capturedContent,
      capturedContentBinding: restoredInput.capturedContentBinding});
  };
}
