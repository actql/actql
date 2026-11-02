/** Generated runtime namespaces and handles are supplied by their owners.
 * These opaque object types intentionally expose no generated MoonBit ABI.
 * Preserve the original objects; copying or constructing one grants no authority. */
export type ConnectorRuntimeOwner = object;
export type ConnectorRuntimeHandle = object;
export type ConnectorJsonValue = null | boolean | number | string |
  readonly ConnectorJsonValue[] | {readonly [key: string]: ConnectorJsonValue};
export type ConnectorJsonObject = {readonly [key: string]: ConnectorJsonValue};
export type Awaitable<T> = T | PromiseLike<T>;

export type RuntimeResult<T> =
  | Readonly<{$tag: 1; _0: T}>
  | Readonly<{$tag: 0; _0: unknown}>;
/** Unwrap the pinned runtime result, or throw its Host failure. */
export declare function checked<T>(result: RuntimeResult<T>): T;
export declare function checked(result: unknown): unknown;

export interface RowSourceDeclarationFacts {
  readonly catalog: string;
  readonly manifest_entry: string;
  readonly contracts: readonly string[];
  readonly view_bodies: readonly string[];
  readonly evidence_schemas: readonly string[];
  readonly evidence_capabilities: readonly string[];
  readonly views: readonly Readonly<{source_ref: string; resource: string}>[];
}
export declare function rowSourceCheckEnvironment(baseWire: string,
  declared: RowSourceDeclarationFacts, mappings?: readonly string[]):
  Readonly<{wire: string; evidenceCid: string}>;

export interface RowMappingSource {
  readonly target: string;
  readonly field: string;
  readonly null_behavior: 'reject' | 'write_null' | 'omit';
}
export interface RowSourceMapping {
  readonly mappingRef: string;
  readonly mappingCid: string;
  readonly body: string;
  readonly target: string;
  readonly writeFields: readonly string[];
  readonly omittable: readonly string[];
}
export declare function rowSourceMapping(moon: ConnectorRuntimeOwner,
  declaration: ConnectorRuntimeHandle, writesJson: string, resource: string,
  sources: readonly RowMappingSource[]): RowSourceMapping;

export type AuthorizationBoundary = 'preparation' | 'acquisition' |
  'activation' | 'transfer' | 'effect_commit';
export interface AuthorizationTuple {
  readonly connection: string;
  readonly resource: string;
  readonly operation: string;
}
/** The gate owns this decision's provenance; a copied decision is not admitted. */
export interface InstallationDecision {
  readonly action: string;
  readonly [key: string]: unknown;
}
export interface InstallationAuthorization {
  readonly accountConfiguration: string;
  readonly configurationCid: string | undefined;
  readonly context: Readonly<{principal: string; contextCid: string}>;
  issued(decision: unknown): boolean;
  authorize(boundary: AuthorizationBoundary, tuple: AuthorizationTuple,
    options?: Readonly<{subjectCid?: string; signal?: AbortSignal}>):
    Promise<InstallationDecision>;
  resume(boundary: AuthorizationBoundary, tuple: AuthorizationTuple,
    options?: Readonly<{subjectCid?: string; signal?: AbortSignal;
      resumption?: ConnectorRuntimeHandle; sealedSubjectCid?: string;
      setApproval?: ConnectorRuntimeHandle}>): Promise<InstallationDecision>;
  close(): boolean;
  cleanup(): boolean;
  cleanupPending(): boolean;
}
export declare function installRowSourceAuthorization(options: Readonly<{
  accountConfiguration: string; principalId: string; root: string;
  connectorRegistration: string;
}>): Promise<InstallationAuthorization>;

export type InvocationPrimitive = string | number | boolean | bigint |
  null | undefined;
export type CredentialScope = Readonly<Record<string, InvocationPrimitive>> &
  Readonly<{operation: string}>;
