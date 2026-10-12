import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independently fixed real cube-root controls for the finite Number subset.
// Approximate values use rational-cube brackets, never Math.cbrt or product output.
// General last-bit equality with BigQuery or other backends is not a promise.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#cbrt
const formats = ['sql','aql-text','json'];
const literal = value => ({literal:value});
const unary = value => ({cbrt:value});
const number = (name,text,expression,expected,nullable=false) => ({name,text,expression,expected,contract:{type:'number',nullable}});
const intervals = [
  [2,1.25992104989487,1.25992104989488],
  [3,1.44224957030740,1.44224957030742],
  [10,2.15443469003188,2.15443469003189],
  [0.5,0.79370052598409,0.79370052598411],
  [27,2.99999999999999,3.00000000000001],
  [125,4.99999999999999,5.00000000000001],
  [5e-324,1.70318393600325e-108,1.70318393600327e-108],
  [2.225073858507201e-308,2.81264428523625e-103,2.81264428523628e-103],
  [2.2250738585072014e-308,2.81264428523625e-103,2.81264428523628e-103],
  [1.7976931348623157e308,5.64380309412235e102,5.64380309412238e102],
];
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-cbrt-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'public-cbrt',
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

// Approximate controls use independent enclosing decimal intervals, never
// Math.* or product output as an oracle. Exact boundary controls stay exact.
function assertRows(actual, cases) {
  assert.equal(actual.length, 1);
  assert.deepEqual(Object.keys(actual[0]).sort(), cases.map(item => item.name).sort());
  for (const item of cases) {
    const value = actual[0][item.name];
    if (item.interval) {
      assert.equal(typeof value, 'number');
      assert.ok(value > item.interval[0] && value < item.interval[1],
        `${item.name}: ${value} must be inside ${JSON.stringify(item.interval)}`);
    } else {
      assert.equal(value, item.expected, item.name);
    }
    if (value !== null) {
      assert.ok(Number.isFinite(value), item.name + ' is finite');
      assert.ok(!Object.is(value, -0), item.name + ' publishes canonical zero');
    }
  }
}

