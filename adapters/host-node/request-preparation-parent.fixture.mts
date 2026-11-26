import assert from 'node:assert/strict';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import resources from './ordinary-node-resource-runtime.cjs';

import type {TestContext} from 'node:test';

type Installation = Parameters<typeof prepareOrdinarySourceManagedInstallation>;
type FixtureContext = NonNullable<ReturnType<NonNullable<Installation[1]['preparationContext']>>>;
type Runtime = FixtureContext['runtime'];
type Mutable<Value> = {-readonly [Key in keyof Value]: Value[Key]};
type FixtureRuntime = Partial<Mutable<Runtime>> & {
  clientProgramAbortRequestPreparation: Runtime['clientProgramAbortRequestPreparation'];
  clientProgramFinishRequestComputation: NonNullable<Runtime['clientProgramFinishRequestComputation']>;
  clientProgramReserveRequestSnapshot(parent: unknown, receipt: object, units: bigint, values: bigint): unknown;
  clientProgramPrepareRequestProgramNormalization?(parent: unknown, receipt: object): unknown;
  clientProgramRequestProgramNormalizationIssueCode?(): unknown;
  clientProgramPrepareRequestProgramAuthoringContext?(parent: unknown, receipt: object): unknown;
  clientProgramRequestProgramAuthoringContextIssueCode?(): unknown;
  clientProgramRequestProgramModuleIssueCode?(): unknown;
  clientProgramRequestPreparationIssueCode?(): unknown;
  clientProgramPreparationBorrowRead?(holder: unknown): unknown;
  clientProgramRequestProgramCompilationOriginal?(parent: unknown, receipt: object): unknown;
  clientProgramPrepareRequestProgramCompilation?(): unknown;
  clientProgramPrepareRequestOriginalExplanation?(parent: unknown, receipt: object,
    ...bounds: [maxBytes: number, maxNodes: number, maxDepth: number, debugEntryInstalled: boolean]): unknown;
  clientProgramAdoptRequestProgramWithExplanation?(): unknown;
  clientProgramCaptureRequestOriginalExplanation?(): unknown;
  clientProgramOriginalExplanationPlanWire?(): unknown;
  clientProgramOriginalExplanationFactsWire?(): unknown;
  clientProgramReturnOriginalExplanationCapture?(): unknown;
  clientProgramReturnRequestOriginalExplanation?(loan: unknown): unknown;
  clientProgramCurrentRunView?(): unknown;
  clientProgramRequestOriginalStaticPlanWire?(loan: unknown, inspectInstalled: boolean): unknown;
  clientProgramRequestCheckedStaticPlanIssueCode?(): unknown;
  clientProgramReadRequestCheckedStaticPlan?(parent: unknown, receipt: object,
    maxBytes: number, maxNodes: number, maxDepth: number, models: readonly unknown[], inspectInstalled: boolean): unknown;
  clientProgramEffectInferOccurrences?(prepared: unknown): unknown;
};
type FixtureOptions = {
  beginFailure?: unknown;
  environment?: unknown;
  observe?: unknown;
  sourceFreeMaxWork?: number;
  validate?: () => void;
  validateRetained?: () => void;
  control?: bigint[];
  policyLimits?: bigint[];
};
type ParentFixture = {
  view: Awaited<ReturnType<typeof prepareOrdinarySourceManagedInstallation>>;
  calls: string[];
  shapes: {units: bigint; values: bigint}[];
  context: Readonly<{runtime: FixtureRuntime; environment: unknown; preparedEnvironment: object;
    retainedRelationOutput: false; sourceFreeMaxWork?: number}>;
  originals: Mutable<Installation[0]>;
  readonly parent: object;
  readonly original: object | undefined;
};
type NormalizationFixture = {
  f: ParentFixture;
  request: object;
  prepared: object;
  events: string[];
  environment: object;
};

