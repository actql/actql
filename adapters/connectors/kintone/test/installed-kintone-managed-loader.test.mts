import assert from 'node:assert/strict';
import test from 'node:test';
import {loadInstalledKintoneSource} from '../host/installed-kintone-source.mjs';


import type {KintoneMaterialsConstruction} from '../host/installed-kintone-source.mjs';
import type {createKintoneManagedSequence} from '../site/kintone-managed-sequence.mjs';

type LoaderOptions = Parameters<typeof loadInstalledKintoneSource>[1];
type LoaderConstruction = NonNullable<LoaderOptions['construction']>;
type SourceReaderSetup = Parameters<LoaderConstruction['createSourceReader']>[0];
type SiteSetup = Parameters<LoaderConstruction['openRowSite']>[0];
type ReaderSelection = Readonly<{columnCount: number; limits: Readonly<Record<string, number>>;
  readSequenceConstruction: Readonly<{capacity: unknown; sequence: Readonly<{maxUses: number; children: unknown}>}>}>;
type SourceSetup = Readonly<{providerReader: unknown; prepareAcquisition?: unknown; readPages?: unknown;
  physicalTarget(resource: string, columns: string[]): Readonly<{metadataCid: string}>}>;
type GrantRequest = Readonly<{runInvocationCid: string; dispatchRequestCid: string; operation: string;
  resource: string; maxUses: number}>;
type Sequence = ReturnType<ReturnType<typeof createKintoneManagedSequence>>;
type ReadContext = Parameters<Sequence['read']>[0];
type ReadChild = Parameters<ReadContext['readChild']>[0];
type Form = ReturnType<ReadChild['prepare']> & Readonly<{authorization: Readonly<{useId: string}>}>;

