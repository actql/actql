import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, writeFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {parse} from 'acorn';
import {readOriginalConfigurationBytes, readOriginalConfigurationText,
  captureConfigurationReaders} from './source-profile-json.mjs';
import {createRestSourceMetadata} from './rest-source-metadata.mjs';
import {createInstalledRestSource} from './installed-rest-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {captureInstalledSourceServices} from './installed-host-services.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {restSourcePageReader} from './rest-source-page.mjs';
import {installedJsonSourceReaderLimitNames} from './installed-credential-source-reader.mjs';
import {projectRestConnector} from '../../scripts/connector-authoring.mjs';

const beforePath = process.env.ACTQL_TEST_REST_METADATA_BEFORE;
function selectedMetadata() {
  if (beforePath === undefined) return createRestSourceMetadata;
  const text = readFileSync(beforePath, 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const body = ast.body.filter(node => node.type !== 'ImportDeclaration')
    .map(node => text.slice((node.declaration ?? node).start, node.end)).join('\n');
  return new Function('createHash', 'isAbsolute', 'types', 'checked', 'captureConfigurationReaders',
    body + ';return createRestSourceMetadata;')(
    createHash, isAbsolute, types, checked, captureConfigurationReaders);
}
const definition = {registration: 'explicit-rest', revision: 'one',
  profileVersion: 'actql-installed-explicit-rest/0.1', origin: 'https://explicit.invalid',
  auth: {kind: 'bearer'}, authoredViewsWire: '{"views":[]}', sources: [{resource: 'records',
    fields: [{name: 'id', type: 'string', nullable: false}], read: {path: '/records'},
    pagination: {kind: 'none', items: []}, limits: {maxPageRows: 2, maxPageBytes: 1024,
      maxPages: 2, maxRows: 3, maxNodes: 128, maxDepth: 8, maxCursorBytes: 64}}]};
const profile = {version: definition.profileVersion, connectorId: 'original-rest',
  siteProfilePath: '/explicit/rest-site.json', accountConfigurationWire: '{}'};
const site = {version: 'actql-installed-rest-site/0.1', apiOrigin: definition.origin,
  credentialAuthorityId: 'original-authority', credentialKeyId: 'original-key',
  credentialPrivateKeyPath: '/explicit/key.pem', environment: 'explicit',
  journalRoot: '/explicit/journal', namespaceId: 'original-namespace', siteGeneration: 0,
  siteKey: 'original-site', caPath: '/explicit/ca.pem'};

test('REST CA input retains the original byte reader before configuration await and hashes exact bytes', async () => {
  const metadata = selectedMetadata()(definition), ca = Buffer.from([0xef, 0xbb, 0xbf, 13, 10, 0, 0xff]);
  let release, reads = 0;
  const reader = {readJson: async () => new Promise(done => {release = () => done(site);}),
    readText() {assert.fail('No CA text/default read');},
    async readOriginalBytes(path) {assert.equal(this, reader);assert.equal(path, site.caPath);reads++;return ca;}};
  const pending = metadata.readInputs(profile, {configurationReader: reader});
  reader.readOriginalBytes = () => assert.fail('No replacement method after configuration await');
  release();
  const input = await pending;
  assert.equal(input.ca, ca);assert.equal(reads, 1);
  const changed = await metadata.readInputs(profile, {configurationReader: {
    readJson: async () => site, readText() {}, readOriginalBytes: async () => Buffer.from([0xef, 0xbb, 0xbf, 10, 0, 0xff]),
  }});
  assert.notEqual(input.originalStringsCid, changed.originalStringsCid);
});

test('original byte reader funds the opened FD extent before reading and preserves binary and empty bytes', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-original-ca-'));
  for (const [index, bytes] of [Buffer.from([0xef, 0xbb, 0xbf, 13, 10, 0, 0xff]), Buffer.alloc(0)].entries()) {
    const path = join(directory, String(index));await writeFile(path, bytes);
    let reserved = false, decoded = false, closes = 0, received = 0;
    const operations = new Set(), pending = new Set();
    const io = {
      begin(size) {const operation = {};operations.add(operation);pending.add(operation);return operation;},
      charge(operation, size) {assert(operations.has(operation));received += Number(size);},
      uncertain() {assert.fail('Exact reads require no uncertain transfer');},
      finish(operation) {assert(pending.delete(operation));},
    };
    const value = await readOriginalConfigurationBytes(path, {io,
      beforeRead(size) {assert.equal(size, bytes.length);reserved = true;},
      beforeDecode(size) {assert(reserved);assert.equal(size, bytes.length);decoded = true;},
      async openFile(name, flags) {
        const handle = await open(name, flags);
        return {stat: () => handle.stat(),
          async read(...args) {assert(reserved);return handle.read(...args);},
          async close() {closes++;await handle.close();}};
      }});
    assert(Buffer.isBuffer(value));assert.deepEqual(value, bytes);assert(decoded);
    assert.equal(closes, 1);assert.equal(received, bytes.length);assert.equal(pending.size, 0);
  }
});

