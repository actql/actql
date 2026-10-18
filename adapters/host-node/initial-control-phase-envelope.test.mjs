import assert from 'node:assert/strict';
import test from 'node:test';
import module from './initial-control-phase-envelope.cjs';

const original = Object.freeze({node: process.versions.node, v8: process.versions.v8,
  openssl: process.versions.openssl, platform: process.platform, arch: process.arch,
  eager: true, libraries: Object.freeze({...process.versions})});
const inspect = (inventory, heap) => module.inspectInitialControlPhaseEnvelope(inventory,
  module.declareInitialControlPhaseEnvelope(heap), original);
const file = (path, bytes) => ({path, bytes, sha256: '0'.repeat(64)});
const inventory = () => ({engine: original, images: [file('original.cjs', 1024)], dependencies: [],
  packages: [], publicNode: null});
const unavailable = {code: 'NodeInitialControlEnvelopeUnavailable'};

// Accounting DATA only: these cases do not authenticate a startup, supply an
// operational original, demonstrate its native bound or open a real Host.
test('finite disposition includes simultaneous managed, native, compiler and full capture terms', () => {
  const selected = inspect(inventory(), 1024 * 1024);
  assert.equal(selected.declaration.compilerBytes, 2147483648);
  assert.equal(selected.declaration.moduleNativeBytes, 134217728);
  assert.equal(selected.declaration.sourceBackingBytes, 167772160);
  assert.equal(selected.declaration.nativeBytes, 2550136832);
  assert.equal(selected.declaration.preparationExternalBytes, 1214251008);
  assert.equal(selected.declaration.journalExternalBytes, 1114112);
  assert.equal(selected.declaration.bytes, 3934322688);
  assert.equal(selected.limits.generations, 1);
  assert.equal(selected.limits.preparations, 1);
  assert.equal(selected.limits.opaqueCallerAliases, 0);
  assert.deepEqual(selected.declaration.journalInspection, {
    pinnedSourceBytes: 67108864, isolatedCopyBytes: 67108864,
    readBufferBytes: 65536, names: 100000, sequential: true,
    lifetime: 'same-original-physical-child-until-its-close-acknowledgement'});
  assert.equal(selected.declaration.lifetime, 'original-process-and-escaped-module-lifetime');
  assert.ok(Object.isFrozen(selected)); assert.ok(Object.isFrozen(selected.limits));
  assert.equal(selected.begin, undefined); assert.equal(selected.close, undefined);
});

test('ordinary lazy compilation is a separate selected disposition without an eager or second-VM claim', () => {
  const runtime=Object.freeze({...original,eager:false});
  const data={...inventory(),ordinaryEngine:runtime};
  const declaration=module.declareOrdinaryInitialControlPhaseEnvelope(1024*1024);
  const phase=module.inspectOrdinaryInitialControlPhaseEnvelope(data,declaration,runtime);
  assert.equal(phase.declaration.eager,false);
  assert.equal(phase.declaration.compilation,'ordinary-lazy');
  assert.equal(phase.declaration.heapCeilingBytes,1048576);
  assert.equal(phase.declaration.compilerBytes,8589934592);
  assert.equal(phase.declaration.nativeBytes,8992587776);
  assert.equal(phase.declaration.bytes,10376773632);
  assert.equal(phase.declaration.lifetime,'original-process-and-escaped-module-lifetime');
  assert.throws(()=>module.inspectOrdinaryInitialControlPhaseEnvelope(
    {...data,ordinaryEngine:original},declaration,runtime),unavailable);
  assert.throws(()=>module.inspectInitialControlPhaseEnvelope(data,declaration,runtime),unavailable);
});

test('mock definition acquisition adds original Task rereads and answer documents before capture without Model credit', () => {
  const declaration = module.declareInitialControlPhaseEnvelope(1024 * 1024);
  const held = declaration.mockAnswerPreparation;
  assert.equal(held.documents, 128); assert.equal(held.taskRereads, 128);
  assert.equal(held.additionalExternalBytes, 805306368);
  assert.equal(declaration.preparationExternalBytes - held.additionalExternalBytes, 408944640);
  assert.equal(held.coversInvocation, false);
  assert.equal(held.lifetime, 'same-original-preparation-and-all-escaped-definition-aliases');
  assert.deepEqual(held.readLimits, {contractDepth:64,contractNodes:4096,contractTextBytes:65536,
    maxBytes:65536,maxDepth:64,maxEntries:128,maxMembers:256,maxNodes:4096,
    maxTasks:128,maxWork:2097152,valueDepth:64,valueNodes:4096,valueTextBytes:65536});
  assert.ok(Object.isFrozen(held)); assert.ok(Object.isFrozen(held.readLimits));
  assert.equal(declaration.heapCeilingBytes, 1048576);
  assert.equal(declaration.nativeBytes, 2550136832);
});

