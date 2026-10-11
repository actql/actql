import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Fixed expected values from the selected GoogleSQL C++ reference and the
// public finite-FLOAT64 contract, independently of this product's evaluator.
// The ordinary/subnormal/modular cases intentionally reject simple x*10^n
// implementations and the previously investigated exact-rational proxy.
const literal = value => ({literal: value});
const call = (op, x, n) => ({[op]: [literal(x), literal(n)]});
const number = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});
const vectors = [
  ['ordinary', [
    ['round',1.235,2,1.24], ['trunc',1.235,2,1.23],
    ['round',1.005,2,1], ['round',1.0050000000000001,2,1.01],
    ['round',2.675,2,2.67], ['round',2.6750000000000003,2,2.68],
    ['trunc',0.3,1,0.2], ['trunc',0.30000000000000004,1,0.3],
  ]],
  ['left_and_sign', [
    ['round',125,-1,130], ['trunc',125,-1,120],
    ['round',-125,-1,-130], ['trunc',-125,-1,-120],
    ['round',124.99999999999999,-1,120], ['round',125.00000000000001,-1,130],
    ['round',-1.005,2,-1], ['trunc',-0.3,1,-0.2],
  ]],
  ['subnormal', [
    ['round',2.2250738585072014e-308,311,2.2250000000000004e-308],
    ['trunc',2.2250738585072014e-308,311,2.2250000000000004e-308],
    ['round',2.2250738585072014e-308,316,2.22507386e-308],
    ['trunc',2.2250738585072014e-308,316,2.2250738499999997e-308],
    ['round',5e-324,323,0], ['round',5e-324,324,5e-324],
    ['round',1e-323,323,1e-323], ['trunc',1e-323,323,0],
  ]],
  ['extended_precision', [
    ['round',2.328158521232893e41,-26,2.3281585212328932e41],
    ['round',2.3281585212328932e41,-26,2.3281585212328932e41],
    ['trunc',2.3281585212328932e41,-26,2.3281585212328932e41],
    ['trunc',1.1640792606164466e41,-25,1.1640792606164466e41],
    ['trunc',1.0608098227205722e-8,24,1.0608098227205722e-8],
    ['trunc',9.293272072201609e-11,26,9.293272072201609e-11],
    ['trunc',1.0182419849537964e-8,24,1.0182419849537964e-8],
  ]],
  ['extreme_position', [
    ['round',1.7976931348623157e308,1,1.7976931348623157e308],
    ['trunc',1.7976931348623157e308,-308,1e308],
    ['round',1.7976931348623157e308,-309,0],
    ['round',1.25,1e100,1.25], ['trunc',1.25,-1e100,0],
    ['round',4503599627370497,0,4503599627370497],
    ['trunc',-0.1,0,0], ['round',-5e-324,323,0],
  ]],
];
const batches = vectors.map(([id, values]) => ({id, cases: values.map(([op,x,n,y],i) =>
  number('v'+i, `${op.toUpperCase()}(${x}, ${n})`, call(op,x,n), y))}));

function program(id, cases, params, empty = false) {
  const names = cases.map(item => item.name);
  return {version: 'actql/0.1', id, ...(params ? {params} : {}), stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {unit: {type: 'boolean', nullable: false}},
        rows: empty ? [] : [{unit: true}]}, as: 'seed'},
      {from: 'seed', derive: Object.fromEntries(cases.map(item =>
        [item.name, item.expression])), as: 'derived'},
      {select: names, as: 'out'},
    ], results: {rows: {from: 'out', fields: names}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}

function sourceFor(format, id, cases, params, empty = false) {
  if (format === 'json') return JSON.stringify(program(id, cases, params, empty));
  const select = 'SELECT ' + cases.map(item => `${item.text} AS ${item.name}`).join(', ');
  return format === 'aql-text' ? 'SELECT TRUE AS unit |> ' + (empty ? 'WHERE FALSE |> ' : '') + select : select + (empty ? ' WHERE FALSE' : '');
}

