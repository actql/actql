import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// All scalar, byte and contract expectations below are authored independently.
// Official GoogleSQL string-function semantics; admitted STRING/Number subset only.
const formats = ['sql', 'aql-text', 'json'];
const literal = value => ({literal: value});
const unary = (tag, value) => ({[tag]: value});
const numberContract = (nullable = false) => ({type:'number', nullable});
const chrContract = (nullable = false) => ({type:'string', nullable, max_codepoints:1, max_utf8_bytes:4});
const valueCase = (name, text, expression, expected, contract) => ({name,text,expression,expected,contract});
const sqlString = value => "'" + value.replace(/[\\'\u0000-\u001f]/gu, character => {
  if (character === '\\' || character === "'") return '\\' + character;
  return '\\u' + character.charCodeAt(0).toString(16).padStart(4,'0');
}) + "'";
const stringVectors = [
  ['',0,0], ['abc',3,97], ['é',2,233], ['e\u0301',3,101], ['\u0301e',3,769],
  ['😀e\u0301',7,128512], ['абвгд',10,1072], ['\0\r\n',3,0], ['\r\n',2,13],
  ['\u{10ffff}',4,1114111],
];
const chrVectors = [[0,''],[1,'\u0001'],[13,'\r'],[34,'"'],[92,'\\'],[65,'A'],
  [255,'ÿ'],[513,'ȁ'],[55295,'\ud7ff'],[57344,'\ue000'],[65536,'\u{10000}'],
  [128512,'😀'],[1114111,'\u{10ffff}']];
const literalCases = stringVectors.flatMap(([input,bytes,point],i) => [
  valueCase('bytes_'+i,`BYTE_LENGTH(${sqlString(input)})`,unary('byte_length',literal(input)),bytes,numberContract()),
  valueCase('octets_'+i,`OCTET_LENGTH(${sqlString(input)})`,unary('byte_length',literal(input)),bytes,numberContract()),
  valueCase('point_'+i,`UNICODE(${sqlString(input)})`,unary('unicode',literal(input)),point,numberContract()),
]).concat(chrVectors.map(([number,text],i) => valueCase('chr_'+i,`CHR(${number})`,unary('chr',literal(number)),text,chrContract())));
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
async function fixture(t, {onAdvance, onComputed} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-unicode-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'public-unicode',
        entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {all: true},
          exclusions: []}],
      }),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) {
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


test('public Unicode scalars publish fixed bytes first code points and CHR boundaries across SQL Pipe JSON', {timeout:90_000}, async t => {
  const f=await fixture(t);
  for(let offset=0;offset<literalCases.length;offset+=9) {
    const cases=literalCases.slice(offset,offset+9);
    for(const format of formats) await published(f,sourceFor(format,'unicode_literals_'+offset,cases),
      {format,submissionRef:f.client.newSubmission({nonce:offset+'-'+format})},cases);
  }
});

test('public Unicode scalars retain NULL contracts and empty relation schemas', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const cases=['byte_length','unicode','chr'].map(tag => valueCase(tag,`${tag.toUpperCase()}(NULL)`,unary(tag,literal(null)),null,tag==='chr'?chrContract(true):numberContract(true)));
  for(const empty of [false,true]) for(const format of formats) await published(f,sourceFor(format,'unicode_nulls',cases,undefined,empty),
    {format,submissionRef:f.client.newSubmission({nonce:empty+'-'+format})},cases,empty?[]:undefined);
});

