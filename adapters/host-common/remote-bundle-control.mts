import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';
import type {BundleHoldScopeInput} from '../../packages/coordinator-core/index.js';

type BigIntInput = Parameters<typeof BigInt>[0];
type Component = Readonly<{role: string; cid: string; bytes: BigIntInput}>;
type ManifestIdentity = Readonly<{
  issuerAuthority: string;
  bundleName: string;
  revision: string;
  targetTriple: string;
  connectorRegistration: string;
  connectorRevision: string;
  strategyRevision: string;
}>;
type SingleComponentManifest = ManifestIdentity & Readonly<{
  components?: undefined | null;
  componentCid: string;
  componentBytes: BigIntInput;
}>;
type ComponentManifest = ManifestIdentity & Readonly<{components: readonly Component[]}>;
type ManifestDeclaration = SingleComponentManifest | ComponentManifest;
type SignatureEnvelope = Readonly<{
  version: string;
  keyId: string;
  runtimeBundleCid: string;
  body: string;
  signature: string;
}>;

// Reuse the shared scope DATA without imposing another runtime's opaque handle.
type HoldScope = Readonly<Omit<BundleHoldScopeInput, 'distribution'> & {distribution: unknown}>;
type HoldBinding = HoldScope & Readonly<{catalogIncarnation: string; initialRevision: number}>;
type HoldObservation = Readonly<{
  catalogIncarnation: string;
  record: unknown;
  binding: unknown;
  exactLiveHold: boolean;
}>;
type HoldRetention = Readonly<{
  catalogIncarnation: string;
  activeBundleCid?: string;
  record: unknown;
  binding: unknown;
  maxOwners: number;
}>;
type CustodyResponse = Readonly<{status: string; catalogIncarnation?: string; revision?: number}>;

