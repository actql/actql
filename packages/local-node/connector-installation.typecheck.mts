import {
  checked, createInstalledRestSource, createInstalledRowEffect, createInstalledRowSource,
  installRowSourceAuthorization, invokeScopedCredentialOperation,
  openRowSourceCredentialSite, retainInstalledHostInitializationFailure,
  rowSourceCheckEnvironment, rowSourceMapping,
} from '@actql/local-node/connector-installation';
import {validateRestReadDeclaration} from '@actql/local-node/connector-authoring';
import type {
  ConnectorJsonObject, ConnectorRuntimeHandle, ConnectorRuntimeOwner,
  CredentialResponse, RowSourceCredentialProfile, RowSourceDeclarationFacts,
  InstalledRowProviderReader, RowProviderReaderRequest,
  RowEffectDriver, RowEffectMember, RowEffectRequestChild, RowEffectCreateWrite, RowEffectUpdateWrite, RowEffectUpdateConstructionProvider, InstalledRowEffectOptions,
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

// An opaque original is not the public tuple returned by its typed accessor.
// @ts-expect-error Capacity internals are not public record fields.
providerReaderCapacity._0;
// @ts-expect-error Opaque handles do not expose numeric array elements.
providerReaderCapacity[0];

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

// Standard CREATE uses the same factory without implementing Host-owned hooks.
type CreateRequest = Readonly<{path: string; body: string}>;
const standardWrite: RowEffectCreateWrite<CreateRequest> = {
  kind: 'create', operation: 'items.create', resourceKind: 'items', boundaryCid: bindingCid,
  http: {origin: 'https://example.invalid', method: 'POST', path: '/items',
    maxRequestBytes: 4096, maxResponseBytes: 4096},
  request({resource, value}) {
    if (resource !== 'items') throw new Error('UndeclaredResource');
    return {path: '/items', body: JSON.stringify(value)};
  },
  classify({request, observation}) {
    const body: string = request.body;
    const status: number = observation.statusCode;
    void [body, status];
    return {kind: 'unclassified-response'};
  },
  confirmation: {resource: 'items', operation: 'items.read',
    http: {origin: 'https://example.invalid', method: 'GET', path: '/items',
      query: [['limit', '1']], maxRequestBytes: 4096, maxResponseBytes: 4096},
    body: () => undefined,
    // No matching provider evidence remains Unknown, not a fabricated success.
    project: () => undefined,
  },
};
declare const standardHostOptions: Omit<InstalledRowEffectOptions<CreateRequest, unknown, 'create'>,
  'driver' | 'write'>;
const standardCreate = createInstalledRowEffect({...standardHostOptions, write: standardWrite});
declare const originalCreateDriver: RowEffectDriver<CreateRequest, unknown, 'create'>;
// @ts-expect-error Standard CREATE [mode-conflict]: Exactly one implementation is selected.
const conflictingCreate = createInstalledRowEffect({...standardHostOptions, write: standardWrite, driver: originalCreateDriver});
// @ts-expect-error Standard CREATE [mode-missing]: An implementation cannot be absent.
const missingCreate = createInstalledRowEffect<CreateRequest>({...standardHostOptions});
type DeclaredUpdateRequest = Readonly<{body: string}>;
declare const compiledUpdateProvider: RowEffectUpdateConstructionProvider;
const updateTransport = Object.freeze({maxRequestBytes: 128, maxResponseBytes: 128, maxTargetBytes: 80});
declare const standardUpdateHost: Omit<InstalledRowEffectOptions<DeclaredUpdateRequest, unknown, 'update'>, 'driver' | 'write'>;
const standardUpdateWrite: RowEffectUpdateWrite<DeclaredUpdateRequest> = {
  kind: 'update', operation: 'records.update', transport: updateTransport,
  targetRead: {operation: 'records.read', transport: updateTransport},
  prepareRequest: ({value}) => ({request: {body: JSON.stringify(value)}, requestCid: 'original'}),
  requestFacts: request => ({value: {name: request.body}, target: 'record'}),
  requestCid: () => 'original',
  prepareUpdateWrite(member, request, _current, origin, registration, signal) {
    void [member, origin, registration];
    signal?.throwIfAborted();
    return {method: 'PUT', path: '/records', body: request.body};
  },
  async observeTargets({readTarget, entries}) {
    const headRequest = {method: 'HEAD', path: '/records'} as const;
    // @ts-expect-error The declared target slot supports GET and POST only.
    void readTarget(0, headRequest, response => ({identity: 'record',
      versionCid: response.useCid, before: {name: 'original'}}), () => {});
    const rows = [];
    for (const [index] of entries.entries()) {
      rows.push(await readTarget(index, {method: 'GET', path: '/records'},
        response => ({identity: 'record', versionCid: response.useCid, before: {name: 'original'}}), () => {}));
    }
    return rows;
  },
  project: () => ({kind: 'unclassified-response'}),
  footprint: () => ({providerNamespace: 'records', resourceKind: 'record', boundaryCid: 'original'}),
  recoveryEntry: ({entries}) => ({kind: 'record_update', observationCid: 'original', wire: JSON.stringify(entries)}),
  recoverRequests({members}) {
    return {requests: members.map(member => {
      const kind: 'update' = member.kind;
      // @ts-expect-error A singular UPDATE owner cannot receive a Command member.
      const command: RowEffectMember<'command'> = member;
      void [kind, command];
      return [];
    })};
  },
};
const standardUpdate = createInstalledRowEffect<DeclaredUpdateRequest, unknown, 'update'>({...standardUpdateHost,
  write: Object.freeze(standardUpdateWrite), providerMoon: compiledUpdateProvider});
// @ts-expect-error Standard UPDATE requires the compiled implementation profile.
const unpreparedUpdate = createInstalledRowEffect<DeclaredUpdateRequest, unknown, 'update'>({...standardUpdateHost, write: standardUpdateWrite});
const asyncUpdate: RowEffectUpdateWrite<DeclaredUpdateRequest> = {...standardUpdateWrite,
  // @ts-expect-error Standard UPDATE encodes synchronous request DATA.
  prepareUpdateWrite: async (...args) => standardUpdateWrite.prepareUpdateWrite(...args),
};
const externalUpdateSend: RowEffectUpdateWrite<DeclaredUpdateRequest> = {...standardUpdateWrite,
  // @ts-expect-error Standard UPDATE cannot take over physical sending.
  send: () => undefined,
};
void [standardUpdate, unpreparedUpdate, asyncUpdate, externalUpdateSend];
const asynchronousWrite: RowEffectCreateWrite<CreateRequest> = {...standardWrite,
  // @ts-expect-error Standard CREATE [async-request]: Request mapping is synchronous DATA work.
  request: async input => standardWrite.request(input),
};
const asynchronousClassifier: RowEffectCreateWrite<CreateRequest> = {...standardWrite,
  // @ts-expect-error Standard CREATE [async-classification]: Classification is synchronous provider DATA.
  classify: async input => standardWrite.classify(input),
};
// @ts-expect-error Standard CREATE [unsupported-kind]: The standard declaration does not implement DELETE.
const standardDelete = createInstalledRowEffect<CreateRequest, unknown, 'delete'>({...standardHostOptions, write: standardWrite});
const invalidWriteMethod: RowEffectCreateWrite<CreateRequest> = {...standardWrite,
  // @ts-expect-error Standard CREATE [write-method]: A read verb cannot dispatch a CREATE.
  http: {...standardWrite.http, method: 'GET'},
};
const ignoredWriteQuery: RowEffectCreateWrite<CreateRequest> = {...standardWrite,
  // @ts-expect-error Standard CREATE [request-query]: Write query belongs to the mapped original request.
  http: {...standardWrite.http, query: [['ignored', 'value']]},
};
const requestDataOnly: RowEffectCreateWrite<CreateRequest> = {...standardWrite,
  request(input) {
    // @ts-expect-error Standard CREATE [no-authority]: Pure author mapping receives no authorization.
    input.authorization;
    return standardWrite.request(input);
  },
};
void [standardCreate, conflictingCreate, missingCreate, asynchronousWrite,
  asynchronousClassifier, standardDelete, invalidWriteMethod, ignoredWriteQuery, requestDataOnly];

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
  recoverMemberRequests({members, memberIndexes, previewWire, body}) {
    const originalIndex: number | undefined = memberIndexes[0];
    const originalWire: string = previewWire;
    const originalBody: ConnectorJsonObject = body;
    void [originalIndex, originalWire, originalBody];
    const preceding = members[0];
    if (preceding.kind === 'command') {
      const commandCid: string = preceding.command.commandCid;
      void commandCid;
    }
    return {requests: memberIndexes.map(index => {
      const member = members[index];
      if (member.kind !== 'update') throw new Error('UnexpectedOriginalMemberKind');
      return originalRebuiltRequests[index];
    })};
  },
};
const invalidScopedRecoveryDriver: RowEffectDriver<Request> = {...originalDriver,
  // @ts-expect-error Recovery cannot replace original typed requests with strings.
  recoverMemberRequests: () => ({requests: [['request-cid']]}),
};
declare const originalUpdateMember: RowEffectMember<'update'>;
const wholeRecoveryPreview = Object.freeze([originalCommandMember, originalUpdateMember]);
const recoveredUpdate = scopedRecoveryDriver.recoverMemberRequests?.({members: wholeRecoveryPreview,
  memberIndexes: Object.freeze([1]), previewWire: 'original', body: {}, durable: undefined, recorded: undefined});