export interface CredentialGrant {
  readonly grant: ConnectorRuntimeHandle;
  readonly scope: CredentialScope;
}
export interface InvocationAuthorization extends CredentialGrant {
  readonly useId: string;
}
export type HttpPairs = readonly (readonly [string, string])[];
export type HttpMethod = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
export interface CredentialObservation {
  readonly useCid: string;
  readonly statusCode: number;
  readonly body: Uint8Array;
}
export interface CredentialResponse extends CredentialObservation {
  readonly accepted: boolean;
  readonly headers: HttpPairs;
}
export interface CredentialSecretScope {
  readonly grantCid: string;
  readonly principal: string;
  readonly namespaceId: string;
  readonly environment: string;
  readonly operation: string;
  readonly resourceOrigin: string;
  readonly siteKey: string;
  readonly siteGeneration: number;
  readonly connectorRegistration: string;
}
/** Only the physical credential owner calls the resolver. */
export interface CredentialSecretResolver {
  (scope: CredentialSecretScope, signal?: AbortSignal): Awaitable<string>;
  invalidate?(secret: string): void;
}
export interface CredentialContext {
  readonly control: ConnectorRuntimeOwner;
  readonly journal: ConnectorRuntimeOwner;
  readonly resolveSecret: CredentialSecretResolver;
  readonly ca?: string | Uint8Array | readonly (string | Uint8Array)[];
  readonly cert?: string | Uint8Array | readonly (string | Uint8Array)[];
  readonly key?: string | Uint8Array | readonly (string | Uint8Array)[];
  readonly now?: () => number;
}
export interface CredentialOperation {
  readonly method: HttpMethod;
  readonly path: string;
  readonly body?: string;
  readonly headers?: HttpPairs;
  readonly responseHeaders?: readonly string[];
}
export interface CredentialCallOptions extends CredentialContext,
  InvocationAuthorization {
  readonly operations: ReadonlyMap<string, CredentialOperation>;
  readonly maxRequestBytes?: number;
  readonly maxResponseBytes?: number;
  readonly returnRejectedResponse: true;
  readonly signal?: AbortSignal;
}
export type CredentialCall<Result = Promise<CredentialResponse>> =
  (options: CredentialCallOptions) => Result;
/** Assemble one physical call under the existing grant and credential owner. */
export declare function invokeScopedCredentialOperation<Result>(options:
  Readonly<{
    authorization: InvocationAuthorization;
    credential: CredentialContext;
    callResource: CredentialCall<Result>;
    operation: string;
    method: HttpMethod;
    path: string;
    query?: HttpPairs;
    headers?: HttpPairs;
    body?: string;
    responseHeaders?: readonly string[];
    maxRequestBytes?: number;
    maxResponseBytes?: number;
    signal?: AbortSignal;
  }>): Result;

export interface RowSourceCredentialProfile {
  readonly credentialPrivateKeyPath: string;
  readonly credentialAuthorityId: string;
  readonly credentialKeyId: string;
  readonly journalRoot: string;
  readonly resourceOrigin: string;
  readonly namespaceId: string;
  readonly environment: string;
  readonly siteKey: string;
  readonly siteGeneration: number;
}
export interface ReadGrantRequest {
  readonly operation: string;
  readonly decision: InstallationDecision;
  readonly resource: string;
  readonly runInvocationCid: string;
  readonly dispatchRequestCid: string;
  readonly maxUses: number;
}
export type EffectGrantRequest = Omit<ReadGrantRequest, 'maxUses'> &
  Readonly<{subjectCid: string}>;
export interface RowSourceCredentialSite {
  readonly credential: CredentialContext;
  readonly connection: string;
  readonly callResource: CredentialCall;
  admitCheckpointReadApproval(decision: InstallationDecision):
    InstallationDecision;
  issueReadGrant(request: ReadGrantRequest): CredentialGrant;
  issueEffectGrant(request: EffectGrantRequest): CredentialGrant;
  close(): void;
}
/** An injected journal retains the common journal ABI and its opaque handles. */
export interface CredentialJournalOwner {
  acceptGrant(grant: object, control: ConnectorRuntimeOwner): unknown;
  close(): void;
}
export declare function openRowSourceCredentialSite(options: Readonly<{
  profile: RowSourceCredentialProfile;
  principalId: string;
  authorization: InstallationAuthorization;
  connection: string;
  connectorRegistration: string;
  connectorRevision: string;
  runtimeBundleCid: string;
  commonMoon: ConnectorRuntimeOwner;
  resolveSecret: CredentialSecretResolver;
  ca?: CredentialContext['ca'];
  admitsApprovalTarget: (binding: unknown, resource: string) => boolean;
  responseHeaders?: readonly string[];
  now?: () => number;
  grantLifetimeMs?: number;
  openCredentialJournal?: (root: string, options: Readonly<{
    credentialAuthorities: ReadonlyMap<string, ReadonlyMap<string, object>>;
  }>) => CredentialJournalOwner;
}>): Promise<RowSourceCredentialSite>;

