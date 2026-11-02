import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { fieldLayout } from '../backing/native-extent.mjs';
import {reviewedFunction, checkConstructionSourceReview} from './provider-construction-source-review.mjs';
const profileBytes = readFileSync(new URL('./provider-construction-current.json', import.meta.url));
const profile = JSON.parse(profileBytes);
export function providerConstructionBound(read) {
  return constructionBound(read, false);
}
export function retainedProviderConstructionBound(read) {
  return constructionBound(read, true);
}
function constructionBound(read, retained) {
  assert.equal(profile.version, 'actql-native-provider-construction/0.1');
  const retainedProfile = retained ? JSON.parse(read(
    'proofs/relation-pipeline/capacity/parent-control/provider-construction.json')) : undefined;
  // The current census binds current complete sources directly. Archived
  // reverse deltas qualify only their retained observations and layouts.
  const sourceReview = retained ? checkConstructionSourceReview(retainedProfile, read)
    : checkCurrentConstructionSources(read);
  const sourceProfile = retained ? retainedProfile : profile;
  if (!retained) {
    const managed = read('src/connectors/local/managed_provider.mbt').toString();
    for (const name of ['managed_provider_with_inputs', 'managed_provider_with_numeric']) {
      const wrapper = reviewedFunction(managed, name);
      assert.equal(wrapper.split('infer_relation_prefix: None,').length, 2,
        'Candidate wrapper must not own a bound Infer tuple');
    }
    const model = reviewedFunction(managed, 'managed_provider_with_infer_relation_prefix');
    assert(model.includes('infer_relation_prefix: Some((prefix, boundary_step, execution, measurement))'),
      'Model recipe ownership changed');
    for (const provider of sourceProfile.providers) {
      assert(!reviewedFunction(read(provider.path).toString(), provider.name)
        .includes('managed_provider_with_infer_relation_prefix'), 'Model tuple entered candidate census');
    }
  }

  for (const p of sourceProfile.providers) {
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
  const record = 8 + fieldLayout(Array(retained ? 4 : 5).fill('ref')).payloadBytes;
  // One code pointer and at most three captures. It has pointer width but is
  // not a GC reference. Noncapturing callbacks can be static, contributing zero
  // newly owned bytes. Shared callback identities also count only once.
  const callback = 8 + fieldLayout(Array(4).fill('ref')).payloadBytes;
  const candidates = 24 + 8 + 8 * profile.bounds.candidateArraySlots;
  const family = 24; // Array owner; its zero-length backing is process-static.
  const bytes = profile.bounds.providerRecords * (record + 4 * callback) + candidates + family;
  assert.equal(bytes, retained ? 2344 : 2432);
  return { subject: profile.scope, sourceReview, providerCount: 11, recordBytes: record, callbackBytes: callback,
    callbackCount: 44, candidateContainerBytes: candidates, defaultFamilyBytes: family, bytes,
    layoutRevision: retained ? 'retained-four-field' : 'current-five-field',
    modelPrefixTuple: {included: false, reason: 'Separate Model-bound family owner; tuple and borrowed recipe lifetime are not established by this eleven-candidate component'},
    unit: 'conditional pinned native requested header and payload bytes',
    premises: [retained ? 'four historical pointer-sized ManagedProvider fields'
      : 'five current pointer-sized ManagedProvider fields; all eleven candidate Infer prefix slots are None',
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

function checkCurrentConstructionSources(read) {
  const recipe = read('proofs/relation-pipeline/capacity/parent-control/provider-construction-current.json');
  assert.equal(recipe.toString(), profileBytes.toString(), 'Changed current constructor recipe');
  const sources = {...Object.fromEntries(profile.providers.map(p => [p.path, p.sourceDigest])),
    ...profile.sourcePremises};
  for (const [path, digest] of Object.entries(sources)) {
    assert.equal(hash(read(path)), digest, `Unreviewed current constructor source ${path}`);
  }
  assert.deepEqual(Object.keys(profile.wrapperDigests),
    ['managed_provider', 'managed_provider_with_inputs', 'managed_provider_with_numeric']);
  const managed = read('src/connectors/local/managed_provider.mbt').toString();
  for (const [name, digest] of Object.entries(profile.wrapperDigests)) {
    assert.equal(hash(reviewedFunction(managed, name)), digest,
      `Changed current candidate construction wrapper ${name}`);
  }
  return {recipeDigest: hash(recipe),
    selectedDigest: sources['src/connectors/local/selected_relation_provider.mbt'],
    managedDigest: sources['src/connectors/local/managed_provider.mbt'],
    generatedDigest: sources['src/execution_relation/generated_sequence.mbt'],
    scope: profile.scope,
    completeConstructorByteCorrespondence: false,
    completeParentUpper: false, completePipelineUpper: false};
}

// Compose only the independently audited generated-code result with the exact
// indexed census from that execution. This establishes a finite point union;
// neither the structural envelope nor an equal maximum authenticates a point.
export function inspectProviderConstructionPoint(facts, code, read, target, options = {}) {
  const indexed = inspectProviderConstruction(facts, read, target, options);
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

export function inspectProviderConstruction(facts, read, target, {retained = false} = {}) {
  assert.equal(target, 'native', 'Provider construction ABI is native only');
  const bound = retained ? retainedProviderConstructionBound(read) : providerConstructionBound(read);
  assert(facts.length > 0, 'Missing real eleven-provider constructor observation');
  let maximum = 0;
  for (const f of facts) {
    assert.equal(f.kind, 'provider construction observation');
    if (retained) assert(f.providerRecordFields === undefined || f.providerRecordFields === 4,
      'Retained four-field source cannot authenticate current observations');
    if (!retained) assert.equal(f.providerRecordFields, 5,
      'Current five-field source cannot authenticate retained four-field observations');
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
