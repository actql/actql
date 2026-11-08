import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, writeFile, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {createInstalledHostServices, retainInstalledHostServiceInstallation} from './installed-host-services.mjs';
import {installedJsonSourceReaderProfileLimitNames} from './installed-credential-source-reader.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {loadInstalledSource} from './installed-source.mjs';

// Common policy/capacity and connector work are explicit ports. This executes
// the actual public service and top-level loader, not numerical admission.
const values = [1000000, 103000000, 100000, 64, 100, 100, 103, 100,
  4000000, 1000000, 9180448, 10000, 1000000, 10000000, 100000, 100,
  100, 10000, 10000, 1024, 10000000, 100000, 65536];
function fixture(extra = {}) {
  const capacity = Object.freeze({}), installation = Object.freeze({});
  let current = true, profileCalls = 0, capacityCalls = 0;
  const receiver = Object.freeze({});
  const moon = {
    clientProgramInstalledSourceReaderPolicy() {assert.equal(this, moon); return [65536, 100000, 100];},
    clientProgramInstalledJsonSourceReaderProfile(metadata, origin) {
      assert.equal(this, moon); assert.equal(metadata, 3); assert.equal(origin, 20);
      profileCalls++; return {$tag: 1, _0: values.slice()};
    },
    clientProgramInstalledJsonSourceReaderCapacity(limits, columns, secret) {
      assert.equal(this, moon); assert.deepEqual(limits, values.slice(0, 16));
      assert.equal(columns, 3); assert.equal(secret, 65536); capacityCalls++; return capacity;
    },
  };
  Object.assign(moon, extra);
  const services = createInstalledHostServices({root: '/UNOPENED/source-service', principalId: 'fixture',
    moon, receiver, assertCurrent() {assert.equal(this, receiver); if (!current) throw new Error('same current failure');}});
  return {services, installation, capacity, moon,
    counts: () => [profileCalls, capacityCalls], close() {current = false;}};
}

test('public Source service keeps original installation policy and typed capacity before any Site', () => {
  const f = fixture();
  assert.throws(() => f.services.sourceReaderImplementationProfile({installation: f.installation,
    metadataResponses: 3, originUnits: 20}), {code: 'ForeignInstalledHostServiceInstallation'});
  retainInstalledHostServiceInstallation(f.services, f.installation, 'sha256:' + 'a'.repeat(64));
  const input = {installation: f.installation, metadataResponses: 3, originUnits: 20};
  const policy = f.services.sourceReaderImplementationProfile(input);
  assert.equal(Object.isFrozen(policy), true);
  assert.deepEqual(policy, Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map((name, i) => [name, values[i]])));
  assert.equal(f.services.sourceReaderImplementationProfile({...input}), policy);
  const implementation = f.services.sourceReaderImplementation({installation: f.installation, limits: policy, columnCount: 3});
  assert.equal(implementation.capacity, f.capacity);
  assert.equal(f.services.sourceReaderImplementation({installation: f.installation, limits: {...policy}, columnCount: 3}), implementation);
  assert.deepEqual(f.counts(), [1, 1]);
  assert.throws(() => f.services.sourceReaderImplementation({installation: f.installation,
    limits: {...policy, maxPages: policy.maxPages + 1}, columnCount: 3}), {code: 'InstalledSourceReaderImplementationBoundsExceeded'});
  assert.throws(() => f.services.sourceReaderImplementationProfile({...input, installation: {...f.installation}}),
    {code: 'ForeignInstalledHostServiceInstallation'});
  assert.throws(() => retainInstalledHostServiceInstallation(f.services, f.installation, 'sha256:' + 'b'.repeat(64)),
    {code: 'InstalledHostServiceRuntimeChanged'});
  let observed = 0;
  for (const options of [{...input, get originUnits() {observed++; return 20;}},
    new Proxy(input, {ownKeys() {observed++; return [];}})]) {
    assert.throws(() => f.services.sourceReaderImplementationProfile(options), {code: 'InvalidInstalledSourceReaderSelection'});
  }
  assert.equal(observed, 0);
  f.close();
  assert.throws(() => f.services.sourceReaderImplementationProfile(input), /same current failure/);
});