// Actual normal manager/adapter/Resource originals; Core phase/shape results
// are explicit ports. This does not certify a matching Common or body tariff.
export const ok = <Value,>(value: Value) => ({$tag:1, _0:value});
export const input = () => ({version:'actql/0.1',id:'parent',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{
  schema:{n:{type:'number',nullable:false}},rows:[{n:1}],
}}],results:{rows:{from:'v',fields:['n']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
export const connection = Object.freeze({mode:'local',owner:'local',consentRefs:Object.freeze([]),runners:Object.freeze([])});
export async function fixture({beginFailure, environment, observe, sourceFreeMaxWork,
  validate = () => {}, validateRetained = validate, control = [1024n, 0n],
  policyLimits = [10000n, 10000n, 10000n, 100000n, 100000n, 100000n]}: FixtureOptions = {}): Promise<ParentFixture> {
  const calls: string[] = [], shapes: {units: bigint; values: bigint}[] = [];
  const policy = {}, parent = {};
  let admission: {original: object; receipt: object;
    ports: NonNullable<ReturnType<typeof resources.prepareOriginalLocalPreparationPorts>>} | undefined;
  const stop = () => {
    assert.ok(admission);
    assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0),0);
    assert.equal(admission.ports.status(2),0);
    return ok(undefined);
  };
  const moon: FixtureRuntime = {
    clientLocalResourcePolicyOriginal(){assert.equal(this,moon);return policy;},
    clientProgramRequestPreparationControl(actual){assert.equal(this,moon);assert.equal(actual,policy);calls.push('control');return control;},
    clientLocalPreparationResourceLimits(actual){assert.equal(this,moon);assert.equal(actual,policy);calls.push('policy-limits');return policyLimits;},
    clientProgramPrepareLocalPreparationAdmission(original,receipt){
      assert.equal(this,moon);calls.push('admission');
      const ports = resources.prepareOriginalLocalPreparationPorts(original, receipt);
      assert.ok(ports);
      admission = {original, receipt, ports};
      return ok(admission);
    },
    clientProgramBeginRequestPreparation(actual,receipt,selectedPolicy){
      assert.ok(admission);
      assert.equal(this,moon);assert.equal(actual,admission);assert.equal(receipt,admission.receipt);assert.equal(selectedPolicy,policy);
      if(beginFailure!==undefined) throw beginFailure;
      assert.equal(admission.ports.status(0),0);calls.push('parent');return ok(parent);
    },
    clientProgramReserveRequestSnapshot(actual,receipt,units,values){
      assert.ok(admission);
      assert.equal(this,moon);assert.equal(actual,parent);assert.equal(receipt,admission.receipt);
      assert.equal(typeof units,'bigint');assert.equal(typeof values,'bigint');
      assert.ok(units>=values && values>0n);shapes.push({units,values});calls.push('snapshot-grow');return ok(undefined);
    },
    clientProgramAbortRequestPreparation(actual){assert.equal(this,moon);assert.equal(actual,parent);calls.push('abort-parent');return stop();},
    clientProgramCleanupLocalPreparationAdmission(actual){
      assert.ok(admission);
      assert.equal(this,moon);assert.equal(actual,admission);calls.push('cancel-admission');assert.equal(admission.ports.cancelUnpublished(),0);return ok(undefined);
    },
    clientProgramPrepareRequestNativeComputation(){assert.fail('No semantic compilation selected');},
    clientProgramPrepareRequestSourceComputation(){assert.fail('No Source semantic check selected');},
    clientProgramFinishRequestComputation(owner,actual,selected,publication){
      assert.ok(admission);
      assert.equal(this,moon);assert.equal(owner,parent);assert.equal(actual,admission.receipt);
      assert.equal(selected,environment);assert.equal(publication,context.preparedEnvironment);
      calls.push('compiler-finish');return ok('effect_free');
    },
    clientProgramPrepareRequestPolicySubjects(){assert.fail('No policy verifier selected');},
    clientProgramReadRequestPolicySubject(){assert.fail('No policy descriptor selected');},
    clientProgramBindRequestPolicySubject(){assert.fail('No policy binding selected');},
    clientProgramFinishRequestPolicySubjects(){assert.fail('No policy supplement selected');},
    clientProgramPrepareRequestProgramNormalization(){return ok(undefined);},
    clientProgramRequestProgramNormalizationIssueCode() {},
    clientProgramPrepareRequestProgramAuthoringContext(){return ok({});},
    clientProgramRequestProgramAuthoringContextIssueCode() {},
    clientProgramPrepareRequestProgramModuleBody(){assert.fail('No module compilation selected');},
    clientProgramReserveRequestEffectOriginalMaterial(){assert.fail('No Effect original projection selected');},
    clientProgramRequestProgramModuleIssueCode(){assert.fail('No module failure projection selected');},
    clientProgramRequestPreparationIssueCode(){assert.fail('No typed Request refusal selected');},
    clientProgramBorrowRequestProgramPlanInput(){assert.fail('No constructor input borrow selected');},
    clientProgramComposedInferOccurrences: () => ok([]),
    clientProgramSerializationOccurrences: () => [],
    clientProgramAcquisitionCount(){return 0;},
    clientProgramAdoptRequestProgramPreparation(){assert.fail('No Run adoption selected');},
  };
  const context=Object.freeze({runtime:moon,environment,preparedEnvironment:{},retainedRelationOutput:false as const,
    ...(sourceFreeMaxWork===undefined?{}:{sourceFreeMaxWork})});
  const originals: Mutable<Installation[0]> = observe === undefined ? {} : {installation: {authorization: {observe}}};
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator(actual){assert.equal(actual,originals);validate();},
    retainedValidator(actual){assert.equal(actual,originals);validateRetained();},
    preparationContext(actual) {
      assert.equal(actual, originals);
      // Each case selects the Common ports it exercises. Unselected ports
      // remain absent so the real manager still sees the original inventory.
      return context as typeof context & FixtureContext;
    },
    retireInitialPreparation(actual,prepared){assert.equal(actual,originals);assert.ok(prepared);calls.push('retire-registry-original');},
  },false);
  return {view,calls,shapes,context,originals,get parent(){return parent;},get original(){return admission?.original;}};
}

