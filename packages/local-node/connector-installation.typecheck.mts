import {
  checked, createInstalledRowEffect, createInstalledRowSource,
  installRowSourceAuthorization, invokeScopedCredentialOperation,
  openRowSourceCredentialSite, retainInstalledHostInitializationFailure,
  rowSourceCheckEnvironment, rowSourceMapping,
} from '@actql/local-node/connector-installation';
import type {
  ConnectorJsonObject, ConnectorRuntimeHandle, ConnectorRuntimeOwner,
  CredentialResponse, RowSourceCredentialProfile, RowSourceDeclarationFacts,
} from '@actql/local-node/connector-installation';

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