async function fixture(t, {onAdvance, onComputed} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-round-precision-'));
  const keys = generateKeyPairSync('ed25519');
  let client;
  let dispatches = 0;
  let advances = 0;
  let computed;
  t.after(async () => {
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {
    directory, retainedRelationOutput: true, authorization: {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'round-precision',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) { if (name === 'computed') {computed = detail; onComputed?.(detail);} },
      async faultInjection(name, detail) {
        if (name === 'dispatch_reserved') dispatches++;
        if (name === 'local_compute_advanced' && BigInt(detail.work) > 0n) {
          advances++; await onAdvance?.(advances, detail);
        }
      },
    },
  }});
  return {client, dispatches: () => dispatches, advances: () => advances,
    computed: () => computed};
}

async function assertPublished(f, source, options, cases) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [Object.fromEntries(cases.map(item => [item.name, item.expected]))];
  const columns = cases.map(item => ({name: item.name, contract: item.contract}));
  const actual = await run.result('answer').all();
  assert.deepEqual(actual, expected);
  for (const value of Object.values(actual[0])) {
    if (value !== null) {
      assert.ok(Number.isFinite(value));
      assert.ok(!Object.is(value, -0), 'published zero is canonical');
    }
  }
  assert.deepEqual((await run.result('answer').describe()).columns, columns);
  assert.ok(f.advances() > beforeAdvances, 'ordinary execution must make charged Local progress');
  assert.ok(f.computed().outputRepresentations.some(entry => entry.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  assert.deepEqual((await attached.result('answer').describe()).columns, columns);
  assert.equal(f.dispatches(), before, 'resend and retained reread must not dispatch again');
}

async function assertRefused(f, source, options) {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.equal(outcome.problem.code, 'ClientProgramInvalidInput');
    return true;
  });
}


test('public precision rounding publishes exact SQL Pipe JSON values and retained schemas',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    for (const batch of batches) for (const format of ['sql','aql-text','json']) {
      await assertPublished(f, sourceFor(format, 'precision_'+batch.id, batch.cases),
        {format, submissionRef:f.client.newSubmission({nonce:batch.id+'-'+format})}, batch.cases);
    }
  });

test('public precision rounding infers both nullable parameter operands and strict NULL',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = {x:{type:'number',nullable:true}, n:{type:'number',nullable:true}, k:{type:'number',nullable:false}};
    for (const [id, parameters, result] of [
      ['value',{x:1.235,n:2,k:2},1.24], ['value_null',{x:null,n:2,k:2},null],
      ['precision_null',{x:1.235,n:null,k:2},null],
    ]) {
      const cases = [
        number('both','ROUND(@x,@n)',{round:[{$param:'x'},{$param:'n'}]},result,true),
        number('position','ROUND(1.235,@n)',{round:[literal(1.235),{$param:'n'}]},parameters.n===null?null:1.24,true),
        number('required','ROUND(1.235,@k)',{round:[literal(1.235),{$param:'k'}]},1.24),
        number('untyped','TRUNC(NULL,2)',call('trunc',null,2),null,true),
      ];
      for (const format of ['sql','aql-text','json']) await assertPublished(f,
        sourceFor(format,'precision_nullable',cases,parameterDeclarations),
        {format,parameters,...(format==='json'?{}:{parameterDeclarations}),
         submissionRef:f.client.newSubmission({nonce:id+'-'+format})},cases);
    }
  });

