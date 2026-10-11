import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {localOutputLimits} from './local-values-plan.mjs';

// Independently authored finite-Number compatibility controls. Transcendental
// live-BigQuery last-bit equality is not asserted. ActQL targets use one pinned
// portable numeric kernel. Runtime acceptance
// requires current identity closure and the ordinary rebuilt Host packages.
// The finite-FLOAT64 domain excludes INT64/NUMERIC/BIGNUMERIC and nonfinite
// inputs. MOD has no GoogleSQL FLOAT64 overload and is deliberately absent.
// https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions
const literal = value => ({literal: value});
const number = (name, text, expression, expected, nullable = false) =>
  ({name, text, expression, expected, contract: {type: 'number', nullable}});
const cases = [
  number('power', 'POWER(2,3)', {pow: [literal(2),literal(3)]}, 8),
  number('odd', 'POW(-2,3)', {pow: [literal(-2),literal(3)]}, -8),
  number('reciprocal', 'POW(2,-3)', {pow: [literal(2),literal(-3)]}, 0.125),
  number('zero_power_zero', 'POW(0,0)', {pow: [literal(0),literal(0)]}, 1),
  number('subnormal', 'POW(2,-1074)', {pow: [literal(2),literal(-1074)]}, 5e-324),
  number('underflow', 'POW(2,-1075)', {pow: [literal(2),literal(-1075)]}, 0),
  number('exponential', 'EXP(0)', {exp: literal(0)}, 1),
  number('exp_underflow', 'EXP(-746)', {exp: literal(-746)}, 0),
  number('natural', 'LN(1)', {ln: literal(1)}, 0),
  number('log_alias', 'LOG(1)', {ln: literal(1)}, 0),
  number('base_log', 'LOG(8,2)', {log: [literal(8),literal(2)]}, 3),
  number('fractional_base', 'LOG(0.25,0.5)', {log: [literal(0.25),literal(0.5)]}, 2),
  number('decimal_log', 'LOG10(100)', {log10: literal(100)}, 2),
  number('null_pow', 'POW(NULL,-1)', {pow: [literal(null),literal(-1)]}, null,true),
  number('null_log', 'LOG(-1,NULL)', {log: [literal(-1),literal(null)]}, null,true),
  number('null_ln', 'LN(NULL)', {ln: literal(null)}, null,true),
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-finite-math-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'finite-math',
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

test('public finite math publishes fixed SQL Pipe JSON values and retained schemas',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    // The installed public result mapper admits at most ten fields. Keep all
    // original value/schema oracles, in two batches within that unchanged cap.
    for (const format of ['sql','aql-text','json']) for (const offset of [0,8]) {
      const selected = cases.slice(offset,offset+8);
      await assertPublished(f, sourceFor(format,'finite_math_'+offset,selected),
        {format,submissionRef:f.client.newSubmission({nonce:'math-'+format+'-'+offset})},selected);
    }
  });

test('public finite math rejects wrong arities shapes and Number domains before dispatch',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const invalid = [
      {text:'POW(1)',expression:{pow:[literal(1)]}},
      {text:'POWER(1,2,3)',expression:{pow:[literal(1),literal(2),literal(3)]}},
      {text:'LOG()',expression:{log:[]}},
      {text:'LOG(1,2,3)',expression:{log:[literal(1),literal(2),literal(3)]}},
      {text:'EXP(1,2)',expression:{exp:[literal(1),literal(2)]}},
      {text:'LN(1,2)',expression:{ln:[literal(1),literal(2)]}},
      {text:'LOG10()',expression:{log10:[]}},
      {text:"POW('2',3)",expression:{pow:[literal('2'),literal(3)]}},
      {text:'POW(NULL,TRUE)',expression:{pow:[literal(null),literal(true)]}},
      {text:"LOG(8,'2')",expression:{log:[literal(8),literal('2')]}},
      {text:'EXP(TRUE)',expression:{exp:literal(true)}},
      {text:"LN('1')",expression:{ln:literal('1')}},
      {text:"LOG10(CAST('1' AS DECIMAL(2,0)))",expression:{log10:{cast:{value:literal('1'),target:{type:'decimal',precision:2,scale:0}}}}},
    ];
    for (const [i,item] of invalid.entries()) for (const format of ['sql','aql-text','json']) {
      await assertRefused(f, sourceFor(format,'finite_math_invalid',[{name:'value',...item}]),
        {format,submissionRef:f.client.newSubmission({nonce:'invalid-'+i+'-'+format})});
    }
    assert.equal(f.dispatches(),0);
    assert.equal(f.advances(),0);
  });

