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
function fixture() {
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
    listingPolicy: undefined, prepareAcquisition: undefined, originalReader: {capacity: provider}, site,
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

function calendarImplementationFixture() {
  const installation=Object.freeze({registration:'calendar'}),capacity=Object.freeze({});
  const observed=[];
  const moon={clientProgramInstalledSourceReaderPolicy() {return [65536,100000,100];},
    clientProgramInstalledJsonSourceReaderProfile(metadata,origin) {
      assert.equal(metadata,0);assert.equal(origin,20);return {$tag:1,_0:values.slice()};},
    clientProgramInstalledJsonSourceReaderCapacity(limits,columns,secret) {
      observed.push({limits,columns,secret});return capacity;}};
  const services=createInstalledHostServices({root:'/UNOPENED/calendar',principalId:'fixture',moon,assertCurrent() {}});
  retainInstalledHostServiceInstallation(services,installation,'sha256:'+'c'.repeat(64));
  const policy=services.sourceReaderImplementationProfile({installation,metadataResponses:0,originUnits:20});
  const limits=Object.freeze({maxResponseBytes:1000,maxNodes:64,maxDepth:8,maxPages:2,maxRows:4,
    maxRequests:9,perPage:2,maxCursorUnits:17,maxValueNodes:64,maxValueTextBytes:256,
    maxRowsWireBytes:10000,maxRowsWireNodes:64,maxRowsWireDepth:8,
    maxDeclarationBytes:100000,maxDeclarationNodes:64,maxSecretBytes:64,maxCaBytes:16000000});
  return {services,installation,capacity,policy,limits,observed};
}

test('Calendar original profile selects the same trusted reader implementation without invented fields',() => {
  const f=calendarImplementationFixture();
  const options={installation:f.installation,limits:f.limits,columnCount:4};
  const implementation=f.services.sourceReaderImplementation(options);
  assert.equal(implementation.capacity,f.capacity);
  assert.deepEqual(f.observed,[{limits:[1000,2000,64,8,2,4,2,2,68,256,f.policy.maxTargetBytes,64,256,10000,64,8],columns:4,secret:64}]);
  assert.equal(f.limits.maxRequests,9);assert.equal(f.limits.maxCaBytes,16000000);
  assert.equal(Object.hasOwn(f.limits,'maxTotalResponseBytes'),false);
  assert.equal(Object.hasOwn(f.limits,'maxTargetBytes'),false);
  assert.equal(implementation.limits.maxPages,2);
  assert.equal(f.services.sourceReaderImplementation({...options,limits:{...f.limits}}),implementation);
  assert.equal(f.observed.length,1);
  assert.throws(()=>f.services.sourceReaderImplementation({...options,limits:{...f.limits,maxRequests:8}}),
    {code:'InstalledSourceReaderSelectionChanged'});
});
