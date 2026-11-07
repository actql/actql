import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {installModelProviders} from './installed-model.mjs';
import {installedEffectModelPreparation} from './installed-effect-managed-run.mjs';
import {selectedInferOriginalCurrentStateCodec, bindInferOriginalReadRecipe, inferOriginalReadStartupCapacity} from './infer-original-installation.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {selectedInferOriginalMetadataLimits} from './infer-original-installation.mjs';

function fixture() {
  let installations = 0, sends = 0, lookups = 0;
  const reconcileResponse = () => {lookups++; return undefined;};
  return {moon: {
    clientProgramInstallModelProvider() {installations++; return {mode: 'sync'};},
    clientProgramInstallAsyncModelProvider() {installations++; return {mode: 'async'};},
  },
    entry: {providerId: 'models/fixture', invoke() {sends++;},
      validatePrompt: () => true, reconcileResponse},
    counts: () => ({installations, sends, lookups})};
}

const originalInstallation = () => ({
  bootstrap: {bootstrapRetainedBytes: 20n, bootstrapExecutionBytes: 10n,
    maxReservations: 8, maxHoldings: 8, maxDelegations: 8},
  modelRetainedBytes: 100n, modelExecutionBytes: 5n,
  nodeInstallation: {runtimeArtifactCid: 'runtime', layoutArtifactCid: 'layout',
    probability: undefined, installation: {sdk: {version: 'fixture'}},
    layout: {response_profile: {}, runtime_artifact_cid: 'runtime', layout_artifact_cid: 'layout',
      program_definition_cid: 'program', parameter_values_cid: 'parameters',
      barrier_cid: 'barrier', prepared_rows: 3n, retained_bytes: 7n, execution_bytes: 5n}}});

const nativeRecipeLimits = [11n, 12n, 70n, 30n, 90n, 40n, 9n, 10n, 11n];
const nativeModelLedgerBytes = [90n, 40n];

const originalRecipe = () => {
  const value = originalInstallation();
  for (const name of ['program_definition_cid', 'parameter_values_cid', 'barrier_cid']) {
    delete value.nodeInstallation.layout[name];
  }
  return value;
};