const ok = <Value,>(value: Value) => ({$tag: 1, _0: value});
// Loader wiring only. These explicit ports are not Account, native capacity,
// a physical binding or evidence of installed/public-route acceptance.
function fixture({noCapacity = false, overflow = false, noDeclarationCapacity = false} = {}) {
  const events: string[] = [], initial = {}, original = {}, calls: {
    grants: number; decisions: number; metadataUnits?: number[]; capacityArguments?: unknown[];
    grantRequest?: GrantRequest; selection?: ReaderSelection; implementation?: SourceReaderSetup['implementation'];
    siteOptions?: SiteSetup; readerOptions?: SourceReaderSetup; sourceOptions?: SourceSetup;
  } = {grants: 0, decisions: 0};
  const profile = {version: 'actql-installed-kintone-source/0.1', connectorId: 'tickets',
    appId: '12', resource: 'records', formResource: 'form', fieldCodes: ['Subject'],
    metadataPath: '/metadata.json', siteProfilePath: '/site.json', accountConfigurationWire: '{}',
    limits: {maxResponseBytes: overflow ? 2147483647 : 8192, maxNodes: 2000, maxDepth: 20,
      maxFields: 16, maxNameUnits: 512, maxColumns: 16, maxCells: 64, maxTableRows: 16,
      maxValueNodes: 2000, maxValueDepth: 20, maxValueTextBytes: 8192, maxContractPairs: 100,
      maxRequestBytes: 4096, maxRequests: 5, maxPages: 2, perPage: 2,
      maxSecretBytes: 128, maxRows: 4, maxDeclarationBytes: 20000, maxDeclarationNodes: 2000}};
  const siteProfile = {version: 'actql-installed-kintone-site/0.1', apiOrigin: 'https://example.invalid',
    credentialAuthorityId: 'issuer', credentialKeyId: 'key', credentialPrivateKeyPath: '/key.pem',
    environment: 'test', journalRoot: '/journal', namespaceId: 'namespace', siteGeneration: 1,
    siteKey: 'site', tokenEnvironment: 'KINTONE_TOKEN'};
  const metadata = {version: 'actql-kintone-record-metadata/0.1', connectorId: 'tickets',
    appId: '12', apiOrigin: siteProfile.apiOrigin, formBody: Buffer.from('{}').toString('base64')};
  let forms = 0, pages = 0;
  const moon = {
    clientProgramKintoneReadDeclarationConstructionCapacity: () => noDeclarationCapacity ? undefined : {},
    clientProgramKintoneMetadataIdentityCapacity(base: unknown, ...units: number[]) { calls.metadataUnits = units; return base; },
    clientProgramKintoneFormLimits: (...values: unknown[]) => ({values}),
    clientProgramKintonePageLimits: (...values: unknown[]) => ({values}),
    clientProgramKintoneValueLimits: (...values: unknown[]) => ({values}),
    clientProgramKintoneDeclarationLimits: (...values: unknown[]) => ({values}),
    clientProgramKintoneProjectForm: () => ok({}),
    clientProgramKintoneDeclareRecords: () => ok(original),
    clientProgramKintoneRecordDeclaration: () => 'declared',
    clientProgramKintoneManagedSourceReaderCapacity(...args: unknown[]) {
      events.push('capacity'); calls.capacityArguments = args; assert.equal(args[2], original);
      return noCapacity ? undefined : initial;
    },
    clientProgramKintoneManagedResponseCapacity: () => ({}),
    clientProgramKintoneAdoptManagedBorrow: () => ok({}),
    clientProgramKintoneManagedColumns: () => ['$id', 'Subject'],
    clientProgramKintoneManagedFormRequest: () => ok('{"app":"12"}'),
    clientProgramKintoneManagedPageRequest: () => ok('{"app":"12"}'),
    clientProgramKintoneManagedRecheckForm() { forms++; return ok(undefined); },
    clientProgramKintoneManagedProjectPage() { pages++; return ok([]); },
    clientProgramKintoneManagedComplete: () => pages > 0 && forms > pages,
    clientProgramKintoneManagedRetire() {},
  };
  const authorization = {context: {contextCid: 'context'}, async authorize(_phase: string, access: {resource: string}) {
    assert.equal(access.resource, 'form'); calls.decisions++; return {action: 'dispatch'};
  }};
  const site = {credential: {}, issueReadGrant(request: GrantRequest) {
    calls.grants++; calls.grantRequest = request;
    return {scope: {runInvocationCid: request.runInvocationCid, dispatchRequestCid: request.dispatchRequestCid,
      operation: request.operation}, grant: {}};
  }};
  const construction = {
    configurationReader: {async readJson(path: string) { return path === '/site.json' ? siteProfile : metadata; }},
    prepareNativeDeclaration(projection: Parameters<KintoneMaterialsConstruction['prepareNativeDeclaration']>[0]) {
      projection.capacity(); const prepared = projection.project();
      return {original: prepared.original, metadataCid: prepared.metadataCid, declared: {views: [{fields: ['$id', 'Subject']}]}};
    },
    sourceReaderImplementation(selection: ReaderSelection) {
      events.push('implementation'); calls.selection = selection;
      return calls.implementation = {capacity: selection.readSequenceConstruction.capacity,
        runAcquisitionLimits: {maxBindings: 3, maxSecretBytes: 128}};
    },
    async openRowSite(options: SiteSetup) {
      events.push('site'); calls.siteOptions = options; return {site, authorization};
    },
    createSourceReader(options: SourceReaderSetup) {
      events.push('reader'); calls.readerOptions = options;
      return {capacity: options.implementation.capacity};
    },
    async createRowSource(options: SourceSetup) { events.push('source'); calls.sourceOptions = options; return options; },
  };
  return {calls, events, profile, initial, mutateMetadata: () => {metadata.formBody = 'changed';},
    load: () => loadInstalledKintoneSource(profile, {moon, runtimeBundleCid: 'runtime', construction: construction as unknown as LoaderConstruction})};
}

