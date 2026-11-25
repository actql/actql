// Actual imported Host assembly with explicit construction ports. These
// component cases issue no Common parent, read grant or physical stop ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installFinitePageSource} from '../../../host-node/installed-finite-page-source.mjs';

type FiniteOptions = {capacityFailure?:unknown;publicationFailure?:unknown;foreignCapacity?:object;
  retire?:()=>boolean;openingFailure?:unknown};
type InitializationFailure = Error & {primaryFailure?:Error & {code?:string};cleanupHandle:{
  status():{pending:boolean;owners:readonly string[]};retry():Promise<unknown>;
}};
type FixtureSelection = Readonly<{installation:unknown;sourceInitialization:unknown;
  profile?:unknown;runAcquisitionLimits?:unknown;implementation?:unknown;site?:unknown;
  preparePageReader?:unknown;operation?:unknown}>;
type LoaderOptions = {changeAfterRead?:boolean;implementationFailure?:unknown;requestFailure?:unknown};
type ReaderInput = {operation:unknown;preparePageReader(request:{resource:string;columns:readonly string[]},
  projection:()=>unknown):unknown};
type ImplementationInput = {cursorProgress:unknown;requestConstruction:unknown};

function fixture({capacityFailure, publicationFailure, foreignCapacity, retire = () => true, openingFailure}:FiniteOptions = {}) {
  const events:string[] = [], capacity = {}, installation = {}, sourceInitialization = {};
  const implementation = {capacity, runAcquisitionLimits: {original: 'acquisition'}};
  const authorization = {}, source = {}, siteOptions = {profile: {}, resolveSecret() {
    assert.fail('No secret is resolved during constructor-only assembly');
  }};
  const site = {async close() {assert.equal(this, site);events.push('site.close');}};
  Object.assign(siteOptions, {installation, sourceInitialization,
    runAcquisitionLimits: implementation.runAcquisitionLimits});
  const reader = {get capacity() {
    events.push('reader.capacity');if (capacityFailure) throw capacityFailure;return foreignCapacity ?? capacity;
  }, retire() {assert.equal(this, reader);events.push('reader.retire');return retire();}};
  const preparePageReader = (...args:unknown[]) => {events.push('page');return args;};
  const input = {services(name:'openRowSite'|'createSourceReader', selected:FixtureSelection) {
    assert.equal(selected.installation, installation);
    assert.equal(selected.sourceInitialization, sourceInitialization);
    if (name === 'openRowSite') {
      events.push('site');assert.equal(selected.profile, siteOptions.profile);
      assert.equal(selected.runAcquisitionLimits, implementation.runAcquisitionLimits);
      if (openingFailure) throw openingFailure;
      return {site, authorization};
    }
    assert.equal(name, 'createSourceReader');events.push('reader');
    assert.equal(selected.implementation, implementation);assert.equal(selected.site, site);
    assert.equal(selected.preparePageReader, preparePageReader);
    assert.equal(selected.operation, 'notion:users:list');
    return reader;
  }, installation, sourceInitialization, implementation, siteOptions,
  operation: 'notion:users:list', preparePageReader,
  implementationMismatch: 'InstalledNotionReaderImplementationMismatch',
  publish(opened:{site:typeof site;authorization:typeof authorization}, originalReader:typeof reader) {
    events.push('publish');assert.equal(opened.site, site);assert.equal(opened.authorization, authorization);
    assert.equal(originalReader, reader);if (publicationFailure) throw publicationFailure;return source;
  }};
  const run = () => (installFinitePageSource as typeof installFinitePageSource & ((
    services:typeof input.services,siteInput:typeof siteOptions,implementation:typeof input.implementation,
    operation:string,prepare:typeof preparePageReader,mismatch:string,publish:typeof input.publish,
  )=>Promise<typeof source>))(input.services, siteOptions as typeof siteOptions & {installation:object;sourceInitialization:object}, implementation,
    input.operation, preparePageReader, input.implementationMismatch, input.publish);
  return {events, input, source, site, reader, preparePageReader, run};
}

