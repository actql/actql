import assert from 'node:assert/strict';
import test from 'node:test';
import {retireCompletedEffectfulCapture} from
  './completed-run-publication.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

test('terminal capture retirement keeps its record until deletion succeeds',
  async () => {
    const run = {name: 'run_definition', identity: cid('a'), wire: 'run'};
    const recordCid = cid('b');
    const captureCid = cid('c');
    const sourceCid = cid('d');
    const previewCid = cid('e');
    const capturedCid = cid('f');
    const sourceArtifactCid = cid('1');
    const body = {version: 'actql-completed-effectful-capture/0.1',
      store_authority_cid: cid('0'), run_definition: run.wire,
      invocation: 'invocation', definitions: ['definition'],
      artifacts: ['artifact'], derivations: [], orderings: [],
      retentions: [], durable_bindings: [], result_schemas: [],
      manifest: 'manifest', computation_receipt: 'receipt',
      captured_run: 'captured', preview: 'preview',
      authoring_context: 'authoring',
      effect_source_artifacts: [{member_index: 0, artifact: 'source'}],
      connector_recovery: []};
    const holdings = new Map([
      [recordCid, {namespace: 'publication-private',
        manifest_cid: capturedCid, objects: [{}]}],
      [captureCid, {namespace: 'effect-capture',
        manifest_cid: capturedCid, objects: []}],
      [sourceCid, {namespace: 'effect-source',
        manifest_cid: sourceArtifactCid, objects: []}],
      [previewCid, {namespace: 'publication-private',
        manifest_cid: previewCid, objects: [{}]}],
    ]);
    const visits = [];
    let failCaptureDeletion = true;
    const store = {storeAuthorityCid: cid('0'),
      async inspectPhysicalHolding(key) { return holdings.get(key); },
      async readPrivateEvidence() {
        return Buffer.from(JSON.stringify(body));
      },
      async retirePhysicalHolding(key) {
        visits.push(key);
        if (key === captureCid && failCaptureDeletion) {
          failCaptureDeletion = false;
          return {cleanup: {status: () => ({pending: true})}};
        }
        holdings.delete(key);
        return {cleanup: {status: () => ({pending: false})}};
      }};
    const control = {
      admit(name, wire) { return {name, wire, identity: wire === 'run'
        ? run.identity : wire === 'captured' ? capturedCid :
          wire === 'source' ? sourceArtifactCid : cid('2')}; },
      admitRunEvidence() { return {identity: cid('3')}; },
      admitEffectComputationPreview() { return {}; },
      effectPrivateEvidenceBinding() {
        return {holdingCid: previewCid, semanticCid: previewCid};
      },
      effectComputationRecordHoldingCid() { return recordCid; },
      effectComputationCaptureHoldingCid() { return captureCid; },
      effectfulComputationEvidenceChainValid() { return true; },
      capturedEffectSourceRecoveryInventoryValid() { return true; },
      admitCapturedEffectSourceArtifact() { return {}; },
      capturedEffectSourceHoldingCid() { return sourceCid; },
    };
    const options = {store, control, runDefinition: run,
      contractLimits: {maxWireBytes: 1000, maxNodes: 100, maxDepth: 10}};
    await assert.rejects(retireCompletedEffectfulCapture(options),
      {code: 'CompletedEffectfulCaptureCleanupPending'});
    assert.deepEqual(visits, [sourceCid, captureCid]);
    assert.ok(holdings.has(recordCid));
    assert.ok(holdings.has(captureCid));
    assert.equal(await retireCompletedEffectfulCapture(options), true);
    assert.deepEqual(visits.slice(2), [sourceCid, captureCid,
      previewCid, recordCid]);
    assert.equal(holdings.size, 0);
    assert.equal(await retireCompletedEffectfulCapture(options), false);
  });