void [scopedRecoveryDriver, invalidScopedRecoveryDriver, recoveredUpdate];

declare const originalRestDefinition: RestSourceInstallationDefinition;
const originalReadWire: string = validateRestReadDeclaration('{"method":"GET","path":"/records"}');
// @ts-expect-error Offline author validation consumes an original wire, not an object/Host or grant.
validateRestReadDeclaration({method: 'GET', path: '/records'});
void originalReadWire;
// Both supported static declaration representations remain explicit. Neither
// an absent read nor two competing originals can select a Source constructor.
const restReadBase = {resource: 'records', resource_kind: 'record', fields: [],
  pagination: {kind: 'none' as const, items: []}, limits: {maxPageRows: 1,
    maxPageBytes: 1024, maxPages: 1, maxRows: 1, maxNodes: 64, maxDepth: 8, maxCursorBytes: 64}};
const originalReadSource: RestSourceInstallationDefinition['sources'][number] = {
  ...restReadBase, read: {method: 'GET', path: '/records'}};
const finiteReadSource: RestSourceInstallationDefinition['sources'][number] = {
  ...restReadBase, readWire: '{"method":"GET","path":"/records"}'};
// @ts-expect-error A generated original and a legacy object cannot both select the same read.
const competingRestReads: RestSourceInstallationDefinition['sources'][number] = {...restReadBase, read: {method: 'GET', path: '/records'}, readWire: '{}'};
// @ts-expect-error A Source must select one actual request declaration.
const absentRestRead: RestSourceInstallationDefinition['sources'][number] = restReadBase;
void [originalReadSource, finiteReadSource, competingRestReads, absentRestRead];
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
