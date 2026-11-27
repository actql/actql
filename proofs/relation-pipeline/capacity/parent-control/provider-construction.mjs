import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { fieldLayout } from '../backing/native-extent.mjs';
import {reviewedFunction, checkConstructionSourceReview} from './provider-construction-source-review.mjs';
const profileBytes = readFileSync(new URL('./provider-construction-current.json', import.meta.url));
const profile = JSON.parse(profileBytes);
// Attributes belong to the declaration even across a documentation marker.
// Skip comments/quoted contents while locating only the attached #name(args)
// or #name headers; this does not traverse callback or runtime callees.
function currentDeclarationAttributes(source, start) {
  const tokens = [...source.slice(0, start).matchAll(
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'|\/\/[^\n]*|\/\*[\s\S]*?\*\/|#[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|\S/gu,
  )].filter(token => !token[0].startsWith('//') && !token[0].startsWith('/*'));
  const attributes = [];
  let end = tokens.length;
  while (end > 0) {
    let begin = end - 1;
    if (tokens[begin][0] === ')') {
      let depth = 1;
      while (begin > 0 && depth > 0) {
        begin--;
        if (tokens[begin][0] === ')') depth++;
        else if (tokens[begin][0] === '(') depth--;
      }
      if (depth !== 0 || begin === 0) break;
      begin--;
    }
    if (!/^#[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$/u.test(tokens[begin][0])) break;
    attributes.unshift(source.slice(tokens[begin].index,
      tokens[end - 1].index + tokens[end - 1][0].length));
    end = begin;
  }
  return attributes.length ? attributes.join('\n') + '\n' : '';
}
// Canonical MoonBit top-level declarations end with an unindented brace.
// Exclude trailing module comments and subsequent helpers from this boundary.
export function currentFactoryDeclaration(source, name) {
  const declaration = reviewedFunction(source, name);
  const end = declaration.indexOf('\n}');
  assert(end >= 0, `Missing complete factory ${name}`);
  return currentDeclarationAttributes(source, source.indexOf(declaration)) +
    declaration.slice(0, end + 2);
}
export function currentProviderRecordDeclaration(source, name) {
  assert.equal(name, 'ManagedProvider');
  const declarations = [...source.matchAll(/^struct ManagedProvider \{/gm)];
  assert.equal(declarations.length, 1, 'Changed current ManagedProvider declaration');
  const start = declarations[0].index;
  const end = source.indexOf('\n}', start);
  assert(end >= 0, 'Missing complete ManagedProvider declaration');
  return currentDeclarationAttributes(source, start) + source.slice(start, end + 2);
}
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
    const prefix = cleanConstruction(model).replace(/\s+/gu, ' ');
    assert(prefix.includes('infer_relation_prefix: Some( match metered_output_start { Some(start) => Metered(prefix, boundary_step, execution, measurement, start) None => Prepaid(prefix, boundary_step, execution, measurement) }, ),'),
      'Model recipe ownership changed');
    const workspace = cleanConstruction(currentFactoryDeclaration(managed, 'managed_provider_with_task_workspace'))
      .replace(/\s+/gu, ' ');
    assert(workspace.includes('start_extension: Some(TaskWorkspace(start)),'),
      'Changed separately owned Model start extension');
    for (const provider of sourceProfile.providers) {
      assert(!reviewedFunction(read(provider.path).toString(), provider.name)
        .includes('managed_provider_with_infer_relation_prefix'), 'Model tuple entered candidate census');
    }
  }

  for (const p of sourceProfile.providers) {
    const source = read(p.path).toString();
    const constructor = retained ? reviewedFunction(source, p.name)
      : currentFactoryDeclaration(source, p.name);
    if (retained) assert.equal(hash(source), p.sourceDigest,
      `Unreviewed provider constructor ${p.name}`);
    assert(constructor.includes(`${p.binding}(`), `Changed provider binding ${p.name}`);
  }
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
  const list = source.match(/for\s+provider in \[([\s\S]*?)\]\s*\{/);
  assert(list);
  assert.deepEqual([...list[1].matchAll(/\b(\w+_provider)\(/g)].map(m => m[1]), profile.providers.map(p => p.name),
    'Unreviewed provider candidate inventory');
  assert.deepEqual(profile.bounds, { providerRecords: 11, callbacksPerProvider: 4,
    callbackReferenceCaptures: 3, defaultFamilyArrays: 1, candidateArraySlots: 11 });
  const recordFieldCount = retained ? 4 : sourceReview.recordFieldCount;
  const record = 8 + fieldLayout(Array(recordFieldCount).fill('ref')).payloadBytes;
  // One code pointer and at most three captures. It has pointer width but is
  // not a GC reference. Noncapturing callbacks can be static, contributing zero
  // newly owned bytes. Shared callback identities also count only once.
  const callback = 8 + fieldLayout(Array(4).fill('ref')).payloadBytes;
  const candidates = 24 + 8 + 8 * profile.bounds.candidateArraySlots;
  const family = 24; // Array owner; its zero-length backing is process-static.
  const componentBytes = profile.bounds.providerRecords * (record + 4 * callback) + candidates + family;
  const numericStartExtensions = retained ? 0 : sourceReview.numericCandidateOrdinals.length;
  // The pinned Native tagged value owns a header and one callback reference.
  // Its callback is already in the existing identity union.
  const numericStartExtensionBytes = numericStartExtensions *
    (8 + fieldLayout(Array(profile.startExtension.numericPayloadReferences).fill('ref')).payloadBytes);
  const bytes = componentBytes + numericStartExtensionBytes;
  assert.equal(bytes, retained ? 2344 : 2552);
  return { subject: profile.scope, sourceReview, providerCount: 11, recordBytes: record, callbackBytes: callback,
    callbackCount: 44, recordFieldCount, candidateContainerBytes: candidates, defaultFamilyBytes: family,
    numericStartExtensions, numericStartExtensionBytes, bytes,
    layoutRevision: retained ? 'retained-four-field' : 'current-six-field-tagged-start',
    modelPrefixTuple: {included: false, reason: 'Separate Model-bound family owner; tuple and borrowed recipe lifetime are not established by this eleven-candidate component'},
    unit: 'conditional pinned native requested header and payload bytes',
    premises: [retained ? 'four historical pointer-sized ManagedProvider fields'
      : 'six current pointer-sized ManagedProvider fields; all eleven candidate bounded quote and Infer prefix slots are None, with two owned Numeric start tags',
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

// This parser accounts for construction structure only. Callback bodies are
// deferred execution and are authenticated by the compiled input and actual
// lifecycle checks, rather than a second private-source version ledger.
const cleanConstruction = source => source.replace(/\/\/[^\n]*/gu, '')
  .replace(/\/\*[\s\S]*?\*\//gu, '').replace(/"(?:\\.|[^"\\])*"/gu, '""');
function splitConstruction(source) {
  const parts = []; let start = 0; const stack = [];
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if ('([{'.includes(c)) stack.push(c);
    else if (')]}'.includes(c)) {
      assert.equal(stack.pop(), {')':'(', ']':'[', '}':'{'}[c], 'Unbalanced construction syntax');
    } else if (c === ',' && stack.length === 0) {parts.push(source.slice(start, i).trim()); start = i + 1;}
  }
  assert.equal(stack.length, 0, 'Unbalanced construction syntax');
  if (source.slice(start).trim()) parts.push(source.slice(start).trim());
  return parts;
}
function constructionBody(source, name) {
  const declaration = cleanConstruction(currentFactoryDeclaration(source, name)).trim();
  assert(!declaration.startsWith('#'), name.startsWith('managed_provider')
    ? `Changed current candidate construction wrapper representation ${name}`
    : `Unreviewed current constructor source representation ${name}`);
  const bodyStart = declaration.indexOf(' {');
  assert(bodyStart > 0 && declaration.endsWith('}'), `Missing construction body ${name}`);
  return {header: declaration.slice(0, bodyStart).replace(/\s+/gu, ' '),
    body: declaration.slice(bodyStart + 2, -1).trim()};
}
function checkCurrentConstructionSources(read) {
  const recipe = read('proofs/relation-pipeline/capacity/parent-control/provider-construction-current.json');
  assert.equal(recipe.toString(), profileBytes.toString(), 'Changed current constructor recipe');
  const managed = read(profile.providerRecord.path).toString();
  const record = cleanConstruction(currentProviderRecordDeclaration(managed, profile.providerRecord.name));
  assert(record.startsWith('struct ManagedProvider {'), 'Changed current ManagedProvider declaration representation');
  const fieldText = record.slice(record.indexOf('{') + 1, record.lastIndexOf('}'));
  const starts = [...fieldText.matchAll(/^  (\w+)\s*:/gmu)];
  const fields = starts.map((match, index) => ({name: match[1], type: fieldText.slice(
    match.index + match[0].length, starts[index + 1]?.index ?? fieldText.length).trim().replace(/\s+/gu, ' ')}));
  assert.deepEqual(fields, profile.providerRecord.fields, 'Changed current ManagedProvider declaration field accounting');
  // Every admitted slot is a nullable/reference ABI word. A tuple referent
  // would have its own obligation; all current candidates keep that slot None.
  assert.equal(fields.length, 6);
  const extensions = [...managed.matchAll(/^priv enum ManagedProviderStartExtension \{/gm)];
  assert.equal(extensions.length, 1, 'Changed current start extension declaration');
  const start = extensions[0].index;
  const end = managed.indexOf('\n}', start);
  assert(end >= 0, 'Missing current start extension declaration');
  assert.equal(currentDeclarationAttributes(managed, start), '', 'Changed current start extension representation');
  const extension = cleanConstruction(managed.slice(start, end + 2)).replace(/\s+/gu, ' ');
  assert.equal(extension, profile.startExtension.declaration, 'Changed current start extension declaration');
  const numericCandidateOrdinals = profile.providers.flatMap((provider, index) =>
    provider.binding === 'managed_provider_with_numeric' ? [index] : []);
  assert.deepEqual(numericCandidateOrdinals, profile.startExtension.numericCandidateOrdinals);
  const bindings = ['managed_provider', 'managed_provider_with_inputs', 'managed_provider_with_numeric'];
  const wrappers = Object.fromEntries(bindings.map(name => [name, constructionBody(managed, name)]));
  const adapter = wrappers.managed_provider.body;
  assert(adapter.startsWith('managed_provider_with_inputs(') && adapter.endsWith(')'),
    'Changed current candidate construction wrapper');
  const adapted = splitConstruction(adapter.slice('managed_provider_with_inputs('.length, -1));
  assert.equal(adapted.length, 4, 'Changed current candidate construction wrapper allocations');
  assert.deepEqual(adapted.slice(0, 2), ['accepts', 'capacity'], 'Changed current candidate construction wrapper aliases');
  assert.match(adapted[2], /^\([^)]*\)\s*=>\s*\{/u, 'Changed current candidate construction wrapper callback');
  assert.equal(adapted[3], 'bounded_relation_capacity~', 'Changed current candidate construction wrapper quote');
  for (const name of bindings.slice(1)) {
    const body = wrappers[name].body;
    assert(body.startsWith('{') && body.endsWith('}'), 'Changed current candidate construction wrapper');
    const entries = splitConstruction(body.slice(1, -1));
    assert.deepEqual(entries.map(entry => entry.match(/^\w+/u)?.[0]), fields.map(field => field.name),
      'Changed current candidate construction wrapper fields');
    const slots = Object.fromEntries(entries.map(entry => [entry.match(/^\w+/u)[0], entry]));
    assert.equal(slots.accepts, 'accepts', 'Changed current candidate construction wrapper accepts');
    assert.equal(slots.capacity, 'capacity', 'Changed current candidate construction wrapper capacity');
    if (name === 'managed_provider_with_inputs') assert.equal(slots.start, 'start', 'Changed current candidate construction wrapper start');
    else assert.match(slots.start, /^start: \([^)]*\)\s*=>\s*\{/u, 'Changed current candidate construction wrapper callback');
    assert.equal(slots.infer_relation_prefix, 'infer_relation_prefix: None', 'Candidate wrapper must not own a bound Infer tuple');
    assert.equal(slots.bounded_relation_capacity, name === 'managed_provider_with_inputs'
      ? 'bounded_relation_capacity' : 'bounded_relation_capacity: None', 'Changed current candidate construction wrapper quote');
    assert.equal(slots.start_extension, name === 'managed_provider_with_inputs'
      ? 'start_extension: None' : 'start_extension: Some(Numeric(start))', 'Changed current candidate construction wrapper capture');
  }
  const constructors = [];
  for (const provider of profile.providers) {
    const factory = constructionBody(read(provider.path).toString(), provider.name);
    const header = factory.header;
    assert.match(header, new RegExp(`^fn ${provider.name}\\( limits : @execution\\.SequenceExecutionLimits, measurement : @execution\\.FixedInputGuardMeasureLimits,(?: family\\? : Array\\[ManagedProvider\\] = \\[\\],)? \\) -> ManagedProvider$`, 'u'),
      `Unreviewed current constructor source parameters ${provider.name}`);
    assert(factory.body.startsWith(provider.binding + '(') && factory.body.endsWith(')'),
      `Unreviewed current constructor source allocations ${provider.name}`);
    const callbacks = splitConstruction(factory.body.slice(provider.binding.length + 1, -1));
    assert.equal(callbacks.length, 3, `Unreviewed current constructor source callbacks ${provider.name}`);
    for (const callback of callbacks) assert.match(callback, /^(?:\w+|\([^)]*\))\s*=>\s*\{/u,
      `Unreviewed current constructor source callback ${provider.name}`);
    constructors.push({name: provider.name, callbacks: callbacks.length,
      borrowedParameters: header.includes('family?') ? 3 : 2});
  }
  const selected = read(profile.selectionFactory.path).toString();
  const selector = constructionBody(selected, profile.selectionFactory.name).body;
  const list = selector.match(/for\s+provider in \[([\s\S]*?)\]\s*\{/u);
  assert(list, 'Unreviewed provider candidate inventory');
  assert(!/\b(?:Ref|Array::make)\s*\(/u.test(selector.slice(0, list.index)),
    'Unreviewed current constructor source allocation before candidate list');
  assert(!/\blet\s+\w+\s*=\s*\[/u.test(selector.slice(0, list.index)),
    'Unreviewed current constructor source allocation before candidate list');
  return {recipeDigest: hash(recipe), recordFieldCount: fields.length, fields, constructors,
    numericCandidateOrdinals,
    selectedDigest: hash(read('src/connectors/local/selected_relation_provider.mbt')),
    managedDigest: hash(managed), generatedDigest: hash(read('src/execution_relation/generated_sequence.mbt')),
    scope: profile.scope, completeConstructorByteCorrespondence: false,
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
    if (!retained) assert.equal(f.providerRecordFields, bound.recordFieldCount,
      'Current source field census cannot authenticate a different provider layout');
    assert.equal(f.providers, 11); assert.equal(f.arraySlots, 11);
    assert.equal(f.records, 11, 'Missing distinct provider candidate records');
    assert(Number.isSafeInteger(f.callbacks) && f.callbacks >= 0 && f.callbacks <= 44);
    assert(Number.isSafeInteger(f.defaultArrays) && f.defaultArrays >= 0 && f.defaultArrays <= 1);
    assert.equal(f.unclassifiedCaptures, 0, 'Unaccounted provider callback capture');
    if (!retained) {
      assert.equal(f.numericStartExtensions, bound.numericStartExtensions, 'Missing current Numeric start extent evidence');
      assert.equal(f.numericStartExtensionBytes, bound.numericStartExtensionBytes, 'Changed current Numeric start extent');
    }
    const candidateBytes = 11 * bound.recordBytes + bound.candidateContainerBytes;
    assert(Number.isSafeInteger(f.indexedBytes) && f.indexedBytes >= candidateBytes,
      'Missing candidate container or record bytes');
    assert(f.indexedBytes >= candidateBytes + bound.numericStartExtensionBytes,
      'Missing candidate Numeric start bytes from measured union');
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
