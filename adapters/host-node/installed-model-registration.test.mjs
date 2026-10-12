import assert from 'node:assert/strict';
import test from 'node:test';
import {installModelProviders} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

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