async function assertPublished(f, source, options, cases) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const columns = cases.map(item => ({name: item.name, contract: item.contract}));
  const actual = await run.result('answer').all();
  assertRows(actual, cases);
  assert.deepEqual((await run.result('answer').describe()).columns, columns);
  assert.ok(f.advances() > beforeAdvances, 'ordinary execution must make charged Local progress');
  assert.ok(f.computed().outputRepresentations.some(entry => entry.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  const retained = await attached.result('answer').all();
  assertRows(retained, cases);
  assert.deepEqual(retained, actual, 'retained reread preserves the published finite values');
  const retainedDescription = await attached.result('answer').describe();
  const description = await run.result('answer').describe();
  assert.deepEqual(retainedDescription.columns, columns);
  for (const key of ['programDefinitionCid','resultDefinitionCid','resultArtifactCid','resultSchemaCid']) assert.equal(retainedDescription[key],description[key]);
  assert.equal(f.dispatches(), before, 'resend and retained reread must not dispatch again');
  return {run,description};
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


// Decode literal binary64 bits and cube them with exact BigInt rational arithmetic.
// This proves each fixed oracle encloses the mathematical root of the admitted
// binary64 input, independently of either the Node or MoonBit math library.
function fraction(value) {
  const view=new DataView(new ArrayBuffer(8));view.setFloat64(0,value);
  const bits=view.getBigUint64(0),exponent=Number((bits>>52n)&2047n);
  const significand=(bits&((1n<<52n)-1n))+(exponent?1n<<52n:0n);
  const shift=exponent?exponent-1075:-1074;
  return shift<0?[significand,1n<<BigInt(-shift)]:[significand<<BigInt(shift),1n];
}
const less=([a,b],[c,d])=>a*d<c*b;
const cube=([a,b])=>[a*a*a,b*b*b];
test('public cbrt numerical oracles have independent exact rational cube brackets',()=>{
  for(const [input,lower,upper] of intervals) {
    assert.ok(less(cube(fraction(lower)),fraction(input)));
    assert.ok(less(fraction(input),cube(fraction(upper))));
  }
});

test('public cbrt publishes exact cubes computed zero and NULL across SQL Pipe JSON',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const cases=[
    number('zero','CBRT(0)',unary(literal(0)),0),
    number('computed_zero','CBRT(-1*0)',unary({multiply:[literal(-1),literal(0)]}),0),
    number('one','CBRT(1)',unary(literal(1)),1),
    number('negative_one','CBRT(-1)',unary(literal(-1)),-1),
    number('cube','CBRT(8)',unary(literal(8)),2),
    number('negative_cube','CBRT(-8)',unary(literal(-8)),-2),
    number('fraction','CBRT(0.125)',unary(literal(.125)),.5),
    number('null_value','CBRT(NULL)',unary(literal(null)),null,true),
  ];
  for(const format of formats) await assertPublished(f,sourceFor(format,'cbrt_exact',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public cbrt independently bounds positive negative subnormal and max finite results',{timeout:120_000},async t=>{
  const f=await fixture(t);
  const cases=intervals.flatMap(([input,lower,upper],i)=>[
    {name:'positive_'+i,text:`CBRT(${input})`,expression:unary(literal(input)),interval:[lower,upper],contract:{type:'number',nullable:false}},
    {name:'negative_'+i,text:`CBRT(${-input})`,expression:unary(literal(-input)),interval:[-upper,-lower],contract:{type:'number',nullable:false}},
  ]);
  for(let offset=0;offset<cases.length;offset+=8) for(const format of formats) {
    const selected=cases.slice(offset,offset+8);
    await assertPublished(f,sourceFor(format,'cbrt_intervals_'+offset,selected),{format,submissionRef:f.client.newSubmission({nonce:offset+'-'+format})},selected);
  }
});

test('public cbrt preserves nullable parameters and empty result schemas',{timeout:90_000},async t=>{
  const f=await fixture(t),declarations={n:{type:'number',nullable:true}};
  for(const [i,input] of [-8,null].entries()) for(const format of formats) {
    const cases=[number('value','CBRT(@n)',unary({$param:'n'}),input===null?null:-2,true)];
    await assertPublished(f,sourceFor(format,'cbrt_parameters',cases,declarations),{format,parameters:{n:input},...(format==='json'?{}:{parameterDeclarations:declarations}),submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
  }
  const empty=[number('value','CBRT(1 / 0)',unary({divide:[literal(1),literal(0)]}),undefined)];
  for(const format of formats) {
    const source=sourceFor(format,'cbrt_empty',empty,undefined,true),options={format,submissionRef:f.client.newSubmission({nonce:'empty-'+format})};
    const run=await f.client.startSource(source,options);
    assert.equal((await run.wait({signal:AbortSignal.timeout(15000)})).status,'succeeded');
    const columns=[{name:'value',contract:{type:'number',nullable:false}}];
    assert.deepEqual(await run.result('answer').all(),[]);assert.deepEqual((await run.result('answer').describe()).columns,columns);
    const before=f.dispatches(),attached=await f.client.attach(run.ref);
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
    assert.deepEqual(await attached.result('answer').all(),[]);assert.deepEqual((await attached.result('answer').describe()).columns,columns);assert.equal(f.dispatches(),before);
  }
});

test('public cbrt rejects wrong arities types malformed bodies and nonfinite source before dispatch',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const invalid=[
    {text:'CBRT()',expression:{cbrt:[]}},
    {text:'CBRT(1,2)',expression:{cbrt:[literal(1),literal(2)]}},
    {text:"CBRT('8')",expression:unary(literal('8'))},
    {text:'CBRT(TRUE)',expression:unary(literal(true))},
    {text:"CBRT(CAST('8' AS DECIMAL(2,0)))",expression:unary({cast:{value:literal('8'),target:{type:'decimal',precision:2,scale:0}}})},
    {text:"IF(FALSE,CBRT('8'),1)",expression:{if:[literal(false),unary(literal('8')),literal(1)]}},
  ];
  for(const [i,item] of invalid.entries()) for(const format of formats) await assertRefused(f,sourceFor(format,'cbrt_invalid',[{name:'value',...item}]),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})});
  for(const [i,expression] of [{cbrt:[literal(8)]},{cbrt:{value:literal(8)}},{CBRT:literal(8)}].entries()) await assertRefused(f,sourceFor('json','cbrt_shape',[{name:'value',expression}]),{format:'json',submissionRef:f.client.newSubmission({nonce:'shape-'+i})});
  for(const format of formats) {
    const source=format==='json'?sourceFor(format,'cbrt_nonfinite',[{name:'value',expression:unary(literal('NONFINITE'))}]).replace('"NONFINITE"','1e309'):sourceFor(format,'cbrt_nonfinite',[{name:'value',text:'CBRT(1e309)'}]);
    await assertRefused(f,source,{format,submissionRef:f.client.newSubmission({nonce:'nonfinite-'+format})});
  }
  // Existing query-number admission rejects authored negative zero and unsafe
  // exact integer tokens before function checking. Keep these refusal controls;
  // computed zero succeeds above, and direct signed-zero bits are covered in Core.
  for(const text of ['CBRT(-0.0)','CBRT(-0)','CBRT(9007199254740992)']) for(const format of ['sql','aql-text']) {
    await assertRefused(f,sourceFor(format,'cbrt_number_token',[{name:'value',text}]),{format,submissionRef:f.client.newSubmission({nonce:text+'-'+format})});
  }
  assert.equal(f.dispatches(),0);assert.equal(f.advances(),0);
});

test('public cbrt demanded child failures remain durable without partial publication',{timeout:90_000},async t=>{
  const f=await fixture(t),divide={divide:[literal(1),literal(0)]};
  const cases=[{text:'CBRT(1/0)',expression:unary(divide)},
    {text:'SAFE_DIVIDE(CBRT(1/0),0)',expression:{safe_divide:[unary(divide),literal(0)]}},
    {text:'GREATEST(NULL,CBRT(1/0))',expression:{greatest:[literal(null),unary(divide)]}}];
  for(const [i,item] of cases.entries()) for(const format of formats) {
    const source=sourceFor(format,'cbrt_failure',[{name:'value',...item}]),options={format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})};
    const run=await f.client.startSource(source,options),state=await run.wait({signal:AbortSignal.timeout(15000)});
    assert.equal(state.status,'failed',JSON.stringify(state));assert.equal(state.control.physical_stop,'confirmed');assert.equal(state.result_availability.answer.state,'unavailable');
    await assert.rejects(run.result('answer').all());await assert.rejects(run.result('answer').describe());
    const before=f.dispatches(),attached=await f.client.attach(run.ref);
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);assert.equal((await attached.status()).status,'failed');
    await assert.rejects(attached.result('answer').all());await assert.rejects(attached.result('answer').describe());assert.equal(f.dispatches(),before);
  }
});

