import './local-values-retention-original.test.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';
import {sourceFreeValuesPlan, sourceFreeValuesAdmissionEvidence, sourceFreePlanOriginal,
  sourceFreePlanExecutionOwner, prepareTimedClientInvocation, acquiredTaskRunAdmission}
  from './local-values-plan.mjs';

// Exercise the real assembly functions. Core issuers below are explicit ports;
// these checks prove forwarding/custody, not Core admission or physical work.
const digest = value => 'sha256:' + createHash('sha256').update(JSON.stringify(value)).digest('hex');
function publicationFixture(rows = 10) {
  const prepared = {}, publication = {}, original = {}, calls = [];
  const compiled = {kind: 'values', admission: {}, compiledPlan: {identity: 'compiled-original'},
    preparedEvidence: {wire: 'prepared-original'}, authorization: {wire: 'authorization-original'}};
  const control = {
    prepareCheckedClientCompiledRun(actual, kind, policy) {
      assert.strictEqual(actual, prepared); assert.equal(kind, 'values'); calls.push(policy); return compiled;
    },
    defineCheckedClientCompiledRun(actual, options) {
      assert.strictEqual(actual, compiled);
      return {identity: 'run-original', wire: options.retainedDefinitionWire ?? JSON.stringify({
        created_at: options.createdAt, valid_until: options.validUntil})};
    },
    issueCheckedClientCompiledInvocation: () => ({observation: {}, invocation: {}}),
    seal: (name, wire) => Object.freeze({name, wire}),
    sealRunEvidence: (name, wire) => Object.freeze({name, wire}),
    preparedClientNormalizationEvidence(actual) {assert.strictEqual(actual, prepared); return {};},
      preparedClientAuthoringContextEvidence(actual, original){assert.strictEqual(actual,prepared);assert.ok(original);return {};},
    compiledRunResultTransformation: () => undefined,
    captureOriginalClientRunPlan(actual, owner) {
      assert.strictEqual(actual, compiled); assert.strictEqual(owner, prepared); return original;
    },
  };
  const moon = {
    clientProgramPreparedLocalPublicationLimits(actual, owner) {
      assert.strictEqual(actual, publication); assert.strictEqual(owner, prepared);
      return resultOutputLimitFields.map(name => name === 'maxRows' ? rows : 1000);
    },
    clientProgramDefinitionCid: () => 'program-original', clientProgramResultCount: () => 1,
  };
  return {prepared, publication, compiled, original, calls, control, moon, options: {
    moon, control, preparedProgram: prepared, publicationOriginal: {kind: 'preparation', value: publication, authoringContext: {}},
    authorityScopeCid: 'scope', namespaceId: 'namespace', storeAuthorityCid: 'store',
    now: () => new Date().toISOString()}};
}

test('large original Values demand uses the existing policy identity across retained definition replay', () => {
  const f = publicationFixture(100000), first = sourceFreeValuesPlan(f.options);
  const second = sourceFreeValuesPlan({...f.options, retainedDefinitionWire: first.runDefinition.wire});
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[0].hostPolicyCid,
    digest({version: 'actql-installed-local-policy/0.1', name: 'source-free-values'}));
  assert.deepEqual(f.calls[1], f.calls[0]);
  assert.equal(second.runDefinition.wire, first.runDefinition.wire);
  assert.equal(first.outputLimits.maxRows, 100000);
  assert.deepEqual(sourceFreeValuesAdmissionEvidence(first),
    {prepared: 'prepared-original', authorization: 'authorization-original'});
  assert.strictEqual(sourceFreePlanOriginal(first), f.original);
});

test('original publication owner remains required, independent of row count', () => {
  const f = publicationFixture(121);
  assert.throws(() => sourceFreeValuesPlan({...f.options, publicationOriginal: {}}),
    {message: 'InvalidCheckedLocalPublicationOriginal'});
  assert.throws(() => sourceFreeValuesPlan({...f.options,
    publicationOriginal: {kind: 'preparation', value: {}}}), assert.AssertionError);
  assert.equal(sourceFreeValuesPlan(f.options).outputLimits.maxRows, 121);
});

