import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {resolve} from 'node:path';
import test from 'node:test';
import {parse} from 'acorn';
import ownerModule from './initial-control-installation-owner.cjs';
import {snapshotInitialControlHostInput} from './initial-control-host-input.mjs';
import {retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const connect = tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openPreparedInstalledHost');
const body = connect.body.body.find(node => node.type === 'TryStatement').block.body;
const end = body.findIndex(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(value => value.id.type === 'ObjectPattern' &&
    value.id.properties.some(property => property.type === 'RestElement' && property.argument.name === 'clientOptions')));
assert.ok(end > 0);
const remote = body.find(node => node.type === 'IfStatement' &&
  source.slice(node.test.start, node.test.end) === "initialEntry === 'remote'");
const routeSource = source.slice(body[0].start, remote.start) +
  source.slice(remote.end, body[end].end);
const makeRoute = compileFunction('return async function(options, initialEntry) {' +
  'let control,controlClose,duty;const record={};' + routeSource +
  '\nreturn {control,controlClose,duty,record,options,clientOptions,suppliedInstallation,requestedProfile};};',
['beginInitialControlInstallation', 'assertInitialControlInstallationCurrent',
  'readInitialControlInstallationInput', 'originals', 'resolve', 'clientOperationError']);
const limits = Object.freeze({maxProperties: 100, maxNodes: 100, maxDepth: 10,
  maxStringCodeUnits: 100, maxTotalStringCodeUnits: 1000,
  maxArrayItems: 100, maxOpaqueAliases: 20, maxWork: 10000});

// Execute the exact Host intake statements with the real private Owner and
// explicit operational fixture. No selected startup admission, public facade,
// Common runtime, backing-byte supplier or normal Host positive is inferred.
function fixture(raw, {packet = raw, path = resolve} = {}) {
  const originals = Object.freeze({host: {}, installation: {}, generation: {},
    supplier() {}, moduleLifetime: {}});
  let bundle, resolve, current = true, prepares = 0, reads = 0, closes = 0;
  const initialized = new Promise(done => { resolve = done; });
  const refused = Object.freeze(new Error('OriginalInputCurrentRefused'));
  const root = {prepare(held, input) {
    assert.equal(this, root); assert.equal(input, raw); assert.equal(held.host, originals.host);
    prepares++;
    // Only the explicit fixture owns this acquisition condition. Real selected
    // coverage must exist BEFORE this reader's first reflection/allocation.
    bundle = snapshotInitialControlHostInput(packet, limits);
    return initialized;
  }, readInput(held) {
    assert.equal(this, root); assert.equal(held.host, originals.host);
    reads++; return bundle.packet;
  }, assertCurrent(held) {
    assert.equal(this, root); assert.equal(held.host, originals.host);
    if (!current) throw refused;
  }, close() {closes++; return {pending: false};}};
  const owner = ownerModule.createInitialControlInstallationOwner(root);
  const route = makeRoute(owner.begin, owner.assertCurrent, owner.readInput, originals, path,
    code => Object.assign(new Error(code), {code}));
  return {route, owner, originals, refused, finish: resolve,
    stale() {current = false;}, get bundle() {return bundle;},
    get prepares() {return prepares;}, get reads() {return reads;}, get closes() {return closes;}};
}

test('Host passes raw input before awaiting and consumes only the same captured packet afterwards', async () => {
  const callback = () => {}, authorization = Object.freeze({});
  const raw = {mode: 'local', owner: 'local', profile: 'original', consentRefs: ['original'],
    installation: {directory: 'original', authorization, resolveSourceSecret: callback}};
  const f = fixture(raw), pending = f.route(raw);
  assert.equal(f.prepares, 1); assert.equal(f.reads, 0);
  raw.profile = 'replacement'; raw.consentRefs[0] = 'replacement';
  raw.installation = {directory: 'replacement'};
  f.finish(); const result = await pending;
  assert.equal(result.options, f.bundle.packet); assert.equal(result.record.input, result.options);
  assert.equal(result.requestedProfile, 'original');
  assert.deepEqual(result.clientOptions.consentRefs, ['original']);
  assert.equal(result.suppliedInstallation.directory, 'original');
  assert.equal(result.suppliedInstallation.authorization, authorization);
  assert.equal(result.suppliedInstallation.resolveSourceSecret, callback);
  assert.equal(f.reads, 1);
  assert.equal((await result.control.close()).pending, true);
  assert.equal(f.closes, 0); assert.equal(result.record.input, result.options);
  result.record.input = undefined; result.duty.releaseReferences(result.record);
  assert.equal((await result.control.close()).pending, false); assert.equal(f.closes, 1);
});

test('omitted open enters the same original begin before path selection and keeps its call-time path', async () => {
  let selected = '/original', paths = 0;
  const f = fixture(undefined, {packet: {}, path(...values) {
    assert.equal(f.prepares, 1); paths++;
    if (values.length === 1) {assert.equal(values[0], '.'); return selected;}
    return resolve(...values);
  }});
  const pending = f.route(undefined, 'open');
  assert.equal(f.prepares, 1); assert.equal(paths, 1); assert.equal(f.reads, 0);
  selected = '/replacement';
  f.finish(); const result = await pending;
  assert.equal(paths, 2); assert.equal(f.reads, 1);
  assert.equal(result.record.input, f.bundle.packet);
  assert.deepEqual(result.record.input, {});
  assert.equal(result.record.openOptions, result.options);
  assert.deepEqual(result.clientOptions, {mode: 'local', owner: 'local'});
  assert.deepEqual({...result.suppliedInstallation}, {directory: '/original/.actql'});
  assert.equal(Object.getPrototypeOf(result.suppliedInstallation), null);
  assert.equal((await result.control.close()).pending, true);
  assert.equal(f.closes, 0);
  for (const name of Object.keys(result.record)) result.record[name] = undefined;
  result.duty.releaseReferences(result.record);
  assert.equal((await result.control.close()).pending, false);
  assert.equal(f.closes, 1);
});

test('explicit open keeps original stateDir, installation and consent across initialization', async () => {
  let cwd = '/original';
  const raw = {stateDir: '.explorer', durability: 'durable', consentRefs: ['original'],
    installation: {observation: Object.freeze({original: true})}};
  const f = fixture(raw, {path(...values) {return values.length === 1 ? cwd : resolve(...values);}});
  const pending = f.route(raw, 'open');
  assert.equal(f.prepares, 1); assert.equal(f.reads, 0);
  raw.stateDir = '.replacement'; raw.consentRefs[0] = 'replacement';
  raw.installation = {}; cwd = '/replacement';
  f.finish(); const result = await pending;
  assert.equal(result.record.input, f.bundle.packet);
  assert.equal(result.suppliedInstallation.directory, '/original/.explorer');
  assert.equal(result.suppliedInstallation.observation, f.bundle.packet.installation.observation);
  assert.deepEqual(result.clientOptions, {mode: 'local', owner: 'local',
    durability: 'durable', consentRefs: ['original']});
  assert.equal(Object.hasOwn(result.clientOptions, 'stateDir'), false);
  assert.equal(Object.hasOwn(result.clientOptions, 'profile'), false);
  assert.equal(result.record.openOptions, result.options);
});

test('explicit captured open retains existing closed fields and type refusals', async () => {
  for (const raw of [{unknown: true}, {stateDir: ''}, {stateDir: 1},
    {installation: null}, {installation: []}, {installation: {directory: '/foreign'}}]) {
    const f = fixture(raw), pending = f.route(raw, 'open'); f.finish();
    await assert.rejects(pending, {code: 'InvalidOpenOptions'});
    assert.equal(f.prepares, 1); assert.equal(f.reads, 1); assert.equal(f.closes, 0);
  }
});

test('captured open refuses inherited options added during initialization without reading them', async () => {
  for (const name of ['stateDir', 'installation', 'durability', 'consentRefs']) {
    const raw = name === 'stateDir' ? {} : {stateDir: '.explorer'};
    const f = fixture(raw), pending = f.route(raw, 'open');
    assert.equal(f.prepares, 1); assert.equal(f.reads, 0);
    assert.equal(Object.hasOwn(f.bundle.packet, name), false);
    let reads = 0;
    assert.equal(Object.getOwnPropertyDescriptor(Object.prototype, name), undefined);
    Object.defineProperty(Object.prototype, name, {configurable: true,
      get() {reads++; throw new Error('UnownedOpenGetter');}});
    try {
      f.finish(); await assert.rejects(pending, {code: 'NodeInitialControlInputUnavailable'});
      assert.equal(reads, 0);
    } finally { delete Object.prototype[name]; }
    assert.equal(f.reads, 1); assert.equal(f.closes, 0);
  }
});

test('captured open projection never borrows later inherited profile or installation values', async () => {
  const raw = {stateDir: '.explorer', installation: {}};
  const f = fixture(raw), pending = f.route(raw, 'open');
  let reads = 0;
  for (const name of ['profile', 'authorization']) {
    assert.equal(Object.getOwnPropertyDescriptor(Object.prototype, name), undefined);
    Object.defineProperty(Object.prototype, name, {configurable: true,
      get() {reads++; throw new Error('UnownedProjectionGetter');}});
  }
  try {
    f.finish(); const result = await pending;
    assert.equal(result.requestedProfile, undefined);
    assert.equal(result.suppliedInstallation.authorization, undefined);
    assert.equal(Object.hasOwn(result.clientOptions, 'profile'), false);
    assert.equal(Object.getPrototypeOf(result.options), null);
    assert.equal(Object.getPrototypeOf(result.suppliedInstallation), null);
    assert.equal(reads, 0);
  } finally {
    delete Object.prototype.profile; delete Object.prototype.authorization;
  }
});

test('open never drops fields from a nonempty supplier packet', async () => {
  const f = fixture(undefined, {packet: {unknown: 'original'}});
  const pending = f.route(undefined, 'open'); f.finish();
  await assert.rejects(pending, {code: 'NodeInitialControlOriginalChanged'});
  assert.equal(f.bundle.packet.unknown, 'original');
  assert.equal(f.prepares, 1); assert.equal(f.reads, 1); assert.equal(f.closes, 0);
});

test('open path refusal does not abandon the original initialization or replace its cause', async () => {
  const cause = Object.freeze(new Error('OriginalPathRefused'));
  const f = fixture(undefined, {packet: {}, path() {throw cause;}});
  let settled = false;
  const pending = f.route(undefined, 'open').finally(() => {settled = true;});
  await Promise.resolve(); assert.equal(settled, false); assert.equal(f.reads, 0);
  f.finish(); await assert.rejects(pending, error => error === cause);
  assert.equal(f.prepares, 1); assert.equal(f.reads, 1); assert.equal(f.closes, 0);
});

test('the selected Host consumer forwards admitted connect and open without a raw observation', async () => {
  const consumer = tree.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'connectInitialControlHostPreparation');
  assert.ok(consumer);
  let observations = 0, connects = 0;
  const raw = new Proxy({}, {get() {observations++;}, ownKeys() {observations++;}});
  const originalPromise = Promise.resolve(Object.freeze({originalClient: true}));
  const route = compileFunction(source.slice(consumer.body.start + 1, consumer.body.end - 1),
    ['kind', 'rawInput', 'connectEmbeddedLocal', 'clientOperationError']);
  const connect = (input, entry) => {
    connects++;
    assert.ok(entry === 'open' || entry === 'connect');
    assert.ok(input === raw || entry === 'open' && (input === undefined || input === null));
    return originalPromise;
  };
  const error = code => Object.assign(new Error(code), {code});
  for (const [kind, input] of [['foreign', undefined]]) {
    assert.throws(() => route(kind, input, connect, error), {code: 'NodeInitialControlInputUnavailable'});
  }
  assert.equal(observations, 0); assert.equal(connects, 0);
  assert.equal(route('open', undefined, connect, error), originalPromise);
  assert.equal(route('open', raw, connect, error), originalPromise);
  assert.equal(route('open', null, connect, error), originalPromise);
  assert.equal(route('connect', raw, connect, error), originalPromise);
  assert.equal(connects, 4); assert.equal(observations, 0);
});

