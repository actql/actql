import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import ownerModule from './initial-control-installation-owner.cjs';
import {snapshotInitialControlHostInput} from './initial-control-host-input.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const connect = tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'connectEmbeddedLocal');
const body = connect.body.body.find(node => node.type === 'TryStatement').block.body;
const end = body.findIndex(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(value => value.id.type === 'ObjectPattern' &&
    value.id.properties.some(property => property.type === 'RestElement' && property.argument.name === 'clientOptions')));
assert.ok(end > 0);
const routeSource = source.slice(body[0].start, body[end].end);
const makeRoute = compileFunction('return async function(options) {' +
  'let control,controlClose,duty;const record={};' + routeSource +
  '\nreturn {control,controlClose,duty,record,options,clientOptions,suppliedInstallation,requestedProfile};};',
['beginInitialControlInstallation', 'assertInitialControlInstallationCurrent',
  'readInitialControlInstallationInput', 'originals']);
const limits = Object.freeze({maxProperties: 100, maxNodes: 100, maxDepth: 10,
  maxStringCodeUnits: 100, maxTotalStringCodeUnits: 1000,
  maxArrayItems: 100, maxOpaqueAliases: 20, maxWork: 10000});

// Execute the exact Host intake statements with the real private Owner and
// explicit operational fixture. No selected startup admission, public facade,
// Common runtime, backing-byte supplier or normal Host positive is inferred.
function fixture(raw) {
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
    bundle = snapshotInitialControlHostInput(input, limits);
    return initialized;
  }, readInput(held) {
    assert.equal(this, root); assert.equal(held.host, originals.host);
    reads++; return bundle.packet;
  }, assertCurrent(held) {
    assert.equal(this, root); assert.equal(held.host, originals.host);
    if (!current) throw refused;
  }, close() {closes++; return {pending: false};}};
  const owner = ownerModule.createInitialControlInstallationOwner(root);
  const route = makeRoute(owner.begin, owner.assertCurrent, owner.readInput, originals);
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
