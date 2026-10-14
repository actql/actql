import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';

test('original current loss in BeforeInvoke diagnostic requests Core stop before the final gate',async()=>{
  // Actual operation observer/stop wiring with explicit Common doubles. This
  // proves callback ordering, not a compiled gate, Scope admission or I/O ACK.
  const active={},compiled={},definition={},graph={},scope={},read={},consumer={},callSet={};
  const events=[];let current=true,stopped=false,observer;
  const control={
    claimCheckedClientInferNodePreparationLayout(_compiled,_definition,_graph,actualRead){
      assert.equal(_compiled,compiled);assert.equal(_definition,definition);
      assert.equal(_graph,graph);assert.equal(actualRead,read);return consumer;
    },
    startCheckedClientInferOriginalPreparation(...args){
      assert.equal(args[8],consumer);return active;
    },
  };
  const moon={
    clientProgramBindInferPhysicalPreflightCurrent:()=>assert.fail('no physical factory in this counter'),
    clientProgramRequireInferCallEntry:()=>({$tag:1,_0:undefined}),
    clientProgramBindInferModelObservation(owner,prepared,callback){
      assert.equal(owner,active);assert.equal(prepared,callSet);observer=callback;
      return {$tag:1,_0:undefined};
    },
    clientProgramInferPhysicalObservationFacts:()=>({_0:0,_1:'attempt',_2:'before_invoke',_3:undefined}),
    clientProgramCancelInferExecution(owner){assert.equal(owner,active);events.push('stop');stopped=true;},
    clientProgramAdvanceInferExecution(){
      observer({});events.push('finalGate');
      if(!stopped)events.push('send');
      return {$tag:1,_0:stopped?'stopped':'waiting'};
    },
    clientProgramInferExecutionPollKind:value=>value,
    clientProgramInferExecutionStopped:()=>stopped,
    clientProgramCleanupInferExecution:()=>({$tag:1,_0:true}),
  };
  const operation=openNodeInferOperation({moon,provider:{},graph,durableCalls:true,
    originalPreparation:{compiled,runDefinition:definition,control,scope,read,
      readRetainedBytes:7n,readExecutionBytes:5n,modelRetainedBytes:100n,modelExecutionBytes:5n,
      nodeInstallation:{layout:{},installation:{},runtimeArtifactCid:'runtime',
        layoutArtifactCid:'layout',probability:undefined}},
    assertRuntimeCurrent(){if(!current)throw new Error('OriginalRuntimeChanged');}});
  operation.bindModelObservation(callSet,()=>{events.push('diagnostic');current=false;});
  await assert.rejects(operation.run(),{code:'InferExecutionStopped'});
  assert.deepEqual(events,['diagnostic','stop','finalGate']);
  assert.equal(operation.cleanup(),true);
});

for (const route of ['plain', 'composed', 'keyed']) {
  const composed = route !== 'plain', keyed = route === 'keyed';
  test(`restored ${route} INFER forwards the current issuer without deriving authority from saved rows`, async () => {
    const issuer = {}, active = {}, savedScope = {};
    const prefix = {}, ledger = {}, suffix = {};
    const token = {available: true};
    const snapshot = {binding: 'original-binding', descriptorWire: 'original-descriptor',
      rows: ['original-row']};
    let opens = 0, stopped = false;
    const start = (...args) => {
      opens++;
      const index = composed ? 4 : 6;
      assert.equal(args[index], snapshot.binding);
      assert.equal(args[index + 1], snapshot.descriptorWire);
      assert.equal(args[index + 2], snapshot.rows);
      assert.equal(args[index + 3](), true);
      token.available = false;
      assert.equal(args[index + 3](), false, 'restoration cannot freeze original custody as available');
      assert.equal(args[index + 4], savedScope);
      assert.equal(args[index + (composed ? 5 : 7)], issuer,
        'only the current Host issuer reaches common readmission');
      if (composed) {
        assert.equal(args[2], prefix);
        assert.equal(args[index + 6], keyed ? ledger : undefined,
          'only the keyed root reserves on the original receiving Ledger');
        assert.equal(args[index + 7], keyed ? suffix : undefined,
          'root construction receives the checked suffix before allocation');
        assert.equal(args.length, 12);
      } else {
        assert.equal(args[index + 5], 'fragment');
        assert.equal(args[index + 6], 'ordered');
        assert.equal(args.length, 14);
      }
      return {$tag: 1, _0: active};
    };
    const moon = {
      clientProgramStartRestoredInferInput: composed ? () => assert.fail('wrong occurrence route') : start,
      clientProgramStartRestoredComposedInferInput: composed ? start : () => assert.fail('wrong occurrence route'),
      clientProgramCancelInferExecution: owner => { assert.equal(owner, active); stopped = true; },
      clientProgramInferExecutionStopped: () => stopped,
      clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
      clientProgramRestrictInferSendSlots: () => ({$tag: 1, _0: undefined}),
      clientProgramAdvanceInferRoot: () => assert.fail('cleanup must not resume Compute'),
      clientProgramBindInferComputeSuffix: () => assert.fail('root suffix cannot be bound after allocation'),
    };
    const operation = openNodeInferOperation({moon, preparedProgram: {}, graph: {}, provider: {},
      registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered',
      restoredInput: {token, snapshot, savedScope}, restoredReferenceIssuer: issuer,
      ...(keyed ? {keyedInput: {occurrence: {}, prefix, ledger}, computeSuffix: suffix}
        : composed ? {composedInput: {occurrence: {}, prefix}} : {})});
    await operation.close();
    assert.equal(opens, 1, 'cleanup never repeats restored input admission');
  });
}