test('public cbrt retains outer and inner lazy guards quoted spellings and nested composition',{timeout:60_000},async t=>{
  const f=await fixture(t),divide={divide:[literal(1),literal(0)]};
  const cases=[
    number('outer','IF(FALSE,CBRT(1/0),7)',{if:[literal(false),unary(divide),literal(7)]},7),
    number('coalesced','COALESCE(7,CBRT(1/0))',{coalesce:[literal(7),unary(divide)]},7),
    number('child','CBRT(IF(TRUE,-8,1/0))',unary({if:[literal(true),literal(-8),divide]}),-2),
    number('quoted','`CbRt`(64)',unary(literal(64)),4),
    number('nested','cBrT(CBRT(512))',unary(unary(literal(512))),2),
  ];
  for(const format of formats) await assertPublished(f,sourceFor(format,'cbrt_lazy',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public cbrt retained delivery receipts bind independently fixed JSONL bytes across all sources',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const vectors=[
  {
    "text": "CBRT(8)",
    "expression": {
      "cbrt": {
        "literal": 8
      }
    },
    "expected": 2,
    "wire": "{\"value\":2}\n",
    "bytes": 12,
    "sha256": "6e0d9d0268c35e8b9c620e4f529378b20d9e71af3a03cd57ad43c1f74a9ebc40"
  },
  {
    "text": "CBRT(-8)",
    "expression": {
      "cbrt": {
        "literal": -8
      }
    },
    "expected": -2,
    "wire": "{\"value\":-2}\n",
    "bytes": 13,
    "sha256": "8068820793c039ec4e60a4e6a3068a2d30852e83a80e40051ba35e98e08a6c00"
  },
  {
    "text": "CBRT(-1*0)",
    "expression": {
      "cbrt": {
        "multiply": [{"literal":-1},{"literal":0}]
      }
    },
    "expected": 0,
    "wire": "{\"value\":0}\n",
    "bytes": 12,
    "sha256": "2cb5e96e08607ddbc0bd13fb3a5e75e3245b536c076ad46bf3d66fc9f69f0b28"
  },
  {
    "text": "CBRT(NULL)",
    "expression": {
      "cbrt": {
        "literal": null
      }
    },
    "expected": null,
    "wire": "{\"value\":null}\n",
    "bytes": 15,
    "sha256": "2e5bb0a6612ff9082a69f530010db34d0b9c459b345be114936568de2fdcfaee"
  }
];
  for(const [i,item] of vectors.entries()) for(const format of formats) {
    assert.equal(Buffer.byteLength(item.wire),item.bytes);assert.equal(createHash('sha256').update(item.wire).digest('hex'),item.sha256);
    const cases=[number('value',item.text,item.expression,item.expected,item.expected===null)];
    const {run,description}=await assertPublished(f,sourceFor(format,'cbrt_identity',cases),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
    const before=f.dispatches();let first;
    for(const result of [run.result('answer'),(await f.client.attach(run.ref)).result('answer')]) {
      const reader=result.rows(),rows=[];for await(const row of reader) rows.push(row);
      assert.equal(reader.state(),'complete');assert.deepEqual(rows,[{value:item.expected}]);
      const lookup=await result.deliveryAttempt(reader.attemptId);assert.equal(lookup.kind,'found');assert.equal(lookup.record.state,'succeeded');
      const receipt=lookup.hostReleaseReceipt;
      assert.equal(receipt.result_artifact_cid,description.resultArtifactCid);assert.equal(receipt.run_definition_cid,run.ref.runDefinitionCid);
      assert.equal(receipt.result_name,'answer');assert.equal(receipt.serialization_contract_cid,description.serialization.contractCid);
      assert.equal(receipt.delivered_byte_count,item.bytes);assert.equal(receipt.delivered_sha256,item.sha256);
      if(first)assert.notEqual(reader.attemptId,first);else first=reader.attemptId;
    }
    assert.equal(f.dispatches(),before);
  }
});

test(`public cbrt cancellation stops after charged math progress`,
  {timeout: 60_000}, async t => {
    const reached = Promise.withResolvers(), resume = Promise.withResolvers();
    let completions = 0;
    t.after(() => resume.resolve());
    const f = await fixture(t,{
      onComputed() { completions++; reached.reject(new Error('completed before cancellation boundary')); },
      async onAdvance(_count,detail) {
        if (detail.task === 1 && BigInt(detail.progress) > 0n) {
          reached.resolve(detail); await resume.promise;
        }
      },
    });
    // Keep the inherited 100-row Values ceiling and installed caps. This is
    // charged-progress/cancellation coverage, not a per-operation budget knob.
    // Exact work/workspace boundary oracles belong to the common Core owner.
    const source = JSON.stringify({version:'actql/0.1',id:'cbrt_cancel',stages:[{
      id:'seed',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:false}},
          rows:Array.from({length:100},()=>({x:8}))},as:'out'}],
        results:{rows:{from:'out',fields:['x']}}},{
      id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[
        {from:'rows',derive:{value:unary({field:'x'})},as:'derived'},
        {select:['value'],as:'out'}],results:{rows:{from:'out',fields:['value']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const options = {format:'json',submissionRef:f.client.newSubmission({nonce:'cbrt-cancel'})};
    const run = await f.client.startSource(source,options);
    const barrier = await reached.promise;
    assert.equal(barrier.task,1);
    assert.ok(BigInt(barrier.work)>0n);
    assert.ok(BigInt(barrier.progress)>0n);
    const before = f.advances();
    try {
      await run.cancel();
      const pending = await run.status();
      assert.equal(pending.control.cancellation_requested,true);
      assert.notEqual(pending.control.physical_stop,'confirmed');
      assert.notEqual(pending.status,'cancelled');
      assert.equal(completions,0);
    } finally { resume.resolve(); }
    const stopped = await run.wait({signal:AbortSignal.timeout(15000)});
    assert.equal(stopped.status,'cancelled',JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop,'confirmed');
    assert.equal(stopped.result_availability.answer.state,'unavailable');
    await assert.rejects(run.result('answer').all());
    await assert.rejects(run.result('answer').describe());
    assert.equal(completions,0);
    assert.equal(f.advances(),before);
    assert.equal(f.dispatches(),1);
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
    const attached = await f.client.attach(run.ref);
    assert.equal((await attached.status()).status,'cancelled');
    await assert.rejects(attached.result('answer').all());
    await assert.rejects(attached.result('answer').describe());
    assert.equal(f.dispatches(),1);
  });
