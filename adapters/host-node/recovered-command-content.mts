// Restore the saved Command occurrence through the existing Content/Store
// owners. The parent retains this child before prepare; no provider, encoder,
// new holding, Model scope or replacement Run is opened.
import {restoreStoredGeneratedContentOriginal, consumeStoredContentOriginal,
  closeStoredContentReaders} from './generated-content-holding.mjs';

import type {contentGenerationControl} from '../host-common/content-generation-control.mjs';

type Restore = Parameters<typeof restoreStoredGeneratedContentOriginal>[0];
type Consume = Parameters<typeof consumeStoredContentOriginal>[0];
type Original = Parameters<Restore['retainOriginal']>[0];
type GenerationControl = ReturnType<typeof contentGenerationControl>;
export type RecoveredContentBorrow = Readonly<{
  binding: unknown;
  current(): boolean;
  matchesIssued(value: Original['issued']): boolean;
  wire(): unknown;
  release(): void;
}>;
export type RecoveredContentArguments = Readonly<{
  prepared: unknown;
  definition: Readonly<{wire: string; identity: string}>;
  captured: unknown;
  preview: unknown;
  invocation: unknown;
  source: unknown;
  storeAuthorityCid: string;
  memberIndex: number;
  row: number;
  inputName: string;
  limits: Readonly<{maxFields: number; maxWork: number; maxWireBytes: number; maxNodes: number; maxDepth: number}>;
}>;
export type RecoveredContentContext = RecoveredContentArguments & Readonly<{
  principalId: string;
  ownerPrincipal: string;
  authorityScopeCid: string;
  now(): string;
  authorize(principalId: string): unknown;
  referenceWire: string;
  referenceLimits: Restore['limits'];
  assertCurrent(): unknown;
  signal?: AbortSignal;
}>;
type GeneratedArgument = RecoveredContentArguments & Readonly<{
  compiled: unknown;
  generationIndex: number;
  candidate: Restore['candidate'];
  issued: Original['issued'];
}>;
type RecoveredCommandOptions = RecoveredContentContext & Readonly<{
  moon?: unknown;
  compiled: unknown;
  store: Restore['store'] & Consume['store'];
  publications: Restore['publications'] & Readonly<{
    recoverEffectCommandContent(input: GeneratedArgument): RecoveredContentBorrow;
  }>;
  control: Restore['control'] & Pick<GenerationControl, 'recoveryCandidate'>;
  installedBinding(plan: Readonly<{compiled: unknown; runDefinition: RecoveredContentArguments['definition']}>):
    Readonly<{graphPolicy: Readonly<{cid: string}>; binding: unknown}>;
  recoveryResources?: Readonly<{
    constructCaptured(captured: unknown, receiver: undefined, method: (input: GeneratedArgument) => RecoveredContentBorrow,
      argument: GeneratedArgument): unknown;
  }>;
}>;