test('managed Kintone loader selects complete capacity before Site and preserves independent limits', async () => {
  const f = fixture(); await f.load();
  assert.deepEqual(f.events, ['capacity', 'implementation', 'site', 'reader', 'source']);
  assert.equal(f.calls.siteOptions!.runAcquisitionLimits, f.calls.implementation!.runAcquisitionLimits);
  assert.equal(f.calls.siteOptions!.secretPresentation, 'kintone-api-token');
  const selection = f.calls.selection!;
  assert.equal(selection.columnCount, 2);
  assert.equal(selection.limits.maxPages, 5);
  assert.equal(selection.limits.maxTotalResponseBytes, 5 * 8192);
  assert.equal(selection.limits.maxTargetBytes, '/k/v1/app/form/fields.json'.length);
  assert.equal(selection.readSequenceConstruction.sequence.maxUses, 2);
  assert.deepEqual(selection.readSequenceConstruction.sequence.children,
    [{operation: 'kintone:form:read', resource: 'form', maxUses: 5}]);
  assert.ok(f.calls.sourceOptions!.providerReader);
  assert.equal(f.calls.sourceOptions!.prepareAcquisition, undefined);
  assert.equal(f.calls.sourceOptions!.readPages, undefined);
  assert.deepEqual(f.calls.metadataUnits, [4, 7, 2, 23]);
  const before = f.calls.sourceOptions!.physicalTarget('records', ['$id']).metadataCid;
  f.mutateMetadata();
  assert.equal(f.calls.sourceOptions!.physicalTarget('records', ['$id']).metadataCid, before);
});

test('managed Kintone loader refuses missing capacity and aggregate overflow before Site', async () => {
  for (const options of [{noCapacity: true}, {overflow: true}, {noDeclarationCapacity: true}]) {
    const f = fixture(options);
    await assert.rejects(f.load(), {code: options.overflow
      ? 'KintoneManagedAggregateUnavailable' : options.noDeclarationCapacity
        ? 'KintoneDeclarationCapacityUnavailable' : 'KintoneManagedCapacityUnavailable'});
    if (options.noDeclarationCapacity) assert.equal(f.calls.metadataUnits, undefined);
    assert.equal(f.events.includes('site'), false);
    assert.equal(f.events.includes('reader'), false);
  }
});

test('managed Kintone loader keeps one original Form grant and current callback through final recheck', async () => {
  const f = fixture(); await f.load();
  const input = {resource: 'records', columns: ['$id', 'Subject'], responseBorrow: {},
    originalAuthorization: {scope: {runInvocationCid: 'run-original', dispatchRequestCid: 'dispatch-original'}}};
  const sequence = f.calls.readerOptions!.prepareReadSequence(input);
  const forms: Form[] = [];
  await sequence.read({signal: new AbortController().signal,
    async readChild(child) {
      const prepared = child.prepare();
      if (child.operation === 'kintone:form:read') {
        forms.push(prepared as Form); await prepared.verifyCurrent!();
      }
      sequence.responseCapacity(2);
      return prepared.project({statusCode: 200, body: Buffer.from('{}')});
    }, async consumeObservation() {}, async consumeValues() {},
  });
  assert.equal(forms.length, 2);
  assert.equal(f.calls.grants, 1);
  assert.equal(forms[0].originalAuthorization, forms[1].originalAuthorization);
  assert.equal(forms[0].verifyCurrent, forms[1].verifyCurrent);
  assert.notEqual(forms[0].authorization.useId, forms[1].authorization.useId);
  assert.equal(f.calls.grantRequest!.runInvocationCid, 'run-original');
  assert.equal(f.calls.grantRequest!.dispatchRequestCid, 'dispatch-original');
  assert.equal(f.calls.grantRequest!.resource, 'form');
  assert.equal(f.calls.grantRequest!.maxUses, 5);
  assert.equal(f.calls.decisions, 4);
  sequence.retire();
});
