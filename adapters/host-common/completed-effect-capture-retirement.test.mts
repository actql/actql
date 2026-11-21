import assert from 'node:assert/strict';
import test from 'node:test';
import {retireCompletedEffectfulCapture} from
  './completed-run-publication.mjs';

type RetirementOptions = Parameters<typeof retireCompletedEffectfulCapture>[0];
type Control = RetirementOptions['control'];
type Run = RetirementOptions['runDefinition'];
type PrepareSources = Parameters<Control['prepareCapturedEffectSourceInventory']>;
type ValidateSources = Parameters<Control['capturedEffectSourceInventoryFromCaptureValid']>;
type RestoreSource = Parameters<Control['admitCapturedEffectSourceFromCapture']>;
type DependencyBindings = Parameters<Control['capturedEffectDependencyPayloadBindings']>;
type MetadataReader<Value> = (plaintext: undefined, read: Readonly<{releaseBytes(): string}>) => Value | PromiseLike<Value>;

const cid = (digit: string) => `sha256:${digit.repeat(64)}`;

for (const preparedProjection of [false, true]) {
for (const dependencyPayloads of [false, true]) {
for (const publicResults of [false, true]) {
test(`terminal capture retirement keeps its record until deletion succeeds (${publicResults ? 1 : 0} public Results)${dependencyPayloads ? " with retained Table/Result dependencies" : ""}${preparedProjection ? ' using prepared Source projection' : ''}`,
  async () => {
    const run = {name: 'run_definition', identity: cid('a'), wire: 'run'};
    const recordCid = cid('b');
    const captureCid = cid('c');
    const sourceCid = cid('d');
    const previewCid = cid('e');
    const capturedCid = cid('f');
    const sourceArtifactCid = cid('1');
    // Physical custody metadata is separate from the public Result count.
    const dependencies = dependencyPayloads ? [
      {artifact_cid: cid('4'), physical_cid: cid('5'), byte_count: 13},
      {artifact_cid: cid('6'), physical_cid: cid('7'), byte_count: 21},
    ] : [];
    const body = {version: 'actql-completed-effectful-capture/0.1',
      store_authority_cid: cid('0'), run_definition: run.wire,
      invocation: 'invocation', definitions: publicResults ? ['definition'] : [],
      artifacts: publicResults ? ['artifact'] : [], derivations: [], orderings: [],
      retentions: [], durable_bindings: [], result_schemas: [],
      manifest: 'manifest', computation_receipt: 'receipt',
      captured_run: 'captured', preview: 'preview',
      authoring_context: 'authoring',
      effect_source_artifacts: [{member_index: 0, artifact: 'source'}],
      connector_recovery: [], effect_dependency_payloads: dependencies};
    const holdings = new Map([
      [recordCid, {namespace: 'publication-private',
        manifest_cid: capturedCid, objects: [{}]}],
      [captureCid, {namespace: 'effect-capture',
        manifest_cid: capturedCid, objects: dependencies.map(value => ({
          cid: value.physical_cid, byte_count: value.byte_count}))}],
      [sourceCid, {namespace: 'effect-source',
        manifest_cid: sourceArtifactCid, objects: []}],
      [previewCid, {namespace: 'publication-private',
        manifest_cid: previewCid, objects: [{}]}],
    ]);
    const visits: string[] = [];
    let failCaptureDeletion = true;
    let captureCustody = true;
    const store = {storeAuthorityCid: cid('0'),
      async inspectPhysicalHolding(key: string) { return holdings.get(key); },
      // The fixture has metadata only. Retirement inspection never supplies
      // payload usability or consumption evidence.
      async inspectPhysicalHoldingForRetirement(key: string) { return holdings.get(key); },
      async retireEffectCaptureCustody(definition: Run) {
        assert.equal(definition.identity, run.identity);
        const retired = captureCustody;
        captureCustody = false;
        return retired;
      },
      async forgetEffectCaptureCustody(definition: Run) {
        assert.equal(definition.identity, run.identity);
        assert.equal(holdings.size, 0, 'custody is forgotten only after all holdings retire');
        captureCustody = false;
      },
      async readPrivateEvidence<Value>(_name: string, _semantic: string, _holding: string, consume: MetadataReader<Value>) {
        return consume(undefined, {releaseBytes: () => JSON.stringify(body)});
      },
      async retirePhysicalHolding(key: string) {
        visits.push(key);
        if (key === captureCid && failCaptureDeletion) {
          failCaptureDeletion = false;
          return {cleanup: {status: () => ({pending: true})}};
        }
        holdings.delete(key);
        return {cleanup: {status: () => ({pending: false})}};
      }};
    let chainChecked=false,projectionCalls=0;
    const originalSource={};
    const control = {
      admit(name: string, wire: string) { return {name, wire, identity: wire === 'run'
        ? run.identity : wire === 'captured' ? capturedCid :
          wire === 'source' ? sourceArtifactCid : cid('2')}; },
      admitRunEvidence() { return {identity: cid('3')}; },
      admitEffectComputationPreview() { return {}; },
      effectPrivateEvidenceBinding() {
        return {holdingCid: previewCid, semanticCid: previewCid};
      },
      effectComputationRecordHoldingCid() { return recordCid; },
      effectComputationCaptureHoldingCid() { return captureCid; },
      effectfulComputationEvidenceChainValid() {assert.equal(preparedProjection,false);chainChecked=true; return true; },
      ...(preparedProjection?{hasPreparedCapturedEffectRun:()=>true,
      prepareCapturedEffectSourceInventory(chain: PrepareSources[0], preview: PrepareSources[1],
        sources: PrepareSources[2], authority: PrepareSources[3]): readonly object[] | undefined {
        assert.equal(chain.capturedRun.identity,capturedCid);assert.equal(chain.runDefinition.identity,run.identity);
        assert.equal(authority,store.storeAuthorityCid);assert.equal(chain.invocation.wire,'invocation');
        chainChecked=true;
        assert.deepEqual(sources.map(source=>source.memberIndex),[0]);projectionCalls++;
        return [originalSource];
      }}:{}),
      capturedEffectSourceInventoryFromCaptureValid(preview: ValidateSources[0], sources: ValidateSources[1],
        invocation: ValidateSources[2], captured: ValidateSources[3], storeAuthorityCid: ValidateSources[4]) {
        assert.equal(preparedProjection,false,'prepared projection does not repeat whole-context admission');
        assert.equal(captured.identity, capturedCid);
        assert.equal(invocation.wire, 'invocation');
        assert.equal(storeAuthorityCid, store.storeAuthorityCid);
        assert.deepEqual(sources.map(s => s.memberIndex), [0]);
        return true;
      },
      admitCapturedEffectSourceFromCapture(_preview: RestoreSource[0], memberIndex: RestoreSource[1],
        invocation: RestoreSource[2], artifact: RestoreSource[3], captured: RestoreSource[4],
        storeAuthorityCid: RestoreSource[5]) {
        assert.equal(preparedProjection,false,'prepared typed Source is consumed directly');
        assert.equal(memberIndex, 0);
        assert.equal(artifact.identity, sourceArtifactCid);
        assert.equal(captured.identity, capturedCid);
        assert.equal(invocation.wire, 'invocation');
        assert.equal(storeAuthorityCid, store.storeAuthorityCid);
        return {};
      },
      capturedEffectSourceHoldingCid(source: object) {if(preparedProjection)assert.strictEqual(source,originalSource);return sourceCid; },
      capturedEffectDependencyPayloadBindings(_captured: DependencyBindings[0], dependencies: DependencyBindings[1]) {
        assert.deepEqual(dependencies, body.effect_dependency_payloads);
        return dependencies;
      },
    };
    // Only the retirement path is exercised; these explicit metadata ports do
    // not claim to be original Core admission or a complete production Store.
    const options = {store, control, runDefinition: run,
      contractLimits: {maxWireBytes: 1000, maxNodes: 100, maxDepth: 10}} as unknown as RetirementOptions;
    if(preparedProjection&&!dependencyPayloads&&!publicResults){
      const original=control.prepareCapturedEffectSourceInventory;
      control.prepareCapturedEffectSourceInventory=()=>undefined;
      await assert.rejects(retireCompletedEffectfulCapture(options),{code:'InvalidCompletedEffectfulCaptureSource'});
      assert.deepEqual(visits,[],'routing DATA alone never permits deletion or legacy fallback');
      control.prepareCapturedEffectSourceInventory=original;
    }
    await assert.rejects(retireCompletedEffectfulCapture(options),
      {code: 'CompletedEffectfulCaptureCleanupPending'});
    assert.deepEqual(visits, [sourceCid, captureCid]);
    assert.ok(holdings.has(recordCid));
    assert.ok(holdings.has(captureCid));
    assert.equal(captureCustody, true);
    assert.equal(await retireCompletedEffectfulCapture(options), true);
    assert.deepEqual(visits.slice(2), [sourceCid, captureCid,
      previewCid, recordCid]);
    assert.equal(holdings.size, 0);
    assert.equal(captureCustody, false);
    assert.equal(await retireCompletedEffectfulCapture(options), false);
    assert.equal(projectionCalls,preparedProjection?2:0);
    assert(chainChecked);
  });
}
}
}