export function prepareRecoveredCommandContent({moon, publications, control,
  prepared, compiled, definition, captured, preview, invocation, source, store,
  principalId, ownerPrincipal, storeAuthorityCid, authorityScopeCid, now, authorize,
  installedBinding, referenceLimits, memberIndex, row, inputName, referenceWire,
  assertCurrent, signal, limits, recoveryResources}: RecoveredCommandOptions) {
  if (principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
      typeof assertCurrent !== 'function' || typeof referenceWire !== 'string') {
    throw new TypeError('InvalidRecoveredCommandContent');
  }
  const plan = {compiled, runDefinition: definition};
  const expiresAt = JSON.parse(definition.wire).valid_until;
  const {graphPolicy, binding} = installedBinding(plan);
  let stopping = false, released = false, attempted = false, flight: Promise<unknown> | undefined,
    original: Original | undefined, borrow: RecoveredContentBorrow | undefined;
  const readers: Consume['readers'] = new Set();
  const live = () => !stopping && !released && store.status().closed === false &&
    Date.parse(now()) < Date.parse(expiresAt) && authorize(principalId) === true;
  const current = () => {
    signal?.throwIfAborted();
    const result = assertCurrent();
    if (result !== undefined) {
      if (result instanceof Promise) void result.catch(() => {});
      throw new TypeError('InvalidRecoveredContentCurrentFence');
    }
    if (!live()) throw new Error('RecoveredContentUnavailable');
  };
  const selected = (value: unknown) => {
    current();
    const retained = original, retainedBorrow = borrow;
    if (retained === undefined || retainedBorrow === undefined || value !== retainedBorrow.binding ||
        !retainedBorrow.current() || !retainedBorrow.matchesIssued(retained.issued)) {
      throw new Error('OriginalEffectContentUnavailable');
    }
    current();
    if (retained !== original || retainedBorrow !== borrow || stopping) {
      throw new Error('OriginalEffectContentUnavailable');
    }
    return retained;
  };
  const contentOwner = Object.freeze({
    storageForContent: selected,
    storageCurrentForContent: (value: unknown, binding: unknown) => selected(binding) === value,
    consumeContent(value: unknown, accept: Consume['accept']) {
      const retained = selected(value);
      return consumeStoredContentOriginal({store, original: retained, readers, accept,
        assertCurrent() {
          if (selected(value) !== retained) throw new Error('OriginalEffectContentUnavailable');
        }});
    },
  });
  const child = Object.freeze({
    prepare() {
      if (attempted || stopping || released) throw new Error('RecoveredContentAlreadyAttempted');
      attempted = true;
      const operation = (async () => {
        current();
        const candidate = control.recoveryCandidate(referenceWire, binding, referenceLimits);
        const description = control.inspect(candidate);
        const count = publications.capturedContentGenerationCount(captured);
        if (!Number.isSafeInteger(count) || count < 1 || count > 32) {
          throw new TypeError('InvalidRecoveredContentInventory');
        }
        let generationIndex;
        for (let index = 0; index < count; index++) {
          current();
          const occurrence = publications.capturedContentGenerationStorage(
            captured, definition, storeAuthorityCid, index);
          if (occurrence.manifestCid !== description.identity) continue;
          if (generationIndex !== undefined) throw new Error('AmbiguousRecoveredContentOccurrence');
          generationIndex = index;
        }
        if (generationIndex === undefined) throw new Error('OriginalEffectContentUnavailable');
        const issued = await restoreStoredGeneratedContentOriginal({store, publications, control,
          capturedRun: captured, runDefinition: definition, index: generationIndex, candidate,
          workspaceScopeCid: authorityScopeCid, effectiveDataPolicyCid: graphPolicy.cid,
          available: live, authorize: () => live(), assertCurrent: current,
          limits: referenceLimits, readers, signal,
          retainOriginal(value) { original = value; }});
        current();
        const argument = {compiled, prepared, definition,
          captured, preview, invocation, source, storeAuthorityCid, generationIndex,
          memberIndex, row, inputName, candidate, issued, limits};
        // The decoded Read cut its temporary workspace after Store return.
        // Re-enter that SAME original for this inverse, then cut only after
        // the synchronous validator returns. Legacy explicit ports keep their
        // original bounded path; an installed recovery always supplies it.
        const recoverOriginal = (value: GeneratedArgument) => {
          // Retain the returned view BEFORE the Read's success/current cut.
          // A failed cut still leaves its original release on this child.
          borrow = publications.recoverEffectCommandContent(value);
          return borrow;
        };
        if (recoveryResources === undefined) recoverOriginal(argument);
        else recoveryResources.constructCaptured(captured, undefined,
          recoverOriginal, argument);
        current();
        selected(borrow!.binding);
        return Object.freeze({borrow, contentOwner});
      })();
      flight = operation;
      return operation.finally(() => { if (flight === operation) flight = undefined; });
    },
    async release() {
      stopping = true;
      if (flight !== undefined || !await closeStoredContentReaders(readers)) return false;
      borrow?.release();
      borrow = original = undefined;
      released = true;
      return true;
    },
    status: () => Object.freeze({pending: !released || flight !== undefined || readers.size !== 0}),
  });
  return child;
}
