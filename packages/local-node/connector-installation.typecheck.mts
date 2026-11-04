import {
  checked, createInstalledRestSource, createInstalledRowEffect, createInstalledRowSource,
  installRowSourceAuthorization, invokeScopedCredentialOperation,
  openRowSourceCredentialSite, retainInstalledHostInitializationFailure,
  rowSourceCheckEnvironment, rowSourceMapping,
} from '@actql/local-node/connector-installation';
import type {
  ConnectorJsonObject, ConnectorRuntimeHandle, ConnectorRuntimeOwner,
  CredentialResponse, RowSourceCredentialProfile, RowSourceDeclarationFacts,
  InstalledRowProviderReader, RowProviderReaderRequest,
  RowEffectDriver, RowEffectRequestChild,
  RestSourceInstallationDefinition, RestSourceTransform, InstallationCloseOwner,
} from '@actql/local-node/connector-installation';
import type {HostRequestValuePolicyVerifier} from '@actql/local-node';

const verifyPolicy: HostRequestValuePolicyVerifier = (subject, {signal}) => {
  signal?.throwIfAborted();
  const origin = subject.origins.selector;
  if (typeof origin === 'object') {
    const parameter: string = origin.parameter;
    void parameter;
  }
  // @ts-expect-error Trusted subjects are immutable, not caller assertions.
  subject.request.selector = 'replacement';
  return undefined;
};
// @ts-expect-error A classification object is not an admitted policy CID.
const fabricatedPolicy: HostRequestValuePolicyVerifier = () => ({classification: 'public'});
void [verifyPolicy, fabricatedPolicy];

// These are supplied by the installed Host and declaration owner, not minted
// by this compile-only consumer. The generated runtime ABI stays opaque.
declare const commonMoon: ConnectorRuntimeOwner;
declare const declaration: ConnectorRuntimeHandle;
declare const declared: RowSourceDeclarationFacts;
declare const profile: RowSourceCredentialProfile;
declare const baseEnvironmentWire: string;
declare const accountConfiguration: string;
declare const runtimeBundleCid: string;
declare const bindingCid: string;
declare const writesJson: string;
declare const providerReaderCapacity: ConnectorRuntimeHandle;

const originalReaderPreparer = (request: RowProviderReaderRequest): InstalledRowProviderReader => ({
  async read() {await request.verifyRead(); return request.rowRun.acquisition;},
  requestStop() {},
  observe() {return {cleanupConfirmed: false};},
});
type SourceOptions = Parameters<typeof createInstalledRowSource>[0];
const selectedReader: NonNullable<SourceOptions['providerReader']> = {
  capacity: providerReaderCapacity, prepare: originalReaderPreparer,
};
const unavailableAsyncReader: NonNullable<SourceOptions['providerReader']> = {
  capacity: providerReaderCapacity,
  // @ts-expect-error Reader preparation is synchronous and cannot hide I/O.
  prepare: async request => originalReaderPreparer(request),
};
// @ts-expect-error A reader factory cannot omit its original capacity declaration.
const unboundedReader: NonNullable<SourceOptions['providerReader']> = {prepare: originalReaderPreparer};
void [selectedReader, unavailableAsyncReader, unboundedReader];

const authorization = await installRowSourceAuthorization({
  accountConfiguration, principalId: 'operator', root: '/host',
  connectorRegistration: 'example-rows',
});
const site = await openRowSourceCredentialSite({
  profile, principalId: 'operator', authorization, connection: 'example',
  connectorRegistration: 'example-rows', connectorRevision: 'example-revision',
  runtimeBundleCid, commonMoon,
  resolveSecret: async (_scope, _signal) => 'fixture-secret',
  admitsApprovalTarget: binding => binding !== null && typeof binding === 'object',
});
const mapping = rowSourceMapping(commonMoon, declaration, writesJson, 'items',
  [{target: 'name', field: 'name', null_behavior: 'reject'}]);
const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared,
  [mapping.body]);