test('public finite math retains demanded child and value-domain failures',
  {timeout: 120_000}, async t => {
    const f = await fixture(t);
    const divide = {divide:[literal(1),literal(0)]};
    const invalid = [
      {text:'POW(NULL,1/0)',expression:{pow:[literal(null),divide]}},
      {text:'LOG(1/0,NULL)',expression:{log:[divide,literal(null)]}},
      {text:'POW(1/0,NULL)',expression:{pow:[divide,literal(null)]}},
      {text:'LOG(NULL,1/0)',expression:{log:[literal(null),divide]}},
      {text:'EXP(1/0)',expression:{exp:divide}},
      {text:'LN(1/0)',expression:{ln:divide}},
      {text:'LOG10(1/0)',expression:{log10:divide}},
      {text:'POW(0,-1)',expression:{pow:[literal(0),literal(-1)]}},
      {text:'POW(-2,0.5)',expression:{pow:[literal(-2),literal(0.5)]}},
      {text:'POW(2,1024)',expression:{pow:[literal(2),literal(1024)]}},
      {text:'EXP(710)',expression:{exp:literal(710)}},
      {text:'LN(0)',expression:{ln:literal(0)}},
      {text:'LOG10(-1)',expression:{log10:literal(-1)}},
      {text:'LOG(8,1)',expression:{log:[literal(8),literal(1)]}},
      {text:'LOG(8,0)',expression:{log:[literal(8),literal(0)]}},
      {text:'LOG(8,-2)',expression:{log:[literal(8),literal(-2)]}},
      {text:'LOG(0,2)',expression:{log:[literal(0),literal(2)]}},
      {text:'SAFE_DIVIDE(LN(0),0)',expression:{safe_divide:[{ln:literal(0)},literal(0)]}},
    ];
    for (const [i,item] of invalid.entries()) for (const format of ['sql','aql-text','json']) {
      const source=sourceFor(format,'finite_math_failure',[{name:'value',...item}]);
      const options={format,submissionRef:f.client.newSubmission({nonce:'failure-'+i+'-'+format})};
      const before=f.dispatches();
      const run=await f.client.startSource(source,options);
      const state=await run.wait({signal:AbortSignal.timeout(15_000)});
      assert.equal(state.status,'failed',JSON.stringify(state));
      assert.ok(f.dispatches()>before);
      assert.equal(state.result_availability.answer.state,'unavailable');
      await assert.rejects(run.result('answer').all());
      await assert.rejects(run.result('answer').describe());
      const spent=f.dispatches();
      assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
      const attached=await f.client.attach(run.ref);
      assert.equal((await attached.status()).status,'failed');
      await assert.rejects(attached.result('answer').all());
      await assert.rejects(attached.result('answer').describe());
      assert.equal(f.dispatches(),spent);
    }
  });

test('public finite math preserves outer lazy demand', {timeout:60_000},async t=>{
  const f=await fixture(t);
  const lazy=[
    number('pow_skipped','IF(FALSE,POW(0,-1),7)',{if:[literal(false),{pow:[literal(0),literal(-1)]},literal(7)]},7),
    number('ln_skipped','COALESCE(7,LN(0))',{coalesce:[literal(7),{ln:literal(0)}]},7),
    number('log_skipped','IF(FALSE,LOG(8,1),7)',{if:[literal(false),{log:[literal(8),literal(1)]},literal(7)]},7),
    number('exp_skipped','IF(FALSE,EXP(710),7)',{if:[literal(false),{exp:literal(710)},literal(7)]},7),
    number('log10_skipped','COALESCE(7,LOG10(0))',{coalesce:[literal(7),{log10:literal(0)}]},7),
    number('inside','POW(IF(TRUE,2,1/0),3)',{pow:[{if:[literal(true),literal(2),{divide:[literal(1),literal(0)]}]},literal(3)]},8),
  ];
  for(const format of ['sql','aql-text','json']) await assertPublished(f,
    sourceFor(format,'finite_math_lazy',lazy),
    {format,submissionRef:f.client.newSubmission({nonce:'lazy-'+format})},lazy);
});


