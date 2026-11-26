import assert from 'node:assert/strict';
import test from 'node:test';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import resources from './ordinary-node-resource-runtime.cjs';
import {connection, fixture, input, normalizationManagerFixture, ok} from './request-preparation-parent.fixture.mjs';

type Fixture = Awaited<ReturnType<typeof fixture>>;
type Sequence = NonNullable<NonNullable<Fixture['originals']['installation']>['sequenceContractOriginal']>;

test('static Plan manager retains one admitted original and never constructs a module or Run', async t => {
  for (const outcome of ['returned', 'quote-unavailable', 'read-failed']) {
    const {f, request, events, environment} = await normalizationManagerFixture(t);
    const moon = f.context.runtime, artifact = {}, loan = {};
    const limits = Object.freeze({maxWireBytes: 2048, maxNodes: 256, maxDepth: 32});
    const primary = Error('original static Plan read failure');
    let compilation: object | undefined;
    let reentry: Promise<unknown> | undefined;
    let reads = 0, returns = 0;
    moon.clientProgramRequestProgramCompilationOriginal = parent => {
      assert.strictEqual(parent, f.parent); return compilation;
    };
    moon.clientProgramPrepareRequestProgramCompilation = () => {
      assert.equal(compilation, undefined); compilation = artifact;
      events.push('plan-compile'); return ok(artifact);
    };
    moon.clientProgramPrepareRequestOriginalExplanation = (parent, receipt, ...bounds) => {
      assert.strictEqual(parent, f.parent); assert.strictEqual(compilation, artifact);
      assert.deepEqual(bounds, [2048, 256, 32, false]); events.push('plan-quote');
      return ok(outcome === 'quote-unavailable' ? undefined : loan);
    };
    for (const name of ['clientProgramAdoptRequestProgramWithExplanation',
      'clientProgramCaptureRequestOriginalExplanation', 'clientProgramOriginalExplanationPlanWire',
      'clientProgramOriginalExplanationFactsWire', 'clientProgramReturnOriginalExplanationCapture',
      'clientProgramPrepareRequestProgramModuleBody'] as const) {
      moon[name] = () => assert.fail('Static read must not enter ' + name);
    }
    moon.clientProgramReturnRequestOriginalExplanation = value => {
      assert.strictEqual(value, loan); returns++; return ok(false);
    };
    if (outcome === 'returned') moon.clientProgramCurrentRunView = () => assert.fail('A static Plan does not inspect a Run');
    moon.clientProgramRequestOriginalStaticPlanWire = (value, inspectInstalled) => {
      assert.strictEqual(value, loan);
      assert.equal(inspectInstalled, outcome === 'returned');
      reads++; events.push('plan-read');
      reentry = f.view.fundedPreparation(request, environment, undefined, undefined, undefined, limits);
      if (outcome === 'read-failed') throw primary;
      // Explicit compiler wire port only. Core owns actual Plan/schema proof.
      return ok('same original compiler Plan wire');
    };
    const pending = f.view.fundedPreparation(request, environment, undefined, undefined, undefined, limits);
    if (outcome === 'returned') assert.equal(await pending, 'same original compiler Plan wire');
    else await assert.rejects(pending, outcome === 'read-failed'
      ? cause => cause === primary : {code: 'ClientOperationUnavailable'});
    if (reentry) await assert.rejects(reentry, {code: 'ForeignInstalledSourceProducer'});
    assert.equal(reads, outcome === 'quote-unavailable' ? 0 : 1);
    assert.equal(returns, 0, 'Return belongs to the existing producer retirement');
    assert(!events.includes('module'));
    assert.deepEqual(events.slice(0, 5), ['compiled', 'normalization', 'plan-borrow', 'plan-compile', 'plan-quote']);
    assert(!f.calls.includes('retire-registry-original'), 'No submitted preparation alias was issued');
  }
});