test('public precision rounding refuses unsupported modes and operand types before dispatch',
  {timeout:90_000}, async t => {
    const f=await fixture(t);
    for (const op of ['round','trunc']) {
      const name=op.toUpperCase();
      const invalid=[
        {text:`${name}(1.25, '2')`,expression:call(op,1.25,'2')},
        {text:`${name}(1.25, TRUE)`,expression:call(op,1.25,true)},
        {text:`${name}(NULL, '2')`,expression:call(op,null,'2')},
        {text:`${name}('1.25', 2)`,expression:call(op,'1.25',2)},
        {text:`${name}(1.25, 2, 'ROUND_HALF_EVEN')`,expression:{[op]:[literal(1.25),literal(2),literal('ROUND_HALF_EVEN')]}},
      ];
      for (const [i,item] of invalid.entries()) for (const format of ['sql','aql-text','json']) {
        await assertRefused(f,sourceFor(format,'precision_invalid',[{name:'value',...item}]),
          {format,submissionRef:f.client.newSubmission({nonce:`${op}-${i}-${format}`})});
      }
    }
    assert.equal(f.dispatches(),0); assert.equal(f.advances(),0);
  });

test('public precision rounding keeps overflow fractional precision and demanded failures terminal',
  {timeout:120_000}, async t => {
    const f=await fixture(t); const divide={divide:[literal(1),literal(0)]};
    const failures=[
      {text:'ROUND(1.7976931348623157e308,-308)',expression:call('round',1.7976931348623157e308,-308)},
      {text:'ROUND(1.25,1.5)',expression:call('round',1.25,1.5)},
      {text:'TRUNC(1.25,-1.5)',expression:call('trunc',1.25,-1.5)},
      {text:'ROUND(NULL,1 / 0)',expression:{round:[literal(null),divide]}},
      {text:'TRUNC(NULL,1 / 0)',expression:{trunc:[literal(null),divide]}},
    ];
    for (const [i,item] of failures.entries()) for (const format of ['sql','aql-text','json']) {
      const source=sourceFor(format,'precision_failure',[{name:'value',...item}]);
      const options={format,submissionRef:f.client.newSubmission({nonce:`failure-${i}-${format}`})};
      const run=await f.client.startSource(source,options);
      const state=await run.wait({signal:AbortSignal.timeout(15000)});
      assert.equal(state.status,'failed',JSON.stringify(state));
      assert.equal(state.result_availability.answer.state,'unavailable');
      await assert.rejects(run.result('answer').all());
      const before=f.dispatches();
      assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
      const attached=await f.client.attach(run.ref);
      assert.equal((await attached.status()).status,'failed');
      await assert.rejects(attached.result('answer').all());
      assert.equal(f.dispatches(),before);
    }
  });