export interface RowSourceLimits {
  readonly maxPages: number;
  readonly maxPageBytes: number;
  readonly maxPageRows: number;
  readonly maxCaptureRows: number;
}
export interface RowPageRequest {
  readonly resource: string;
  readonly columns: readonly string[];
  readonly operation: string;
  readonly signal?: AbortSignal;
  authorizationFor(index: number): Promise<InvocationAuthorization>;
  chargePage(body: Uint8Array): ConnectorRuntimeHandle;
  consumePage(rows: readonly ConnectorJsonObject[],
    admission?: Readonly<{charge?: ConnectorRuntimeHandle}>): number;
}
export interface InstalledConnectorBinding {
  readonly connectorId: string;
  readonly bindingCid: string;
}
/** Host-private originals passed to one I/O-free installed reader preparer. */
export interface RowProviderReaderRequest extends RowPageRequest {
  readonly requestWire: string;
  readonly rowRun: Readonly<{
    acquisition: ConnectorRuntimeHandle;
    run: ConnectorRuntimeHandle;
    requestId: string;
    runInvocationCid: string;
    dispatchRequestCid: string;
  }>;
  verifyRead(): Promise<InstallationDecision>;
  consumeObservation?: (charge: ConnectorRuntimeHandle) => unknown;
}
/** Same original receiver and methods, retained until actual reader/caller
 * custody retires. Neither read nor requestStop settlement is that ACK. */
export interface InstalledRowProviderReader {
  read(): Awaitable<unknown>;
  requestStop(): Awaitable<void>;
  observe(): Readonly<{cleanupConfirmed: boolean}>;
}
/** The installed Host owns preparation and execution through this object. */
export interface InstalledRowSource extends InstallationCloseOwner {
  readonly realizationKey: 'row-source-acquired';
  readonly supportsRetainedRelationOutput: true;
  readonly connectorRegistration: string;
  readonly connectorRevision: string;
  readonly environmentWire: string;
  readonly connectorBindings: readonly InstalledConnectorBinding[];
  admitsSource(sourceRef: string): boolean;
}
export declare function createInstalledRowSource(options: Readonly<{
  moon: ConnectorRuntimeOwner;
  declaration: ConnectorRuntimeHandle;
  declared: RowSourceDeclarationFacts;
  environmentWire: string;
  connectorId: string;
  connectorRegistration: string;
  connectorRevision: string;
  site: RowSourceCredentialSite;
  authorization: InstallationAuthorization;
  readOperation: string;
  physicalTarget: (resource: string, fields: readonly string[]) => ConnectorJsonObject;
  readPages: (request: RowPageRequest) => Awaitable<unknown>;
  bindingCid: string;
  limits: RowSourceLimits;
  /** Trusted target-bound ExecutionCapacity declaration from the selected
   * Core runtime. Not a grant; the original Source Ledger must reserve it
   * before additional report allocations or page I/O. No numeric default. */
  listingReportCapacity?: ConnectorRuntimeHandle;
  /** Supplemental ordinary reader selection, mutually exclusive with listing
   * reports. DATA only: same-runtime Core planning/reservation and original
   * physical/caller retirement are independently required. No fallback. */
  providerReader?: Readonly<{
    capacity: ConnectorRuntimeHandle;
    prepare(request: RowProviderReaderRequest): InstalledRowProviderReader;
  }>;
}>): Promise<InstalledRowSource>;

export type RowEffectKind = 'create' | 'update' | 'upsert' | 'delete' | 'command';
export type RowEffectMappingKind = Exclude<RowEffectKind, 'command'>;
/** Preserve the existing value-bearing driver default. Select 'delete'
 * explicitly for its absent-value request; no placeholder value is admitted. */
export type RowEffectValueKind = Exclude<RowEffectMappingKind, 'delete'>;
export type RowEffectValue<Kind extends RowEffectKind> =
  Kind extends 'delete' ? undefined : ConnectorJsonObject;