test('selected connect defaults only the admitted omitted owner and retains call-time installation', async () => {
  const raw = {mode: 'local', installation: {directory: '.actql'}, profile: 'mock'};
  const f = fixture(raw), pending = f.route(raw, 'connect');
  assert.equal(f.prepares, 1); assert.equal(f.reads, 0);
  raw.installation.directory = 'replacement'; raw.profile = 'replacement';
  f.finish();
  const result = await pending;
  assert.equal(result.clientOptions.owner, 'local');
  assert.equal(result.clientOptions.mode, 'local');
  assert.equal(result.requestedProfile, 'mock');
  assert.equal(result.suppliedInstallation.directory, '.actql');
  assert.equal(result.record.connectOptions, result.options);
  assert.equal(result.record.input, f.bundle.packet);
});

test('failed original initialization retains the open path aliases until its original cleanup confirms', async () => {
  const retire = connect.body.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'retirePreparationReferences');
  const caught = connect.body.body.find(node => node.type === 'TryStatement').handler.body;
  assert.ok(retire); assert.ok(caught);
  const record = {openStateDirectory: '/original/.actql',
    openPathFailure: {cause: Object.freeze(new Error('OriginalPathRefused'))}};
  let closed = false, retries = 0, retirements = 0;
  const originalInstallation = {}, host = {}, profiles = {retainedMockPreparation(h, i, generation) {
    assert.equal(h, host); assert.equal(i, originalInstallation); assert.equal(generation, host);
  }, retirePreparation(h, i, generation) {
    assert.equal(h, host); assert.equal(i, originalInstallation); assert.equal(generation, host);
    retirements++;
  }};
  const retireReferences = compileFunction(
    'let referencesRetired=false,referenceRetirement,mockPreparation,projectProfile,project,moon,duty,' +
    'mockAnswers,mockModelProfile,mockModelProfileRetire,mockModelFlight;' +
    source.slice(retire.start, retire.end) + '\nreturn retirePreparationReferences;',
    ['record', 'originalInstallation', 'profiles', 'host']) (record, originalInstallation, profiles, host);
  const caughtFailure = compileFunction('return async function(cause){' +
    'const adopted=false,observedClose=undefined,control=undefined;' +
    source.slice(caught.start + 1, caught.end - 1) + '\n};',
    ['retainInstalledHostRuntimeFailure', 'retirePreparationReferences', 'profiles',
      'host', 'originalInstallation'])
    (retainInstalledHostRuntimeFailure, retireReferences, profiles, host, originalInstallation);
  const cleanupHandle = Object.freeze({status() {return {pending: !closed};},
    retry() {retries++;}});
  const cause = Object.freeze(Object.assign(new Error('OriginalPrepareUnknown'), {cleanupHandle}));
  let failure;
  await assert.rejects(caughtFailure(cause), value => {
    failure = value; return value.primaryFailure === cause && value.cleanupHandle.status().pending;
  });
  assert.equal(record.openStateDirectory, '/original/.actql');
  assert.equal(record.openPathFailure.cause.message, 'OriginalPathRefused');
  assert.equal(retries, 0); assert.equal(retirements, 0);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(retries, 1); assert.equal(retirements, 0);
  assert.equal(record.openStateDirectory, '/original/.actql');
  closed = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retirements, 1); assert.equal(retries, 1);
  assert.deepEqual(record, {openStateDirectory: undefined, openPathFailure: undefined});
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retirements, 1);
});