// Opaque Common values and raised Results retain their original representation.
type CommonBundleBindings = {
  strategyRemoteBundleCatalogIncarnationValid(value: string): boolean;
  strategyRemoteBundleDistributionPrepare(runtimeBundleCids: readonly string[]): unknown;
  strategyRemoteBundleDistributionIdentity(value: unknown): string;
  strategyRemoteBundleDistributionJson(value: unknown): unknown;
  strategyRemoteBundleDistributionProjection(value: unknown): readonly string[];
  strategyRemoteBundleDistributionContains(value: unknown, runtimeBundleCid: string): boolean;
  strategyRemoteBundleDistributionAdmitJson(body: string, claimedDistributionCid: string): unknown;
  strategyRemoteBundleHoldScopePrepare(
    distribution: unknown, coordinatorAuthority: string, workspaceId: string, authorityScopeCid: string,
    environment: string, setRevisionCid: string, runtimeBundleCid: string, siteKey: string,
    siteGeneration: number, attemptId: string,
  ): unknown;
  strategyRemoteBundleHoldScopeIdentity(value: unknown): string;
  strategyRemoteBundleHoldScopeJson(value: unknown): unknown;
  strategyRemoteBundleHoldScopeProjection(value: unknown): readonly string[];
  strategyRemoteBundleHoldScopeAdmitJson(
    distribution: unknown, body: string, claimedScopeCid: string,
  ): unknown;
  strategyRemoteBundleHoldBindingPrepare(
    distribution: unknown, catalogIncarnation: string, coordinatorAuthority: string,
    workspaceId: string, authorityScopeCid: string, environment: string, setRevisionCid: string,
    runtimeBundleCid: string, siteKey: string, siteGeneration: number, initialRevision: number,
    attemptId: string,
  ): unknown;
  strategyRemoteBundleHoldBindingFromScope(
    scope: unknown, catalogIncarnation: string, initialRevision: number,
  ): unknown;
  strategyRemoteBundleHoldBindingIdentity(value: unknown): string;
  strategyRemoteBundleHoldBindingJson(value: unknown): unknown;
  strategyRemoteBundleHoldBindingProjection(value: unknown): readonly string[];
  strategyRemoteBundleHoldBindingMatchesScope(binding: unknown, scope: unknown): boolean;
  strategyRemoteBundleHoldBindingScope(binding: unknown): unknown;
  strategyRemoteBundleHoldBindingAdmitJson(
    distribution: unknown, body: string, claimedBindingCid: string,
  ): unknown;
  strategyRemoteBundleHoldObservationProjection(value: number): string;
  strategyRemoteBundleHoldObserve(
    catalogIncarnation: string, record: unknown, binding: unknown, exactLiveHold: boolean,
  ): number;
  strategyRemoteBundleHoldFencePrepare(
    catalogIncarnation: string, record: unknown, binding: unknown, exactLiveHold: boolean,
  ): unknown;
  strategyRemoteBundleHoldRetainPrepare(
    catalogIncarnation: string, activeBundleCid: string | undefined, record: unknown, binding: unknown,
    maxOwners: number,
  ): unknown;
  strategyRemoteBundleCustodyContextQueryPrepare(distribution: unknown, scope: unknown): unknown;
  strategyRemoteBundleCustodyRequestPrepare(
    distribution: unknown, binding: unknown, operation: string,
  ): unknown;
  strategyRemoteBundleCustodyRequestAdmitJson(body: string, claimedRequestCid: string): unknown;
  strategyRemoteBundleCustodyRequestIdentity(value: unknown): string;
  strategyRemoteBundleCustodyRequestJson(value: unknown): unknown;
  strategyRemoteBundleCustodyRequestOperation(value: unknown): string;
  strategyRemoteBundleCustodyRequestDistribution(value: unknown): unknown;
  strategyRemoteBundleCustodyRequestScope(value: unknown): unknown;
  strategyRemoteBundleCustodyRequestBinding(value: unknown): unknown;
  strategyRemoteBundleCustodyContextResponsePrepare(request: unknown, binding: unknown): unknown;
  strategyRemoteBundleCustodyResponseFieldsPrepare(
    request: unknown, observation: string, catalogPresent: boolean, catalogIncarnation: string,
    revisionPresent: boolean, recordRevision: number,
  ): unknown;
  strategyRemoteBundleCustodyResponseAdmitJson(
    request: unknown, body: string, claimedResponseCid: string,
  ): unknown;
  strategyRemoteBundleCustodyResponseIdentity(value: unknown): string;
  strategyRemoteBundleCustodyResponseJson(value: unknown): unknown;
  strategyRemoteBundleCustodyResponseKind(value: unknown): string;
  strategyRemoteBundleCustodyResponseBinding(value: unknown): unknown;
  strategyRemoteBundleCustodyResponseObservationText(value: unknown): string;
  strategyRemoteBundleCustodyResponseCatalogIncarnationText(value: unknown): string;
  strategyRemoteBundleCustodyResponseRecordRevisionText(value: unknown): string;
  strategyRemoteBundleManifestPrepareComponents(
    issuerAuthority: string, bundleName: string, revision: string, targetTriple: string,
    components: unknown, connectorRegistration: string, connectorRevision: string,
    strategyRevision: string,
  ): unknown;
  strategyRemoteBundleComponentPrepare(role: string, cid: string, bytes: bigint): unknown;
  strategyRemoteBundleManifestPrepare(
    issuerAuthority: string, bundleName: string, revision: string, targetTriple: string,
    componentCid: string, componentBytes: bigint, connectorRegistration: string,
    connectorRevision: string, strategyRevision: string,
  ): unknown;
  strategyRemoteBundleManifestIdentity(manifest: unknown): string;
  strategyRemoteBundleManifestJson(manifest: unknown): unknown;
  strategyRemoteBundleManifestAdmitJson(body: string, claimedRuntimeBundleCid: string): unknown;
  strategyRemoteBundleManifestProjection(manifest: unknown): readonly string[];
  strategyRemoteBundleManifestComponentsProjection(manifest: unknown): readonly (readonly string[])[];
  strategyRemoteBundleSignaturePreimage(manifest: unknown): unknown;
  strategyRemoteBundleSignatureEnvelopePrepare(
    manifest: unknown, keyId: string, signature: string,
  ): unknown;
  strategyRemoteBundleSignatureEnvelopeAdmit(
    version: string, keyId: string, runtimeBundleCid: string, body: string, signature: string,
  ): unknown;
  strategyRemoteBundleSignatureEnvelopeProjection(envelope: unknown): readonly string[];
  strategyRemoteBundleSignatureEnvelopeManifest(envelope: unknown): unknown;
  strategyRemoteBundleOpen(manifest: unknown): unknown;
  strategyRemoteBundleActivationPrepare(current: unknown, target: unknown): unknown;
  strategyRemoteBundleActivationTransitionCount(activation: unknown): number;
  strategyRemoteBundleActivationTransitionAt(activation: unknown, index: number): unknown;
  strategyRemoteBundleActivationCommit(activation: unknown, durable: boolean): unknown;
  strategyRemoteBundleActivatePrepare(record: unknown): unknown;
  strategyRemoteBundleDrainPrepare(record: unknown): unknown;
  strategyRemoteActiveBundleDrainPrepare(activeBundleCid: string | undefined, record: unknown): unknown;
  strategyRemoteBundleRetainPrepare(record: unknown, maxOwners: number): unknown;
  strategyRemoteActiveBundleRetainPrepare(
    activeBundleCid: string | undefined, record: unknown, maxOwners: number,
  ): unknown;
  strategyRemoteBundleReleasePrepare(record: unknown): unknown;
  strategyRemoteBundleReclaimPrepare(record: unknown): unknown;
  strategyRemoteInactiveBundleReclaimPrepare(activeBundleCid: string | undefined, record: unknown): unknown;
  strategyRemoteBundleTransitionProjection(
    transition: unknown,
  ): readonly [readonly string[], readonly string[]];
  strategyRemoteBundleTransitionKey(transition: unknown): string;
  strategyRemoteBundleTransitionCommit(transition: unknown, durable: boolean): unknown;
  strategyRemoteBundleRecordProjection(record: unknown): readonly string[];
  strategyRemoteBundleRecordRestore(
    manifest: unknown, revision: number, phase: number, owners: number,
  ): unknown;
};