test('restored reference authority cannot be supplied to fresh or generated input routes', () => {
  for (const serializedInput of [undefined, {control: {}}]) {
    assert.throws(() => openNodeInferOperation({moon: {}, provider: {},
      restoredReferenceIssuer: {}, ...(serializedInput === undefined ? {} : {
        restoredInput: {token: {}, snapshot: {}}, serializedInput,
      })}), /InvalidRestoredInferReferenceIssuer/);
  }
});

test('serialized input adopts the original generation and joint observation under existing operation custody', async () => {
  const active = {}, compiled = {}, generation = {}, issued = {}, ledger = {};
  const capturedRecovery = {originalInventory: true};
  const capturedBinding = {originalSourceBinding: true};
  const events = [];
  let stopped = false;
  const control = {
    startCheckedClientGeneratedInferExecution(run, original) {
      assert.equal(run, compiled);
      assert.equal(original, generation);
      events.push('borrow');
      events.push('start');
      return active;
    },
    startCheckedClientContentInferObservation(run, executions, originals, actualLedger, limits) {
      assert.equal(run, compiled);
      assert.deepEqual(executions, [active]);
      assert.deepEqual(originals, [generation]);
      assert.equal(actualLedger, ledger);
      assert.deepEqual(limits, {maxSlots: 1, maxWireBytes: 4096, maxWork: 4});
      return issued;
    },
  };
  const moon = {
    clientProgramStartScopedInferExecution() { throw new Error('No pure-prefix fallback'); },
    clientProgramStartSerializedInferExecution() { throw new Error('No bare output fallback'); },
    clientProgramCancelInferExecution(owner) {
      assert.equal(owner, active);
      events.push('stop');
      stopped = true;
    },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
    clientProgramStartInferObservationIssuance() { throw new Error('No Model-only fallback'); },
  };
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 3,
    graph: {}, provider: {}, serializedInput: {control, compiled, generation, capturedRecovery, capturedBinding},
    retainOperation(value) { assert.equal(typeof value.close, 'function'); events.push('retain'); }});
  assert.deepEqual(events, ['borrow', 'start', 'retain']);
  assert.equal(operation.capturedContentRecovery(), capturedRecovery,
    'Model fixed-input persistence receives the original capture inventory, not a regenerated envelope');
  assert.equal(operation.capturedContentBinding(), capturedBinding,
    'physical Source binding follows the same generation rather than current candidate selection');
  assert.equal(operation.startObservation({ledger, maxSlots: 1, maxWireBytes: 4096, maxWork: 4}), issued);
  await operation.close();
  assert.equal(events.includes('stop'), true);
});

for (const other of ['acquiredInput', 'composedInput', 'restoredInput', 'savedCapture', 'savedSlots']) {
  test(`serialized input cannot silently replace the ${other} recovery/input owner`, () => {
    let starts = 0;
    const moon = {clientProgramStartSerializedInferExecution() { starts++; }};
    assert.throws(() => openNodeInferOperation({moon, provider: {}, [other]: {},
      serializedInput: {control: {startCheckedClientGeneratedInferExecution() { starts++; }}}}),
    TypeError);
    assert.equal(starts, 0);
  });
}

