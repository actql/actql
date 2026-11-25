import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type CommonObject = Extract<SynchronousRuntimeData, object>;
type LimitArguments = [maxBytes: number, maxNodes: number, maxDepth: number, maxTextUnits: number];
type ReferenceLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxTextUnits: number}>;
type CapturedBytes = Readonly<{sizeBytes: number; mediaType: string; contentCid: string}>;
type CapturedWire = Readonly<{
  media_type: string;
  metadata: Readonly<{effective_data_policy_cid: string}>;
}>;
type ResolveOriginal = (mediaType: string | undefined, wire: string) => CommonObject | undefined;
type ValidateResource = (resourceKind: string, wire: string) => boolean;
type ValidateContent = (mediaType: string | undefined, wire: string) => boolean;
type AuthorizeReference = (wire: string) => boolean;

type CapturePublicationBindings = Readonly<{
  checkedClientRunCapturedContentCandidate(
    compiled: unknown, definition: unknown, acquisition: unknown, request: unknown,
    bindingWire: string, mediaType: string, contentCid: string, sizeBytes: number, limits: LimitArguments,
  ): CommonObject;
  checkedClientStoredRunCapturedContentCandidate(
    compiled: unknown, definition: unknown, acquisition: unknown, originalWire: string, bindingWire: string,
    limits: LimitArguments,
  ): CommonObject;
  checkedRecoveredSourceContentCandidate(
    original: unknown, prepared: unknown, request: unknown, originalWire: string, bindingWire: string,
    limits: LimitArguments,
  ): CommonObject;
}>;

// Common owns the checked candidate, reference issuer, and workspace reservation.
type CommonContentCaptureBindings = {
  clientProgramCapturedContentCandidate(
    acquisition: unknown, request: unknown, bindingWire: string, mediaType: string, contentCid: string,
    sizeBytes: number, ...limits: LimitArguments
  ): unknown;
  clientProgramCapturedContentCid(candidate: CommonObject): string;
  clientProgramCapturedContentHoldingCid(candidate: CommonObject): string | undefined;
  clientProgramCapturedContentReissuer(resolve: ResolveOriginal): CommonObject;
  clientProgramCapturedContentStorage(candidate: CommonObject): readonly [string, string, string, number];
  clientProgramCapturedContentWire(candidate: CommonObject): string;
  clientProgramGrowCapturedContentInventoryWorkspace(
    ledger: unknown, reservation: unknown, maxBytes: number, inventoryCount: number, inventoryWireUnits: bigint,
  ): unknown;
  clientProgramGrowCapturedContentWorkspace(
    ledger: unknown, reservation: unknown, maxBytes: number, inventoryCount: number,
  ): unknown;
  clientProgramIssueCapturedContent(candidate: CommonObject, issuer: CommonObject, ...limits: LimitArguments): unknown;
  clientProgramReleaseCapturedContentWorkspace(ledger: unknown, reservation: unknown): unknown;
  clientProgramReserveCapturedContentWorkspace(ledger: unknown, maxBytes: number, inventoryCount: number): unknown;
  clientProgramRowReferenceIssuer(
    validateResource: ValidateResource, validateContent: ValidateContent, authorize: AuthorizeReference,
  ): CommonObject;
};