const remoteBundleControls = new WeakMap<object, ReturnType<typeof createRemoteBundleControl>>();

export function remoteBundleControl(moon: CommonBundleBindings) {
  let control = remoteBundleControls.get(moon);
  if (control !== undefined) return control;
  control = createRemoteBundleControl(moon);
  remoteBundleControls.set(moon, control);
  return control;
}

function createRemoteBundleControl(moon: CommonBundleBindings) {
  return Object.freeze({
    catalogIncarnationValid: moon.strategyRemoteBundleCatalogIncarnationValid,
    prepareDistribution: (members: readonly string[]) => checked(moon.strategyRemoteBundleDistributionPrepare(members)),
    distributionIdentity: moon.strategyRemoteBundleDistributionIdentity,
    distributionJson: (value: unknown) => checked(moon.strategyRemoteBundleDistributionJson(value)) as string,
    distributionProjection: moon.strategyRemoteBundleDistributionProjection,
    distributionContains: moon.strategyRemoteBundleDistributionContains,
    admitDistributionJson: (body: string, cid: string) => checked(
      moon.strategyRemoteBundleDistributionAdmitJson(body, cid)),
    prepareHoldScope: (value: HoldScope) => checked(moon.strategyRemoteBundleHoldScopePrepare(
      value.distribution, value.coordinatorAuthority, value.workspaceId,
      value.authorityScopeCid, value.environment, value.setRevisionCid,
      value.runtimeBundleCid, value.siteKey, value.siteGeneration, value.attemptId)),
    holdScopeIdentity: moon.strategyRemoteBundleHoldScopeIdentity,
    holdScopeJson: (value: unknown) => checked(moon.strategyRemoteBundleHoldScopeJson(value)) as string,
    holdScopeProjection: moon.strategyRemoteBundleHoldScopeProjection,
    admitHoldScopeJson: (distribution: unknown, body: string, cid: string) => checked(
      moon.strategyRemoteBundleHoldScopeAdmitJson(distribution, body, cid)),
    prepareHoldBinding: (value: HoldBinding) => checked(moon.strategyRemoteBundleHoldBindingPrepare(
      value.distribution, value.catalogIncarnation, value.coordinatorAuthority,
      value.workspaceId, value.authorityScopeCid, value.environment,
      value.setRevisionCid, value.runtimeBundleCid, value.siteKey,
      value.siteGeneration, value.initialRevision, value.attemptId)),
    prepareHoldBindingFromScope: (scope: unknown, catalog: string, revision: number) => checked(
      moon.strategyRemoteBundleHoldBindingFromScope(scope, catalog, revision)),
    holdBindingIdentity: moon.strategyRemoteBundleHoldBindingIdentity,
    holdBindingJson: (value: unknown) => checked(moon.strategyRemoteBundleHoldBindingJson(value)) as string,
    holdBindingProjection: moon.strategyRemoteBundleHoldBindingProjection,
    holdBindingMatchesScope: moon.strategyRemoteBundleHoldBindingMatchesScope,
    holdBindingScope: (value: unknown) => checked(moon.strategyRemoteBundleHoldBindingScope(value)),
    admitHoldBindingJson: (distribution: unknown, body: string, cid: string) => checked(
      moon.strategyRemoteBundleHoldBindingAdmitJson(distribution, body, cid)),
    observeHold: (value: HoldObservation) => moon.strategyRemoteBundleHoldObservationProjection(
      moon.strategyRemoteBundleHoldObserve(value.catalogIncarnation,
        value.record, value.binding, value.exactLiveHold)),
    prepareHoldFence: (value: HoldObservation) => checked(moon.strategyRemoteBundleHoldFencePrepare(
      value.catalogIncarnation, value.record, value.binding, value.exactLiveHold)),
    prepareHoldRetain: (value: HoldRetention) => checked(moon.strategyRemoteBundleHoldRetainPrepare(
      value.catalogIncarnation, value.activeBundleCid, value.record,
      value.binding, value.maxOwners)),
    prepareCustodyContextQuery: (distribution: unknown, scope: unknown) => checked(
      moon.strategyRemoteBundleCustodyContextQueryPrepare(distribution, scope)),
    prepareCustodyRequest: (distribution: unknown, binding: unknown, operation: string) => checked(
      moon.strategyRemoteBundleCustodyRequestPrepare(distribution, binding, operation)),
    admitCustodyRequestJson: (body: string, cid: string) => checked(
      moon.strategyRemoteBundleCustodyRequestAdmitJson(body, cid)),
    custodyRequestIdentity: moon.strategyRemoteBundleCustodyRequestIdentity,
    custodyRequestJson: (value: unknown) => checked(moon.strategyRemoteBundleCustodyRequestJson(value)) as string,
    custodyRequestOperation: moon.strategyRemoteBundleCustodyRequestOperation,
    custodyRequestDistribution: moon.strategyRemoteBundleCustodyRequestDistribution,
    custodyRequestScope: moon.strategyRemoteBundleCustodyRequestScope,
    custodyRequestBinding: moon.strategyRemoteBundleCustodyRequestBinding,
    prepareCustodyContextResponse: (request: unknown, binding: unknown) => checked(
      moon.strategyRemoteBundleCustodyContextResponsePrepare(request, binding)),
    prepareCustodyResponse: (request: unknown, value: CustodyResponse) => {
      const catalogPresent = value.catalogIncarnation !== undefined;
      const revisionPresent = value.revision !== undefined;
      if (catalogPresent && typeof value.catalogIncarnation !== 'string' ||
          revisionPresent && (!Number.isInteger(value.revision) ||
            value.revision < 0 || value.revision > 2147483647)) {
        throw new TypeError('InvalidRemoteBundleRetentionObservation');
      }
      return checked(moon.strategyRemoteBundleCustodyResponseFieldsPrepare(
        request, value.status, catalogPresent, value.catalogIncarnation ?? '',
        revisionPresent, value.revision ?? 0));
    },
    admitCustodyResponseJson: (request: unknown, body: string, cid: string) => checked(
      moon.strategyRemoteBundleCustodyResponseAdmitJson(request, body, cid)),
    custodyResponseIdentity: moon.strategyRemoteBundleCustodyResponseIdentity,
    custodyResponseJson: (value: unknown) => checked(moon.strategyRemoteBundleCustodyResponseJson(value)) as string,
    custodyResponseKind: moon.strategyRemoteBundleCustodyResponseKind,
    custodyResponseBinding: moon.strategyRemoteBundleCustodyResponseBinding,
    custodyResponseObservation: moon.strategyRemoteBundleCustodyResponseObservationText,
    custodyResponseCatalog: (value: unknown) => moon.strategyRemoteBundleCustodyResponseCatalogIncarnationText(value) || undefined,
    custodyResponseRevision: (value: unknown) => {
      const revision = moon.strategyRemoteBundleCustodyResponseRecordRevisionText(value);
      return revision === '' ? undefined : Number(revision);
    },
    prepare: (manifest: ManifestDeclaration) => Array.isArray(manifest.components) ? checked(
      moon.strategyRemoteBundleManifestPrepareComponents(
        manifest.issuerAuthority,
        manifest.bundleName,
        manifest.revision,
        manifest.targetTriple,
        manifest.components.map((component: Component) =>
          moon.strategyRemoteBundleComponentPrepare(
            component.role,
            component.cid,
            BigInt(component.bytes),
          )),
        manifest.connectorRegistration,
        manifest.connectorRevision,
        manifest.strategyRevision,
      ),
    ) : checked(moon.strategyRemoteBundleManifestPrepare(
      manifest.issuerAuthority,
      manifest.bundleName,
      manifest.revision,
      manifest.targetTriple,
      (manifest as SingleComponentManifest).componentCid,
      BigInt((manifest as SingleComponentManifest).componentBytes),
      manifest.connectorRegistration,
      manifest.connectorRevision,
      manifest.strategyRevision,
    )),
    identity: moon.strategyRemoteBundleManifestIdentity,
    json: (manifest: unknown) => checked(moon.strategyRemoteBundleManifestJson(manifest)) as string,
    admitJson: (body: string, claimedCid: string) => checked(
      moon.strategyRemoteBundleManifestAdmitJson(body, claimedCid),
    ),
    projection: moon.strategyRemoteBundleManifestProjection,
    componentsProjection:
      moon.strategyRemoteBundleManifestComponentsProjection,
    signaturePreimage: (manifest: unknown) => checked(
      moon.strategyRemoteBundleSignaturePreimage(manifest),
    ) as Uint8Array,
    prepareSignatureEnvelope: (manifest: unknown, keyId: string, signature: string) => checked(
      moon.strategyRemoteBundleSignatureEnvelopePrepare(
        manifest,
        keyId,
        signature,
      ),
    ),
    admitSignatureEnvelope: (envelope: SignatureEnvelope) => checked(
      moon.strategyRemoteBundleSignatureEnvelopeAdmit(
        envelope.version,
        envelope.keyId,
        envelope.runtimeBundleCid,
        envelope.body,
        envelope.signature,
      ),
    ),
    signatureEnvelopeProjection:
      moon.strategyRemoteBundleSignatureEnvelopeProjection,
    signatureEnvelopeManifest:
      moon.strategyRemoteBundleSignatureEnvelopeManifest,
    open: moon.strategyRemoteBundleOpen,
    prepareActivation: (current: unknown, target: unknown) => checked(
      moon.strategyRemoteBundleActivationPrepare(current, target),
    ),
    activationTransitionCount:
      moon.strategyRemoteBundleActivationTransitionCount,
    activationTransitionAt: (activation: unknown, index: number) => checked(
      moon.strategyRemoteBundleActivationTransitionAt(activation, index),
    ),
    commitActivation: (activation: unknown, durable: boolean) => checked(
      moon.strategyRemoteBundleActivationCommit(activation, durable),
    ),
    prepareActivate: (record: unknown) => checked(
      moon.strategyRemoteBundleActivatePrepare(record),
    ),
    prepareDrain: (record: unknown) => checked(
      moon.strategyRemoteBundleDrainPrepare(record),
    ),
    prepareActiveDrain: (activeBundleCid: string | undefined, record: unknown) => checked(
      moon.strategyRemoteActiveBundleDrainPrepare(activeBundleCid, record),
    ),
    prepareRetain: (record: unknown, maxOwners: number) => checked(
      moon.strategyRemoteBundleRetainPrepare(record, maxOwners),
    ),
    prepareActiveRetain: (activeBundleCid: string | undefined, record: unknown, maxOwners: number) => checked(
      moon.strategyRemoteActiveBundleRetainPrepare(
        activeBundleCid,
        record,
        maxOwners,
      ),
    ),
    prepareRelease: (record: unknown) => checked(
      moon.strategyRemoteBundleReleasePrepare(record),
    ),
    prepareReclaim: (record: unknown) => checked(
      moon.strategyRemoteBundleReclaimPrepare(record),
    ),
    prepareInactiveReclaim: (activeBundleCid: string | undefined, record: unknown) => checked(
      moon.strategyRemoteInactiveBundleReclaimPrepare(
        activeBundleCid,
        record,
      ),
    ),
    transitionProjection: (transition: unknown) => tuplePair(
      moon.strategyRemoteBundleTransitionProjection(transition),
    ) as ReturnType<CommonBundleBindings['strategyRemoteBundleTransitionProjection']> | undefined,
    transitionKey: moon.strategyRemoteBundleTransitionKey,
    commitTransition: (transition: unknown, durable: boolean) => checked(
      moon.strategyRemoteBundleTransitionCommit(transition, durable),
    ),
    recordProjection: moon.strategyRemoteBundleRecordProjection,
    restore: (manifest: unknown, state: unknown) => {
      if (!Array.isArray(state) || state.length !== 3 ||
          state.some(value => typeof value !== 'string') ||
          state.some(value => !/^(0|[1-9][0-9]*)$/.test(value as string))) {
        throw new TypeError('Invalid Remote Bundle state');
      }
      const values = state.map(Number);
      if (values.some(value => !Number.isSafeInteger(value))) {
        throw new TypeError('Invalid Remote Bundle state');
      }
      return checked(moon.strategyRemoteBundleRecordRestore(
        manifest,
        values[0],
        values[1],
        values[2],
      ));
    },
  });
}
