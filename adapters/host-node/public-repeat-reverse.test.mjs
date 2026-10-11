import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Fixed semantic, schema and JSONL byte expectations, authored without runtime output.
// GoogleSQL STRING semantics with the ActQL finite Number count adaptation.
const formats = ['sql', 'aql-text', 'json'];
const literal = value => ({literal: value});
const unary = value => ({reverse: value});
const repeat = (value, count) => ({repeat:[value, count]});
const stringContract = (nullable = false) => ({type:'string', nullable});
const boundedString = bytes => ({type:'string',nullable:false,max_utf8_bytes:bytes});
// The SQL profile rejects unsafe exact integer tokens before Number admission.
const sqlCount = count => Number.isInteger(count) && !Number.isSafeInteger(count) ? count.toExponential() : String(count);
const valueCase = (name, text, expression, expected, contract = stringContract()) => ({name,text,expression,expected,contract});
const sqlString = value => "'" + value.replace(/[\\'\u0000-\u001f]/gu, character => {
  if (character === '\\' || character === "'") return '\\' + character;
  return '\\u' + character.charCodeAt(0).toString(16).padStart(4,'0');
}) + "'";
const reverseVectors = [['',''],['abc','cba'],['é','é'],['e\u0301','\u0301e'],
  ['A😀e\u0301','\u0301e😀A'],['👩‍💻','💻‍👩'],['A\0\r\n😀','😀\n\r\0A'],
  ['\ud7ff\ue000\u{10000}\u{10ffff}','\u{10ffff}\u{10000}\ue000\ud7ff']];
const repeatVectors = [['abc',3,'abcabcabc'],['😀e\u0301',2,'😀e\u0301😀e\u0301'],
  ['\0\r\n',2,'\0\r\n\0\r\n'],['a',0,''],['',0,''],['',1,''],
  ['',4294967296,''],['',9007199254740992,''],['',9223372036854775808,''],
  ['',1e100,''],['',1.7976931348623157e308,'']];
// Independent UTF-8 widths of the fixed literals: REVERSE preserves this evidence.
const reverseInputBytes = [0,3,2,3,8,11,8,14];
const literalCases = reverseVectors.map(([input,expected],i) =>
  valueCase('reverse_'+i,`REVERSE(${sqlString(input)})`,unary(literal(input)),expected,boundedString(reverseInputBytes[i])))
  .concat(repeatVectors.map(([input,count,expected],i) =>
    valueCase('repeat_'+i,`REPEAT(${sqlString(input)},${sqlCount(count)})`,repeat(literal(input),literal(count)),expected)));
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
  return format === 'aql-text'
    ? 'SELECT TRUE AS unit |> ' + (empty ? 'WHERE FALSE |> ' : '') + select
    : select + (empty ? ' WHERE FALSE' : '');
}

