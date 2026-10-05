import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { fieldLayout } from '../backing/native-extent.mjs';
import { checkConstructionSourceReview } from './provider-construction-source-review.mjs';
const profile = JSON.parse(readFileSync(new URL('./provider-construction.json', import.meta.url)));
export function providerConstructionBound(read) {
  assert.equal(profile.version, 'actql-native-provider-construction/0.1');
  const sourceReview = checkConstructionSourceReview(profile, read);
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
    unresolved: ['complete compiled allocation-site correspondence for dynamic scalar callback payload extents',
      'constructor lifetime union and borrowed configuration ownership'],
    completeConstructorByteCorrespondence: false,
    completeParentUpper: false, completePipelineUpper: false };
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
