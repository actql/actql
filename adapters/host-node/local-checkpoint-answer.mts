// The existing Local Host's purpose-confined Reviewer connection. No key or
// generic sign callback escapes to the SDK; its explicit answer operation is
// still independently admitted by the Checkpoint/Account/Effect owners.
import {createHash, randomUUID, sign, verify, createPublicKey} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

import type {createLocalSigningMetadata} from '../host-common/local-signing-metadata.mjs';
import type {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import type {CheckpointSummary} from '../../packages/sdk/index.mjs';

type Decision = 'approved' | 'rejected';
type ProofRole = 'approval' | 'resolution';
type Summary = CheckpointSummary & Readonly<{
  subject: Readonly<{runDefinitionCid: string; runId: string}>;
}>;
type SigningView = Readonly<{runDefinitionCid: string | null; requiredArtifact: Readonly<{cid: string}> | null}>;
type Ref = Readonly<{namespaceId: string; authorityScopeCid: string; runDefinitionCid: string}>;
type Observation = Readonly<{cancellationRequested: boolean}>;
type SubmittedIntent = Readonly<{referenceWire: string; assertCurrent(): unknown}>;
type Invocation = Readonly<{identity: unknown}>;
type Recovery = Readonly<{
  materials?: unknown; originalSubmittedIntent?: SubmittedIntent; requestIdentity: unknown;
  computation: Readonly<{preview: unknown; invocation: Invocation}>;
  assertUpdateSelectionCurrent?(): unknown;
}>;
type Restored<Managed, Original> = Readonly<{managedEffect: Managed; original?: Original}>;
type Borrowed = Readonly<{
  materials: unknown; requestIdentity: unknown; referenceWire: string; invocation: Invocation;
  assertCurrent(): unknown;
}>;
type LoadOriginal = <Result>(view: SigningView, signal: AbortSignal | undefined,
  consume: (original: Borrowed) => Result) => Promise<Awaited<Result>>;
type SigningReaderControl = Readonly<{effectComputationPreviewSemanticCid(preview: unknown): unknown}>;
type ReaderOptions<Managed, Original, Runtime, Control extends SigningReaderControl,
  Frame extends Observation, Recovered extends Recovery> = Readonly<{
  namespaceId: string; authorityScopeCid: string; moon: Runtime; control: Control;
  journal: Readonly<{
    lookupRunDefinition(ref: Ref, moon: Runtime, control: Control, previous?: Frame): Frame | undefined;
    canReinspectRunForSigning(previous: Frame, next: Frame): boolean;
  }>;
  restoreEffectManagedPreparation(ref: Ref, signal?: AbortSignal):
    Restored<Managed, Original> | PromiseLike<Restored<Managed, Original>>;
  recoverEffectCapture(ref: Ref, signal: AbortSignal | undefined, managedEffect: Managed,
    preparation: undefined, original: Original | undefined, signing: true): Recovered | PromiseLike<Recovered>;
  localSigningRecoveries: Set<Recovered>;
  assertCurrent(): unknown;
  releaseLocalSigningRecovery(original: Recovered): unknown;
  clientOperationError(code: string): unknown;
}>;
type ProofRuntime = Readonly<{
  clientLocalCheckpointProofPrepare(checkpointWire: string, resolutionWire: string): unknown;
  clientLocalCheckpointProofPreimage(proof: unknown): string;
  clientLocalCheckpointProofActor(proof: unknown): string;
  clientLocalCheckpointProofSeal(proof: unknown, keyId: string, signature: string): unknown;
  clientLocalCheckpointProofEffectSubject(materials: unknown, referenceWire: string, checkpointWire: string): unknown;
}>;
type Runtime = ProofRuntime & Readonly<{
  clientRequestIntentCid(requestIdentity: unknown): unknown;
  clientRequestScopeCid(requestIdentity: unknown): unknown;
}>;
type MockAccount = Pick<NonNullable<Awaited<ReturnType<typeof initializeOrdinaryMockAccount>>>, 'reviewer' | 'signingOriginal' | 'assertSigningCurrent'>;
type Store = Parameters<MockAccount['signingOriginal']>[0];
type Key = ReturnType<MockAccount['signingOriginal']> & Readonly<{sampledAt: bigint; expiresAt: bigint}>;
type SigningContext = Readonly<{view: SigningView; wire: string; configurationCid: string | undefined; assertCurrent(): unknown}>;
type SigningJournal = Readonly<{
  localSigningRecord(key: string): string | undefined;
  transitionLocalSigningRecord(key: string, previous: string | undefined, nextWire: string): string;
}>;
type AnswerOptions = Readonly<{
  moon: Runtime;
  checkpoints: Readonly<{journal: SigningJournal; localSigningContext(input: Readonly<{
    principalId: string; summary: Summary; signingResource?: string; signal?: AbortSignal;
  }>): SigningContext | PromiseLike<SigningContext>}>;
  mockAccount: MockAccount; store: Store;
  authorityScopeCid: string; principalId: string; metadata: ReturnType<typeof createLocalSigningMetadata>;
  assertCurrent(): unknown;
  loadRunOriginal: LoadOriginal;
  now?: () => number;
}>;
type Proof = Readonly<{state: 'claimed'; preimage: string; grantWire: string; grantCid: string; useWire: unknown; useCid: unknown}> |
  Readonly<{state: 'saved'; preimage: string; grantWire: string; grantCid: string; useWire: unknown; useCid: unknown; signature: string}>;
type Answer = Readonly<{checkpointCid: string; resolutionWire: string; approvalEvidenceWire: string}>;
type Record = Readonly<{
  binding: unknown; summary: Summary; decision: Decision; attemptId: string; sampledAt: string; expiresAt: string;
  policyWire: string; policyCid: string; issuer: unknown;
  signatures: Readonly<Partial<{[Role in ProofRole]: Proof}>>; answer: Answer | null;
}>;
type ApprovalProof = Readonly<{scheme: string; key_id: string; signature: string}>;
const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const hash = (value: unknown) => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const own = <Value,>(value: Value): Value => JSON.parse(canonicalJson(value));
const names = ['clientLocalCheckpointProofPrepare', 'clientLocalCheckpointProofPreimage',
  'clientLocalCheckpointProofActor', 'clientLocalCheckpointProofSeal',
  'clientLocalCheckpointProofEffectSubject'] as const;

// The existing Host signing reader borrows its restored parent through the
// consumer and releases it once. Only the Journal may recognize its own
// one-way physical-stop/status progressions; no signing original is reconstructed.
export function createLocalSigningOriginalReader<Managed, Original, Runtime,
  Control extends SigningReaderControl, Frame extends Observation, Recovered extends Recovery>({namespaceId, authorityScopeCid, moon, control, journal,
  restoreEffectManagedPreparation, recoverEffectCapture, localSigningRecoveries,
  assertCurrent, releaseLocalSigningRecovery, clientOperationError}: ReaderOptions<Managed, Original, Runtime, Control, Frame, Recovered>) {
  return async function loadRunOriginal<Result>(view: SigningView, signal: AbortSignal | undefined,
    consume: (original: Borrowed) => Result): Promise<Awaited<Result>> {
    if (typeof consume !== 'function') throw clientOperationError('LocalSigningOriginalConflict');
    const ref = {namespaceId, authorityScopeCid, runDefinitionCid: view.runDefinitionCid!};
    let retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || retained.cancellationRequested) {
      throw clientOperationError('LocalSigningOriginalConflict');
    }
    let restored: Restored<Managed, Original> | undefined = await restoreEffectManagedPreparation(ref, signal);
    let recovered: Recovered | undefined = await recoverEffectCapture(ref, signal, restored.managedEffect, undefined, restored.original, true);
    localSigningRecoveries.add(recovered);
    let originalFailure: unknown, failed = false;
    try {
      if (recovered.materials === undefined || recovered.originalSubmittedIntent === undefined ||
          control.effectComputationPreviewSemanticCid(recovered.computation.preview) !== view.requiredArtifact!.cid) {
        throw clientOperationError('LocalSigningOriginalConflict');
      }
      const current = () => {
        if (recovered === undefined) throw clientOperationError('LocalSigningOriginalConflict');
        assertCurrent();
        recovered.originalSubmittedIntent!.assertCurrent();
        recovered.assertUpdateSelectionCurrent?.();
        const next = journal.lookupRunDefinition(ref, moon, control, retained);
        if (next === undefined || next.cancellationRequested || next !== retained &&
            !journal.canReinspectRunForSigning(retained!, next)) {
          throw clientOperationError('LocalSigningOriginalConflict');
        }
        retained = next;
      };
      current();
      return await Reflect.apply(consume, undefined, [Object.freeze({materials: recovered.materials,
        requestIdentity: recovered.requestIdentity,
        referenceWire: recovered.originalSubmittedIntent.referenceWire,
        invocation: recovered.computation.invocation, assertCurrent: current})]) as Awaited<Result>;
    } catch (cause) {originalFailure = cause; failed = true; throw cause;}
    finally {
      let original: Recovered | undefined = recovered;
      recovered = restored = undefined;
      try {
        const release = releaseLocalSigningRecovery(original!);
        original = undefined;
        await release;
      }
      catch (cleanup) {
        if (failed) throw Object.assign(new AggregateError([originalFailure, cleanup],
          'Original signing capture and cleanup failed', {cause: originalFailure}),
        {code: 'LocalSigningCaptureCleanupPending', cleanupPending: true});
        throw cleanup;
      }
    }
  };
}