test('generated Model child borrows the actual Local inputs and cannot drive a second executor', async () => {
  const active = {}, compiled = {}, generation = {}, graph = {}, provider = {}, ledger = {}, issued = {};
  const inputs = [Object.freeze({originalProducer: true})];
  let stopped = false, opened = 0, advances = 0;
  const control = {
    startCheckedClientGeneratedInferInputs(run, original, selected, actualInputs, physical) {
      assert.equal(run, compiled);
      assert.equal(original, generation);
      assert.equal(selected, graph);
      assert.equal(actualInputs, inputs);
      assert.equal(physical, provider);
      opened++;
      return active;
    },
    startCheckedClientGeneratedInferExecution() { throw new Error('No producer replay'); },
    startCheckedClientContentInferObservation(run, executions, originals, actualLedger) {
      assert.equal(run, compiled);
      assert.deepEqual(executions, [active]);
      assert.deepEqual(originals, [generation]);
      assert.equal(actualLedger, ledger);
      return issued;
    },
  };
  const moon = {
    clientProgramStartScopedInferExecution() { throw new Error('No pure Program fallback'); },
    clientProgramAdvanceInferExecution() { advances++; throw new Error('Local alone advances'); },
    clientProgramCancelInferExecution(owner) { assert.equal(owner, active); stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
    clientProgramStartInferObservationIssuance() { throw new Error('No Model-only evidence'); },
  };
  const operation = openNodeInferOperation({moon, graph, provider,
    serializedInput: {control, compiled, generation, inputs}});
  assert.equal(opened, 1);
  assert.equal(operation.contentGenerationCount, 1);
  assert.deepEqual(operation.contentGenerations(), [generation]);
  await assert.rejects(operation.run(), /InferComponentDrivenByLocal/);
  assert.equal(advances, 0);
  assert.equal(operation.startObservation({ledger, maxSlots: 1, maxWireBytes: 4096, maxWork: 4}), issued);
  await operation.close();
  assert.equal(opened, 1);
});

test('generated Model child refuses malformed inputs and unconnected restored input before opening', () => {
  let opened = 0;
  const control = {startCheckedClientGeneratedInferInputs() { opened++; }};
  for (const inputs of [null, {}, 'rows']) {
    assert.throws(() => openNodeInferOperation({moon: {}, graph: {}, provider: {},
      serializedInput: {control, compiled: {}, generation: {}, inputs}}), TypeError);
  }
  assert.throws(() => openNodeInferOperation({moon: {}, graph: {}, provider: {}, restoredInput: {},
    serializedInput: {control, compiled: {}, generation: {}, inputs: []}}), TypeError);
  assert.equal(opened, 0);
});

for (const [name, text] of [['decomposed', 'e\u0301'], ['composed', '\u00e9'],
  ['carriage return', '\r'], ['line feed', '\n'], ['CRLF', '\r\n'],
  ['nested mixed text', 'nested e\u0301 \u00e9\r\n\r\n']]) {
  test(`Model original Run packaging preserves ${name} data bytes`, () => {
    const wire = JSON.stringify({text, nested: [{text}, {child: {text}}]});
    const compiled = {template: {wire}, preparedEvidence: {wire},
      authorization: {wire}, compiledPlan: {wire}};
    const actual = JSON.parse(originalModelRunWire(compiled, {wire}));
    assert.deepEqual(actual, {boundInvocationTemplateWire: wire,
      preparedInvocationWire: wire, runAuthorizationWire: wire,
      compiledPlanWire: wire, runDefinitionWire: wire});
    for (const original of Object.values(actual)) {
      assert.equal(JSON.parse(original).text, text);
      assert.deepEqual(JSON.parse(original).nested, [{text}, {child: {text}}]);
    }
  });
}

// Adapter lifetime tests. The Core ports are explicit doubles; public Store
// authentication and process restart are covered by the installed acceptance.
function fixture({count = 1, missingSlot = false, missingOwner = false, cleanupResult = () => true} = {}) {
  const active = {}, inventory = {}, input = {}, artifact = {};
  let stopped = false;
  let advances = 0;
  const moon = {
    clientProgramStartScopedInferExecution: () => ({$tag: 1, _0: active}),
    clientProgramRequireInferCallEntry: owner => {
      assert.equal(owner, active);
      return {$tag: 1, _0: undefined};
    },
    clientProgramAdvanceInferExecution: () => {
      advances++;
      return {$tag: 1, _0: stopped ? 'stopped' : 'waiting'};
    },
    clientProgramInferExecutionPollKind: poll => poll,
    clientProgramInferPreparedCallSet: () => missingOwner ? undefined : inventory,
    clientProgramInferPreparedCallCount: () => count,
    clientProgramInferPreparedInput: () => input,
    clientProgramInferPreparedInputArtifact: () => artifact,
    clientProgramInferPreparedIdentities: () => ({_0: 'models/fixture', _1: 'task', _2: 'request'}),
    clientProgramInferPreparedCallAt: () => missingSlot ? undefined : 'slot',
    strategyRunEvidenceJson: value => value === artifact ? 'artifact' : 'slot',
    clientProgramInferCallScopeUnitId: () => 'input',
    clientProgramInferCallScopeSnapshot: () => ({$tag: 1, _0: 'original-scope'}),
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: cleanupResult()}),
  };
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 0,
    graph: {}, registry: '', values: '', fragment: '', ordered: '', provider: {},
    durableCalls: true});
  return {operation, inventory, input, advances: () => advances};
}