test('public precision rounding preserves outer and inner lazy demand',
  {timeout:60_000}, async t => {
    const f=await fixture(t); const divide={divide:[literal(1),literal(0)]};
    const cases=[
      number('outer','IF(FALSE,ROUND(NULL,1 / 0),7)',{if:[literal(false),{round:[literal(null),divide]},literal(7)]},7,true),
      number('inner','ROUND(1.235,IF(TRUE,2,1 / 0))',{round:[literal(1.235),{if:[literal(true),literal(2),divide]}]},1.24),
      number('coalesced','COALESCE(7,TRUNC(1.25,1 / 0))',{coalesce:[literal(7),{trunc:[literal(1.25),divide]}]},7),
    ];
    for (const format of ['sql','aql-text','json']) await assertPublished(f,
      sourceFor(format,'precision_lazy',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
  });


test('public precision rounding keeps complete nullable contracts on empty relations',
  {timeout:60_000}, async t => {
    const f=await fixture(t);
    const cases=[number('required','ROUND(1.235,2)',call('round',1.235,2),1.24),
      number('nullable','TRUNC(1.235,NULL)',call('trunc',1.235,null),null,true)];
    for (const format of ['sql','aql-text','json']) {
      const run=await f.client.startSource(sourceFor(format,'precision_empty',cases,undefined,true),
        {format,submissionRef:f.client.newSubmission({nonce:format})});
      assert.equal((await run.wait({signal:AbortSignal.timeout(15000)})).status,'succeeded');
      assert.deepEqual(await run.result('answer').all(),[]);
      assert.deepEqual((await run.result('answer').describe()).columns,
        cases.map(item=>({name:item.name,contract:item.contract})));
    }
  });

test('public precision rounding retains field and prior-slot references in ordered derive',
  {timeout:60_000}, async t => {
    const f=await fixture(t);
    const source=JSON.stringify({version:'actql/0.1',id:'precision_ordered',stages:[{
      id:'main',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:true},n:{type:'number',nullable:true}},
          rows:[{x:1.235,n:2},{x:-125,n:-1},{x:null,n:1},{x:1.25,n:null}]},as:'seed'},
        {from:'seed',derive:[{x:{round:[{field:'x'},{field:'n'}]}},{y:{trunc:[{field:'x'},{field:'n'}]}}],as:'derived'},
        {select:['x','y'],as:'out'}],results:{rows:{from:'out',fields:['x','y']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const run=await f.client.startSource(source,{format:'json',submissionRef:f.client.newSubmission({nonce:'ordered'})});
    assert.equal((await run.wait({signal:AbortSignal.timeout(15000)})).status,'succeeded');
    assert.deepEqual(await run.result('answer').all(),[{x:1.24,y:1.23},{x:-130,y:-130},{x:null,y:null},{x:null,y:null}]);
    assert.deepEqual((await run.result('answer').describe()).columns,
      ['x','y'].map(name=>({name,contract:{type:'number',nullable:true}})));
  });

for (const tag of ['round','trunc']) test(`public ${tag} precision cancellation stops after charged progress`,
  {timeout:60_000}, async t => {
    const reached=Promise.withResolvers(),resume=Promise.withResolvers();let completions=0;
    t.after(()=>resume.resolve());
    const f=await fixture(t,{onComputed(){completions++;reached.reject(new Error('completed before cancellation boundary'));},
      async onAdvance(_count,detail){if(detail.task===1 && BigInt(detail.progress)>0n){reached.resolve(detail);await resume.promise;}}});
    // Keep the inherited 100-row Values ceiling. A separate consumer task
    // makes the cancellation barrier specific to numeric derivation progress.
    const source=JSON.stringify({version:'actql/0.1',id:tag+'_precision_cancel',stages:[{
      id:'seed',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:false}},
          rows:Array.from({length:100},()=>({x:2.2250738585072014e-308}))},as:'out'}],
        results:{rows:{from:'out',fields:['x']}}},{
      id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[
        {from:'rows',derive:{value:{[tag]:[{field:'x'},literal(311)]}},as:'derived'},
        {select:['value'],as:'out'}],results:{rows:{from:'out',fields:['value']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const options={format:'json',submissionRef:f.client.newSubmission({nonce:tag+'-cancel'})};
    const run=await f.client.startSource(source,options);
    const barrier=await reached.promise;
    assert.equal(barrier.task,1);assert.ok(BigInt(barrier.work)>0n);assert.ok(BigInt(barrier.progress)>0n);
    const before=f.advances();
    try {await run.cancel();const pending=await run.status();
      assert.equal(pending.control.cancellation_requested,true);assert.notEqual(pending.control.physical_stop,'confirmed');
      assert.notEqual(pending.status,'cancelled');assert.equal(completions,0);
    } finally {resume.resolve();}
    const stopped=await run.wait({signal:AbortSignal.timeout(15000)});
    assert.equal(stopped.status,'cancelled',JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop,'confirmed');assert.equal(stopped.result_availability.answer.state,'unavailable');
    await assert.rejects(run.result('answer').all());await assert.rejects(run.result('answer').describe());
    assert.equal(completions,0);assert.equal(f.advances(),before);assert.equal(f.dispatches(),1);
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
    const attached=await f.client.attach(run.ref);assert.equal((await attached.status()).status,'cancelled');
    await assert.rejects(attached.result('answer').all());assert.equal(f.dispatches(),1);
  });