export interface RowEffectMapping {
  readonly resource: string;
  readonly mappingRef: string;
  readonly mappingCid: string;
  readonly body: string;
}
export interface RowEffectMappingMember<Kind extends RowEffectMappingKind = RowEffectMappingKind> {
  /** A recovered member does not carry a stage index. */
  readonly stageIndex?: number;
  readonly effectId: string;
  readonly memberIndex: number;
  readonly kind: Kind;
  readonly resource: string;
  readonly mapping: RowEffectMapping & Readonly<{
    target: string; primaryIdentity: string;
    rules: readonly ConnectorJsonValue[]; approval: 'required' | 'none';
  }>;
}
export interface RowEffectCommand {
  readonly resource: string;
  readonly commandRef: string;
  readonly commandCid: string;
  readonly body: string;
}
export interface RowEffectCommandMember {
  readonly stageIndex?: number;
  readonly effectId: string;
  readonly memberIndex: number;
  readonly kind: 'command';
  readonly resource: string;
  readonly command: RowEffectCommand & Readonly<{
    target: string; permissions: readonly string[]; approval: 'required' | 'none';
  }>;
}
export type RowEffectMember<Kind extends RowEffectKind = RowEffectMappingKind> =
  Kind extends 'command' ? RowEffectCommandMember :
    RowEffectMappingMember<Extract<Kind, RowEffectMappingKind>>;
export interface RowEffectEntry<Request, Kind extends RowEffectKind = RowEffectKind> {
  readonly request: Request;
  readonly requestCid: string;
  readonly value: RowEffectValue<Kind>;
  readonly target?: ConnectorJsonValue;
}
export interface RowEffectInvocation<Request, Current,
  Kind extends RowEffectKind = RowEffectValueKind> {
  readonly member: RowEffectMember<Kind>;
  readonly request: Request;
  readonly current: Current | undefined;
  readonly authorization: InvocationAuthorization;
  readonly credential: CredentialContext;
  readonly callResource: CredentialCall;
  readonly signal?: AbortSignal;
}
export type RowEffectRequestFacts<Kind extends RowEffectKind> =
  Kind extends 'delete' ? Readonly<{value?: undefined; target: ConnectorJsonValue}> :
    Readonly<{value: ConnectorJsonObject; target?: ConnectorJsonValue}>;
export type RowEffectProjection = Readonly<{
  kind: string;
  outcome?: ConnectorJsonObject & Readonly<{state: 'applied' | 'failed'}>;
}>;
export type RowEffectFootprint = Readonly<{
  providerNamespace: string; resourceKind: string; boundaryCid: string;
}> | Readonly<{
  kind: 'exact_targets' | 'collection' | 'opaque';
  provider_boundary_cid: string; provider_namespace: string;
  resource_kind: string; resource_identity_scheme_cid: string;
  provider_object_identity_cids: readonly string[];
}>;
/** Existing capture-owned child. Preparation completion is not cleanup. */
export interface RowEffectRequestChild<Request extends object> {
  prepare(): Awaitable<Readonly<{request: Request; requestCid: string}>>;
  release(): Awaitable<boolean | void>;
  retry(): Awaitable<boolean | void>;
  status(): Readonly<{pending: boolean}>;
}
/** Original provider observations, never inferred from a missing value/404.
 * Only UPSERT has an insert-side absence; the original unique key must remain
 * enforced at physical creation. Current reads and cleanup stay with the Site. */
export type RowEffectTargetObservation<Kind extends RowEffectKind = RowEffectValueKind> =
  Readonly<{identity: ConnectorJsonValue; state?: 'present';
    versionCid: string; before: ConnectorJsonObject}> |
  (Kind extends 'upsert' ? Readonly<{identity: ConnectorJsonValue; state: 'absent';
    versionCid?: never; before?: never}> : never);