const source = await createInstalledRowSource({
  moon: commonMoon, declaration, declared, environmentWire: environment.wire,
  connectorId: 'example', connectorRegistration: 'example-rows',
  connectorRevision: 'example-revision', site, authorization, bindingCid,
  readOperation: 'items.read',
  physicalTarget: (resource, fields) => ({resource, fields}),
  limits: {maxPages: 2, maxPageBytes: 4096, maxPageRows: 10, maxCaptureRows: 20},
  async readPages({authorizationFor, chargePage, consumePage, operation, signal}) {
    const response: CredentialResponse = await invokeScopedCredentialOperation({
      authorization: await authorizationFor(0), credential: site.credential,
      callResource: site.callResource, operation, method: 'GET', path: '/items',
      query: [['limit', '10']], responseHeaders: [], signal,
    });
    const charge = chargePage(response.body);
    const count: number = consumePage([{name: 'sample'}], {charge});
    return count;
  },
});

type Request = Readonly<{value: ConnectorJsonObject}>;
const effect = await createInstalledRowEffect<Request>({
  moon: commonMoon, mappings: [{resource: 'items', ...mapping}],
  environmentWire: environment.wire, connectorId: 'example',
  connectorRegistration: 'example-rows', connectorRevision: 'example-revision',
  connection: site.connection, site, authorization, runtimeBundleCid,
  bindingCid, ledgerRoot: '/host/ledger',
  driver: {
    kinds: ['create'],
    prepareRequest: ({value}) => ({request: {value}, requestCid: bindingCid}),
    requestFacts: request => ({value: request.value}),
    writeOperation: () => 'items.create',
    async send({request, authorization, credential, callResource, signal}) {
      const response = await invokeScopedCredentialOperation({
        authorization, credential, callResource, operation: 'items.create',
        method: 'POST', path: '/items', body: JSON.stringify(request.value), signal,
      });
      return {observation: response, headers: response.headers};
    },
    project: () => ({kind: 'unclassified-response'}),
    footprint: () => ({providerNamespace: 'example-rows', resourceKind: 'items',
      boundaryCid: bindingCid}),
  },
});

const failure = await retainInstalledHostInitializationFailure(new Error('fixture'),
  {sourceProfile: source, installedEffect: effect});
const pending: boolean = (await failure.cleanupHandle.retry()).pending;
const count: number = checked({$tag: 1, _0: 2});
// @ts-expect-error checked preserves the runtime result's value type.
const text: string = checked({$tag: 1, _0: 2});
// @ts-expect-error Generated runtime methods are not inferred by this facade.
commonMoon.fabricatedRuntimeMethod();
// @ts-expect-error Mapping null behavior is an existing finite contract.
rowSourceMapping(commonMoon, declaration, writesJson, 'items', [{target: 'name', field: 'name', null_behavior: 'invented'}]);
// @ts-expect-error Physical invocation always requires an existing authorization.
invokeScopedCredentialOperation({credential: site.credential, callResource: site.callResource, operation: 'items.read', method: 'GET', path: '/items'});
void [pending, count, text];

declare const originalDriver: RowEffectDriver<Request>;
const guardedDriver: RowEffectDriver<Request> = {
  ...originalDriver, kinds: ['update'],
  prepareRequestChild(context): RowEffectRequestChild<Request> {
    if (context.rowIndex === undefined) throw new Error('GuardedContextRequired');
    const row: number = context.rowIndex;
    // @ts-expect-error The original row cannot be replaced by the child.
    context.rowIndex = row + 1;
    return {
      async prepare() {
        await context.authorizationForRow();
        // @ts-expect-error Read authorization is closed over the original row.
        await context.authorizationForRow(row + 1);
        return {request: {value: context.value}, requestCid: bindingCid};
      },
      release: () => false,
      retry: async () => undefined,
      status: () => ({pending: true}),
    };
  },
};
const asynchronousFactory: RowEffectDriver<Request> = {...guardedDriver,
  // @ts-expect-error The existing capture must own the child before first await.
  prepareRequestChild: async context => guardedDriver.prepareRequestChild!(context),
};
const missingCleanup: RowEffectDriver<Request> = {...guardedDriver,
  // @ts-expect-error A request Promise alone cannot replace original cleanup custody.
  prepareRequestChild: context => ({prepare: () => ({request: {value: context.value}, requestCid: bindingCid}),
    status: () => ({pending: true})}),
};
void [guardedDriver, asynchronousFactory, missingCleanup];