// Captured candidates are sealed by the checked keyed Source owner. This
// transport facade holds no acquisition, byte or cleanup state machine.
export function contentCaptureControl(moon: CommonContentCaptureBindings, publications: CapturePublicationBindings) {
  const candidates = new WeakSet<CommonObject>();
  const issuers = new WeakSet<CommonObject>();
  const args = (limits: ReferenceLimits) => {
    const fields = ['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'] as const;
    if (!fields.every(key => Number.isInteger(limits?.[key]) &&
        limits[key] > 0 && limits[key] <= 2147483647)) {
      throw new TypeError('Invalid captured Content reference limits');
    }
    return fields.map(key => limits[key]) as LimitArguments;
  };
  const own = (set: WeakSet<CommonObject>, value: CommonObject) => {
    if (!set.has(value)) throw new TypeError('Foreign captured Content candidate');
    return value;
  };
  return Object.freeze({
    candidate(
      acquisition: unknown, request: unknown, binding: unknown, bytes: CapturedBytes, limits: ReferenceLimits,
    ) {
      if (!Number.isInteger(bytes?.sizeBytes) || bytes.sizeBytes < 0 ||
          bytes.sizeBytes > 2147483647) {
        throw new TypeError('Invalid captured Content byte facts');
      }
      const value = checked(moon.clientProgramCapturedContentCandidate(
        acquisition, request, JSON.stringify(binding), bytes.mediaType,
        bytes.contentCid, bytes.sizeBytes, ...args(limits))) as CommonObject;
      candidates.add(value);
      return value;
    },
    candidateForRun(
      compiled: unknown, definition: unknown, acquisition: unknown, request: unknown, binding: unknown,
      bytes: CapturedBytes, limits: ReferenceLimits,
    ) {
      if (!Number.isInteger(bytes?.sizeBytes) || bytes.sizeBytes < 0 ||
          bytes.sizeBytes > 2147483647) throw new TypeError('Invalid captured Content byte facts');
      const value = publications.checkedClientRunCapturedContentCandidate(compiled,
        definition, acquisition, request, JSON.stringify(binding), bytes.mediaType,
        bytes.contentCid, bytes.sizeBytes, args(limits));
      candidates.add(value);
      return value;
    },
    recoveryCandidateForRun(
      compiled: unknown, definition: unknown, acquisition: unknown, originalWire: string, binding: unknown, limits: ReferenceLimits,
    ) {
      const value = publications.checkedClientStoredRunCapturedContentCandidate(
        compiled, definition, acquisition, originalWire, JSON.stringify(binding), args(limits));
      candidates.add(value);
      return value;
    },
    recoveryCandidateForEffectOriginal(
      original: unknown, prepared: unknown, request: unknown, originalWire: string, bindingWire: string, limits: ReferenceLimits,
    ) {
      if (typeof bindingWire !== 'string') throw new TypeError('Invalid recovered Source Content binding wire');
      const value = publications.checkedRecoveredSourceContentCandidate(original,
        prepared, request, originalWire, bindingWire, args(limits));
      candidates.add(value);
      return value;
    },
    holdingCid(candidate: CommonObject) {
      const value = moon.clientProgramCapturedContentHoldingCid(own(candidates, candidate));
      if (value === undefined) throw new TypeError('Captured Content requires original Run custody');
      return value;
    },
    reserveWorkspace(ledger: unknown, maxBytes: number, inventoryCount = 0) {
      return checked(moon.clientProgramReserveCapturedContentWorkspace(ledger, maxBytes, inventoryCount)) as CommonObject;
    },
    growWorkspace(
      ledger: unknown, reservation: unknown, maxBytes: number, inventoryCount: number, inventoryWireUnits?: bigint,
    ) {
      if (inventoryWireUnits === undefined) {
        return checked(moon.clientProgramGrowCapturedContentWorkspace(ledger, reservation, maxBytes, inventoryCount)) as undefined;
      }
      return checked(moon.clientProgramGrowCapturedContentInventoryWorkspace(
        ledger, reservation, maxBytes, inventoryCount, inventoryWireUnits)) as undefined;
    },
    releaseWorkspace(ledger: unknown, reservation: unknown) {
      return checked(moon.clientProgramReleaseCapturedContentWorkspace(ledger, reservation)) as undefined;
    },
    reissuer(resolve: ResolveOriginal) {
      if (typeof resolve !== 'function') throw new TypeError('Invalid captured Content resolver');
      return moon.clientProgramCapturedContentReissuer(resolve);
    },
    inspect(candidate: CommonObject) {
      own(candidates, candidate);
      const storage = moon.clientProgramCapturedContentStorage(candidate);
      const wire = moon.clientProgramCapturedContentWire(candidate);
      const body = JSON.parse(wire) as CapturedWire;
      return Object.freeze({wire,
        identity: moon.clientProgramCapturedContentCid(candidate),
        storeCid: runtimeField(storage, 0) as string, workspaceScopeCid: runtimeField(storage, 1) as string,
        contentCid: runtimeField(storage, 2) as string, sizeBytes: runtimeField(storage, 3) as number,
        mediaType: body.media_type,
        effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
    },
    issuer(validate: ValidateContent, authorize: AuthorizeReference) {
      if (typeof validate !== 'function' || typeof authorize !== 'function') {
        throw new TypeError('Invalid captured Content issuer callbacks');
      }
      const issuer = moon.clientProgramRowReferenceIssuer(() => false, validate, authorize);
      issuers.add(issuer);
      return issuer;
    },
    issue(candidate: CommonObject, issuer: CommonObject, limits: ReferenceLimits) {
      return checked(moon.clientProgramIssueCapturedContent(
        own(candidates, candidate), own(issuers, issuer), ...args(limits))) as CommonObject;
    },
  });
}