test('installed Request recipe retains the actual Model ledger floor separately from legacy read allowances', () => {
  const {moon, entry} = fixture(), graph = {}, occurrence = {}, selected = {};
  const physical = installModelProviders(moon, () => [{...entry, originalReadRecipe: originalRecipe()}])
    .get(entry.providerId);
  const calls = [], id = letter => `sha256:${letter.repeat(64)}`;
  const legacy = [11n, 12n, 70n, 30n, 7n, 13n, 9n, 10n, 11n];
  const model = [200n, 300n];
  moon.clientProgramPreparedComposedInferBounds = (o, g) => {
    assert.equal(o, occurrence); assert.equal(g, graph); calls.push('bounds'); return selected;
  };
  moon.clientProgramComposedInferRetainedLimits = value => {
    assert.equal(value, selected); calls.push('legacy'); return legacy;
  };
  moon.clientProgramComposedInferModelLedgerBytes = function(value) {
    assert.equal(this, moon); assert.equal(value, selected); calls.push('model'); return model;
  };
  moon.clientProgramInferPlanProgramCid = value => {assert.equal(value, graph); return id('a');};
  moon.clientProgramInferPlanParametersCid = value => {assert.equal(value, graph); return id('b');};
  moon.clientProgramInferPlanBoundary = value => {assert.equal(value, graph); return {_3: id('c')};};
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('const selectedBounds = physical.originalReadRecipe');
  const end = text.indexOf("admissionBoundary = 'provider_binding';", start);
  assert(start >= 0 && end > start);
  const bind = Function('physical', 'moon', 'occurrence', 'graph', 'checked', 'bindInferOriginalReadRecipe',
    'clientOperationError', text.slice(start, end) + '\nreturn {selectedBounds, originalReadInstallation};');
  const bound = bind(physical, moon, occurrence, graph, value => value, bindInferOriginalReadRecipe,
    code => Object.assign(new Error(code), {code}));
  assert.equal(bound.selectedBounds, selected);
  assert.deepEqual(calls, ['bounds', 'model', 'legacy']);
  assert.equal(bound.originalReadInstallation.modelRetainedBytes, 300n);
  assert.equal(bound.originalReadInstallation.modelExecutionBytes, 305n);
  assert.equal(bound.originalReadInstallation.nodeInstallation.layout.retained_bytes, 77n);
  assert.deepEqual(legacy, [11n, 12n, 70n, 30n, 7n, 13n, 9n, 10n, 11n]);
  delete moon.clientProgramComposedInferModelLedgerBytes;
  calls.length = 0;
  assert.throws(() => bind(physical, moon, occurrence, graph, value => value, bindInferOriginalReadRecipe,
    code => Object.assign(new Error(code), {code})), {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.deepEqual(calls, ['bounds'], 'missing new original projection cannot use the legacy suffix');
});

test('installed read recipe refuses absent or malformed actual Model ledger amounts before identity getters', () => {
  const {moon, entry} = fixture(), graph = {}, id = letter => `sha256:${letter.repeat(64)}`;
  let calls = 0;
  moon.clientProgramInferPlanProgramCid = () => {calls++; return id('a');};
  moon.clientProgramInferPlanParametersCid = () => {calls++; return id('b');};
  moon.clientProgramInferPlanBoundary = () => {calls++; return {_3: id('c')};};
  const recipe = installModelProviders(moon, () => [{...entry, originalReadRecipe: originalRecipe()}])
    .get(entry.providerId).originalReadRecipe;
  for (const model of [undefined, [], [200n], [200n, 300n, 1n], [200, 300n], [-1n, 300n],
    [200n, -1n], [9223372036854775808n, 300n]]) {
    assert.throws(() => bindInferOriginalReadRecipe(moon, recipe, graph, nativeRecipeLimits, model),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  assert.equal(calls, 0);
});

test('installed read recipe binds only the same selected Graph identities without another preparation', () => {
  const {moon, entry, counts} = fixture(), recipe = originalRecipe(), graph = {};
  const calls = [], id = letter => `sha256:${letter.repeat(64)}`;
  moon.clientProgramInferPlanProgramCid = value => {assert.equal(value, graph); calls.push('program'); return id('a');};
  moon.clientProgramInferPlanParametersCid = value => {assert.equal(value, graph); calls.push('parameters'); return id('b');};
  moon.clientProgramInferPlanBoundary = value => {assert.equal(value, graph); calls.push('boundary'); return {_0: 4, _1: 0, _2: 0, _3: id('c')};};
  const physical = installModelProviders(moon, () => [{...entry, originalReadRecipe: recipe}]).get(entry.providerId);
  const profile = recipe.nodeInstallation.layout.response_profile;
  recipe.nodeInstallation.layout.retained_bytes = 999n;
  const bound = bindInferOriginalReadRecipe(moon, physical.originalReadRecipe, graph, nativeRecipeLimits, nativeModelLedgerBytes);
  assert.deepEqual(calls, ['program', 'parameters', 'boundary']);
  assert.equal(bound.nodeInstallation.layout.response_profile, profile);
  assert.equal(bound.nodeInstallation.layout.retained_bytes, 77n);
  assert.equal(bound.nodeInstallation.layout.program_definition_cid, id('a'));
  assert.equal(bound.nodeInstallation.layout.parameter_values_cid, id('b'));
  assert.equal(bound.nodeInstallation.layout.barrier_cid, id('c'));
  assert.equal(bound.modelRetainedBytes, 190n);
  assert.equal(bound.modelExecutionBytes, 45n);
  assert.equal(bound.bootstrap.bootstrapRetainedBytes, 31n);
  assert.equal(bound.bootstrap.maxHoldings, 10);
  assert.equal(physical.originalReadInstallation, undefined);
  assert.ok(Object.isFrozen(bound.nodeInstallation.layout));
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
  assert.throws(() => bindInferOriginalReadRecipe(moon, {...physical.originalReadRecipe}, graph, nativeRecipeLimits, nativeModelLedgerBytes),
    {code: 'InferOriginalReadRecipeUnavailable'});
  assert.throws(() => bindInferOriginalReadRecipe(moon, bound, graph, nativeRecipeLimits, nativeModelLedgerBytes),
    {code: 'InferOriginalReadRecipeUnavailable'});
});

test('installed read recipe refuses partial identities and competing fixed installations before provider construction', () => {
  for (const change of [value => {value.originalReadRecipe.nodeInstallation.layout.program_definition_cid = 'copied';},
    value => {value.originalReadInstallation = originalInstallation();},
    value => {value.originalReadRecipe.nodeInstallation.layout.retained_bytes = 0n;},
    value => {value.originalReadRecipe.nodeInstallation.layout.execution_bytes = 1;},
    value => {value.originalReadRecipe.nodeInstallation.layout.prepared_rows = -1n;}]) {
    const {moon, entry, counts} = fixture(), value = {...entry, originalReadRecipe: originalRecipe()};
    change(value);
    assert.throws(() => installModelProviders(moon, () => [value]), /InvalidInstalledInferOriginalReadInstallation/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('installed read recipe preserves native census work and refuses additive overflow', () => {
  const {moon, entry} = fixture(), graph = {}, value = originalRecipe(), id = letter => `sha256:${letter.repeat(64)}`;
  value.currentStateCodec = {quantum: 1, comparisonWork: 1, decode: {maxWork: 100,
    parse: {max_input_bytes: 100, max_nodes: 10, max_depth: 4},
    tree: {max_nodes: 10, max_depth: 4, max_string_bytes: 100, max_total_string_bytes: 100}}};
  const recipe = installModelProviders(moon, () => [{...entry, originalReadRecipe: value}])
    .get(entry.providerId).originalReadRecipe;
  moon.clientProgramInferPlanProgramCid = () => id('a');
  moon.clientProgramInferPlanParametersCid = () => id('b');
  moon.clientProgramInferPlanBoundary = () => ({_3: id('c')});
  const bound = bindInferOriginalReadRecipe(moon, recipe, graph, nativeRecipeLimits, nativeModelLedgerBytes);
  assert.equal(bound.currentStateCodec.comparisonWork, 2 + 9 + 10 + 11);
  for (const index of [0, 1, 2, 3]) {
    const limits = [...nativeRecipeLimits]; limits[index] = 9223372036854775807n;
    assert.throws(() => bindInferOriginalReadRecipe(moon, recipe, graph, limits, nativeModelLedgerBytes),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
  for (const index of [0, 1]) {
    const model = [...nativeModelLedgerBytes]; model[index] = 9223372036854775807n;
    assert.throws(() => bindInferOriginalReadRecipe(moon, recipe, graph, nativeRecipeLimits, model),
      {code: 'InferOriginalReadRecipeUnavailable'});
  }
});

test('installed read recipe refuses missing or malformed original getters without any fallback', () => {
  const {moon, entry} = fixture(), graph = {};
  const original = installModelProviders(moon, () => [{...entry, originalReadRecipe: originalRecipe()}])
    .get(entry.providerId).originalReadRecipe;
  assert.throws(() => bindInferOriginalReadRecipe(moon, original, graph, nativeRecipeLimits, nativeModelLedgerBytes), {code: 'InferOriginalReadRecipeUnavailable'});
  moon.clientProgramInferPlanProgramCid = () => 'copied';
  moon.clientProgramInferPlanParametersCid = () => `sha256:${'b'.repeat(64)}`;
  moon.clientProgramInferPlanBoundary = () => ({_3: `sha256:${'c'.repeat(64)}`});
  assert.throws(() => bindInferOriginalReadRecipe(moon, original, graph, nativeRecipeLimits, nativeModelLedgerBytes), {code: 'InferOriginalReadRecipeUnavailable'});
});

test('metadata declaration is captured only by the retained original installation and exact selection', () => {
  const {moon, entry, counts} = fixture();
  const declaration = originalInstallation();
  declaration.metadataAcquisition = {metadata: {maxWireBytes: 512, maxLedgerEntries: 4},
    directory: {maxWireBytes: 256, maxDirectoryEntries: 2}, retainedBytes: 7n, workspaceBytes: 5n};
  const selected = installModelProviders(moon, () => [{...entry, originalReadInstallation: declaration}])
    .get(entry.providerId).originalReadInstallation;
  const original = selectedInferOriginalMetadataLimits(selected, selected.nodeInstallation);
  declaration.metadataAcquisition.metadata.maxLedgerEntries = 100;
  declaration.metadataAcquisition.workspaceBytes = 100n;
  assert.equal(original.metadata.maxLedgerEntries, 4);
  assert.equal(original.workspaceBytes, 5n);
  assert.ok(Object.isFrozen(original.metadata) && Object.isFrozen(original.directory));
  for (const [value, node] of [[{...selected}, selected.nodeInstallation],
    [selected, {...selected.nodeInstallation}], [true, selected.nodeInstallation]]) {
    assert.throws(() => selectedInferOriginalMetadataLimits(value, node), {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  }
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});

test('metadata declaration refuses missing amounts nonfinite clamps and Provider metadata substitutes before installation', () => {
  const good = {metadata: {maxWireBytes: 512, maxLedgerEntries: 4},
    directory: {maxWireBytes: 256, maxDirectoryEntries: 2}, retainedBytes: 7n, workspaceBytes: 5n};
  for (const metadataAcquisition of [null, {}, {...good, workspaceBytes: undefined},
    {...good, retainedBytes: 0n}, {...good, workspaceBytes: 1},
    {...good, metadata: {maxWireBytes: Infinity, maxLedgerEntries: 4}},
    {...good, metadata: {maxWireBytes: 512, maxLedgerEntries: undefined}},
    {...good, directory: {maxWireBytes: 256, maxDirectoryEntries: -1}},
    {...good, metadata_bytes: 512}, {...good, maxObjectBytes: 512}]) {
    const {moon, entry, counts} = fixture();
    assert.throws(() => installModelProviders(moon, () => [{...entry,
      originalReadInstallation: {...originalInstallation(), metadataAcquisition}}]),
    /InvalidInstalledInferMetadataAcquisition/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

const rawSelection = () => ({profile: {}, probability: undefined,
  installation: {sdk: null, endpoint: 'original'}, retention: {}, metadata: {}, clock: {}, data: {},
  selectedAt: 'original', availableUntil: 'availability', deleteBy: 'deletion',
  extensionCeilingAt: 'ceiling', metadataDeleteBy: 'metadata', selectionAvailable: () => true});

const asyncEntry = entry => {
  const {invoke: _fixtureInvoke, ...original} = entry;
  return {...original, entryPersistence: 'async', physicalPreflight: () => assert.fail('not invoked'),
    bindingOriginals: providerBindingOriginals(entry.providerId), rawCaptureSelection: rawSelection(),
    quantityCapacity: {limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}}};
};

test('trusted raw selection is snapshotted before provider installation without authority or I/O', () => {
  const {moon, entry, counts} = fixture();
  const raw = rawSelection();
  const physical = installModelProviders(moon, () =>
    [{...asyncEntry(entry), rawCaptureSelection: raw}]).get(entry.providerId);
  assert.equal(physical.provider.mode, 'async');
  raw.installation.endpoint = 'changed'; raw.deleteBy = 'extended';
  assert.equal(physical.rawCaptureSelection.installation.endpoint, 'original');
  assert.equal(physical.rawCaptureSelection.installation.sdk, null);
  assert.equal(physical.rawCaptureSelection.deleteBy, 'deletion');
  assert.equal(physical.rawCaptureSelection.data, raw.data);
  assert.equal(physical.rawCaptureSelection.profile, raw.profile);
  assert.equal(physical.originalReadInstallation, undefined);
  assert.deepEqual(physical.quantityCapacity, {limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
    perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}});
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});

test('raw installation refuses missing durable physical caller before provider installation', () => {
  for (const hooks of [{}, {entryPersistence: 'async'}, {physicalPreflight() {}}]) {
    const {moon, entry, counts} = fixture();
    if (hooks.entryPersistence === 'async') delete entry.invoke;
    assert.throws(() => installModelProviders(moon, () =>
      [{...entry, ...hooks, rawCaptureSelection: rawSelection()}]),
    /InstalledInferRawCaptureRequiresAsyncPhysicalPreflight/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('async registration has no sync fallback and refuses every missing installed original before I/O', () => {
  for (const field of ['physicalPreflight', 'quantityCapacity', 'bindingOriginals', 'rawCaptureSelection']) {
    const {moon, entry, counts} = fixture(); const async = asyncEntry(entry);
    delete async[field];
    assert.throws(() => installModelProviders(moon, () => [async]),
      /InvalidInstalledModelAsyncProviderRegistration|InstalledInferRawCaptureRequiresAsyncPhysicalPreflight/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
  for (const invoke of [undefined, () => assert.fail('dummy callback must be refused')]) {
    const {moon, entry, counts} = fixture();
    assert.throws(() => installModelProviders(moon, () => [{...asyncEntry(entry), invoke}]),
      /InvalidInstalledModelProviderRegistration/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('async registration refuses unavailable runtime rather than installing sync fallback', () => {
  const {moon, entry, counts} = fixture(); delete moon.clientProgramInstallAsyncModelProvider;
  assert.throws(() => installModelProviders(moon, () => [asyncEntry(entry)]),
    /InstalledModelAsyncProviderRuntimeUnavailable/u);
  assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
});

test('raw selection omission and malformed input do not opt in or invoke providers', () => {
  const {moon, entry, counts} = fixture();
  const selected = installModelProviders(moon, () => [entry]).get(entry.providerId);
  assert.equal(selected.rawCaptureSelection, undefined);
  assert.throws(() => installModelProviders(moon, () => [{...entry, rawCaptureSelection: {}}]),
    /InvalidInferRawCaptureSelection/u);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});

test('trusted original read installation preserves exact quantities and snapshots selection', () => {
  const {moon, entry, counts} = fixture();
  const declaration = originalInstallation();
  const probability = Object.freeze({});
  declaration.nodeInstallation.probability = probability;
  entry.originalReadInstallation = declaration;
  const selected = installModelProviders(moon, () => [entry]).get('models/fixture');
  declaration.bootstrap.bootstrapRetainedBytes = 999n;
  declaration.nodeInstallation.layout.retained_bytes = 999n;
  declaration.nodeInstallation.installation.sdk.version = 'changed';
  assert.equal(selected.originalReadInstallation.bootstrap.bootstrapRetainedBytes, 20n);
  assert.equal(selected.originalReadInstallation.nodeInstallation.layout.retained_bytes, 7n);
  assert.equal(selected.originalReadInstallation.nodeInstallation.layout.prepared_rows, 3n);
  assert.equal(selected.originalReadInstallation.nodeInstallation.installation.sdk.version, 'fixture');
  assert.equal(selected.originalReadInstallation.nodeInstallation.probability, probability,
    'an opaque admitted probability profile is retained, not copied or reconstructed');
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});

test('original current codec is one immutable installation selection, not a copied amount grant',()=>{
  const {moon,entry,counts}=fixture(),declaration=originalInstallation();
  const codec={quantum:1,comparisonWork:5,decode:{maxWork:20000,
    parse:{max_input_bytes:10000,max_nodes:1000,max_depth:20},
    tree:{max_nodes:1000,max_depth:20,max_string_bytes:10000,max_total_string_bytes:10000}}};
  declaration.currentStateCodec=codec;entry.originalReadInstallation=declaration;
  const installed=installModelProviders(moon,()=>[entry]).get(entry.providerId).originalReadInstallation;
  const chosen=selectedInferOriginalCurrentStateCodec(installed,installed.nodeInstallation);
  assert.deepEqual(chosen,codec);
  assert.ok(Object.isFrozen(chosen)&&Object.isFrozen(chosen.decode)&&Object.isFrozen(chosen.decode.parse));
  codec.quantum=0;codec.decode.parse.max_input_bytes=0;
  assert.equal(chosen.quantum,1);assert.equal(chosen.decode.parse.max_input_bytes,10000);
  assert.strictEqual(selectedInferOriginalCurrentStateCodec(installed,installed.nodeInstallation),chosen);
  for(const [original,node] of [[{...installed},installed.nodeInstallation],
    [installed,{...installed.nodeInstallation}],[undefined,installed.nodeInstallation]]){
    assert.throws(()=>selectedInferOriginalCurrentStateCodec(original,node),
      {code:'InferOriginalStateCodecUnavailable'});
  }
  assert.deepEqual(counts(),{installations:1,sends:0,lookups:0});
});

test('invalid original current codec refuses before Provider installation with no default quantity',()=>{
  for(const codec of [null,{}, {quantum:1,comparisonWork:5,decode:null},
    {quantum:0,comparisonWork:5,decode:{}}, {quantum:1.5,comparisonWork:5,decode:{}},
    {quantum:1,comparisonWork:5,decode:{maxWork:0,parse:{},tree:{}}},
    {quantum:1,comparisonWork:5,decode:{maxWork:1,parse:{max_input_bytes:1,max_nodes:1,max_depth:1},
      tree:{max_nodes:1,max_depth:1,max_string_bytes:1,max_total_string_bytes:1},extra:true}}]){
    const {moon,entry,counts}=fixture(),declaration=originalInstallation();
    declaration.currentStateCodec=codec;entry.originalReadInstallation=declaration;
    assert.throws(()=>installModelProviders(moon,()=>[entry]),{code:'ModelOriginalCurrentCodecUnavailable'});
    assert.deepEqual(counts(),{installations:0,sends:0,lookups:0});
  }
});

test('malformed original read installation refuses before provider or scope construction', () => {
  for (const mutate of [
    value => { value.extra = true; },
    value => { delete value.bootstrap; },
    value => { value.bootstrap.bootstrapRetainedBytes = 0n; },
    value => { value.bootstrap.bootstrapExecutionBytes = -1n; },
    value => { value.bootstrap.maxHoldings = 1.5; },
    value => { value.modelRetainedBytes = 9_223_372_036_854_775_808n; },
    value => { value.modelExecutionBytes = 5; },
    value => { delete value.nodeInstallation.layout; },
    value => { delete value.nodeInstallation.layout.response_profile; },
  ]) {
    const {moon, entry, counts} = fixture(), declaration = originalInstallation();
    mutate(declaration); entry.originalReadInstallation = declaration;
    assert.throws(() => installModelProviders(moon, () => [entry]),
      /InvalidInstalledInferOriginalReadInstallation/u);
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('registration absence supplies no default original read installation or quantities', () => {
  const {moon, entry, counts} = fixture();
  const selected = installModelProviders(moon, () => [entry]).get('models/fixture');
  assert.equal(selected.originalReadInstallation, undefined);
  assert.equal(selected.quantityCapacity, undefined);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});

test('registered original-response lookup is retained without invoking or reading a call', () => {
  const {moon, entry, counts} = fixture();
  const selected = installModelProviders(moon, () => [entry]).get('models/fixture');
  assert.equal(selected.reconcileResponse, entry.reconcileResponse);
  entry.reconcileResponse = () => assert.fail('mutated provider registration');
  assert.equal(selected.reconcileResponse(), undefined);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 1});
});

test('invalid original-response hook is rejected before installing the provider', () => {
  for (const reconcileResponse of [null, false, {}, 'reconcile']) {
    const {moon, entry, counts} = fixture();
    assert.throws(() => installModelProviders(moon, () => [{...entry, reconcileResponse}]),
      {message: 'InvalidInstalledModelProviderRegistration'});
    assert.deepEqual(counts(), {installations: 0, sends: 0, lookups: 0});
  }
});

test('provider without an original-response hook acquires no reconciliation capability', () => {
  const {moon, entry, counts} = fixture();
  delete entry.reconcileResponse;
  assert.equal(installModelProviders(moon, () => [entry]).get('models/fixture').reconcileResponse, undefined);
  assert.deepEqual(counts(), {installations: 1, sends: 0, lookups: 0});
});


test('bound original recipe keeps startup controls separate from its complete Model allowance', () => {
  const {moon, entry}=fixture(), graph={}, id=letter=>`sha256:${letter.repeat(64)}`;
  const physical=installModelProviders(moon,()=>[{...entry,originalReadRecipe:originalRecipe()}]).get(entry.providerId);
  moon.clientProgramInferPlanProgramCid=()=>id('a');
  moon.clientProgramInferPlanParametersCid=()=>id('b');
  moon.clientProgramInferPlanBoundary=()=>({_3:id('c')});
  const bound=bindInferOriginalReadRecipe(moon,physical.originalReadRecipe,graph,nativeRecipeLimits,nativeModelLedgerBytes);
  const startup=inferOriginalReadStartupCapacity(bound);
  assert(Object.isFrozen(startup));
  assert.deepEqual([startup.modelRetainedBytes,startup.modelExecutionBytes],[100n,5n]);
  assert.deepEqual([bound.modelRetainedBytes,bound.modelExecutionBytes],[190n,45n]);
  assert.equal(inferOriginalReadStartupCapacity(bound),startup);
  const copy={...bound}; assert.equal(inferOriginalReadStartupCapacity(copy),copy,
    'copied DATA never acquires the original startup association');
  assert.equal(inferOriginalReadStartupCapacity(physical.originalReadRecipe),physical.originalReadRecipe,
    'unbound and legacy declarations keep their original path');
});


test('actual Effect preparation passes original recipe startup controls while its Plan keeps the total Model allowance', () => {
  const {moon, entry}=fixture(), graph={}, id=letter=>`sha256:${letter.repeat(64)}`;
  const installed=installModelProviders(moon,()=>[{...entry,originalReadRecipe:originalRecipe()}]).get(entry.providerId);
  moon.clientProgramInferPlanProgramCid=()=>id('a');
  moon.clientProgramInferPlanParametersCid=()=>id('b');
  moon.clientProgramInferPlanBoundary=()=>({_3:id('c')});
  const physical=bindInferOriginalReadRecipe(moon,installed.originalReadRecipe,graph,nativeRecipeLimits,nativeModelLedgerBytes);
  const compiled={},definition={},scope={},parent={},demand={},read={};let reads=0;
  const control={prepareCheckedClientInferNodeReadLayout(...args) {
    assert.deepEqual(args,[compiled,definition,graph,scope,physical.nodeInstallation]);reads++;return read;
  }};
  const runtime={clientProgramInstalledEffectModelReadWindow(value) {
    assert.equal(this,runtime);assert.equal(value,demand);return [23n,29n];
  }};
  const run={model:{compiled,graph},publicationControl:control,modelRunDefinition:definition,
    modelScope:scope,value:parent,modelDemand:demand,runtime,
    modelSelection:{originalReadInstallation:physical}};
  const preparation=installedEffectModelPreparation(run,()=>({}),()=>{});
  assert.deepEqual([physical.modelRetainedBytes,physical.modelExecutionBytes],[190n,45n]);
  assert.deepEqual([preparation.modelRetainedBytes,preparation.modelExecutionBytes],[100n,5n]);
  assert.equal(preparation.metadataInstallation,physical);
  preparation.retain();const selected=preparation.prepareRead();
  assert.equal(selected.read,read);assert.equal(selected.scope,scope);assert.equal(selected.compiled,compiled);
  assert.deepEqual([selected.modelRetainedBytes,selected.modelExecutionBytes],[100n,5n]);
  assert.equal(reads,1);
  assert.throws(()=>preparation.prepareRead(),{code:'ForeignInstalledEffectModelScope'});
});