test('unavailable original refuses the actual Host intake before any raw Proxy observation', async () => {
  let observations = 0;
  const raw = new Proxy({}, {get() {observations++;}, ownKeys() {observations++;},
    getOwnPropertyDescriptor() {observations++;}, getPrototypeOf() {observations++;}});
  const owner = ownerModule.createInitialControlInstallationOwner(undefined);
  const route = makeRoute(owner.begin, owner.assertCurrent, owner.readInput, {});
  await assert.rejects(route(raw), {code: 'NodeInitialControlAdmissionUnavailable'});
  assert.equal(observations, 0);
});

test('current refusal after initialization prevents the original packet from reaching Host copies', async () => {
  const raw = {mode: 'local', installation: {directory: 'original'}};
  const f = fixture(raw), pending = f.route(raw);
  f.stale(); f.finish();
  await assert.rejects(pending, error => error === f.refused);
  assert.equal(f.prepares, 1); assert.equal(f.reads, 0); assert.equal(f.closes, 0);
  assert.equal(f.bundle.packet.installation.directory, 'original');
  assert.throws(() => f.owner.begin(f.originals, raw), {code: 'NodeInitialControlOriginalChanged'});
});

test('a missing input original never falls back to rereading the raw caller', async () => {
  let rawReads = 0;
  const raw = Object.defineProperty({}, 'installation', {get() {rawReads++; throw new Error('CallerRead');}});
  const owner = ownerModule.createInitialControlInstallationOwner({
    prepare() {}, assertCurrent() {}, close() {return {pending: false};}});
  const originals = {host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}};
  const route = makeRoute(owner.begin, owner.assertCurrent, owner.readInput, originals);
  await assert.rejects(route(raw), {code: 'NodeInitialControlInputUnavailable'});
  assert.equal(rawReads, 0);
});