export function createLocalCheckpointAnswer({moon, checkpoints, mockAccount, store,
  authorityScopeCid, principalId, metadata, assertCurrent, loadRunOriginal, now = Date.now}: AnswerOptions) {
  const methods = Object.fromEntries(names.map(name => [name, moon[name]]));
  if (names.some(name => typeof methods[name] !== 'function')) fail('CheckpointSignerUnavailable');
  const call = <Name extends keyof ProofRuntime,>(name: Name, ...args: Parameters<ProofRuntime[Name]>) =>
    Reflect.apply(methods[name] as (...args: unknown[]) => unknown, moon, args) as ReturnType<ProofRuntime[Name]>;
  const signingOriginal = mockAccount.signingOriginal, keyCurrent = mockAccount.assertSigningCurrent;
  const signingResource = mockAccount.reviewer?.resource;
  const contextOriginal = checkpoints.localSigningContext;
  const journal = checkpoints.journal, read = journal.localSigningRecord;
  const transition = journal.transitionLocalSigningRecord;
  if (![signingOriginal, keyCurrent, contextOriginal, read, transition, assertCurrent,
    loadRunOriginal, now].every(value => typeof value === 'function') || metadata === undefined) {
    fail('CheckpointSignerUnavailable');
  }
  const flights = new Map<string, Promise<Answer>>();
  const readRecord = (key: string) => Reflect.apply(read, journal, [key]);
  const move = (key: string, previous: string | undefined, next: Record) => Reflect.apply(transition, journal,
    [key, previous, canonicalJson(next)]);

  async function answer(summary: CheckpointSummary, decision: Decision, signal?: AbortSignal) {
    if (!['approved', 'rejected'].includes(decision) || !cid(summary?.checkpointCid)) {
      fail('InvalidCheckpointAnswer');
    }
    // Signing context checks the owned effect_set checkpoint before its Run subject is read.
    const selected = own(summary) as Summary;
    assertCurrent(); signal?.throwIfAborted();
    const context = await Reflect.apply(contextOriginal, checkpoints,
      [{principalId, summary: selected, signingResource, signal}]);
    assertCurrent(); context.assertCurrent();
    let consuming = false, active = true;
    try {
      const result = await loadRunOriginal(context.view, signal, async (original: Borrowed | undefined) => {
        if (!active || consuming) fail('LocalSigningOriginalConflict');
        consuming = true;
        try {
          assertCurrent(); context.assertCurrent(); original!.assertCurrent();
          const operation = hash({checkpoint_cid: selected.checkpointCid, purpose: 'reviewer_proof'});
          let wire = readRecord(operation), record: Record | undefined = wire === undefined ? undefined : JSON.parse(wire);
          const sample = record === undefined ? now() : Number(record.sampledAt);
          if (!Number.isSafeInteger(sample) || sample < 0) fail('InvalidLocalSigningClock');
          assertCurrent(); signal?.throwIfAborted();
          await Reflect.apply(keyCurrent, mockAccount, [store]);
          assertCurrent(); context.assertCurrent(); original!.assertCurrent();
          const key = Reflect.apply(signingOriginal, mockAccount,
            [store, BigInt(sample), BigInt(Date.parse(selected.expiresAt))]) as Key;
          if (key.signingResource !== signingResource) fail('LocalSigningOriginalConflict');
          const subject = checked(call('clientLocalCheckpointProofEffectSubject',
            original!.materials, original!.referenceWire, context.wire));
          const binding = {authority_scope_cid: authorityScopeCid,
            checkpoint_cid: selected.checkpointCid, checkpoint_id: selected.checkpointId,
            checkpoint_kind: selected.kind, account_id: key.accountId,
            account_configuration_cid: context.configurationCid, principal: principalId,
            request_cid: moon.clientRequestIntentCid(original!.requestIdentity),
            request_scope_cid: moon.clientRequestScopeCid(original!.requestIdentity),
            submission_scope_cid: runtimeField(subject, 0), unit_definition_cid: runtimeField(subject, 1),
            run_definition_cid: selected.subject.runDefinitionCid,
            run_invocation_cid: original!.invocation.identity,
            host_adoption_cid: key.adoptionCid, key_generation_cid: key.keyGenerationCid,
            key_public_key_cid: key.publicKeyCid, key_id: key.keyId,
            key_configuration_cid: hash({key_id: key.keyId, key_public_key_cid: key.publicKeyCid,
              purpose: 'reviewer_proof', initialization_intent_cid: key.initializationIntentCid})};
          if (record === undefined) {
            record = {binding, summary: selected, decision, attemptId: randomUUID(),
              sampledAt: key.sampledAt.toString(), expiresAt: key.expiresAt.toString(),
              policyWire: key.policyWire, policyCid: key.policyCid, issuer: key.issuer,
              signatures: {}, answer: null};
            wire = move(operation, undefined, record);
          } else if (canonicalJson(record.binding) !== canonicalJson(binding) ||
              canonicalJson(record.summary) !== canonicalJson(selected) || record.decision !== decision ||
              record.policyWire !== key.policyWire || record.policyCid !== key.policyCid ||
              record.issuer !== key.issuer || record.expiresAt !== key.expiresAt.toString()) {
            fail('LocalSigningOriginalConflict');
          }
          const current = () => {
            assertCurrent(); signal?.throwIfAborted(); context.assertCurrent(); original!.assertCurrent();
            const time = now();
            if (!Number.isSafeInteger(time) || time < sample || BigInt(time) >= key.expiresAt) {
              fail('LocalSigningExpired');
            }
            if (readRecord(operation) !== wire) fail('LocalSigningOriginalConflict');
          };
          async function physicalProof(role: ProofRole, preimage: string) {
            current();
            const previous = record!.signatures[role];
            if (previous !== undefined) {
              if (previous.preimage !== preimage || previous.state !== 'saved') fail('LocalSigningUnknown');
              const expectedGrant = {...binding, attempt_id: record!.attemptId,
                issuer_authority: key.issuer, purpose: 'reviewer_proof', preimage,
                expires_unix_ms: record!.expiresAt, max_uses: key.maxUses,
                version: 'actql-local-signing-credential-grant/0.1'};
              if (previous.grantWire !== canonicalJson(expectedGrant) || previous.grantCid !== hash(expectedGrant)) {
                fail('LocalSigningOriginalConflict');
              }
              const grant = metadata.admitGrant(previous.grantWire, previous.grantCid);
              const use = metadata.admitUse(grant, previous.useWire, previous.useCid);
              const originalUse = metadata.useProjection(use);
              if (originalUse.grantCid !== previous.grantCid || originalUse.ordinal !== 1 ||
                  originalUse.useId !== record!.attemptId + ':' + role) fail('LocalSigningOriginalConflict');
              metadata.checkUseBinding(use, {trustedNowMilliseconds: BigInt(now()), revoked: false,
                expectedScope: metadata.originalScope(grant)});
              if (!verify(null, Buffer.from(preimage), createPublicKey(key.privateKey),
                Buffer.from(previous.signature, 'base64'))) fail('LocalSigningOriginalConflict');
              return previous.signature;
            }
            await Reflect.apply(keyCurrent, mockAccount, [store]); current();
            const grantBody = {...binding, attempt_id: record!.attemptId,
              issuer_authority: key.issuer, purpose: 'reviewer_proof', preimage,
              expires_unix_ms: record!.expiresAt, max_uses: key.maxUses,
              version: 'actql-local-signing-credential-grant/0.1'};
            const grantWire = canonicalJson(grantBody), grantCid = hash(grantBody);
            const grant = metadata.admitGrant(grantWire, grantCid), scope = metadata.originalScope(grant);
            const use = metadata.prepareUse(grant, {useId: record!.attemptId + ':' + role,
              trustedNowMilliseconds: BigInt(now()), usedCount: 0, revoked: false, expectedScope: scope});
            const claim: Proof = {state: 'claimed', preimage, grantWire, grantCid,
              useWire: metadata.useWire(use), useCid: metadata.useCid(use)};
            const next: Record = {...record!, signatures: {...record!.signatures, [role]: claim}};
            wire = move(operation, wire, next); record = next;
            // The original durable claim precedes the native operation. Failure or
            // lost outcome here remains claimed; another answer cannot sign again.
            current();
            metadata.checkUseBinding(use, {trustedNowMilliseconds: BigInt(now()), revoked: false, expectedScope: scope});
            let bytes: Buffer;
            try {bytes = sign(null, Buffer.from(preimage, 'utf8'), key.privateKey);}
            catch (cause) {fail('LocalSigningUnknown', cause);}
            if (bytes.length !== 64) fail('LocalSigningUnknown');
            const saved: Record = {...record, signatures: {...record.signatures,
              [role]: {...claim, state: 'saved', signature: bytes.toString('base64')}}};
            try {wire = move(operation, wire, saved); record = saved;}
            catch (cause) {fail('LocalSigningUnknown', cause);}
            await Reflect.apply(keyCurrent, mockAccount, [store]); current();
            return (record.signatures[role] as Extract<Proof, {state: 'saved'}>).signature;
          }
          current();
          const decidedAt = new Date(sample).toISOString();
          let evidence;
          if (decision === 'approved') {
            const approval: {version: string; effect_preview_cid: string; review_projection_cid: string; authority_scope_cid: string;
              claims: readonly string[]; approver: string; approved_at: string; proof?: ApprovalProof; attestation_cid?: string} = {version: 'actql-approval-attestation/0.1',
              effect_preview_cid: selected.requiredArtifact.cid,
              review_projection_cid: selected.reviewProjectionCid, authority_scope_cid: authorityScopeCid,
              claims: [...selected.requirements], approver: key.reviewerId, approved_at: decidedAt};
            approval.proof = {scheme: 'ed25519-v1', key_id: key.keyId,
              signature: await physicalProof('approval', hash(approval))};
            approval.attestation_cid = hash(approval);
            evidence = {version: 'actql-checkpoint-approval-evidence/0.1', kind: selected.kind,
              checkpoint_cid: selected.checkpointCid, review_projection_cid: selected.reviewProjectionCid,
              compatibility_approval: approval};
          }
          const body = {version: 'actql-checkpoint-resolution/0.1',
            resolution_id: `resolution-${selected.checkpointId}-${decision}`,
            checkpoint_id: selected.checkpointId, checkpoint_cid: selected.checkpointCid,
            run_id: selected.subject.runId, run_definition_cid: selected.subject.runDefinitionCid,
            decision, actor: key.reviewerId, decided_at: decidedAt,
            required_artifact_cid: selected.requiredArtifact.cid, review_projection_cid: selected.reviewProjectionCid,
            ...(evidence === undefined ? {} : {approval_evidence_cid: hash(evidence)})};
          const prepared = checked(call('clientLocalCheckpointProofPrepare', context.wire, canonicalJson(body)));
          if (call('clientLocalCheckpointProofActor', prepared) !== key.reviewerId) fail('LocalSigningOriginalConflict');
          const preimage = call('clientLocalCheckpointProofPreimage', prepared);
          const signature = await physicalProof('resolution', preimage);
          const answer = {checkpointCid: selected.checkpointCid,
            resolutionWire: checked(call('clientLocalCheckpointProofSeal', prepared, key.keyId, signature)) as string,
            approvalEvidenceWire: evidence === undefined ? '' : canonicalJson(evidence)};
          current();
          if (record.answer !== null) {
            if (canonicalJson(record.answer) !== canonicalJson(answer)) fail('LocalSigningOriginalConflict');
          } else {
            const saved = {...record, answer}; wire = move(operation, wire, saved); record = saved;
          }
          current(); return Object.freeze(own(answer));
        } finally {
          // The actual loader still backs this borrowed frame. Drop its heavy
          // originals before that same loader can close the recovery parent.
          original = undefined;
        }
      });
      if (!consuming) fail('LocalSigningOriginalConflict');
      return result;
    } finally {
      active = false;
    }
  }

  return function answerCheckpoint(summary: CheckpointSummary, decision: Decision, signal?: AbortSignal) {
    const selected = own(summary);
    const key = selected?.checkpointCid;
    if (flights.has(key)) fail('LocalSigningAlreadyPending');
    const flight = Promise.resolve().then(() => answer(selected, decision, signal));
    flights.set(key, flight);
    const settled = () => {if (flights.get(key) === flight) flights.delete(key);};
    flight.then(settled, settled);
    return flight;
  };
}