test('original byte reader rejects growth and reservation failure on the same opened handle', async () => {
  const failure = new Error('same-parent-reservation-refusal');
  for (const rejectBeforeRead of [true, false]) {
    let reads = 0, closes = 0, position = 0;
    const result = readOriginalConfigurationBytes('/explicit/original', {
      beforeRead(size) {assert.equal(size, 2);if (rejectBeforeRead) throw failure;},
      beforeDecode() {assert.fail('No output from refused or grown original');},
      async openFile() {return {stat: async () => ({size: 2}),
        async read(buffer, offset, length) {
          reads++;const count = Math.min(length, 3 - position);buffer.fill(0x61, offset, offset + count);position += count;return {bytesRead: count};
        }, async close() {closes++;}};},
    });
    await assert.rejects(result, cause => rejectBeforeRead ? cause === failure : cause.message === 'InvalidInstalledSourceProfile');
    assert.equal(closes, 1);assert.equal(reads, rejectBeforeRead ? 0 : 1);
  }
});

test('REST without CA preserves its original identity and absent byte-reader path', async () => {
  const metadata = createRestSourceMetadata(definition), plain = {...site};delete plain.caPath;
  const input = await metadata.readInputs(profile, {configurationReader: {readJson: async () => plain, readText() {}}});
  const expected = [JSON.stringify(definition), ...['version','connectorId','siteProfilePath','accountConfigurationWire'].map(key => profile[key]),
    ...['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath','environment','journalRoot','namespaceId','siteGeneration','siteKey'].map(key => plain[key])];
  assert.equal(input.ca, undefined);
  assert.equal(input.originalStringsCid, 'sha256:' + createHash('sha256').update(JSON.stringify(expected)).digest('hex'));
  await assert.rejects(metadata.readInputs(profile, {configurationReader: {readJson: async () => site, readText() {}}}),
    {code: 'RestSourceTlsAuthorityPolicyUnavailable'});
});

test('REST factory forwards the same managed CA bytes to its original Site service', async () => {
  const ca = Buffer.from('original CA\r\n'), sentinel = new Error('original-Site-sentinel');
  const policy = {maxRows: 4, maxResponseBytes: 2048, maxPages: 4, maxTotalRows: 8,
    maxNodes: 256, maxDepth: 16, maxCursorBytes: 128, maxTotalResponseBytes: 8192,
    pageSize: 4, maxIdentityBytes: 128, maxTargetBytes: 1024, maxValueNodes: 256,
    maxValueTextBytes: 2048, maxRowsWireBytes: 8192, maxRowsWireNodes: 512,
    maxRowsWireDepth: 32, maxSecretBytes: 1024};
  const installation = {}, sourceInitialization = {prepareAuthoredDeclaration(wire) {
    assert.equal(this, sourceInitialization);assert.equal(wire, definition.authoredViewsWire);
    return {declaration: {}, declared: {views: [{fields: ['id']}]}, environment: {wire: 'original'}};
  }};
  const services = {
    sourceReaderImplementationProfile() {return policy;},
    sourceReaderImplementation() {return {capacity: {}, runAcquisitionLimits: {}};},
    async openRowSite(input) {
      assert.equal(this, services);assert.equal(input.ca, ca);assert.equal(input.installation, installation);
      assert.equal(input.sourceInitialization, sourceInitialization);throw sentinel;
    }, createSourceReader() {assert.fail('No Reader before original Site');},
  };
  await assert.rejects(createInstalledRestSource(definition).load(profile, {installationServices: services,
    sourceInitialization, installation, moon: {}, resolveSecret() {},
    configurationReader: {readJson: async () => site, readText() {}, readOriginalBytes: async () => ca}}),
    cause => cause === sentinel);
});

test('original text reader retains its prior UTF8 projection and opened-FD refusal duties', async () => {
  const bytes = Buffer.from('original text\r\né'), pending = [];
  let position = 0, closes = 0;
  const value = await readOriginalConfigurationText('/explicit/text', {
    beforeRead(size) {assert.equal(size, bytes.length);pending.push('extent');},
    beforeDecode(size) {assert.equal(size, bytes.length);pending.push('projection');},
    async openFile() {return {stat: async () => ({size: bytes.length}),
      async read(buffer, offset, length) {
        assert(pending.includes('extent'));
        const count = Math.min(length, bytes.length - position);
        bytes.copy(buffer, offset, position, position + count);position += count;return {bytesRead: count};
      }, async close() {closes++;}};},
  });
  assert.equal(value, 'original text\r\né');assert.deepEqual(pending, ['extent', 'projection']);assert.equal(closes, 1);
});

