import {originalLocalContentStoragePolicy} from './local-account-config.mjs';
import {prepareRecoveredCommandContent} from './recovered-command-content.mjs';
import {prepareRecoveredSourceCommandContent} from './recovered-source-command-content.mjs';

type Generated = Parameters<typeof prepareRecoveredCommandContent>[0];
type Source = Parameters<typeof prepareRecoveredSourceCommandContent>[0];
type Role = Parameters<Source['sourceConstruction']>[4] | 'metadata' | 'classify';
type Managed = Readonly<{
  runtime: object;
  prepared: unknown;
  value?: unknown;
  request?: unknown;
  closed?: boolean;
  controlConstruction?<Args extends unknown[], Result>(receiver: unknown,
    method: (...args: Args) => Result, args: Args, capacity: unknown): Result;
}>;
type RecoveryOptions = Omit<Generated, 'moon' | 'publications' | 'control' | 'ownerPrincipal' |
  'storeAuthorityCid' | 'authorityScopeCid' | 'now' | 'authorize' | 'installedBinding' |
  'referenceLimits' | 'compiled' | 'recoveryResources' | 'store'> & Readonly<{
  compiled?: unknown;
  allowed?: unknown;
  managedContext?: Managed;
  store: Generated['store'] & Source['store'];
  recoveryResources?: Generated['recoveryResources'] | Source['recoveryResources'];
}>;
type Publications = Generated['publications'] & Source['publications'] & Readonly<{
  recoveredSourceContentConstructionCapacity(wire: string, bindingWire: string,
    limits: Source['referenceLimits'], role: Role): unknown;
  recoveredContentIssuerKind(wire: string, limits: Source['referenceLimits']): unknown;
  adoptCheckedClientEffectSerializationRun(allowed: unknown, definition: Generated['definition']): unknown;
  installedEffectKeyedOriginal(managed: Managed, prepared: unknown): unknown;
  effectKeyedOriginalSourceEvidenceFacts(original: unknown, prepared: unknown,
    request: unknown): readonly [string, string, string, string, string, string];
}>;
type RecoveryPorts = Readonly<{
  moon: object;
  core: Readonly<{contentCaptureControl: Source['control']}>;
  publications: Publications;
  control: Generated['control'];
  ownerPrincipal: string;
  storeAuthorityCid: string;
  authorityScopeCid: string;
  namespaceId: string;
  now: Generated['now'];
  authorize: Generated['authorize'];
  installedBinding: Generated['installedBinding'];
  referenceLimits: Generated['referenceLimits'];
}>;
type ValidatedReference = Readonly<{metadata: Readonly<{
  content_store_id: string;
  expires_at: string;
  issuer_evidence: Readonly<{content_store_cid: string; workspace_scope_cid: string; capture_authority_cid: string}>;
}>}>;

export function createContentRecoveryDispatch({moon, core, publications, control,
  ownerPrincipal, storeAuthorityCid, authorityScopeCid, namespaceId, now, authorize,
  installedBinding, referenceLimits}: RecoveryPorts) {
  return (options: RecoveryOptions) => {
    const referenceWire = options.referenceWire, definition = options.definition;
    const generated = (compiled: unknown) => prepareRecoveredCommandContent({
      ...options, referenceWire, definition, compiled, moon, publications, control, ownerPrincipal, storeAuthorityCid,
      authorityScopeCid, now, authorize, installedBinding, referenceLimits} as Generated);
    // Explicit compiled callers retain the existing generated-only entrance.
    // A restored mixed Program selects each actual Command Reference family;
    // absence of a serialization component is never a fallback signal.
    if (options.compiled !== undefined) return generated(options.compiled);
    const managed = options.managedContext, prepared = options.prepared;
    const request = managed?.request, construct = managed?.controlConstruction;
    const assertCurrent = options.assertCurrent, signal = options.signal;
    if (managed?.runtime !== moon || managed.prepared !== prepared || managed.value === undefined ||
        request === undefined || typeof construct !== 'function' ||
        typeof assertCurrent !== 'function') {
      throw new TypeError('Foreign recovered Effect Source original');
    }
    const current = () => {
      signal?.throwIfAborted();
      const value = Reflect.apply(assertCurrent, options, []);
      if (value !== undefined) {
        if (value instanceof Promise) void value.catch(() => {});
        throw new TypeError('InvalidRecoveredContentCurrentFence');
      }
      if (managed.closed || managed.runtime !== moon || managed.prepared !== prepared ||
          managed.request !== request || managed.controlConstruction !== construct) {
        throw new TypeError('Foreign recovered Effect Source original');
      }
    };
    const sourceConstruction = <Args extends unknown[], Result>(receiver: unknown, method: (...args: Args) => Result,
      args: Args, bindingWire = '', role: Role = 'metadata'): Result => {
      current();
      const quote = publications.recoveredSourceContentConstructionCapacity(
        referenceWire, bindingWire, referenceLimits, role);
      const result = Reflect.apply(construct, undefined, [receiver, method, args, quote]);
      current();
      return result;
    };
    const kind = sourceConstruction(publications, publications.recoveredContentIssuerKind,
      [referenceWire, referenceLimits], '', 'classify');
    if (kind === 'content_derivation') {
      return generated(publications.adoptCheckedClientEffectSerializationRun(
        options.allowed, definition));
    }
    if (kind !== 'connector_capture') throw new TypeError('InvalidRecoveredContentIssuer');
    // The caller's SAME capture Read funds full wire/row admission. This native
    // constructor additionally retains the returned Source carriers until its
    // original control retires; it never spans a Store await.
    return sourceConstruction(undefined, () => {
      const sourceOriginal = publications.installedEffectKeyedOriginal(managed, prepared);
      const facts = publications.effectKeyedOriginalSourceEvidenceFacts(
        sourceOriginal, prepared, request);
      const expiresAt = (JSON.parse(definition.wire) as {valid_until: string}).valid_until;
      // Core just validated this exact immutable full Reference. Borrow only
      // its original capture authority; policy/classification come from the
      // independent checked Source occurrence, not the saved envelope.
      const reference = JSON.parse(referenceWire) as ValidatedReference;
      if (reference.metadata.content_store_id !== namespaceId ||
          reference.metadata.issuer_evidence.content_store_cid !== storeAuthorityCid ||
          reference.metadata.issuer_evidence.workspace_scope_cid !== authorityScopeCid ||
          reference.metadata.expires_at !== expiresAt) {
        throw new TypeError('RecoveredSourceContentBindingMismatch');
      }
      const policy = originalLocalContentStoragePolicy({storeAuthorityCid,
        authorityScopeCid, runDefinitionCid: definition.identity, expiresAt});
      const binding = {content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
        workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace',
        retention_class: 'local-content', expires_at: expiresAt,
        availability_evidence_cid: policy.availabilityEvidenceCid,
        effective_data_policy_cid: facts[3], data_classification: facts[4],
        issuer_contract_cid: policy.issuerContractCid,
        capture_authority_cid: reference.metadata.issuer_evidence.capture_authority_cid};
      const child = prepareRecoveredSourceCommandContent({...options, referenceWire, definition, sourceOriginal, request,
        binding, sourcePolicyCid: facts[3], sourceConstruction, assertCurrent: current, signal, moon, publications,
        control: core.contentCaptureControl, ownerPrincipal, storeAuthorityCid,
        authorityScopeCid, now, authorize, referenceLimits} as Source);
      current();
      return child;
    }, []);
  };
}