test('static Effect Plan manager reads the same checked Request without execution material or Run', async () => {
  const environment = {}, f = await fixture({environment}), moon = f.context.runtime, request = {};
  const original = input();
  const program = {...original, stages: [{...original.stages[0],
    effects: {save: {update: {target: 'connector://crm/account',
      mapping: 'mapping:crm.account.v1', from: {result: 'rows'}, id: 'n', set: {Name: {field: 'n'}}}}}}]};
  const receipt = f.view.beforeSourceSnapshot('program', program, {}, connection);
  assert.ok(receipt && typeof receipt === 'object');
  const body = f.view.captureSourceSnapshot(receipt, {kind: 'program', input: program}, snapshotClientRequest);
  assert.ok(body && typeof body === 'object' && 'input' in body);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
  // The fake supplies only the Common ports reached by this case.
  f.originals.installation = {sequenceContractOriginal: {moon: moon as Sequence['moon'], admission: {}}};
  const bounds = Object.freeze({maxWireBytes: 4096, maxNodes: 512, maxDepth: 32});
  const events: string[] = [], originalWire = 'original Effectful static envelope';
  let reentry: Promise<unknown> | undefined;
  moon.clientProgramPrepareRequestNativeComputation = function(parent, original, captured) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
    assert.equal(captured, body.input); events.push('check'); return ok(undefined);
  };
  moon.clientProgramRequestOriginalStaticPlanWire = () => assert.fail('No Pure Plan loan for an Effect');
  moon.clientProgramRequestCheckedStaticPlanIssueCode = () => assert.fail('No original static refusal selected');
  moon.clientProgramReadRequestCheckedStaticPlan = function(parent, original, ...limits) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
    assert.deepEqual(limits, [4096, 512, 32, [], false]); events.push('original-plan');
    reentry = f.view.fundedPreparation(request, environment, undefined, undefined, undefined, bounds);
    reentry?.catch(() => {});
    return ok(originalWire);
  };
  moon.clientProgramFinishRequestComputation = function(parent, original, selected, publication) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
    assert.equal(selected, environment); assert.equal(publication, f.context.preparedEnvironment);
    moon.clientProgramReadRequestCheckedStaticPlan = () => assert.fail('Substituted later namespace method');
    events.push('compile'); return ok('effectful');
  };
  const holder = {}, prepared = {}; let returned = false, retiring = false;
  const abort = moon.clientProgramAbortRequestPreparation;
  moon.clientProgramBorrowRequestEffectPlanInput = (parent, original, staticModels) => {
    assert.equal(parent, f.parent); assert.equal(original, receipt); assert.equal(staticModels, true);
    events.push('plan-input'); return ok(holder);
  };
  moon.clientProgramEffectPreparationInputRead = value => {assert.equal(value, holder); return prepared;};
  moon.clientProgramEffectPreparationInputRetirementStarted = value => {assert.equal(value, holder); return retiring;};
  moon.clientProgramEffectPreparationInputReturn = value => {assert.equal(value, holder); returned = true; return ok(false);};
  moon.clientProgramAbortRequestPreparation = parent => {
    if (returned) return Reflect.apply(abort, moon, [parent]);
    retiring = true; return ok(undefined);
  };
  moon.clientProgramEffectInferOccurrences = value => {assert.equal(value, prepared); return ok([]);};
  for (const name of ['clientProgramIssueRequestEffectRunMaterials',
    'clientProgramPrepareRequestProgramModuleBody', 'clientProgramAdoptRequestEffectPreparation'] as const) {
    moon[name] = () => assert.fail('Static Effect read cannot enter ' + name);
  }
  try {
    assert.equal(await f.view.fundedPreparation(request, environment, undefined, undefined, undefined, bounds), originalWire);
    assert.ok(reentry);
    await assert.rejects(reentry, {code: 'ForeignInstalledSourceProducer'});
    assert.deepEqual(events, ['check', 'compile', 'plan-input', 'original-plan']);
    assert(!f.calls.includes('retire-registry-original'), 'No submitted alias or Run');
  } finally {
    f.view.finishSourceProducer(receipt, 'returned'); await f.view.close();
  }
  assert.ok(f.original);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});