// These are the two contexts actually passed by the existing capture caller.
// Command has neither a synthetic row index nor a fabricated read grant.
type ChildContext = Parameters<NonNullable<RowEffectDriver<Request>['prepareRequestChild']>>[0];
declare const childMember: ChildContext['member'];
declare const indexedRead: (index: number) => Promise<import('@actql/local-node/connector-installation').InvocationAuthorization>;
const commandWithoutRead: ChildContext = {
  member: childMember, value: {}, current: undefined,
};
const commandWithRead: ChildContext = {...commandWithoutRead, authorizationForRow: indexedRead};
if (commandWithRead.rowIndex === undefined) {
  // @ts-expect-error The optional Command callback cannot be used as a required grant.
  commandWithRead.authorizationForRow(0);
  commandWithRead.authorizationForRow?.(0);
  // @ts-expect-error The original indexed Command callback still requires its index.
  commandWithRead.authorizationForRow?.();
}
// @ts-expect-error A guarded row cannot omit its original read supplier.
const missingGuardedRead: ChildContext = {
  member: childMember, value: {}, current: undefined, rowIndex: 0,
};
void [commandWithoutRead, commandWithRead, missingGuardedRead];

// DELETE has no proposed value in the actual installed Row Effect. Its
// original target still comes from the checked row, not a placeholder body.
type DeleteRequest = Readonly<{target: import('@actql/local-node/connector-installation').ConnectorJsonValue}>;
type DeleteDriver = RowEffectDriver<DeleteRequest, unknown, 'delete'>;
declare const originalDeleteDriver: DeleteDriver;
const deleteDriver: DeleteDriver = {
  ...originalDeleteDriver, kinds: ['delete'],
  prepareRequest({value, selector}) {
    const absent: undefined = value;
    if (selector === undefined) throw new Error('OriginalDeleteTargetRequired');
    void absent;
    return {request: {target: selector}, requestCid: bindingCid};
  },
  requestFacts: request => ({target: request.target}),
  prepareRequestChild(context) {
    if (context.rowIndex === undefined) throw new Error('OriginalDeleteReadRequired');
    const absent: undefined = context.value;
    void absent;
    return {
      async prepare() {
        await context.authorizationForRow();
        return deleteDriver.prepareRequest(context);
      },
      release: () => false, retry: async () => undefined,
      status: () => ({pending: true}),
    };
  },
};
const publicDeleteKind: import('@actql/local-node/connector-installation').RowEffectKind = 'delete';
const publicAbsentEntry: import('@actql/local-node/connector-installation').RowEffectEntry<DeleteRequest> = {
  request: {target: 'original-id'}, requestCid: bindingCid, value: undefined,
};
const deleteEntry: import('@actql/local-node/connector-installation').RowEffectEntry<DeleteRequest, 'delete'> = publicAbsentEntry;
void [publicDeleteKind, publicAbsentEntry, deleteEntry];