export interface RowEffectDriver<Request extends object, Current = unknown,
  Kind extends RowEffectKind = RowEffectValueKind> {
  readonly kinds: readonly Kind[];
  prepareRequest(options: Readonly<{member: RowEffectMember<Kind>;
    value: RowEffectValue<Kind>; selector?: ConnectorJsonValue;
    current: Current | undefined}>): Readonly<{request: Request; requestCid: string}>;
  /** Synchronous, I/O-free factory retained by the existing capture owner.
   * Guarded UPDATE/upsert/DELETE receives the exact row and a zero-argument read
   * supplier. CREATE and Command use the existing unindexed context without a
   * row index/current fence; CREATE has no target-read supplier. No grant is created by the type. */
  prepareRequestChild?(options: Readonly<{member: RowEffectMember<Kind>;
    value: RowEffectValue<Kind>; selector?: ConnectorJsonValue;
    current: Current | undefined; signal?: AbortSignal;
  } & ({rowIndex: number;
    authorizationForRow: () => Promise<InvocationAuthorization>;
    /** Existing selected-preparation fence; absence is not a new current proof. */
    assertCurrent?: () => void;
  } | {rowIndex?: undefined;
    authorizationForRow?: (index: number) => Promise<InvocationAuthorization>;
    assertCurrent?: undefined;
  })>): RowEffectRequestChild<Request>;
  requestFacts(request: Request): RowEffectRequestFacts<Kind>;
  writeOperation(member: RowEffectMember<Kind>): string;
  send(options: RowEffectInvocation<Request, Current, Kind>): Awaitable<Readonly<{
    observation: CredentialObservation; headers?: HttpPairs}>>;
  project(options: Readonly<{member: RowEffectMember<Kind>; memberIndex: number;
    rowIndex: number; preview: ConnectorRuntimeHandle; request: Request;
    current: Current | undefined; observation: CredentialObservation;
    headers: HttpPairs | undefined}>): RowEffectProjection;
  footprint(options: Readonly<{member: RowEffectMember<Kind>;
    entries: readonly RowEffectEntry<Request, Kind>[]}>) : RowEffectFootprint;
  describe?(options: Readonly<{member: RowEffectMember<Kind>; runInvocationCid: string;
    dispatchRequestCid: string; label: string;
    approval?: InstallationDecision; signal?: AbortSignal}>): Awaitable<Current>;
  recheckRequests?(options: Readonly<{member: RowEffectMember<Kind>;
    entries: readonly RowEffectEntry<Request, Kind>[];
    current: Current | undefined}>): void;
  issueCapability?(options: Readonly<{member: RowEffectMember<Kind>;
    entries: readonly RowEffectEntry<Request, Kind>[]; current: Current | undefined;
    runInvocationCid: string; dispatchRequestCid: string}>): Readonly<{
      identity: string; route: 'single_serial'; binding: Readonly<{
        connector_registration: string; connector_revision: string;
        runtime_bundle_cid: string}>}>;
  readonly check?: Readonly<{resource: string; operation: string}>;
  checkRequest?(options: Omit<RowEffectInvocation<Request, Current, Kind>, 'current'>):
    Awaitable<unknown>;
  readonly targetRead?: Readonly<{operation: string}>;
  observeTargets?(options: Readonly<{member: RowEffectMember<Kind>;
    entries: readonly RowEffectEntry<Request, Kind>[]; current: Current | undefined;
    authorizationForRow: (index: number) => Promise<InvocationAuthorization>;
    signal?: AbortSignal}>): Awaitable<readonly RowEffectTargetObservation<Kind>[]>;
  admitTargetReadApproval?(options: Readonly<{member: RowEffectMember<Kind>;
    decision: InstallationDecision}>): InstallationDecision;
  recoveryEntry?(options: Readonly<{member: RowEffectMember<Kind>;
    current: Current | undefined}>): Readonly<{
      kind: string; observationCid: string; wire: string}>;
  recoverRequests?(options: Readonly<{durable: unknown; recorded: unknown;
    previewWire: string; body: ConnectorJsonObject}>): Readonly<{
      requests: readonly (readonly Request[])[];
      currents?: readonly (Current | undefined)[]}>;
  /** Rebuild only these original global members from the unchanged whole Preview.
   * Result arrays follow memberIndexes order; this does not restore authority. */
  recoverMemberRequests?(options: Readonly<{durable: unknown; recorded: unknown;
    previewWire: string; body: ConnectorJsonObject;
    memberIndexes: readonly number[]}>): Readonly<{
      requests: readonly (readonly Request[])[];
      currents?: readonly (Current | undefined)[]}>;
  requestCid?(request: Request): string;
}
export interface RowEffectLimits {
  readonly maxMembers: number;
  readonly maxRows: number;
  readonly maxWork: number;
  readonly maxFrontierWork: number;
  readonly maxPinnedResults: number;
  readonly maxFields: number;
  readonly planWork: number;
  readonly preview: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
  readonly key: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
  readonly locator: RowEffectLimits['key'];
  readonly body: RowEffectLimits['key'];
}
/** The Host retains the returned preparation, ledger and recovery owner. */
export interface InstalledRowEffect extends InstallationCloseOwner {
  readonly environmentWire: string;
  readonly connectorBindings: readonly InstalledConnectorBinding[];
  readonly connectorRegistration: string;
  readonly connectorRevision: string;
  readonly connection: string;
  readonly mappings: readonly Readonly<{
    resource: string; target: string; mappingRef: string; mappingCid: string}>[];
}
export declare function createInstalledRowEffect<Request extends object,
  Current = unknown, Kind extends RowEffectKind = RowEffectValueKind>(options: Readonly<{
    moon: ConnectorRuntimeOwner;
    mappings: readonly RowEffectMapping[];
    commands?: readonly RowEffectCommand[];
    environmentWire: string;
    connectorId: string;
    connectorRegistration: string;
    connectorRevision: string;
    connection: string;
    site: RowSourceCredentialSite;
    authorization: InstallationAuthorization;
    runtimeBundleCid: string;
    bindingCid: string;
    driver: RowEffectDriver<Request, Current, Kind>;
    ledgerRoot: string;
    /** The exact generated installation-table entry, never a reconstructed copy. */
    installation?: object;
    continuationBinding?: string;
    /** Nested limit objects replace their defaults as complete objects. */
    limits?: Partial<RowEffectLimits>;
  }>): Promise<InstalledRowEffect>;