// Same real installed Local Host path as the public ROUND/TRUNC boundary tests.
// All state is private to this test. No cap or execution-policy override.
async function fixture(t, {onAdvance, onComputed, onObserve} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-repeat-reverse-'));
  const keys = generateKeyPairSync('ed25519');
  let client, computed;
  let dispatches = 0, advances = 0;
  t.after(async () => {
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {
    directory, retainedRelationOutput: true, authorization: {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'public-repeat-reverse',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) {
        onObserve?.(name, detail);
        if (name === 'computed') { computed = detail; onComputed?.(detail); }
      },
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

async function published(f, source, options, cases, expectedRows) {
  const beforeAdvances = f.advances();
  const run = await f.client.startSource(source, options);
  const state = await run.wait({signal: AbortSignal.timeout(15_000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = expectedRows ?? [Object.fromEntries(cases.map(item =>
    [item.name, item.expected]))];
  assert.deepEqual(await run.result('answer').all(), expected);
  const description = await run.result('answer').describe();
  assert.deepEqual(description.columns,
    cases.map(item => ({name: item.name, contract: item.contract})));
  if (expected.length !== 0) {
    assert.ok(f.advances() > beforeAdvances, 'nonempty execution must make charged Local progress');
  }
  assert.ok(f.computed().outputRepresentations.some(item => item.representation === 'retained-file'));
  const before = f.dispatches();
  assert.deepEqual((await f.client.startSource(source, options)).ref, run.ref);
  const attached = await f.client.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  const retained = await attached.result('answer').describe();
  assert.deepEqual(retained.columns, description.columns);
  for (const key of ['programDefinitionCid', 'resultDefinitionCid',
    'resultArtifactCid', 'resultSchemaCid']) assert.equal(retained[key], description[key]);
  assert.equal(f.dispatches(), before, 'resend and retained reread must not redispatch');
  return {run, description};
}

async function refused(f, source, options) {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.equal(outcome.problem.code, 'ClientProgramInvalidInput');
    return true;
  });
}



test('public repeat reverse publish fixed Unicode values across SQL Pipe JSON', {timeout:90_000}, async t => {
  const f=await fixture(t);
  for(let offset=0;offset<literalCases.length;offset+=7) {
    const cases=literalCases.slice(offset,offset+7);
    for(const format of formats) await published(f,sourceFor(format,'repeat_reverse_literals_'+offset,cases),
      {format,submissionRef:f.client.newSubmission({nonce:offset+'-'+format})},cases);
  }
});

test('public repeat reverse retain NULL contracts and empty relation schemas', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const cases=[valueCase('reverse_null','REVERSE(NULL)',unary(literal(null)),null,stringContract(true)),
    valueCase('repeat_null','REPEAT(NULL,-1)',repeat(literal(null),literal(-1)),null,stringContract(true)),
    valueCase('count_null',"REPEAT('',NULL)",repeat(literal(''),literal(null)),null,stringContract(true))];
  for(const empty of [false,true]) for(const format of formats) await published(f,sourceFor(format,'repeat_reverse_nulls',cases,undefined,empty),
    {format,submissionRef:f.client.newSubmission({nonce:empty+'-'+format})},cases,empty?[]:undefined);
});

test('public repeat reverse accept quoted names nested composition and reverse produced String bounds', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const cases=[
    valueCase('quoted',"`REVERSE`(`REPEAT`('A😀é',2))",unary(repeat(literal('A😀é'),literal(2))),'́e😀Áe😀A'),
    valueCase('mixed',"rEpEaT(rEvErSe('A😀é'),2)",repeat(unary(literal('A😀é')),literal(2)),'́e😀Áe😀A'),
    valueCase('bounded',"REVERSE(CHR(128512))",unary({chr:literal(128512)}),'😀',{type:'string',nullable:false,max_codepoints:1,max_utf8_bytes:4}),
    valueCase('twice',"reverse(reverse('A😀é'))",unary(unary(literal('A😀é'))),'A😀é',boundedString(8)),
  ];
  for(const format of formats) await published(f,sourceFor(format,'repeat_reverse_aliases',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public repeat reverse preserve nullable runtime parameters', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const string={type:'string',nullable:true};
  const declarations={s:string,n:{type:'number',nullable:true}};
  for(const [i,row] of [{s:'A😀é',n:2,reversed:'́e😀A',repeated:'A😀éA😀é'}, {s:'',n:1e100,reversed:'',repeated:''}, {s:null,n:-1,reversed:null,repeated:null}, {s:'abc',n:null,reversed:'cba',repeated:null}].entries()) {
    const cases=[valueCase('reversed','REVERSE(@s)',unary({$param:'s'}),row.reversed,string),
      valueCase('repeated','REPEAT(@s,@n)',repeat({$param:'s'},{$param:'n'}),row.repeated,stringContract(true))];
    for(const format of formats) await published(f,sourceFor(format,'repeat_reverse_params',cases,declarations),
      {format,parameters:{s:row.s,n:row.n},...(format==='json'?{}:{parameterDeclarations:declarations}),submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
  }
});

test('public repeat reverse wrong arity types and canonical shapes fail before dispatch', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const invalid=[{text:'REPEAT()',expression:{repeat:[]}},
    {text:"REPEAT('a')",expression:{repeat:[literal('a')]}},
    {text:"REPEAT('a',2,3)",expression:{repeat:[literal('a'),literal(2),literal(3)]}},
    {text:'REPEAT(65,2)',expression:repeat(literal(65),literal(2))},
    {text:"REPEAT('a','2')",expression:repeat(literal('a'),literal('2'))},
    {text:"REPEAT('a',TRUE)",expression:repeat(literal('a'),literal(true))},
    {text:'REVERSE()',expression:{reverse:[]}},
    {text:"REVERSE('a','b')",expression:{reverse:[literal('a'),literal('b')]}},
    {text:'REVERSE(65)',expression:unary(literal(65))},
    {text:'REVERSE(TRUE)',expression:unary(literal(true))}];
  for(const [i,item] of invalid.entries()) for(const format of formats) await refused(f,sourceFor(format,'repeat_reverse_invalid',[{name:'value',...item}]),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})});
  for(const [i,expression] of [{repeat:{value:literal('a'),count:literal(2)}},{reverse:[literal('a')]},{REVERSE:literal('a')},{REPEAT:[literal('a'),literal(2)]}].entries()) await refused(f,sourceFor('json','repeat_reverse_shape',[{name:'value',expression}]),{format:'json',submissionRef:f.client.newSubmission({nonce:'shape-'+i})});
  // Keep the existing exact-integer-token refusal, separate from function domain.
  for(const format of ['sql','aql-text']) await refused(f,sourceFor(format,'repeat_exact_integer_token',[{name:'value',text:"REPEAT('',9007199254740992)"}]),{format,submissionRef:f.client.newSubmission({nonce:'integer-token-'+format})});
  assert.equal(f.dispatches(),0);assert.equal(f.advances(),0);
});

test('public repeat domain overflow and strict child errors retain durable unavailable results', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const failure={divide:[literal(1),literal(0)]};
  const textFailure={cast:{target:{type:'string'},value:failure}};
  const failures=[...[-1,-0.5,0.5,1.5].flatMap(n=>['','a'].map(s=>({text:`REPEAT(${sqlString(s)},${n})`,expression:repeat(literal(s),literal(n))}))),
    ...[4294967296,9007199254740992,1e100].map(n=>({text:`REPEAT('😀',${sqlCount(n)})`,expression:repeat(literal('😀'),literal(n))})),
    {text:'REPEAT(NULL,1/0)',expression:repeat(literal(null),failure)},
    {text:'REPEAT(CAST(1/0 AS STRING),0)',expression:repeat(textFailure,literal(0))},
    {text:'REVERSE(CAST(1/0 AS STRING))',expression:unary(textFailure)}];
  for(const [i,item] of failures.entries()) for(const format of formats) {
    const source=sourceFor(format,'repeat_reverse_failure',[{name:'value',...item}]);
    const options={format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})};
    const run=await f.client.startSource(source,options);
    const state=await run.wait({signal:AbortSignal.timeout(15_000)});
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

test('public repeat reverse enclosing and child-local lazy guards stay lazy', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const failure={divide:[literal(1),literal(0)]};
  const textFailure={cast:{target:{type:'string'},value:failure}};
  const cases=[
    valueCase('outer',"IF(FALSE,REPEAT('a',-1),'safe')",{if:[literal(false),repeat(literal('a'),literal(-1)),literal('safe')]},'safe'),
    valueCase('coalesced',"COALESCE('safe',REVERSE(CAST(1/0 AS STRING)))",{coalesce:[literal('safe'),unary(textFailure)]},'safe'),
    valueCase('child',"REPEAT(IF(TRUE,'😀',CAST(1/0 AS STRING)),IF(TRUE,2,1/0))",repeat({if:[literal(true),literal('😀'),textFailure]},{if:[literal(true),literal(2),failure]}),'😀😀'),
    valueCase('reverse_child',"REVERSE(IF(TRUE,'é',CAST(1/0 AS STRING)))",unary({if:[literal(true),literal('é'),textFailure]}),'́e'),
  ];
  for(const format of formats) await published(f,sourceFor(format,'repeat_reverse_lazy',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public repeat reverse retained delivery receipts bind independently fixed Unicode and escape bytes', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const vectors=[
    {
        "text": "REVERSE('A😀é')",
        "expression": {
            "reverse": {
                "literal": "A😀é"
            }
        },
        "expected": "́e😀A",
        "wire": "{\"value\":\"́e😀A\"}\n",
        "bytes": 21,
        "sha256": "61acf463bef87a5d6469b8a9abda2f966d8b8d78564e668422761e0a1ce23377"
    },
    {
        "text": "REPEAT('😀é',2)",
        "expression": {
            "repeat": [
                {
                    "literal": "😀é"
                },
                {
                    "literal": 2
                }
            ]
        },
        "expected": "😀é😀é",
        "wire": "{\"value\":\"😀é😀é\"}\n",
        "bytes": 27,
        "sha256": "468981ae737c01b0dd29b8a0183b70f5c9cc0516fbe36f71bfeb1450641550b6"
    },
    {
        "text": "REPEAT('\\u0000\\r\\n',2)",
        "expression": {
            "repeat": [
                {
                    "literal": "\u0000\r\n"
                },
                {
                    "literal": 2
                }
            ]
        },
        "expected": "\u0000\r\n\u0000\r\n",
        "wire": "{\"value\":\"\\u0000\\r\\n\\u0000\\r\\n\"}\n",
        "bytes": 33,
        "sha256": "9a241ba0fe1ac68f686a1bc40cb896ee66533cc2875b54bb781ef14096adaa3d"
    },
    {
        "text": "REPEAT('',1e100)",
        "expression": {
            "repeat": [
                {
                    "literal": ""
                },
                {
                    "literal": 1e+100
                }
            ]
        },
        "expected": "",
        "wire": "{\"value\":\"\"}\n",
        "bytes": 13,
        "sha256": "56f87c8f1979dd463838744ec9bc2e0b7c70e2e4c77b25e08798fec199c69b60"
    }
];
  for(const [i,item] of vectors.entries()) {
    assert.equal(Buffer.byteLength(item.wire),item.bytes);
    assert.equal(createHash('sha256').update(item.wire).digest('hex'),item.sha256);
    const cases=[valueCase('value',item.text,item.expression,item.expected,i===0?boundedString(8):stringContract())];
    const {run,description}=await published(f,sourceFor('json','repeat_reverse_identity',cases),{format:'json',submissionRef:f.client.newSubmission({nonce:'fixed-'+i})},cases);
    const before=f.dispatches();let first;
    for(const result of [run.result('answer'),(await f.client.attach(run.ref)).result('answer')]) {
      const reader=result.rows(), rows=[];
      for await(const row of reader) rows.push(row);
      assert.equal(reader.state(),'complete');assert.deepEqual(rows,[{value:item.expected}]);
      const lookup=await result.deliveryAttempt(reader.attemptId);
      assert.equal(lookup.kind,'found');assert.equal(lookup.record.state,'succeeded');
      const receipt=lookup.hostReleaseReceipt;
      assert.equal(receipt.result_artifact_cid,description.resultArtifactCid);
      assert.equal(receipt.run_definition_cid,run.ref.runDefinitionCid);
      assert.equal(receipt.result_name,'answer');
      assert.equal(receipt.serialization_contract_cid,description.serialization.contractCid);
      assert.equal(receipt.delivered_byte_count,item.bytes);assert.equal(receipt.delivered_sha256,item.sha256);
      if(first) assert.notEqual(reader.attemptId,first);else first=reader.attemptId;
    }
    assert.equal(f.dispatches(),before);
  }
});

function cancellationSource(tag,count) {
  const schema={payload:{type:'string',nullable:false}};
  const names=Array.from({length:9},(_,i)=>'value_'+i);
  const operation=tag==='repeat'?repeat({field:'payload'},literal(count)):unary({field:'payload'});
  return JSON.stringify({version:'actql/0.1',id:'repeat_reverse_cancel_'+tag,stages:[{
    id:'seed',inputs:{},steps:[{values:{schema,rows:Array.from({length:100},()=>({payload:'😀é'.repeat(64)}))},as:'out'}],results:{rows:{from:'out',fields:['payload']}}},{
    id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[{from:'rows',derive:Object.fromEntries(names.map(name=>[name,operation])),as:'derived'},{select:names,as:'out'}],results:{rows:{from:'out',fields:names}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
}

for(const tag of ['repeat','reverse']) test(`public ${tag} cancellation waits for charged consumer progress and physical cleanup`, {timeout:60_000}, async t=>{
  const reached=Promise.withResolvers(),resume=Promise.withResolvers();let completions=0;const observations=[],diagnostics=[];
  t.after(()=>resume.resolve());
  const f=await fixture(t,{onObserve(name,detail){if(name==='dispatch_failed')diagnostics.push({name,...detail});},onComputed(){completions++;reached.reject(new Error('completed before cancellation boundary'));},async onAdvance(_count,detail){observations.push(detail);if(detail.task===1&&BigInt(detail.progress)>0n){reached.resolve(detail);await resume.promise;}}});
  // Nine fields at two repetitions stay below the installed row text bound.
  // Four repetitions are retained as the explicit refused-workload control below.
  const source=cancellationSource(tag,2);
  const options={format:'json',submissionRef:f.client.newSubmission({nonce:tag})};
  const run=await f.client.startSource(source,options);const barrier=await Promise.race([reached.promise,run.wait({signal:AbortSignal.timeout(15_000)}).then(state=>{throw new Error('Terminated before charged consumer progress: '+JSON.stringify({state,diagnostics,taskWork:Object.fromEntries([0,1].map(task=>[task,observations.filter(item=>item.task===task).reduce((sum,item)=>sum+Number(item.work),0)])),taskAdvances:Object.fromEntries([0,1].map(task=>[task,observations.filter(item=>item.task===task).length])),observations:observations.slice(-8),maxWork:Math.max(0,...observations.map(item=>Number(item.work)))}));})]);
  assert.equal(barrier.task,1);assert.ok(BigInt(barrier.work)>0n);assert.ok(BigInt(barrier.progress)>0n);
  const before=f.advances();
  try{await run.cancel();const pending=await run.status();assert.equal(pending.control.cancellation_requested,true);assert.notEqual(pending.control.physical_stop,'confirmed');assert.notEqual(pending.status,'cancelled');assert.equal(completions,0);}finally{resume.resolve();}
  const stopped=await run.wait({signal:AbortSignal.timeout(15_000)});
  assert.equal(stopped.status,'cancelled',JSON.stringify(stopped));assert.equal(stopped.control.physical_stop,'confirmed');assert.equal(stopped.result_availability.answer.state,'unavailable');
  await assert.rejects(run.result('answer').all());await assert.rejects(run.result('answer').describe());
  assert.equal(completions,0);assert.equal(f.advances(),before);assert.equal(f.dispatches(),1);
  assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
  const attached=await f.client.attach(run.ref);assert.equal((await attached.status()).status,'cancelled');await assert.rejects(attached.result('answer').all());assert.equal(f.dispatches(),1);
});

// Preserve the original workload and its installed refusal without widening caps.
test('public repeat original oversized cancellation workload fails before consumer row progress', {timeout:30_000}, async t=>{
  let completions=0;const observations=[];
  const f=await fixture(t,{onComputed(){completions++;},onAdvance(_count,detail){observations.push(detail);}});
  const source=cancellationSource('repeat',4);
  const options={format:'json',submissionRef:f.client.newSubmission({nonce:'original-oversized'})};
  const run=await f.client.startSource(source,options);
  const state=await run.wait({signal:AbortSignal.timeout(15_000)});
  assert.equal(state.status,'failed',JSON.stringify(state));
  assert.equal(state.control.physical_stop,'confirmed');
  assert.equal(state.control.cancellation_requested,false);
  assert.equal(state.result_availability.answer.state,'unavailable');
  const consumer=observations.filter(item=>item.task===1);
  assert.ok(consumer.length>0);
  assert.ok(consumer.every(item=>BigInt(item.work)>0n&&BigInt(item.work)<=256n&&BigInt(item.progress)===0n));
  await assert.rejects(run.result('answer').all());
  await assert.rejects(run.result('answer').describe());
  assert.equal(completions,0);assert.equal(f.dispatches(),1);
  assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
  const attached=await f.client.attach(run.ref);
  assert.equal((await attached.status()).status,'failed');
  await assert.rejects(attached.result('answer').all());
  assert.equal(f.dispatches(),1);
});