test('public finite math keeps additional finite boundaries and NULL domain masking',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const extra = [
      number('even', 'POW(-2,4)', {pow:[literal(-2),literal(4)]}, 16),
      // Query integer-token admission stops at 2^53-1; the decimal spelling
      // denotes the same finite binary64 operand as the unchanged JSON value.
      number('large_integer', 'POW(-1,9007199254740992.0)', {pow:[literal(-1),literal(9007199254740992)]}, 1),
      number('negative_underflow', 'POW(-2,-1075)', {pow:[literal(-2),literal(-1075)]}, 0),
      number('exp_subnormal', 'EXP(-745)', {exp:literal(-745)}, 5e-324),
      number('null_exponent', 'POWER(-2,NULL)', {pow:[literal(-2),literal(null)]}, null, true),
      number('null_value', 'LOG(NULL,1)', {log:[literal(null),literal(1)]}, null, true),
      number('null_exp', 'EXP(NULL)', {exp:literal(null)}, null, true),
      number('null_log10', 'LOG10(NULL)', {log10:literal(null)}, null, true),
      number('null_log_alias', 'LOG(NULL)', {ln:literal(null)}, null, true),
    ];
    for (const format of ['sql','aql-text','json']) await assertPublished(f,
      sourceFor(format,'finite_math_boundaries',extra),
      {format,submissionRef:f.client.newSubmission({nonce:'boundaries-'+format})},extra);
  });

test('public finite math checks nontrivial transcendental values with independent intervals',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const bounded = [
      {name:'exp_one',text:'EXP(1)',expression:{exp:literal(1)},interval:[2.71828182845904,2.71828182845905]},
      {name:'ln_two',text:'LN(2)',expression:{ln:literal(2)},interval:[0.69314718055994,0.69314718055995]},
      {name:'log_alias_two',text:'LOG(2)',expression:{ln:literal(2)},interval:[0.69314718055994,0.69314718055995]},
      {name:'log10_two',text:'LOG10(2)',expression:{log10:literal(2)},interval:[0.30102999566398,0.30102999566399]},
      {name:'log_two_three',text:'LOG(2,3)',expression:{log:[literal(2),literal(3)]},interval:[0.63092975357145,0.63092975357146]},
    ].map(item => ({...item,contract:{type:'number',nullable:false}}));
    for (const format of ['sql','aql-text','json']) await assertPublished(f,
      sourceFor(format,'finite_math_intervals',bounded),
      {format,submissionRef:f.client.newSubmission({nonce:'intervals-'+format})},bounded);
  });

test('public finite math preserves nullable parameter schemas independently of values',
  {timeout: 90_000}, async t => {
    const f = await fixture(t);
    const parameterDeclarations = Object.fromEntries(['x','y','n','z'].map(name =>
      [name,{type:'number',nullable:true}]));
    parameterDeclarations.k = {type:'number',nullable:false};
    for (const [id,parameters,power,logarithm,natural,exponential] of [
      ['present',{x:8,y:2,n:1,z:0,k:3},64,3,0,1],
      ['left_null',{x:null,y:2,n:1,z:0,k:3},null,null,0,1],
      ['right_null',{x:8,y:null,n:1,z:0,k:3},null,null,0,1],
      ['unary_null',{x:8,y:2,n:null,z:null,k:3},64,3,null,null],
    ]) {
      const nullable = [
        number('power','POW(@x,@y)',{pow:[{$param:'x'},{$param:'y'}]},power,true),
        number('logarithm','LOG(@x,@y)',{log:[{$param:'x'},{$param:'y'}]},logarithm,true),
        number('natural','LN(@n)',{ln:{$param:'n'}},natural,true),
        number('alias','LOG(@n)',{ln:{$param:'n'}},natural,true),
        number('decimal_log','LOG10(@n)',{log10:{$param:'n'}},natural,true),
        number('exponential','EXP(@z)',{exp:{$param:'z'}},exponential,true),
        number('required','POWER(@k,2)',{pow:[{$param:'k'},literal(2)]},9),
      ];
      for (const format of ['sql','aql-text','json']) await assertPublished(f,
        sourceFor(format,'finite_math_nullable',nullable,parameterDeclarations),
        {format,parameters,...(format==='json'?{}:{parameterDeclarations}),
          submissionRef:f.client.newSubmission({nonce:id+'-'+format})},nullable);
    }
  });