// Actual factory body and existing pure dependencies, with only the final
// row-source construction port replaced. This proves caller selection DATA,
// not C's private construction/funding, a Site or an ordinary public Host.
function demandFactory(finalConstructor) {
  const text = readFileSync(new URL('./installed-rest-source.mjs', import.meta.url), 'utf8');
  const body = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .filter(node => node.type !== 'ImportDeclaration')
    .map(node => text.slice((node.declaration ?? node).start, node.end)).join('\n');
  return new Function('createHash', 'types', 'canonicalJson', 'captureInstalledSourceServices',
    'createInstalledRowSource', 'retainInstalledHostInitializationFailure', 'createRestSourceMetadata',
    'restSourcePageReader', 'installedJsonSourceReaderLimitNames', body + ';return createInstalledRestSource;')(
    createHash, types, canonicalJson, captureInstalledSourceServices, finalConstructor,
    retainInstalledHostInitializationFailure, createRestSourceMetadata, restSourcePageReader,
    installedJsonSourceReaderLimitNames);
}

function demandFixture(authored) {
  const generated = projectRestConnector(authored);
  const definition = JSON.parse(generated.files[`src/connectors/${authored.id}/rest-source.json`]);
  // Original selected standard profile, from installed_source_reader_profile
  // and its standard record/Client policies. These are rejection bounds only.
  const policy = Object.freeze({maxResponseBytes: 1000000, maxTotalResponseBytes: 100000000,
    maxNodes: 100000, maxDepth: 64, maxRows: 100, maxTotalRows: 100, maxPages: 100,
    pageSize: 100, maxCursorBytes: 4000000, maxIdentityBytes: 1000000,
    maxTargetBytes: authored.origin.length + 9180428, maxValueNodes: 10000,
    maxValueTextBytes: 1000000, maxRowsWireBytes: 10000000, maxRowsWireNodes: 100000,
    maxRowsWireDepth: 100, maxColumns: 100, maxProperties: 10000, maxNameUnits: 10000,
    maxObjects: 1024, maxDeclarationBytes: 10000000, maxDeclarationNodes: 100000,
    maxSecretBytes: 65536});
  const profile = {version: generated.profileVersion, connectorId: 'selected-rest',
    siteProfilePath: '/UNOPENED/selected-site.json', accountConfigurationWire: '{}'};
  const selectedSite = {...site, apiOrigin: authored.origin};delete selectedSite.caPath;
  return {definition, policy, profile, selectedSite};
}

async function observeDemand(f) {
  let implementation, rowSource, siteInput, siteCalls = 0;
  const capacity = {}, prepared = {declaration: {}, declared: {catalog_cid: 'authored-catalog',
    views: f.definition.sources.map(source => ({resource: source.resource,
      fields: source.fields.map(field => field.name)}))}, environment: {wire: 'original-environment'}};
  const initialization = {prepareAuthoredDeclaration(wire) {
    assert.equal(wire, f.definition.authoredViewsWire);return prepared;
  }};
  const services = {
    sourceReaderImplementationProfile() {return f.policy;},
    sourceReaderImplementation(input) {implementation = input;
      return {capacity, limits: input.limits, runAcquisitionLimits: {}};},
    async openRowSite(input) {siteInput=input;siteCalls++;return {site: {}, authorization: {context: {contextCid: 'authored-context'}}};},
    createSourceReader(input) {assert.equal(input.implementation.capacity, capacity);return {capacity};},
  };
  const moon = Object.fromEntries(['ProjectJsonPage', 'JsonPageRowsWire', 'JsonPageRowCount',
    'JsonPageHasNextCursor', 'JsonPageNextCursor'].map(name => ['clientProgramRowSource'+name,
    () => assert.fail('No page/decoder call in a selection-only component')]));
  const create = demandFactory(async options => {rowSource = options;return 'selected-source-port';});
  const run = () => create(f.definition).load(f.profile, {installationServices: services,
    sourceInitialization: initialization, installation: {}, moon, resolveSecret() {},
    configurationReader: {readJson: async () => f.selectedSite, readText() {assert.fail('No physical read');}}});
  return {run, observations: () => ({implementation, rowSource, siteInput, siteCalls, prepared})};
}