test('prepared Waiting leaves the physical driver after one advance', async () => {
  const f = fixture();
  const waiting = await f.operation.run();
  assert.equal(waiting.status, 'waiting');
  assert.equal(waiting.preparedCallSet, f.inventory);
  assert.equal(f.advances(), 1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.advances(), 1);
  const facts = f.operation.preparedFacts(f.inventory);
  assert.equal(facts.input, f.input);
  assert.deepEqual(facts.slotWires, ['slot']);
  assert.equal(Object.isFrozen(facts.slotWires), true);
  await f.operation.close();
});

test('prepared Model operation retires input lookup only after successful cleanup', async () => {
  let pending = true, failure, cleanups = 0;
  const f = fixture({cleanupResult() {
    cleanups++;
    if (failure !== undefined) throw failure;
    return !pending;
  }});
  await f.operation.run();
  assert.equal(f.operation.preparedFacts(f.inventory).input, f.input);
  assert.equal(f.operation.cleanup(), false, 'no reclamation before physical stop');
  assert.equal(cleanups, 0);
  await f.operation.stop();
  assert.equal(f.operation.cleanup(), false);
  assert.equal(f.operation.preparedFacts(f.inventory).input, f.input, 'pending cleanup retains the original');
  failure = new Error('ModelCleanupUnavailable');
  assert.throws(() => f.operation.cleanup(), error => error === failure);
  assert.equal(f.operation.cleanupPending(), true);
  assert.equal(f.operation.preparedCallSet(), f.inventory);
  failure = undefined;
  pending = false;
  assert.equal(f.operation.cleanup(), true);
  assert.equal(f.operation.preparedCallSet(), undefined);
  assert.throws(() => f.operation.preparedFacts(f.inventory), /InferPreparedOwnerUnavailable/);
  assert.equal(f.operation.evaluationRequest(0), undefined);
  assert.equal(f.operation.cleanup(), true);
  assert.equal(cleanups, 3, 'successful reclamation is not repeated');
  assert.equal(f.advances(), 1, 'cleanup retries do not restart Compute');
});

test('Waiting without the actual prepared owner is refused', async () => {
  const f = fixture({missingOwner: true});
  await assert.rejects(f.operation.run(), /InferPreparedOwnerUnavailable/);
  await f.operation.close();
});

for (const count of [-1, 129, NaN]) {
  test(`a non-finite or excessive prepared inventory (${count}) is refused`, async () => {
    const f = fixture({count});
    await f.operation.run();
    assert.throws(() => f.operation.preparedFacts(f.inventory), /InferPreparedOwnerUnavailable/);
    await f.operation.close();
  });
}

test('a missing ordered call cannot become a partial approved inventory', async () => {
  const f = fixture({missingSlot: true});
  await f.operation.run();
  assert.throws(() => f.operation.preparedFacts(f.inventory), /InferPreparedCallUnavailable/);
  await f.operation.close();
});