function timedOriginalFixture(kind = 'values', retained = false) {
  const f = publicationFixture(); f.compiled.kind = kind;
  const request = {}, artifact = {}, time = {}, context = {}, counts = {
    prepareTime: 0, compile: 0, define: 0, bind: 0, restore: 0, invocation: 0, now: 0};
  const now = new Date().toISOString();
  const header = {created_at: now, valid_until: new Date(Date.parse(now) + 86400000).toISOString()};
  const definition = {identity: 'timed-definition-original', wire: JSON.stringify(header)};
  const opaque = new Proxy({}, {get() {assert.fail('Opaque Core Option must remain uninspected');}});
  let sampled;
  Object.assign(f.control, {
    prepareClientQueryTime(owner, actualRequest, sample) {
      assert.strictEqual(owner, f.prepared); assert.strictEqual(actualRequest, request);
      assert(Number.isFinite(Date.parse(sample))); sampled = sample; counts.prepareTime++; return time;
    },
    prepareCheckedClientCompiledRun(owner, selected, policy, graph, original) {
      assert.strictEqual(owner, f.prepared); assert.equal(selected, kind);
      assert.strictEqual(original, artifact); assert.equal(graph, undefined);
      assert.equal(policy.expiresAt, header.valid_until); counts.compile++; return f.compiled;
    },
    defineCheckedClientCompiledRun(compiled, selected) {
      assert.strictEqual(compiled, f.compiled); counts.define++;
      if (!retained) {
        assert.equal(selected.createdAt, sampled);
        definition.wire = JSON.stringify({...header, created_at: sampled});
      } else assert.equal(selected.retainedDefinitionWire, definition.wire);
      return definition;
    },
    bindClientQueryTime(actualTime, owner, compiled, run, actualRequest) {
      assert.strictEqual(actualTime, time); assert.strictEqual(owner, f.prepared);
      assert.strictEqual(compiled, f.compiled); assert.strictEqual(run, definition);
      assert.strictEqual(actualRequest, request); counts.bind++; return context;
    },
    restoreClientQueryTime(owner, compiled, run, actualRequest) {
      assert.strictEqual(owner, f.prepared); assert.strictEqual(compiled, f.compiled);
      assert.strictEqual(run, definition); assert.strictEqual(actualRequest, request);
      counts.restore++; return {queryTimePreparation: time, queryTime: context};
    },
    clientQueryTimeInvocationOriginal(actualTime, owner) {
      assert.strictEqual(actualTime, time); assert.strictEqual(owner, f.prepared);
      counts.invocation++; return opaque;
    },
    checkClientCompiledRunOwner(compiled, owner) {
      assert.strictEqual(compiled, f.compiled); assert.strictEqual(owner, f.prepared);
    },
    checkClientCompiledRunDefinition(compiled, run) {
      assert.strictEqual(compiled, f.compiled); assert.strictEqual(run, definition);
    },
  });
  const retainedInvocation = {preparedProgram: f.prepared, requestIdentity: request,
    compiled: undefined, runDefinition: undefined, createdAt: undefined, validUntil: undefined,
    queryTimePreparation: undefined, queryTime: undefined};
  const options = {...f.options, requestIdentity: request, compilationOriginal: artifact,
    retainedInvocation, kind, now: () => {counts.now++; return now;},
    ...(retained ? {retainedDefinitionWire: definition.wire} : {})};
  return {...f, request, time, context, definition, opaque, counts, options,
    build: () => prepareTimedClientInvocation(options)};
}

test('timed original construction binds one sample and first compilation before forwarding Core Option', () => {
  for (const kind of ['values', 'tasks']) {
    const f = timedOriginalFixture(kind), carrier = f.build(), original = carrier.retained;
    assert.strictEqual(carrier.original, f.opaque);
    assert.strictEqual(original.compiled, f.compiled); assert.strictEqual(original.runDefinition, f.definition);
    assert.strictEqual(original.requestIdentity, f.request);
    assert.strictEqual(original.queryTimePreparation, f.time); assert.strictEqual(original.queryTime, f.context);
    assert(Object.isFrozen(original));
    assert.deepEqual(f.counts,
      {prepareTime: 1, compile: 1, define: 1, bind: 1, restore: 0, invocation: 1, now: 1});
  }
});