test('public Unicode scalars accept lowercase mixed case quoted aliases and nested functions', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const cases=[
    valueCase('alias',"`OCTET_LENGTH`('😀')",unary('byte_length',literal('😀')),4,numberContract()),
    valueCase('mixed',"bYtE_lEnGtH('é')",unary('byte_length',literal('é')),3,numberContract()),
    valueCase('first',"unicode(chr(128512))",unary('unicode',unary('chr',literal(128512))),128512,numberContract()),
    valueCase('roundtrip',"CHR(UNICODE('😀tail'))",unary('chr',unary('unicode',literal('😀tail'))),'😀',chrContract()),
    valueCase('zero',"BYTE_LENGTH(CHR(0))",unary('byte_length',unary('chr',literal(0))),0,numberContract()),
  ];
  for(const format of formats) await published(f,sourceFor(format,'unicode_aliases',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public Unicode scalars preserve runtime nullable parameters', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const declarations={s:{type:'string',nullable:true},n:{type:'number',nullable:true}};
  for(const [i,row] of [{s:'😀é',n:128512,bytes:7,point:128512,chr:'😀'}, {s:'\0x',n:0,bytes:2,point:0,chr:''}, {s:null,n:null,bytes:null,point:null,chr:null}].entries()) {
    const cases=[valueCase('bytes','OCTET_LENGTH(@s)',unary('byte_length',{$param:'s'}),row.bytes,numberContract(true)),
      valueCase('point','UNICODE(@s)',unary('unicode',{$param:'s'}),row.point,numberContract(true)),
      valueCase('character','CHR(@n)',unary('chr',{$param:'n'}),row.chr,chrContract(true))];
    for(const format of formats) await published(f,sourceFor(format,'unicode_params',cases,declarations),
      {format,parameters:{s:row.s,n:row.n},...(format==='json'?{}:{parameterDeclarations:declarations}),submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
  }
});

test('public Unicode scalar arity types and canonical alias misuse fail before dispatch', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const invalid=[{text:'BYTE_LENGTH()',expression:{byte_length:[]}},
    {text:"OCTET_LENGTH('a','b')",expression:{byte_length:[literal('a'),literal('b')]}},
    {text:'BYTE_LENGTH(65)',expression:unary('byte_length',literal(65))},
    {text:'UNICODE(TRUE)',expression:unary('unicode',literal(true))},
    {text:"CHR('65')",expression:unary('chr',literal('65'))},
    {text:'CHR(TRUE)',expression:unary('chr',literal(true))},
    {text:'CHR(1,2)',expression:{chr:[literal(1),literal(2)]}},
  ];
  for(const [i,item] of invalid.entries()) for(const format of formats) await refused(f,sourceFor(format,'unicode_invalid',[{name:'value',...item}]),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})});
  await refused(f,sourceFor('json','unicode_alias_invalid',[{name:'value',expression:unary('octet_length',literal('a'))}]),{format:'json',submissionRef:f.client.newSubmission({nonce:'json-alias'})});
  assert.equal(f.dispatches(),0);assert.equal(f.advances(),0);
});