test('actual top-level Source loader registers and passes the same service runtime and installation', async t => {
  const f = fixture(), root = await mkdtemp(join(tmpdir(), 'actql-public-source-service-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const runtimePath = join(root, 'runtime.mjs'), path = join(root, 'source.json');
  await writeFile(runtimePath, 'export {};\n');
  const version = 'actql-installed-source-service-fixture/0.1';
  await writeFile(path, JSON.stringify({version}));
  let loaded = 0, originalEntry;
  const module = {
    check(profile) {assert.equal(profile.version, version); return profile;},
    identityParts(profile) {return [profile];},
    load(profile, options) {
      loaded++; assert.equal(profile.version, version); assert.equal(options.installationServices, f.services);
      originalEntry = options.installation;
      const policy = options.installationServices.sourceReaderImplementationProfile({installation: originalEntry,
        metadataResponses: 3, originUnits: 20});
      assert.equal(policy.maxPages, 103);
      return {connectorRegistration: 'service_fixture', connectorRevision: 'service_fixture/0.1'};
    },
  };
  const connectorTable = createInstalledConnectorTable([{name: 'service_fixture', registration: 'service_fixture',
    revision: 'service_fixture/0.1', source: {profileVersion: version, load: async () => module}}]);
  const result = await loadInstalledSource(path, {root, principalId: 'fixture', moon: f.moon,
    runtimeUrl: pathToFileURL(runtimePath), baseEnvironmentWire: 'UNUSED', connectorTable,
    installationServices: f.services, resolveSecret() {assert.fail('no secret read');}});
  assert.equal(result.connectorRegistration, 'service_fixture'); assert.equal(loaded, 1);
  assert.equal(Object.isFrozen(originalEntry), true);
  assert.deepEqual(f.counts(), [1, 0]);
});

test('generic provider capture selection uses the same original declaration acquisition and provider capacity', async () => {
  const text = await readFile(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('  function prepareOriginalAcquisition(requirement) {');
  const end = text.indexOf('  const captureCapacity = owner => {', start);
  assert(start > 0 && end > start);
  const declaration = {}, requirement = {}, provider = {}, acquisition = {}, capacity = {}, events = [];
  let current = true;
  const site = {referenceCurrent() {assert.equal(this, site); events.push('current'); return current;}};
  const moon = {
    clientProgramRowSourcePrepareAcquisition(d, r, query, evidence, policy) {
      assert.equal(d, declaration); assert.equal(r, requirement);
      assert.equal(query, 'query'); assert.equal(evidence, 'evidence'); assert.equal(policy, undefined);
      events.push('acquisition'); return acquisition;
    },
    clientProgramInstalledProviderRowCaptureCapacity(a, p) {
      assert.equal(a, acquisition); assert.equal(p, provider); events.push('capacity'); return capacity;
    },
    clientProgramInstalledProviderRowCaptureCapacityMatches(c, a, p) {
      return c === capacity && a === acquisition && p === provider;
    },
  };
  const ports = {moon, declaration, queryContract: 'query', evidenceContract: 'evidence',
    listingPolicy: undefined, prepareAcquisition: undefined, retainedAcquisitionContracts:false,
    originalReader: {capacity: provider}, site,
    maxTransferBytes: 7n, limits: {maxPageBytes: 11}, checked: value => value,
    fail(code) {throw Object.assign(new Error(code), {code});}};
  const select = Function(...Object.keys(ports), text.slice(start, end) +
    '\nreturn managedProviderCaptureCapacity;')(...Object.values(ports));
  const selected = select(requirement);
  assert.equal(selected.capacity, capacity); assert.equal(Object.isFrozen(selected), true);
  assert.deepEqual([selected.transferBytes, selected.executionBytes], [7n, 11n]);
  assert.deepEqual(events, ['current', 'acquisition', 'capacity']);
  current = false;
  assert.throws(() => select(requirement), {code: 'InstalledSourceReaderNotCurrent'});
  assert.deepEqual(events, ['current', 'acquisition', 'capacity', 'current']);
});

test('Host service current check preserves optional Project original and closing Model checks', async () => {
  const text = await readFile(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('  function assertProjectRuntime() {');
  const end = text.indexOf('  if (modelRuntimeView !== undefined) assertModelRuntime();', start);
  assert(start > 0 && end > start);
  const originalProject = {}, projectOriginal = {}, moon = {}, view = {};
  let projectChecks = 0, modelChecks = 0, retired = false;
  const ports = {project: undefined, projectOriginal: undefined, moon, modelRuntimeClosing: false,
    modelRuntimeView: undefined,
    installedProjectOriginalsForRuntime(project, runtime) {
      projectChecks++; assert.equal(runtime, moon);
      if (project !== originalProject || retired) throw new Error('same Project original refused');
      return projectOriginal;
    },
    clientOperationError(code) {return Object.assign(new Error(code), {code});},
    assertNewModelRuntime() {modelChecks++;},
  };
  const make = change => {
    const selected = {...ports, ...change};
    return Function(...Object.keys(selected), text.slice(start, end) +
      '\nreturn assertProjectRuntime;')(...Object.values(selected));
  };
  make({})(); assert.equal(projectChecks, 0);
  make({project: originalProject, projectOriginal})(); assert.equal(projectChecks, 1);
  assert.throws(make({project: {...originalProject}, projectOriginal}), /same Project original refused/);
  retired = true;
  assert.throws(make({project: originalProject, projectOriginal}), /same Project original refused/);
  assert.throws(make({modelRuntimeClosing: true}), {code: 'ClientHostClosing'});
  make({modelRuntimeView: view})(); assert.equal(modelChecks, 1);
  const originalFailure = new Error('same Model current refusal');
  assert.throws(make({modelRuntimeView: view, assertNewModelRuntime() {throw originalFailure;}}),
    error => error === originalFailure);
});


// Execute the actual common Site method. Its original installation/context
// maps and physical opening port are explicit here; this does not issue a
// Resource, grant, Credential or physical cleanup acknowledgement.
async function effectCredentialSelectionFixture({policy = [65536, 100000, 100]} = {}) {
  const source = await readFile(new URL('./installed-host-services.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('    openRowSite(options) {');
  const end = source.indexOf('\n  });\n  const restoreDeclaration', start);
  assert(start > 0 && end > start);
  const installation = Object.freeze({}), context = Object.freeze({});
  const scope = {installation, role: 'effect', active: true, prepared: {mappings: []}};
  const material = {phase: 'working'};
  const selected = new WeakMap([[installation, 'original runtime']]);
  const sourceContexts = new WeakMap([[context, {scope, material}]]);
  const implementations = new WeakMap(), sites = new WeakMap(), siteInstallations = new WeakMap();
  const moon = Object.freeze({}), events = [], opened = {site: {}}, reader = Object.freeze({});
  let current = true, calls = 0, onPolicy;
  const bindings = {selected, sourceContexts, implementations, sites, siteInstallations, moon,
    sourcePolicy() {assert.equal(this, moon);events.push('policy');onPolicy?.();return policy;},
    publicationOnly: false, root: '/UNOPENED/effect', principalId: 'original principal',
    current() {events.push('current');if (!current) throw new Error('original current failure');},
    requireSourceConstructor(_services, original, fields) {
      assert.equal(original, installation);
      const value = fields.sourceInitialization?.value;
      if (value !== context || !scope.active || material.phase !== 'working') {
        throw Object.assign(new Error('InstalledSourceInitializationUnavailable'),
          {code: 'InstalledSourceInitializationUnavailable'});
      }
      return value;
    },
    installedSourceConfigurationReader: () => reader,
    async openInstalledRowSite(options) {calls++;events.push('open');return {...opened, options};},
    fail(code) {throw Object.assign(new TypeError(code), {code});},
  };
  const nodeTypes = (await import('node:util')).types;
  const services = new Function(...Object.keys(bindings), 'nodeTypes',
    'const services = {' + source.slice(start, end) + '};return services;')(...Object.values(bindings), nodeTypes);
  return {services, installation, context, scope, material, events, reader, opened,
    input: {installation, sourceInitialization: context}, calls: () => calls,
    duringPolicy(callback) {onPolicy = callback;}, stop() {current = false;}};
}

test('Effect Site selects original Core credential implementation bounds before physical construction', async () => {
  const f = await effectCredentialSelectionFixture();
  const opened = await f.services.openRowSite(f.input);
  assert.deepEqual(opened.options.runAcquisitionLimits, {maxBindings: 100000, maxSecretBytes: 65536});
  assert.equal(Object.isFrozen(opened.options.runAcquisitionLimits), true);
  assert.equal(opened.options.sourceInitialization, f.context);
  assert.equal(opened.options.installation, f.installation);
  assert.equal(opened.options.configurationReader, f.reader);
  assert.deepEqual(f.events, ['current', 'policy', 'open']);
  const again = await f.services.openRowSite(f.input);
  assert.equal(again.options.runAcquisitionLimits, opened.options.runAcquisitionLimits);
  assert.equal(f.events.filter(event => event === 'policy').length, 1,
    'immutable implementation bounds are selected once, not re-admitted per operation');
  f.stop();
  assert.throws(() => f.services.openRowSite(f.input), /original current failure/);
  assert.equal(f.calls(), 2);
});

test('Effect Site refuses supplied bounds and invalidated original selection before opening', async () => {
  const f = await effectCredentialSelectionFixture();
  assert.throws(() => f.services.openRowSite({...f.input,
    runAcquisitionLimits: {maxBindings: 1, maxSecretBytes: 1}}),
  {code: 'InstalledEffectCredentialSelectionUnavailable'});
  assert.equal(f.calls(), 0);
  f.duringPolicy(() => {f.scope.active = false;});
  assert.throws(() => f.services.openRowSite(f.input), {code: 'InstalledSourceInitializationUnavailable'});
  assert.equal(f.calls(), 0);
  for (const policy of [undefined, [1, 2], [0, 2, 3], [1, 2.5, 3], [1, 2147483648, 3]]) {
    const invalid = await effectCredentialSelectionFixture({policy: policy ?? null});
    assert.throws(() => invalid.services.openRowSite(invalid.input),
      {code: 'InstalledEffectCredentialPolicyUnavailable'});
    assert.equal(invalid.calls(), 0);
  }
});

test('Source Site preserves its original selected reader bounds without Effect policy selection', async () => {
  const f = await effectCredentialSelectionFixture();f.scope.role = 'source';
  const runAcquisitionLimits = Object.freeze({maxBindings: 37, maxSecretBytes: 19});
  const opened = await f.services.openRowSite({...f.input, runAcquisitionLimits});
  assert.equal(opened.options.runAcquisitionLimits, runAcquisitionLimits);
  assert.deepEqual(f.events, ['current', 'open']);
});


test('Effect Site same-constructor reentry cannot open another binding policy selection', async () => {
  const f = await effectCredentialSelectionFixture({policy: [19, 37, 5]});
  f.duringPolicy(() => {
    assert.throws(() => f.services.openRowSite(f.input),
      {code: 'InstalledEffectCredentialSelectionUnavailable'});
    assert.equal(f.calls(), 0);
  });
  const opened = await f.services.openRowSite(f.input);
  assert.deepEqual(opened.options.runAcquisitionLimits, {maxBindings: 37, maxSecretBytes: 19});
  assert.equal(f.events.filter(event => event === 'policy').length, 1);
  assert.equal(f.calls(), 1);
});

test('Effect Site copied constructor cannot select policy or reach physical opening', async () => {
  const f = await effectCredentialSelectionFixture();
  assert.throws(() => f.services.openRowSite({...f.input,
    sourceInitialization: Object.freeze({...f.context})}),
  {code: 'InstalledSourceInitializationUnavailable'});
  assert.deepEqual(f.events, ['current']);
  assert.equal(f.calls(), 0);
});


test('Source service retains one original request constructor and refuses replacement without a second quote', () => {
  const original = Object.freeze({}), total = Object.freeze({}), calls=[];
  const construction=Object.freeze({capacity:original,maxRequestBytes:512});
  const f=fixture({clientProgramInstalledJsonSourceReaderCapacityWithRequest(limits,columns,secret,request) {
    assert.equal(this,f.moon);assert.deepEqual(limits,values.slice(0,16));assert.equal(columns,3);
    assert.equal(secret,65536);assert.equal(request,original);calls.push(request);return total;
  }});
  retainInstalledHostServiceInstallation(f.services,f.installation,'sha256:'+'a'.repeat(64));
  const policy=f.services.sourceReaderImplementationProfile({installation:f.installation,metadataResponses:3,originUnits:20});
  const input={installation:f.installation,limits:policy,columnCount:3,requestConstruction:construction};
  const selected=f.services.sourceReaderImplementation(input);
  assert.equal(selected.capacity,total);assert.equal(f.services.sourceReaderImplementation(input),selected);
  assert.deepEqual(calls,[original]);assert.deepEqual(f.counts(),[1,0]);
  assert.throws(()=>f.services.sourceReaderImplementation({...input,requestConstruction:Object.freeze({...construction})}),
    {code:'InstalledSourceReaderSelectionChanged'});
  let getters=0;
  assert.throws(()=>f.services.sourceReaderImplementation({...input,requestConstruction:Object.freeze({
    get capacity(){getters++;return original;},maxRequestBytes:512})}),{code:'InvalidInstalledSourceRequestConstruction'});
  assert.equal(getters,0);
});

test('actual standard Source factory forwards the selected constructor request bound before page callbacks', async () => {
  const {parse}=await import('acorn');const source=await readFile(new URL('./installed-host-services.mjs',import.meta.url),'utf8');
  const found=[];const walk=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='createSourceReader')found.push(node);
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);};
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const owner=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name==='createInstalledHostServices');
  assert.ok(owner);walk(owner.declaration);assert.equal(found.length,1);
  const installation={},selection={},site={},originalSite={},capacity={},cid='sha256:'+'a'.repeat(64),calls=[];
  const limits=Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map((name,i)=>[name,values[i]]));
  const implementation={capacity,limits};const record={runtimeBundleCid:cid,value:implementation,
    requestConstruction:Object.freeze({capacity:{},maxRequestBytes:512})};
  const sourceImplementations=new WeakMap([[selection,record]]),selected=new WeakMap([[installation,cid]]),
    siteInstallations=new WeakMap([[site,selection]]),sourceContexts=new WeakMap([[selection,{scope:{}}]]);
  const {types:nodeTypes}=await import('node:util');const factory={capacity};let captured;
  const ports={nodeTypes,publicationOnly:false,current(){calls.push('current');},
    fail:code=>{throw Object.assign(new Error(code),{code});},requireSourceConstructor(){return selection;},
    services:{},sourceImplementations,selected,siteInstallations,sourceContexts,
    installedRowCredentialOperationSite(){return originalSite;},
    createInstalledCredentialSourceReader(options){captured=options;return factory;}};
  const method=Function(...Object.keys(ports),`return ({${source.slice(found[0].start,found[0].end)}}).createSourceReader;`)(...Object.values(ports));
  const preparePageReader=()=>assert.fail('No page callback before original acquisition prepare');
  assert.equal(method({installation,implementation,site,operation:'sheets:grid:read',preparePageReader}),factory);
  assert.equal(captured.maxRequestBytes,512);assert.equal(captured.originalSite,originalSite);
  assert.equal(captured.capacity,capacity);assert.equal(captured.preparePageReader,preparePageReader);
  assert.equal(captured.operation,'sheets:grid:read');assert.deepEqual(calls,['current']);
  assert.throws(()=>method({installation,implementation,site,operation:'sheets:grid:read',preparePageReader}),
    {code:'InstalledSourceReaderAlreadyConstructed'});
});

test('Source service selects the original preserving constructor once without changing generic decoder choice', () => {
  const original=Object.freeze({}),quantity=Object.freeze({}),calls=[];
  const construction=Object.freeze({capacity:original,maxRequestBytes:512});
  const f=fixture({clientProgramInstalledPreservingJsonSourceReaderCapacityWithRequest(limits,columns,secret,request) {
    assert.equal(this,f.moon);assert.deepEqual(limits,values.slice(0,16));assert.equal(columns,3);
    assert.equal(secret,65536);assert.equal(request,original);calls.push(request);return quantity;
  },clientProgramInstalledJsonSourceReaderCapacityWithRequest(){assert.fail('No normalizing constructor for preserving decoder');}});
  retainInstalledHostServiceInstallation(f.services,f.installation,'sha256:'+'a'.repeat(64));
  const policy=f.services.sourceReaderImplementationProfile({installation:f.installation,metadataResponses:3,originUnits:20});
  const input={installation:f.installation,limits:policy,columnCount:3,preservingRequestConstruction:construction};
  const chosen=f.services.sourceReaderImplementation(input);
  assert.equal(chosen.capacity,quantity);assert.equal(f.services.sourceReaderImplementation(input),chosen);
  assert.deepEqual(calls,[original]);assert.deepEqual(f.counts(),[1,0]);
  assert.throws(()=>f.services.sourceReaderImplementation({installation:f.installation,limits:policy,columnCount:3,
    requestConstruction:construction}),{code:'InstalledSourceReaderSelectionChanged'});
  assert.throws(()=>f.services.sourceReaderImplementation({...input,requestConstruction:construction}),
    {code:'InvalidInstalledSourceReaderSelection'});
  assert.deepEqual(calls,[original]);
});

test('Source preserving selection refuses missing native constructor instead of a cheaper or generic fallback', () => {
  const f=fixture();retainInstalledHostServiceInstallation(f.services,f.installation,'sha256:'+'a'.repeat(64));
  const policy=f.services.sourceReaderImplementationProfile({installation:f.installation,metadataResponses:3,originUnits:20});
  assert.throws(()=>f.services.sourceReaderImplementation({installation:f.installation,limits:policy,columnCount:3,
    preservingRequestConstruction:Object.freeze({capacity:{},maxRequestBytes:512})}),
    {code:'InstalledSourceReaderRuntimeUnavailable'});
  assert.deepEqual(f.counts(),[1,0]);
});

test('actual managed Source factory forwards only the same selected query construction bound', async () => {
  const {parse}=await import('acorn');const source=await readFile(new URL('./installed-host-services.mjs',import.meta.url),'utf8');
  const found=[];const walk=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='createSourceReader')found.push(node);
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);};
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const owner=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name==='createInstalledHostServices');
  assert.ok(owner);walk(owner.declaration);assert.equal(found.length,1);
  const installation={},selection={},site={},originalSite={},capacity={},cid='sha256:'+'a'.repeat(64),calls=[];
  const limits=Object.fromEntries(installedJsonSourceReaderProfileLimitNames.map((name,i)=>[name,values[i]]));
  const implementation={capacity,limits};const record={runtimeBundleCid:cid,value:implementation,
    readSequenceConstruction:Object.freeze({capacity,maxQueryBytes:7000,sequence:Object.freeze({children:[]})})};
  const sourceImplementations=new WeakMap([[selection,record]]),selected=new WeakMap([[installation,cid]]),
    siteInstallations=new WeakMap([[site,selection]]),sourceContexts=new WeakMap([[selection,{scope:{}}]]);
  const {types:nodeTypes}=await import('node:util');const factory={capacity};let captured;
  const ports={nodeTypes,publicationOnly:false,current(){calls.push('current');},
    fail:code=>{throw Object.assign(new Error(code),{code});},requireSourceConstructor(){return selection;},
    services:{},sourceImplementations,selected,siteInstallations,sourceContexts,
    installedRowCredentialOperationSite(){return originalSite;},
    createInstalledCredentialSourceReader(options){captured=options;return factory;}};
  const method=Function(...Object.keys(ports),`return ({${source.slice(found[0].start,found[0].end)}}).createSourceReader;`)(...Object.values(ports));
  const prepareReadSequence=()=>assert.fail('No page callback before original acquisition prepare');
  assert.equal(method({installation,implementation,site,prepareReadSequence}),factory);
  assert.equal(captured.maxRequestBytes,undefined);assert.equal(captured.maxQueryBytes,7000);assert.equal(captured.originalSite,originalSite);
  assert.equal(captured.capacity,capacity);assert.equal(captured.prepareReadSequence,prepareReadSequence);
  assert.equal(captured.operation,undefined);assert.deepEqual(calls,['current']);
  assert.throws(()=>method({installation,implementation,site,prepareReadSequence}),
    {code:'InstalledSourceReaderAlreadyConstructed'});
  // A frozen sequence may legally have a prototype. Only the separately
  // validated own data field may reach the actual shared Reader factory.
  let inheritedReads=0;
  const prototype={get maxQueryBytes(){inheritedReads++;return Infinity;}};
  record.readSequenceConstruction=Object.freeze(Object.create(prototype,{
    capacity:{value:capacity},sequence:{value:Object.freeze({children:[]})},
  }));
  sourceContexts.set(selection,{scope:{}});
  assert.equal(method({installation,implementation,site,prepareReadSequence}),factory);
  assert.equal(inheritedReads,0);
  assert.equal(Object.hasOwn(captured,'maxQueryBytes'),false);

});