test('timed original restoration keeps its retained header without preparing a replacement query time', () => {
  const f = timedOriginalFixture('tasks', true), wire = f.definition.wire, carrier = f.build();
  assert.strictEqual(carrier.original, f.opaque); assert.equal(carrier.retained.runDefinition.wire, wire);
  assert.strictEqual(carrier.retained.queryTimePreparation, f.time);
  assert.strictEqual(carrier.retained.queryTime, f.context);
  assert.deepEqual(f.counts,
    {prepareTime: 0, compile: 1, define: 1, bind: 0, restore: 1, invocation: 1, now: 1});
});

test('timed original downstream Task admission reuses its first Run without preparing another time', () => {
  const f = timedOriginalFixture('tasks'), original = f.build().retained, before = {...f.counts};
  const admitted = acquiredTaskRunAdmission({...f.options, invocationOriginal: original,
    now: () => assert.fail('Downstream Task admission must keep its original header')});
  assert.strictEqual(admitted.compiled, f.compiled); assert.strictEqual(admitted.runDefinition, f.definition);
  assert.strictEqual(admitted.queryTimePreparation, f.time); assert.strictEqual(admitted.queryTime, f.context);
  assert.deepEqual(f.counts, before);
  for (const change of [{preparedProgram: {}}, {requestIdentity: {}}, {retainedDefinitionWire: 'foreign'}]) {
    assert.throws(() => acquiredTaskRunAdmission({...f.options, ...change, invocationOriginal: original}),
      {message: 'ForeignClientQueryInvocationOriginal'});
  }
});

test('timed original downstream Values publication preserves its first Run and original custody', () => {
  const f = timedOriginalFixture(), original = f.build().retained, before = {...f.counts};
  const plan = sourceFreeValuesPlan({...f.options, invocationOriginal: original});
  assert.strictEqual(plan.runDefinition, f.definition);
  assert.strictEqual(sourceFreePlanOriginal(plan), f.original);
  const owner = sourceFreePlanExecutionOwner(plan);
  assert.strictEqual(owner.program, f.prepared); assert.strictEqual(owner.compiled, f.compiled);
  assert(Object.isFrozen(owner)); assert.equal(sourceFreePlanExecutionOwner({...plan}), undefined);
  assert.deepEqual(sourceFreeValuesAdmissionEvidence(plan),
    {prepared: 'prepared-original', authorization: 'authorization-original'});
  assert.doesNotThrow(() => JSON.stringify(plan));
  // The separate retention clock may run; no new invocation or compiler is issued.
  assert.deepEqual({...f.counts, now: before.now}, before);
});

test('timed invocation keeps returned originals in its pre-retained carrier on failure', () => {
  for (const step of ['defineCheckedClientCompiledRun', 'bindClientQueryTime', 'clientQueryTimeInvocationOriginal']) {
    for (const primary of [undefined, Object.freeze(new Error('OriginalInvocationRefusal'))]) {
      const f = timedOriginalFixture('tasks'); f.control[step] = () => {throw primary;};
      let thrown = false;
      try {f.build();} catch (cause) {thrown = true; assert.strictEqual(cause, primary);}
      assert.equal(thrown, true);
      const held = f.options.retainedInvocation;
      assert.strictEqual(held.queryTimePreparation, f.time); assert.strictEqual(held.compiled, f.compiled);
      if (step !== 'defineCheckedClientCompiledRun') assert.strictEqual(held.runDefinition, f.definition);
      if (step === 'clientQueryTimeInvocationOriginal') assert.strictEqual(held.queryTime, f.context);
      assert.equal(f.counts.prepareTime, 1);
    }
  }
});

test('timed invocation refuses missing custody and excessive retained wire before work', () => {
  for (const change of [{retainedInvocation: undefined}, {retainedDefinitionWire: ' '.repeat(100001)}]) {
    const f = timedOriginalFixture('tasks'); Object.assign(f.options, change);
    assert.throws(() => f.build(), {message: 'OriginalClientQueryInvocationRequired'});
    assert.deepEqual(f.counts,
      {prepareTime: 0, compile: 0, define: 0, bind: 0, restore: 0, invocation: 0, now: 0});
  }
});