test('finite provider-page assembly retains the same Host originals and pure page port', async () => {
  const f = fixture();
  assert.equal(await f.run(), f.source);
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'publish']);
  // The factory transfers this one reader; it does not retire a returned Source.
  const request = {resource: 'users', columns: ['id']}, projection = () => {};
  assert.deepEqual(f.preparePageReader(request, projection), [request, projection]);
});

test('finite provider-page capacity getter failure retains reader before Site cleanup', async () => {
  const original = new Error('original capacity getter');let ready = false, failure:InitializationFailure|undefined;
  const f = fixture({capacityFailure: original, retire: () => ready});
  await assert.rejects(f.run(), (cause:InitializationFailure) => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'reader.retire']);
  assert.equal(failure!.cleanupHandle.status().pending, true);
  assert(failure!.cleanupHandle.status().owners.includes('source-reader'));
  // An unfinished original retirement cannot close the dependent Site.
  ready = true;await failure!.cleanupHandle.retry();
  assert.equal(failure!.cleanupHandle.status().pending, false);
  assert.deepEqual(f.events.slice(-2), ['reader.retire', 'site.close']);
});

test('finite provider-page publication refusal keeps its original cause and never republishes', async () => {
  const original = new Error('original declaration/current refusal');
  const f = fixture({publicationFailure: original});let failure:InitializationFailure|undefined;
  await assert.rejects(f.run(), (cause:InitializationFailure) => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'publish', 'reader.retire', 'site.close']);
  assert.equal(failure!.cleanupHandle.status().pending, false);
  await failure!.cleanupHandle.retry();assert.equal(f.events.filter(value => value === 'publish').length, 1);
});