export async function normalizationManagerFixture(t: Pick<TestContext, 'after'>,
  normalizationFailure?: unknown, options: FixtureOptions = {}): Promise<NormalizationFixture> {
  const environment = {}, f = await fixture({environment, ...options}), moon = f.context.runtime;
  const holder = {}, prepared = {}, normalization = {}, admission = {};
  const events: string[] = [];
  f.originals.installation = {sequenceContractOriginal: {moon: moon as FixtureRuntime & Runtime, admission}};
  moon.clientProgramPrepareRequestNativeComputation = () => ok(undefined);
  moon.clientProgramRequestParametersOriginal = () => ok(undefined);
  const finish = moon.clientProgramFinishRequestComputation;
  moon.clientProgramFinishRequestComputation = function(...args) {
    events.push('compiled'); return Reflect.apply(finish, this, args);
  };
  moon.clientProgramPrepareRequestProgramNormalization = function(parent, input) {
    assert.strictEqual(this, moon); assert.strictEqual(parent, f.parent); assert.strictEqual(input, receipt);
    events.push('normalization');
    if (normalizationFailure !== undefined) throw normalizationFailure;
    return ok(normalization);
  };
  moon.clientProgramBorrowRequestProgramPlanInput = function(parent, input) {
    assert.strictEqual(parent, f.parent); assert.strictEqual(input, receipt);
    events.push('plan-borrow'); return ok(holder);
  };
  moon.clientProgramPreparationBorrowRead = actual => {assert.strictEqual(actual, holder); return prepared;};
  moon.clientProgramPreparationBorrowReturn = actual => {assert.strictEqual(actual, holder); return ok(false);};
  moon.clientProgramPreparationBorrowRetirementStarted = actual => {assert.strictEqual(actual, holder); return true;};
  const abort = moon.clientProgramAbortRequestPreparation;
  let aborted = false;
  moon.clientProgramAbortRequestPreparation = function(parent) {
    assert.strictEqual(parent, f.parent);
    if (aborted) return ok(undefined); // Core abort is idempotent after its original return.
    const result = Reflect.apply(abort, moon, [parent]); aborted = true; return result;
  };
  moon.clientProgramPrepareRequestProgramModuleBody = function(parent, input) {
    assert.strictEqual(parent, f.parent); assert.strictEqual(input, receipt);
    events.push('module'); return ok(undefined);
  };
  const request = {}, original = input();
  const receipt = f.view.beforeSourceSnapshot('program', original, {}, connection);
  assert.ok(receipt && typeof receipt === 'object');
  const body = f.view.captureSourceSnapshot(receipt,
    {kind: 'program', input: original, parameters: {}}, snapshotClientRequest);
  assert.ok(body && typeof body === 'object');
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
  t.after(async () => {
    f.view.finishSourceProducer(receipt, 'returned');
    assert.equal((await f.view.close()).pending, false);
    assert.ok(f.original);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  });
  return {f, request, prepared, events, environment};
}