export interface InstallationCleanupStatus {
  readonly pending: boolean;
  readonly owners: readonly string[];
  readonly errors: readonly unknown[];
}
export interface InstallationFailure extends Error {
  readonly code: 'InstalledHostInitializationFailed';
  readonly primaryFailure: unknown;
  readonly cleanupPending: boolean;
  readonly cleanupErrors: readonly unknown[];
  readonly cleanupHandle: Readonly<{
    status(): InstallationCleanupStatus;
    retry(): Promise<InstallationCleanupStatus>;
  }>;
}
export interface InstallationCloseOwner {
  close(): Awaitable<unknown>;
}
/** Retain and drain the original failed installation's resources for retry. */
export declare function retainInstalledHostInitializationFailure(cause: unknown,
  owners: Readonly<{
    journal?: InstallationCloseOwner;
    store?: InstallationCloseOwner;
    checkpoints?: InstallationCloseOwner & {stop(): Awaitable<unknown>};
    dispatchOwner?: {drain(): Awaitable<unknown>};
    sourceProfile?: InstallationCloseOwner;
    installedEffect?: InstallationCloseOwner;
  }>): Promise<InstallationFailure>;

/** Build-generated DATA from one author definition. Common admits the typed
 * fields; this interface does not issue a declaration or resource authority. */
export interface RestSourceInstallationDefinition {
  readonly authoredViewsWire: string;
  readonly registration: string;
  readonly revision: string;
  readonly profileVersion: string;
  readonly origin: string;
  readonly auth: Readonly<{kind: 'bearer'}>;
  readonly sources: readonly Readonly<{
    resource: string;
    resource_kind: string;
    fields: readonly ConnectorJsonObject[];
    read: Readonly<{method: 'GET'; path: string}>;
    pagination: Readonly<{kind: 'none'; items: readonly string[]}> |
      Readonly<{kind: 'cursor'; items: readonly string[]; next: readonly string[]; parameter: string}>;
    limits: Readonly<{maxPageRows: number; maxPageBytes: number; maxPages: number;
      maxRows: number; maxNodes: number; maxDepth: number; maxCursorBytes: number}>;
  }>[];
}
export interface RestSourceProfile {
  readonly version: string;
  readonly connectorId: string;
  readonly siteProfilePath: string;
  readonly accountConfigurationWire: string;
}
export interface RestSourcePageData {
  readonly rowsWire: string;
  readonly rowCount: number;
  readonly nextCursor?: string;
}
/** Pure synchronous provider DATA adaptation, never a reader or an issuer.
 * Return a plain own-data record (Object.prototype or null prototype) with
 * rowsWire and optional nextCursor only. Proxies and accessors are rejected. */
export type RestSourceTransform = (page: Readonly<RestSourcePageData>,
  context: Readonly<{resource: string; columns: readonly string[]}>) =>
  Readonly<{rowsWire: string; nextCursor?: string}>;
/** The installed Host supplies its original initialization and services to
 * load/publication. Connector authors supply only definition and transform. */
export declare function createInstalledRestSource(definition: RestSourceInstallationDefinition,
  options?: Readonly<{decodePage?: RestSourceTransform}>): Readonly<{
    checkProfile(profile: unknown): Readonly<RestSourceProfile>;
    identityParts(profile: object, providerProfile: RestSourceProfile,
      readJson?: (path: string) => Promise<unknown>, installation?: object,
      context?: object): Promise<readonly unknown[]>;
    publish(profile: RestSourceProfile, options: object): Promise<object>;
    load(profile: RestSourceProfile, options: object): Promise<InstalledRowSource>;
  }>;