type DeletePreparation = Parameters<DeleteDriver['prepareRequest']>[0];
declare const originalDeletePreparation: DeletePreparation;
const dummyDeleteObject: DeletePreparation = {...originalDeletePreparation,
  // @ts-expect-error DELETE: An empty object is not an absent proposed value.
  value: {},
};
const dummyDeleteNull: DeletePreparation = {...originalDeletePreparation,
  // @ts-expect-error DELETE: Null is not an absent proposed value.
  value: null,
};
const invalidDeleteFacts: Pick<DeleteDriver, 'requestFacts'> = {
  // @ts-expect-error DELETE: Request facts cannot introduce a proposed object.
  requestFacts: request => ({target: request.target, value: {}}),
};
const invalidDeleteChild: DeleteDriver = {...deleteDriver,
  // @ts-expect-error DELETE: The child must be retained synchronously before any await.
  prepareRequestChild: async context => deleteDriver.prepareRequestChild!(context),
};
const invalidDeleteCleanup: DeleteDriver = {...deleteDriver,
  // @ts-expect-error DELETE: Preparation completion cannot omit original cleanup custody.
  prepareRequestChild: context => ({prepare: () => deleteDriver.prepareRequest(context), status: () => ({pending: true})}),
};
type ExistingPreparation = Parameters<RowEffectDriver<Request>['prepareRequest']>[0];
declare const originalValuePreparation: ExistingPreparation;
const absentUpdateValue: ExistingPreparation = {...originalValuePreparation,
  // @ts-expect-error Value-bearing: Existing value-bearing inputs still require their object.
  value: undefined,
};
const absentUpdateFacts: Pick<RowEffectDriver<Request>, 'requestFacts'> = {
  // @ts-expect-error Value-bearing: A value-bearing request cannot omit its original value.
  requestFacts: () => ({}),
};
void [dummyDeleteObject, dummyDeleteNull, invalidDeleteFacts, invalidDeleteChild,
  invalidDeleteCleanup, absentUpdateValue, absentUpdateFacts];

// Existing Command input remains value-bearing, with the original rowless
// optional indexed read context and a Command contract rather than a Mapping.
type CommandRequest = Readonly<{value: ConnectorJsonObject}>;
type CommandDriver = RowEffectDriver<CommandRequest, unknown, 'command'>;
declare const originalCommandDriver: CommandDriver;
const commandDriver: CommandDriver = {...originalCommandDriver, kinds: ['command'],
  prepareRequest({member, value}) {
    const input: ConnectorJsonObject = value;
    const contract: string = member.command.commandCid;
    void contract;
    return {request: {value: input}, requestCid: bindingCid};
  },
  requestFacts: request => ({value: request.value}),
};
type CommandChildContext = Parameters<NonNullable<CommandDriver['prepareRequestChild']>>[0];
declare const originalCommandMember: CommandChildContext['member'];
const originalCommandWithoutRead: CommandChildContext = {
  member: originalCommandMember, value: {body: 'original'}, current: undefined,
};
const originalCommandWithRead: CommandChildContext = {
  ...originalCommandWithoutRead, authorizationForRow: indexedRead,
};
const absentCommandFacts: Pick<CommandDriver, 'requestFacts'> = {
  // @ts-expect-error Value-bearing: A Command still needs its original input value.
  requestFacts: () => ({}),
};
declare const originalDeleteOptions: Parameters<typeof createInstalledRowEffect<DeleteRequest, unknown, 'delete'>>[0];
const publicDeleteFactory = createInstalledRowEffect({...originalDeleteOptions, driver: deleteDriver});
declare const originalCommandOptions: Parameters<typeof createInstalledRowEffect<CommandRequest, unknown, 'command'>>[0];
const publicCommandFactory = createInstalledRowEffect({...originalCommandOptions, driver: commandDriver});
void [commandDriver, originalCommandWithoutRead, originalCommandWithRead, absentCommandFacts,
  publicDeleteFactory, publicCommandFactory];


// Presence is original observation DATA, not a missing before-value convention.
type UpsertObservation = import('@actql/local-node/connector-installation').RowEffectTargetObservation<'upsert'>;
type UpdateObservation = import('@actql/local-node/connector-installation').RowEffectTargetObservation<'update'>;
type DeleteObservation = import('@actql/local-node/connector-installation').RowEffectTargetObservation<'delete'>;
const originalAbsence: UpsertObservation = {identity: 'original-key', state: 'absent'};
const originalPresence: UpsertObservation = {identity: 'original-key',
  versionCid: bindingCid, before: {id: 'original-key'}};