test('finite provider-page opening failure retains its original partial child without creating a reader', async () => {
  let stopped = false, retries = 0;
  const original = Object.assign(new Error('original Site partial child'), {cleanupPending: true,
    cleanupHandle: {status: () => ({pending: !stopped}), async retry() {retries++;}}});
  const f = fixture({openingFailure: original});let failure:InitializationFailure|undefined;
  await assert.rejects(f.run(), (cause:InitializationFailure) => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site']);assert.equal(failure!.cleanupHandle.status().pending, true);
  stopped = true;await failure!.cleanupHandle.retry();assert.equal(retries, 2);
  assert.equal(failure!.cleanupHandle.status().pending, false);assert.deepEqual(f.events, ['site']);
});

// Direct loader selection controls stop at an explicit constructor refusal.
// They do not replace createInstalledRowSource or issue a nominal Core value.
async function loaderFixture({changeAfterRead = false, implementationFailure, requestFailure}:LoaderOptions = {}) {
  const {loadInstalledNotionSource} = await import('../host/installed-notion-source.mjs');
  const events:string[] = [], sentinel = new Error('original reader constructor refusal');
  const limits = {maxResponseBytes: 8192, maxTotalResponseBytes: 24576, maxNodes: 512,
    maxDepth: 16, maxRows: 2, maxTotalRows: 3, maxPages: 4, pageSize: 2, maxCursorBytes: 128,
    maxIdentityBytes: 128, maxTargetBytes: 1024, maxValueNodes: 100, maxValueTextBytes: 4096,
    maxRowsWireBytes: 8192, maxRowsWireNodes: 200, maxRowsWireDepth: 8,
    maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128, maxCaBytes: 16384};
  const profile = {version: 'actql-installed-notion-source/0.1', connectorId: 'workspace',
    siteProfilePath: '/UNOPENED/notion-site.json', accountConfigurationWire: '{}', limits};
  const siteProfile = {version: 'actql-installed-notion-site/0.1', apiOrigin: 'https://notion.invalid',
    credentialAuthorityId: 'authority', credentialKeyId: 'key', credentialPrivateKeyPath: '/UNOPENED/key',
    environment: 'test', journalRoot: '/UNOPENED/journal', namespaceId: 'original', siteGeneration: 1, siteKey: 'notion'};
  const sourceInitialization = {prepareDeclaration(views:readonly {resource:string;resource_kind:string}[]) {
    assert.equal(this, sourceInitialization);events.push('declaration');
    assert.equal(views[0].resource, 'users');assert.equal(views[0].resource_kind, 'notion_users');
    return {declaration: {}, declared: {views: [{fields: ['id', 'name']}]}, environment: {wire: 'original'}};
  },prepareReadTarget(projection:{capacity():unknown;project():unknown}){
    assert.equal(this,sourceInitialization);assert(Object.isFrozen(projection));
    events.push('request.reserve');projection.capacity();
    if(requestFailure)throw requestFailure;
    events.push('request.project');return projection.project();
  }};
  const provider = {
    notionUserListSchemaWire() {assert.equal(this, provider);events.push('schema');return {$tag: 1, _0: 'schema'};},
    notionUserListRelationFactsWire() {assert.equal(this, provider);return 'facts';},
    notionUserListColumnNames() {assert.equal(this, provider);return ['id', 'name'];},
    notionUserListRowsWire() {assert.fail('No page in constructor scope');},
    notionUserListMetadata() {assert.fail('No page');},
    notionUserListPrepareIdentityProgress() {assert.fail('No page');},
    notionUserListTrackPageIdentities() {assert.fail('No page');},
    notionProjectUserList() {assert.fail('No page');},
  };
  const site = {async close() {assert.equal(this, site);events.push('site.close');}};
  let readerInput:ReaderInput|undefined, implementationInput:ImplementationInput|undefined;
  const services = {
    sourceReaderImplementationProfile() {assert.equal(this, services);events.push('policy');return limits;},
    sourceReaderImplementation(input:ImplementationInput) {
      assert.equal(this, services);events.push('implementation');implementationInput = input;
      if (implementationFailure) throw implementationFailure;
      return {capacity: {}, runAcquisitionLimits: {original: 'limits'}};
    },
    async openRowSite(input:{connection:string;profile:{resourceOrigin:string}}) {
      assert.equal(this, services);events.push('site');assert.equal(input.connection, 'notion:workspace');
      assert.equal(input.profile.resourceOrigin, siteProfile.apiOrigin);return {site, authorization: {}};
    },
    createSourceReader(input:ReaderInput) {assert.equal(this, services);readerInput = input;events.push('reader');throw sentinel;},
  };
  const configurationReader = {async readJson(path:string) {
    assert.equal(path, profile.siteProfilePath);events.push('configuration');
    if (changeAfterRead) {
      for (const key of Object.keys(services)) services[key as keyof typeof services] = () => assert.fail('Replaced service');
      for (const key of Object.keys(provider)) provider[key as keyof typeof provider] = () => assert.fail('Replaced provider');
      sourceInitialization.prepareDeclaration = () => assert.fail('Replaced Source constructor');
      sourceInitialization.prepareReadTarget = () => assert.fail('Replaced Source request constructor');
    }
    return siteProfile;
  }, readText() {assert.fail('No CA selected');}};
  // Explicit constructor-only Core ports. These tokens exercise captured
  // originals, not actual Core admission, funding, page I/O or opaque issuance.
  const read = {}, readQuote = {}, pageCapacity = {}, requestCapacity = {}, constructions = new Set<unknown>();
  const moon = {
    clientProgramInstalledSourceConstructionCapacity(...units:bigint[]) {
      assert.equal(this,moon);assert.equal(units.length,6);
      assert(units.every(value=>typeof value==='bigint'&&value>=0n));
      const capacity = {};constructions.add(capacity);return {$tag:1,_0:capacity};
    },
    clientProgramComposeInstalledSourceConstructionCapacity(original:unknown, quotes:readonly unknown[]) {
      assert.equal(this,moon);assert(constructions.has(original));
      assert.deepEqual(quotes,[readQuote]);return {$tag:1,_0:original};
    },
    clientProgramRowSourceGetReadCapacity(bounds:readonly unknown[]) {
      assert.equal(this,moon);assert.equal(bounds.length,8);return readQuote;
    },
    clientProgramRowSourceAdmitGetRead(bytes:Buffer, present:boolean, cursor:string, bounds:readonly unknown[]) {
      assert.equal(this,moon);assert(Buffer.isBuffer(bytes));assert.equal(bounds.length,8);
      assert.equal(present,true);assert.equal(cursor,'start_cursor');
      assert.equal(JSON.parse(bytes.toString('utf8')).path,'/v1/users');
      return {$tag:1,_0:read};
    },
    clientProgramRowSourceGetReadMetadata(original:unknown) {
      assert.equal(this,moon);assert.equal(original,read);
      return {$tag:1,_0:{_0:'/v1/users',_1:true,_2:100,_3:2,_4:1}};
    },
    clientProgramRowSourceGetPageCapacity(original:unknown) {
      assert.equal(this,moon);assert.equal(original,read);return pageCapacity;
    },
    clientProgramRowSourceGetRequestCapacity(transport:unknown, originals:readonly unknown[]) {
      assert.equal(this,moon);assert(constructions.has(transport));
      assert.deepEqual(originals,[pageCapacity]);return requestCapacity;
    },
    clientProgramRowSourceGetReadPage() {assert.fail('No page in constructor scope');},
    clientProgramRowSourceGetPageFrame() {assert.fail('No page frame in constructor scope');},
    clientProgramRowSourceGetReadIssueCode() {assert.fail('No Core refusal in this constructor fixture');},
  };
  type Options = NonNullable<Parameters<typeof loadInstalledNotionSource>[1]>;
  const options = {moon:moon as typeof moon & NonNullable<Options['moon']>, installation: {}, sourceInitialization, installationServices: services,
    providerMoon: provider, configurationReader, resolveSecret() {assert.fail('No credential resolution');}};
  return {events, options, sentinel, get readerInput() {return readerInput;},
    get implementationInput() {return implementationInput;}, load: (overrides?:Partial<Options>) =>
      loadInstalledNotionSource(profile, {...options, ...overrides})};
}

test('Notion constructor captures original services and provider before configuration await', async () => {
  const f = await loaderFixture({changeAfterRead: true});
  await assert.rejects(f.load(), (cause:InitializationFailure) => cause.primaryFailure === f.sentinel);
  assert.deepEqual(f.events, ['configuration', 'policy', 'schema', 'declaration',
    'request.reserve', 'request.project', 'implementation', 'site', 'reader', 'site.close']);
  assert.equal(f.readerInput!.operation, 'notion:users:list');
  assert.throws(() => f.readerInput!.preparePageReader({resource: 'foreign', columns: []}, () => {}),
    {code: 'UndeclaredNotionResource'});
  assert.equal(f.implementationInput!.cursorProgress, 'codec-identities');
  assert(Object.isFrozen(f.implementationInput!.requestConstruction));
});

test('Notion constructor refuses unavailable original methods before configuration', async () => {
  const f = await loaderFixture();
  await assert.rejects(f.load({sourceInitialization: undefined}), {code: 'NotionSourceInitializationUnavailable'});
  const services = {...f.options.installationServices};
  Object.defineProperty(services, 'openRowSite', {get() {assert.fail('No service accessor');}});
  await assert.rejects(f.load({installationServices: services}), {code: 'InstalledNotionSourceServicesUnavailable'});
  assert.deepEqual(f.events, []);
});

test('Notion constructor keeps the original implementation refusal before any Site or reader', async () => {
  const original = Object.assign(new Error('OriginalImplementationPending'), {cleanupPending: true});
  const f = await loaderFixture({implementationFailure: original});
  await assert.rejects(f.load(), cause => cause === original);
  assert.deepEqual(f.events, ['configuration', 'policy', 'schema', 'declaration',
    'request.reserve', 'request.project', 'implementation']);
});

test('Notion declarative request reservation refuses before snapshot Site and page construction', async () => {
  const original=new Error('original Source request reservation refused');
  const f=await loaderFixture({requestFailure:original});
  await assert.rejects(f.load(),cause=>cause===original);
  assert.deepEqual(f.events,['configuration','policy','schema','declaration','request.reserve']);
  assert.equal(f.readerInput,undefined);
  assert.equal(f.implementationInput,undefined);
});

test('finite provider-page foreign capacity refuses publication and retires only the returned reader', async () => {
  const f = fixture({foreignCapacity: {}});let failure:InitializationFailure|undefined;
  await assert.rejects(f.run(), (cause:InitializationFailure) => {
    failure = cause;return cause.primaryFailure?.code === 'InstalledNotionReaderImplementationMismatch';
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'reader.retire', 'site.close']);
  assert.equal(failure!.cleanupHandle.status().pending, false);
  assert.equal(f.events.includes('publish'), false);
});