test('public CHR domain errors and strict child errors are durable failures without partial result', {timeout:90_000}, async t => {
  const f=await fixture(t);
  const failures=[...[-1,0.5,55296,56320,57343,1114112,4294967361,1e100].map(n=>({text:`CHR(${n})`,expression:unary('chr',literal(n))})),
    {text:'CHR(1/0)',expression:unary('chr',{divide:[literal(1),literal(0)]})},
    {text:'UNICODE(CAST(1/0 AS STRING))',expression:unary('unicode',{cast:{target:{type:'string'},value:{divide:[literal(1),literal(0)]}}})},
    {text:'BYTE_LENGTH(CAST(1/0 AS STRING))',expression:unary('byte_length',{cast:{target:{type:'string'},value:{divide:[literal(1),literal(0)]}}})}];
  for(const [i,item] of failures.entries()) for(const format of formats) {
    const source=sourceFor(format,'unicode_failure',[{name:'value',...item}]);
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

test('public Unicode scalar enclosing and child lazy guards remain lazy', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const failure={divide:[literal(1),literal(0)]};
  const textFailure={cast:{target:{type:'string'},value:failure}};
  const cases=[
    valueCase('outer','IF(FALSE,CHR(-1),CHR(65))',{if:[literal(false),unary('chr',literal(-1)),unary('chr',literal(65))]},'A',chrContract()),
    valueCase('child','CHR(IF(TRUE,128512,1/0))',unary('chr',{if:[literal(true),literal(128512),failure]}),'😀',chrContract()),
    valueCase('coalesced','COALESCE(CHR(65),CHR(55296))',{coalesce:[unary('chr',literal(65)),unary('chr',literal(55296))]},'A',chrContract()),
    valueCase('byte_guard',"IF(FALSE,BYTE_LENGTH(CAST(1/0 AS STRING)),7)",{if:[literal(false),unary('byte_length',textFailure),literal(7)]},7,numberContract()),
    valueCase('first_guard',"UNICODE(IF(TRUE,'😀',CAST(1/0 AS STRING)))",unary('unicode',{if:[literal(true),literal('😀'),textFailure]}),128512,numberContract()),
  ];
  for(const format of formats) await published(f,sourceFor(format,'unicode_lazy',cases),{format,submissionRef:f.client.newSubmission({nonce:format})},cases);
});

test('public CHR retained delivery receipts bind exact supplementary and escaped control bytes', {timeout:60_000}, async t => {
  const f=await fixture(t);
  const vectors=[
    {point:128512,expected:'😀',wire:'{"value":"😀"}\n',bytes:17,sha256:'330aee83d2960ef9c4c98b5f6f75422e34503c744099c6d2c675e614bc31adc9'},
    {point:1,expected:'\u0001',wire:'{"value":"\\u0001"}\n',bytes:19,sha256:'866c1ac58c882cd09ae852ad0096a589585cee41b3c9f6ac8b6dec20d72147ed'},
    {point:0,expected:'',wire:'{"value":""}\n',bytes:13,sha256:'56f87c8f1979dd463838744ec9bc2e0b7c70e2e4c77b25e08798fec199c69b60'},
  ];
  for(const item of vectors) {
    assert.equal(Buffer.byteLength(item.wire),item.bytes);
    assert.equal(createHash('sha256').update(item.wire).digest('hex'),item.sha256);
    const cases=[valueCase('value',`CHR(${item.point})`,unary('chr',literal(item.point)),item.expected,chrContract())];
    const {run,description}=await published(f,sourceFor('json','unicode_identity',cases),{format:'json',submissionRef:f.client.newSubmission({nonce:'point-'+item.point})},cases);
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

for(const tag of ['byte_length','unicode','chr']) test(`public ${tag} cancellation waits for charged consumer progress and physical cleanup`, {timeout:60_000}, async t=>{
  const reached=Promise.withResolvers(),resume=Promise.withResolvers();let completions=0;
  t.after(()=>resume.resolve());
  const f=await fixture(t,{onComputed(){completions++;reached.reject(new Error('completed before cancellation boundary'));},async onAdvance(_count,detail){if(detail.task===1&&BigInt(detail.progress)>0n){reached.resolve(detail);await resume.promise;}}});
  const isChr=tag==='chr',schema={payload:{type:isChr?'number':'string',nullable:false}};
  const names=Array.from({length:9},(_,i)=>'value_'+i);
  const source=JSON.stringify({version:'actql/0.1',id:'unicode_cancel_'+tag,stages:[{
    id:'seed',inputs:{},steps:[{values:{schema,rows:Array.from({length:100},()=>({payload:isChr?128512:'😀é'.repeat(64)}))},as:'out'}],results:{rows:{from:'out',fields:['payload']}}},{
    id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[{from:'rows',derive:Object.fromEntries(names.map(name=>[name,unary(tag,{field:'payload'})])),as:'derived'},{select:names,as:'out'}],results:{rows:{from:'out',fields:names}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
  const options={format:'json',submissionRef:f.client.newSubmission({nonce:tag})};
  const run=await f.client.startSource(source,options);const barrier=await reached.promise;
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