const explicitPresence: UpdateObservation = {...originalPresence, state: 'present'};
// @ts-expect-error UPSERT: Missing before-data/version is not explicit absence.
const missingPresence: UpsertObservation = {identity: 'original-key'};
// @ts-expect-error UPSERT: Null is not a before row or an absence observation.
const nullBefore: UpsertObservation = {identity: 'original-key', state: 'absent', before: null};
// @ts-expect-error UPSERT: Empty-object placeholders cannot accompany explicit absence.
const placeholderBefore: UpsertObservation = {identity: 'original-key', state: 'absent', before: {}};
// @ts-expect-error UPSERT: An absent row cannot carry a fabricated version.
const absentVersion: UpsertObservation = {identity: 'original-key', state: 'absent', versionCid: bindingCid};
// @ts-expect-error UPSERT: UPDATE cannot accept the insert-side absence variant.
const absentUpdate: UpdateObservation = {identity: 'original-key', state: 'absent'};
// @ts-expect-error UPSERT: DELETE cannot accept the insert-side absence variant.
const absentDelete: DeleteObservation = {identity: 'original-key', state: 'absent'};
void [originalAbsence, originalPresence, explicitPresence, missingPresence, nullBefore,
  placeholderBefore, absentVersion, absentUpdate, absentDelete];


// A scoped decoder receives global positions in the original whole Preview;
// its request arrays remain typed exactly as the original driver requests.
declare const originalRebuiltRequests: readonly (readonly Request[])[];
const scopedRecoveryDriver: RowEffectDriver<Request> = {...originalDriver,
  recoverMemberRequests({memberIndexes, previewWire, body}) {
    const originalIndex: number | undefined = memberIndexes[0];
    const originalWire: string = previewWire;
    const originalBody: ConnectorJsonObject = body;
    void [originalIndex, originalWire, originalBody];
    return {requests: originalRebuiltRequests};
  },
};
const invalidScopedRecoveryDriver: RowEffectDriver<Request> = {...originalDriver,
  // @ts-expect-error Recovery cannot replace original typed requests with strings.
  recoverMemberRequests: () => ({requests: [['request-cid']]}),
};
void [scopedRecoveryDriver, invalidScopedRecoveryDriver];

declare const originalRestDefinition: RestSourceInstallationDefinition;
const pureRestTransform: RestSourceTransform = (page, context) => {
  const wire: string = page.rowsWire;
  const column: string | undefined = context.columns[0];
  void column;
  return {rowsWire: wire};
};
const restFacade = createInstalledRestSource(originalRestDefinition, {decodePage: pureRestTransform});
const checkedRestProfile = restFacade.checkProfile({});
const restSitePath: string = checkedRestProfile.siteProfilePath;
// @ts-expect-error An author transform is pure and synchronous, not a reader.
const asyncRestTransform: RestSourceTransform = async () => ({rowsWire: '[]'});
// @ts-expect-error Host services are not an author facade option.
createInstalledRestSource(originalRestDefinition, {installationServices: {}});
// @ts-expect-error A factory cannot accept caller-issued capacity as authority.
createInstalledRestSource(originalRestDefinition, {capacity: providerReaderCapacity});
// @ts-expect-error Generated declaration wire is required, never reconstructed at load.
const missingRestOriginal: RestSourceInstallationDefinition = {registration: 'acme', revision: 'acme/0.1',
  profileVersion: 'actql-installed-acme-rest-source/0.1', origin: 'https://api.acme.invalid',
  auth: {kind: 'bearer'}, sources: []};
void [restSitePath, asyncRestTransform, missingRestOriginal];

// Preserve the same existing cleanup Owner return instead of erasing it to
// void. This is compile-only correspondence, never a physical cleanup ACK.
type ExactCleanupReturn<A, B> =
  (<T>() => T extends A ? 1 : 2) extends
  (<T>() => T extends B ? 1 : 2) ? true : false;
type RequireCleanupReturn<T extends true> = T;
type SourceCleanupOriginal = RequireCleanupReturn<ExactCleanupReturn<
  ReturnType<typeof source.close>, ReturnType<InstallationCloseOwner['close']>>>;
type EffectCleanupOriginal = RequireCleanupReturn<ExactCleanupReturn<
  ReturnType<typeof effect.close>, ReturnType<InstallationCloseOwner['close']>>>;
