import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { fieldLayout } from '../backing/native-extent.mjs';
import { checkCurrentConstructionSourceReview } from './provider-construction-current-review.mjs';
const profile = JSON.parse(readFileSync(new URL('./provider-construction-current.json', import.meta.url)));
export function providerConstructionBound(read) {
  assert.equal(profile.version, 'actql-native-provider-construction/0.1');
  const sourceReview = checkCurrentConstructionSourceReview(profile, read);
  for (const p of profile.providers) {
    const source = read(p.path).toString();
    assert.equal(hash(source), p.sourceDigest, `Unreviewed provider constructor ${p.name}`);
    const constructor = source.slice(source.indexOf(`fn ${p.name}(`));
    assert(constructor.includes(`${p.binding}(`), `Changed provider binding ${p.name}`);
  }
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
  const list = source.match(/for\s+provider in \[([\s\S]*?)\]\s*\{/);
  assert(list);
  assert.deepEqual([...list[1].matchAll(/\b(\w+_provider)\(/g)].map(m => m[1]), profile.providers.map(p => p.name));
  assert.deepEqual(profile.bounds, { providerRecords: 11, callbacksPerProvider: 4,
    callbackReferenceCaptures: 3, defaultFamilyArrays: 1, candidateArraySlots: 11 });
  const record = 8 + fieldLayout(Array(4).fill('ref')).payloadBytes;
  // One code pointer and at most three captures. It has pointer width but is
  // not a GC reference. Noncapturing callbacks can be static, contributing zero
  // newly owned bytes. Shared callback identities also count only once.
  const callback = 8 + fieldLayout(Array(4).fill('ref')).payloadBytes;
  const candidates = 24 + 8 + 8 * profile.bounds.candidateArraySlots;
  const family = 24; // Array owner; its zero-length backing is process-static.
  const bytes = profile.bounds.providerRecords * (record + 4 * callback) + candidates + family;
  assert.equal(bytes, 2344);
  return { subject: profile.scope, sourceReview, providerCount: 11, recordBytes: record, callbackBytes: callback,
    callbackCount: 44, candidateContainerBytes: candidates, defaultFamilyBytes: family, bytes,
    unit: 'conditional pinned native requested header and payload bytes',
    premises: ['four pointer-sized ManagedProvider fields',
      'at most four source/compatibility callbacks per provider, each with code pointer and at most three reference captures',
      'dynamic scalar callbacks have code-pointer-only payloads; native GC descriptors alone do not prove this request extent',
      'optional callback is nullable, without a separate option wrapper',
      'one selected constructor default family array, with static empty backing',
      'candidate array literal has eleven backing slots',
      'borrowed limits, measurement, family and caller configuration are accounted by their original owners'],
    unresolved: ['compiled scalar callback payload extents are not established by the source census alone',
      'constructor lifetime union and borrowed configuration ownership'],
    completeConstructorByteCorrespondence: false,
    completeParentUpper: false, completePipelineUpper: false };
}

// Compose only the independently audited generated-code result with the exact
// indexed census from that execution. This establishes a finite point union;
// neither the structural envelope nor an equal maximum authenticates a point.
export function inspectProviderConstructionPoint(facts, code, read, target) {
  const indexed = inspectProviderConstruction(facts, read, target);
  assert.equal(code.scalarAllocationRequestsEstablished, true, 'Missing audited scalar allocation requests');
  assert.equal(code.scalarPayloadBytesMeasured, false, 'Scalar code evidence is not a payload measurement');
  assert.equal(code.completeConstructorLifetimeUpper, false, 'Unsupported constructor lifetime guarantee');
  assert.equal(code.completeParentUpper, false, 'Unsupported parent capacity guarantee');
  assert.equal(code.completePipelineUpper, false, 'Unsupported pipeline capacity guarantee');
  assert.equal(code.observations.length, facts.length, 'Different constructor observation count');
  let maximum = 0;
  const points = facts.map((fact, index) => {
    const scalar = code.observations[index];
    assert.equal(scalar.observationDigest, hash(JSON.stringify(fact)), 'Different constructor observation input');
    assert.equal(scalar.indexedRequestedBytes, fact.indexedBytes, 'Different indexed constructor extent');
    assert.equal(scalar.callbacks.length, fact.scalarDynamicCallbacks, 'Missing scalar callback extent');
    assert.deepEqual(scalar.callbacks.map(c => c.identity), fact.scalarCodes.map(c => c.identity),
      'Different scalar allocation identities');
    let scalarBytes = 0;
    for (const callback of scalar.callbacks) {
      assert.equal(callback.payloadBytes, 8, 'Unsupported audited scalar payload');
      assert.equal(callback.headerBytes, 8, 'Unsupported audited scalar header');
      assert.equal(callback.requestedBytes, callback.payloadBytes + callback.headerBytes,
        'Different scalar allocation request');
      scalarBytes += callback.requestedBytes;
    }
    assert.equal(scalar.scalarRequestedBytes, scalarBytes, 'Different scalar request subtotal');
    const bytes = fact.indexedBytes + scalarBytes;
    assert.equal(scalar.pointRequestedBytes, bytes, 'Different constructor point subtotal');
    assert(bytes <= indexed.recipe.bytes, 'Point constructor bytes exceed conditional envelope');
    maximum = Math.max(maximum, bytes);
    return {observationDigest: scalar.observationDigest, indexedRequestedBytes: fact.indexedBytes,
      scalarRequestedBytes: scalarBytes, pointRequestedBytes: bytes,
      scalarAllocationIdentities: scalar.callbacks.map(c => c.identity)};
  });
  assert.equal(code.maxPointRequestedBytes, maximum, 'Different constructor point maximum');
  return {...indexed, pointRequestedBytesEstablished: true, maxPointRequestedBytes: maximum, points,
    pointEvidence: 'indexed runtime layouts plus independently audited object/executed-binary scalar allocation requests',
    unresolved: ['transient construction allocations and whole-constructor lifetime union',
      'borrowed configuration referents and their original-owner charges',
      'allocator rounding, fragmentation and physical reclamation'],
    completeConstructorLifetimeUpper: false};
}

export function inspectProviderConstruction(facts, read, target) {
  assert.equal(target, 'native', 'Provider construction ABI is native only');
  const bound = providerConstructionBound(read);
  assert(facts.length > 0, 'Missing real eleven-provider constructor observation');
  let maximum = 0;
  for (const f of facts) {
    assert.equal(f.kind, 'provider construction observation');
    assert.equal(f.providers, 11); assert.equal(f.arraySlots, 11);
    assert.equal(f.records, 11, 'Missing distinct provider candidate records');
    assert(Number.isSafeInteger(f.callbacks) && f.callbacks >= 0 && f.callbacks <= 44);
    assert(Number.isSafeInteger(f.defaultArrays) && f.defaultArrays >= 0 && f.defaultArrays <= 1);
    assert.equal(f.unclassifiedCaptures, 0, 'Unaccounted provider callback capture');
    assert(Number.isSafeInteger(f.indexedBytes) && f.indexedBytes >=
      11 * bound.recordBytes + bound.candidateContainerBytes, 'Missing candidate container or record bytes');
    assert(Number.isSafeInteger(f.scalarDynamicCallbacks) && f.scalarDynamicCallbacks >= 0 &&
      f.callbacks + f.scalarDynamicCallbacks <= bound.callbackCount, 'Too many constructor callbacks');
    assert(f.indexedBytes <= bound.bytes, 'Actual provider construction exceeds source-derived envelope');
    maximum = Math.max(maximum, f.indexedBytes);
  }
  return { recipe: bound, observations: facts.length, maxObservedIndexedBytes: maximum,
    scalarPayloadBytesObserved: false, completeConstructorByteCorrespondence: false,
    scope: 'finite point-in-time provider construction identity union; no callback execution or parent lifetime union',
    completeParentUpper: false, completePipelineUpper: false };
}