test('all package/facade images and dependency edges contribute, not just Local sourceBytes', () => {
  const value = inventory();
  value.sourceBytes = 0;
  value.packages = [{images: [file('dependency.mjs', 2048)], dependencies: [{package: 0}]}];
  value.publicNode = {images: [file('index.mjs', 4096)], dependencies: [{local: true}]};
  value.dependencies = [{package: 0}];
  const selected = inspect(value, 1024);
  assert.equal(selected.images, 3); assert.equal(selected.packages, 1);
  assert.equal(selected.sourceBytes, 7168); assert.equal(selected.dependencyEdges, 3);
});

test('actual heap ceiling must fit the selected finite recipe without subtracting current usage', () => {
  for (const bytes of [0, -1, Infinity, NaN, 1.5, 5 * 1024 ** 3 + 1]) {
    assert.throws(() => inspect(inventory(), bytes), unavailable);
  }
  assert.equal(inspect(inventory(), 5 * 1024 ** 3).declaration.heapCeilingBytes, 5 * 1024 ** 3);
});

test('single-file, aggregate-source, path and image counts refuse before image acquisition', () => {
  for (const change of [
    value => {value.images[0].bytes = 64 * 1024 ** 2 + 1;},
    value => {value.images = [file('a', 64 * 1024 ** 2), file('b', 64 * 1024 ** 2), file('c', 1)];},
    value => {value.images[0].path = 'a'.repeat(4097);},
    value => {value.images = Array.from({length: 2049}, (_, index) => file(String(index), 0));},
  ]) {
    const value = inventory(); change(value); assert.throws(() => inspect(value, 1024), unavailable);
  }
});

test('packages and dependency traversal have distinct finite ceilings', () => {
  const packages = inventory();
  packages.packages = Array.from({length: 65}, () => ({images: [], dependencies: []}));
  assert.throws(() => inspect(packages, 1024), unavailable);
  const edges = inventory(); edges.dependencies = Array.from({length: 513}, () => ({}));
  assert.throws(() => inspect(edges, 1024), unavailable);
});

test('image facts are own DATA; a source-size summary or getter cannot replace them', () => {
  let observed = 0;
  const value = inventory();
  Object.defineProperty(value.images[0], 'bytes', {get() {observed++; return 1;}});
  assert.throws(() => inspect(value, 1024), unavailable);
  assert.equal(observed, 0);
  assert.throws(() => inspect({sourceBytes: 1}, 1024), unavailable);
});

test('the selected backend and every actual native library identity must correspond before capture', () => {
  for (const name of ['node', 'v8', 'openssl', 'platform', 'arch', 'eager']) {
    const value = inventory();
    value.engine = {...original, [name]: name === 'eager' ? false : 'foreign'};
    assert.throws(() => inspect(value, 1024), unavailable);
  }
  for (const libraries of [{...original.libraries, sqlite: 'foreign'},
    {...original.libraries, extra: 'unselected'}, {}]) {
    const value = inventory(); value.engine = {...original, libraries};
    assert.throws(() => inspect(value, 1024), unavailable);
  }
  let reads = 0;
  const value = inventory(); value.engine = {...original};
  Object.defineProperty(value.engine, 'v8', {get() {reads++; return original.v8;}});
  assert.throws(() => inspect(value, 1024), unavailable);
  assert.equal(reads, 0);
});

test('manifest alternatives charge the larger exact representation once, not raw bytes or two files', () => {
  const value = inventory();
  value.images = [{...file('package.json', 128), npmRelease: {bytes: 256}}];
  const selected = inspect(value, 1024);
  assert.equal(selected.images, 1); assert.equal(selected.sourceBytes, 256);
  assert.equal(value.images[0].bytes, 128);
  value.images[0].npmRelease.bytes = 64 * 1024 ** 2 + 1;
  assert.throws(() => inspect(value, 1024), unavailable);
  value.images[0] = {...file('original.cjs', 128), npmRelease: {bytes: 256}};
  assert.throws(() => inspect(value, 1024), unavailable);
});

test('a release representation getter cannot be acquired as ordinary image DATA', () => {
  const value = inventory(); let reads = 0;
  value.images = [{...file('package.json', 128)}];
  Object.defineProperty(value.images[0], 'npmRelease', {get() {reads++; return {bytes: 256};}});
  assert.throws(() => inspect(value, 1024), unavailable); assert.equal(reads, 0);
});

test('an invalid original extent refuses before numeric conversion of manifest alternatives', () => {
  const value = inventory(); let conversions = 0;
  value.images = [{path: 'package.json', bytes: {valueOf() {conversions++; return 128;}},
    npmRelease: {bytes: 256}}];
  assert.throws(() => inspect(value, 1024), unavailable);
  assert.equal(conversions, 0);
});