test('query construction is finite original sequence DATA and never a scalar reader policy override', () => {
  const f=fixture();retainInstalledHostServiceInstallation(f.services,f.installation,'sha256:'+'a'.repeat(64));
  const limits=f.services.sourceReaderImplementationProfile({installation:f.installation,metadataResponses:3,originUnits:20});
  const sequence=Object.freeze({operation:'read',maxUses:1});
  const construction=Object.freeze({capacity:f.capacity,originalLimits:Object.freeze({}),sequence,maxQueryBytes:7000});
  const input={installation:f.installation,limits,columnCount:3,readSequenceConstruction:construction};
  for(const maxQueryBytes of [0,-1,Infinity,2147483648]){
    assert.throws(()=>f.services.sourceReaderImplementation({...input,
      readSequenceConstruction:Object.freeze({...construction,maxQueryBytes})}),{code:'InvalidInstalledSourceSequenceConstruction'});
  }
  assert.throws(()=>f.services.sourceReaderImplementation({...input,limits:{...limits,maxQueryBytes:7000}}),
    {code:'InstalledSourceReaderRequestCapacityUnavailable'});
  const selected=f.services.sourceReaderImplementation(input);assert.equal(selected.capacity,f.capacity);
  assert.throws(()=>f.services.sourceReaderImplementation({...input,
    readSequenceConstruction:Object.freeze({...construction})}),{code:'InstalledSourceReaderSelectionChanged'});
});