test('standard REST supplies exact immutable target DATA while approval keeps its complete matcher', async () => {
  const authored=JSON.parse(readFileSync(new URL('../../scripts/fixtures/external-rest/connector.json',import.meta.url)));
  const f=demandFixture(authored),probe=await observeDemand(f);await probe.run();
  const {rowSource,siteInput,prepared}=probe.observations();
  const input=await createRestSourceMetadata(f.definition).readInputs(f.profile,{configurationReader:{
    readJson:async()=>f.selectedSite,readText(){assert.fail('No physical read');}}});
  assert(Object.isFrozen(rowSource.physicalTarget));
  assert.equal(rowSource.physicalTarget.length,f.definition.sources.length);
  for(const [index,target] of rowSource.physicalTarget.entries()){
    const source=f.definition.sources[index],fields=source.fields.map(field=>field.name);
    assert.deepEqual(target,{connectorRegistration:f.definition.registration,connectorRevision:f.definition.revision,
      catalogCid:prepared.declared.catalog_cid,originalStringsCid:input.originalStringsCid,
      origin:f.definition.origin,path:source.read.path,resource:source.resource,fields});
    assert(Object.isFrozen(target));assert(Object.isFrozen(target.fields));
    assert.equal(siteInput.admitsApprovalTarget(target,source.resource),true);
    assert.equal(siteInput.admitsApprovalTarget({...target,path:'/foreign'},source.resource),false);
    assert.equal(siteInput.admitsApprovalTarget({...target,fields:fields.slice(0,1)},source.resource),true);
    assert.throws(()=>siteInput.admitsApprovalTarget({...target,fields:['undeclared']},source.resource),
      {code:'RestSourceReadTargetMismatch'});
  }
});

test('REST factory selects the same validated authored demand for implementation and Source', async () => {
  const authored = JSON.parse(readFileSync(new URL('../../scripts/fixtures/external-rest/connector.json', import.meta.url)));
  for (const multiple of [false, true]) {
    const selected = structuredClone(authored);
    if (multiple) selected.sources.other = {...structuredClone(selected.sources.customers),
      limits: {maxPageRows: 3, maxPageBytes: 512, maxPages: 4, maxRows: 7,
        maxNodes: 128, maxDepth: 8, maxCursorBytes: 64}};
    const f = demandFixture(selected), probe = await observeDemand(f);
    assert.equal(await probe.run(), 'selected-source-port');
    const {implementation, rowSource, prepared} = probe.observations();
    const expected = multiple ? {maxPages: 4, maxPageBytes: 512, maxPageRows: 3, maxCaptureRows: 7}
      : {maxPages: 3, maxPageBytes: 256, maxPageRows: 2, maxCaptureRows: 4};
    assert.deepEqual(rowSource.limits, expected);
    const parserBounds = multiple ? {maxNodes: 128, maxDepth: 8} : {maxNodes: 64, maxDepth: 6};
    const selectedFields = {maxPages: expected.maxPages, maxResponseBytes: expected.maxPageBytes,
      maxRows: expected.maxPageRows, maxTotalRows: expected.maxCaptureRows,
      ...parserBounds, maxCursorBytes: multiple ? 64 : 32};
    for (const [name,value] of Object.entries(selectedFields))assert.equal(implementation.limits[name], value);
    assert.equal(Object.hasOwn(rowSource, 'originalPageLimits'), false);
    assert.equal(Object.hasOwn(rowSource, 'prepareSourceRead'), false);
    for (const name of [...installedJsonSourceReaderLimitNames, 'maxSecretBytes'])
      if (!Object.hasOwn(selectedFields, name))assert.equal(implementation.limits[name], f.policy[name]);
    assert.strictEqual(rowSource.declaration, prepared.declaration);
    assert.strictEqual(rowSource.declared, prepared.declared);assert.strictEqual(rowSource.environment, prepared.environment);
  }
});

test('REST authored bounds still refuse above any selected policy before implementation or Site', async () => {
  const authored = JSON.parse(readFileSync(new URL('../../scripts/fixtures/external-rest/connector.json', import.meta.url)));
  const names = {maxPageRows: 'maxRows', maxPageBytes: 'maxResponseBytes', maxPages: 'maxPages',
    maxRows: 'maxTotalRows', maxNodes: 'maxNodes', maxDepth: 'maxDepth', maxCursorBytes: 'maxCursorBytes'};
  for (const [authorName,policyName] of Object.entries(names)) {
    const selected = structuredClone(authored), policy = demandFixture(selected).policy;
    selected.sources.customers.limits[authorName] = policy[policyName] + 1;
    if (authorName === 'maxPageRows')selected.sources.customers.limits.maxRows = policy.maxTotalRows + 1;
    const probe = await observeDemand(demandFixture(selected));
    await assert.rejects(probe.run(), {code: 'RestSourceImplementationBoundsExceeded'});
    assert.equal(probe.observations().implementation, undefined);assert.equal(probe.observations().siteCalls, 0);
  }
});