test('public finite math refuses nonfinite source values before dispatch',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    for (const op of ['pow','log','exp','ln','log10']) {
      const unary = !['pow','log'].includes(op);
      const expression = {[op]:unary ? literal('NONFINITE_TOKEN') : [literal('NONFINITE_TOKEN'),literal(2)]};
      for (const format of ['sql','aql-text','json']) {
        const source = format === 'json'
          ? sourceFor(format,'finite_math_nonfinite',[{name:'value',expression}]).replace('"NONFINITE_TOKEN"','1e309')
          : sourceFor(format,'finite_math_nonfinite',[{name:'value',text:`${op}(${unary?'1e309':'1e309,2'})`}]);
        await assertRefused(f,source,{format,submissionRef:f.client.newSubmission({nonce:op+'-'+format})});
      }
    }
    assert.equal(f.dispatches(),0);
    assert.equal(f.advances(),0);
  });

test('public finite math empty results preserve complete schemas without demanding domain failures',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const empty = [
      number('required','LN(0)',{ln:literal(0)},undefined),
      number('nullable','POW(NULL,-1)',{pow:[literal(null),literal(-1)]},undefined,true),
    ];
    const columns = empty.map(item => ({name:item.name,contract:item.contract}));
    for (const format of ['sql','aql-text','json']) {
      const source = sourceFor(format,'finite_math_empty',empty,undefined,true);
      const options = {format,submissionRef:f.client.newSubmission({nonce:'empty-'+format})};
      const run = await f.client.startSource(source,options);
      assert.equal((await run.wait({signal:AbortSignal.timeout(15000)})).status,'succeeded');
      assert.deepEqual(await run.result('answer').all(),[]);
      assert.deepEqual((await run.result('answer').describe()).columns,columns);
      const before = f.dispatches();
      assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
      const attached = await f.client.attach(run.ref);
      assert.deepEqual(await attached.result('answer').all(),[]);
      assert.deepEqual((await attached.result('answer').describe()).columns,columns);
      assert.equal(f.dispatches(),before);
    }
  });

test('public finite math ordered derive uses original fields and prior binding slots',
  {timeout: 60_000}, async t => {
    const f = await fixture(t);
    const source = JSON.stringify({version:'actql/0.1',id:'finite_math_ordered',stages:[{
      id:'main',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:true},n:{type:'number',nullable:true}},
          rows:[{x:2,n:3},{x:4,n:0.5},{x:null,n:2},{x:2,n:null}]},as:'seed'},
        {from:'seed',derive:[{x:{pow:[{field:'x'},{field:'n'}]}},{y:{log:[{field:'x'},literal(2)]}}],as:'derived'},
        {select:['x','y'],as:'out'}],results:{rows:{from:'out',fields:['x','y']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const options = {format:'json',submissionRef:f.client.newSubmission({nonce:'ordered'})};
    const run = await f.client.startSource(source,options);
    assert.equal((await run.wait({signal:AbortSignal.timeout(15000)})).status,'succeeded');
    const expected = [{x:8,y:3},{x:2,y:1},{x:null,y:null},{x:null,y:null}];
    const columns = ['x','y'].map(name => ({name,contract:{type:'number',nullable:true}}));
    assert.deepEqual(await run.result('answer').all(),expected);
    assert.deepEqual((await run.result('answer').describe()).columns,columns);
    const before = f.dispatches();
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
    const attached = await f.client.attach(run.ref);
    assert.deepEqual(await attached.result('answer').all(),expected);
    assert.deepEqual((await attached.result('answer').describe()).columns,columns);
    assert.equal(f.dispatches(),before);
  });

for (const [tag,input,expression] of [
  ['pow',2,{pow:[{field:'x'},literal(3)]}],
  ['log',8,{log:[{field:'x'},literal(2)]}],
  ['exp',0,{exp:{field:'x'}}],
  ['ln',1,{ln:{field:'x'}}],
  ['log10',100,{log10:{field:'x'}}],
]) test(`public ${tag} cancellation stops after charged math progress`,
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
    const source = JSON.stringify({version:'actql/0.1',id:tag+'_finite_math_cancel',stages:[{
      id:'seed',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:false}},
          rows:Array.from({length:100},()=>({x:input}))},as:'out'}],
        results:{rows:{from:'out',fields:['x']}}},{
      id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[
        {from:'rows',derive:{value:expression},as:'derived'},
        {select:['value'],as:'out'}],results:{rows:{from:'out',fields:['value']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const options = {format:'json',submissionRef:f.client.newSubmission({nonce:tag+'-cancel'})};
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


// Fixture-scope regression: preserve the original oversized batch as a failure
// control rather than raising installed limits to make arithmetic cases pass.
test('public finite math preserves the installed ten-field publication ceiling',
  {timeout: 60_000}, async t => {
    assert.equal(localOutputLimits.maxResultFields,10);
    for (const format of ['sql','aql-text','json']) {
      let completions = 0;
      const f = await fixture(t,{onComputed(){completions++;}});
      const exact = cases.slice(0,10);
      await assertPublished(f,sourceFor(format,'finite_math_ten',exact),
        {format,submissionRef:f.client.newSubmission({nonce:'ten-'+format})},exact);
      assert.equal(completions,1);
      for (const count of [11,16]) {
        const selected = cases.slice(0,count);
        const source = sourceFor(format,'finite_math_over_'+count,selected);
        const options = {format,submissionRef:f.client.newSubmission({nonce:'over-'+format+'-'+count})};
        const before = f.dispatches();
        const run = await f.client.startSource(source,options);
        const state = await run.wait({signal:AbortSignal.timeout(15000)});
        assert.equal(state.status,'failed',JSON.stringify(state));
        assert.equal(state.control.physical_stop,'confirmed');
        assert.equal(state.result_availability.answer.state,'unavailable');
        await assert.rejects(run.result('answer').all());
        await assert.rejects(run.result('answer').describe());
        assert.equal(completions,1,'over-capacity output cannot publish');
        assert.equal(f.dispatches(),before+1);
        assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
        const attached = await f.client.attach(run.ref);
        assert.equal((await attached.status()).status,'failed');
        await assert.rejects(attached.result('answer').all());
        await assert.rejects(attached.result('answer').describe());
        assert.equal(f.dispatches(),before+1,'retained refusal never redispatches');
      }
    }
  });

test('public finite math preserves existing exact-integer token refusal',
  {timeout: 30_000}, async t => {
    const f = await fixture(t);
    for (const format of ['sql','aql-text']) {
      await assertRefused(f,sourceFor(format,'finite_math_integer_token',[
        {name:'value',text:'POW(-1,9007199254740992)'}]),
        {format,submissionRef:f.client.newSubmission({nonce:'integer-token-'+format})});
    }
    assert.equal(f.dispatches(),0);
  });

// Independent reference bits retained from run-J1dKXM. The observed primitive
// divergence is not a claim that a public Result CID divergence was measured.
test('public finite math preserves the 14 portable identity counterexamples',
  {timeout: 60_000}, async t => {
    const references = [
      ['exp', -373.8015018526243, null, '1e3a538161077982'],
      ['ln', 8.955102088495668, null, '400189ac70cbeb70'],
      ['ln', 0.7096359903413106, null, 'bfd5f3c36686db50'],
      ['ln', 43.64301119989392, null, '400e35561db2a5ac'],
      ['ln', 93.3951804061785, null, '401225b95140bd10'],
      ['ln', 20.90108389454774, null, '40085183324a30f2'],
      ['ln', 43.83775473204472, null, '400e3e7462d43664'],
      ['ln', 1.4680892331809163, null, '3fd892d42704dce1'],
      ['ln', 1.2783106518366594, null, '3fcf6dd5ccd22ff8'],
      ['log10', 21.265579840947197, null, '3ff53e2a7a60ad4f'],
      ['log10', 2.8956631384538802, null, '3fdd8d47a426e273'],
      ['log10', 83.46167682682146, null, '3ffebe694375ffd0'],
      ['log10', 1.4680892331809163, null, '3fc55824f76150ad'],
      ['pow', 35.82791729235208, 15.398635423713735, '44e6ae0f50dde019'],
    ].map(([op, a, b, bits], index) => number(`v${index}`,
      `${op.toUpperCase()}(${a}${b === null ? '' : ',' + b})`,
      {[op]: b === null ? literal(a) : [literal(a), literal(b)]},
      Buffer.from(bits, 'hex').readDoubleBE()));
    const f = await fixture(t);
    for (const format of ['sql', 'aql-text', 'json']) {
      for (const offset of [0, 7]) {
        const batch = references.slice(offset, offset + 7);
        const id = `portable-${format}-${offset}`;
        await assertPublished(f, sourceFor(format, id, batch),
          {format, submissionRef: f.client.newSubmission({nonce: id})}, batch);
      }
    }
  });
