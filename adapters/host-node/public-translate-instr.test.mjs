import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Fixed independently authored STRING cases; no expected value uses product output.
// GoogleSQL docs and google/googlesql string.cc independently establish mapping,
// overlap and empty-pattern boundaries. ActQL admits finite integral Numbers.
const formats = ['sql', 'aql-text', 'json'];
const literal = value => ({literal: value});
const translate = (...args) => ({translate: args});
const instr = (...args) => ({instr: args});
const stringContract = (nullable = false) => ({type:'string',nullable});
const numberContract = (nullable = false) => ({type:'number',nullable});
const valueCase = (name,text,expression,expected,contract=stringContract()) => ({name,text,expression,expected,contract});
const sqlString = value => "'" + value.replace(/[\\'\u0000-\u001f]/gu, character => {
  if (character === '\\' || character === "'") return '\\' + character;
  return '\\u' + character.charCodeAt(0).toString(16).padStart(4,'0');
}) + "'";
const sqlNumber = value => Object.is(value,-0) ? '-0.0' : Number.isInteger(value) && !Number.isSafeInteger(value) ? value.toExponential() : String(value);
function options(f,format,nonce,extra={}) {
  assert.ok(!f.nonces.has(nonce),'each authored submission nonce must be unique');
  f.nonces.add(nonce);
  return {format,submissionRef:f.client.newSubmission({nonce}),...extra};
}
const translateVectors = [["ab","ab","ba","ba"],["abcabc","abc","x","xx"],["banana","an","xy","bxyxyx"],["This is a cookie","sco","zku","Thiz iz a kuukie"],["abc","a","XYZ","Xbc"],["abc","","XYZ","abc"],["abc","abc","",""],["","ab","ba",""],["😀A😀","😀A","é💻","é💻é"],["A😀é","😀é","xE!","AxE!"],["é é","é","X","X é"],["é é","é","E!","é E!"],["A\u0000\r\n😀","\u0000😀","Z💻","AZ\r\n💻"],["aaab","ab","xx","xxxx"],["a","a","😀","😀"],["퟿𐀀􏿿","퟿􏿿","😀A","😀𐀀A"]];
const instrVectors = [["banana","an",[],2],["banana","an",[1],2],["banana","an",[1,1],2],["banana","an",[1,2],4],["banana","an",[1,3],0],["banana","an",[3,1],4],["banana","an",[-1,1],4],["banana","an",[-3,1],4],["banana","an",[-1,2],2],["banana","an",[-4,1],2],["banana","an",[-7,1],0],["aaaa","aa",[1,3],3],["aaaa","aa",[-1,3],1],["helloooo","oo",[1,2],6],["😀a😀a","😀a",[1,2],3],["😀a😀a","😀a",[-1,2],1],["éé","é",[],3],["é","é",[],0],["A\u0000😀","\u0000😀",[],2],["abc","x",[],0],["","a",[],0],["","",[],1],["","",[-1],1],["","",[2],0],["ab","",[1,3],3],["ab","",[1,4],0],["ab","",[3],3],["ab","",[4],0],["ab","",[-1],3],["ab","",[-2],2],["ab","",[-3],1],["ab","",[-4],0],["ab","",[-1,3],1],["ab","",[-1,4],0],["😀a","",[-2],2],["a","a",[1e+100],0],["a","a",[-1e+100],0],["a","a",[1,1e+100],0],["","",[1,1e+100],0],["a","a",[9007199254740992],0],["a","a",[-9223372036854775808],0]];
const literalCases = translateVectors.map(([s,a,b,expected],i)=>
  valueCase('tr_'+i,`TRANSLATE(${[s,a,b].map(sqlString).join(',')})`,translate(...[s,a,b].map(literal)),expected))
  .concat(instrVectors.map(([s,t,rest,expected],i)=>valueCase('in_'+i,
    `INSTR(${[sqlString(s),sqlString(t),...rest.map(sqlNumber)].join(',')})`,
    instr(literal(s),literal(t),...rest.map(literal)),expected,numberContract())));
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-translate-instr-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'public-translate-instr',
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
  return {client, nonces: new Set(), dispatches: () => dispatches, advances: () => advances,
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

async function refused(f, source, options, code = 'ClientProgramInvalidInput') {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.deepEqual(outcome.problem, {code, classification: code === 'ClientProgramImplementationLimit' ? 'implementation_limit' : 'invalid_input'}, source);
    return true;
  });
}



test('public translate instr publish fixed Unicode overlap and empty boundary values across SQL Pipe JSON', {timeout:120_000}, async t=>{
  const f=await fixture(t);
  for(let offset=0;offset<literalCases.length;offset+=7) {
    const cases=literalCases.slice(offset,offset+7);
    assert.ok(cases.length+1<=10,'derived fields include the retained seed field');
    assert.ok(Buffer.byteLength(JSON.stringify(Object.fromEntries(cases.map(c=>[c.name,c.expected]))))<10000);
    for(const format of formats) await published(f,sourceFor(format,'translate_instr_literals_'+offset,cases),options(f,format,offset+'-'+format),cases);
  }
});

test('public translate instr NULL dominance follows strict children and preserves empty relation schemas', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  const cases=[
    valueCase('null_value',"TRANSLATE(NULL,'aa','x')",translate(literal(null),literal('aa'),literal('x')),null,stringContract(true)),
    valueCase('null_source',"TRANSLATE('a',NULL,'x')",translate(literal('a'),literal(null),literal('x')),null,stringContract(true)),
    valueCase('null_target',"TRANSLATE('a','aa',NULL)",translate(literal('a'),literal('aa'),literal(null)),null,stringContract(true)),
    valueCase('null_instr',"INSTR(NULL,'a',0,-1)",instr(literal(null),literal('a'),literal(0),literal(-1)),null,numberContract(true)),
    valueCase('null_pattern',"INSTR('a',NULL,0,-1)",instr(literal('a'),literal(null),literal(0),literal(-1)),null,numberContract(true)),
    valueCase('null_position',"INSTR('a','a',NULL,-1)",instr(literal('a'),literal('a'),literal(null),literal(-1)),null,numberContract(true)),
    valueCase('null_occurrence',"INSTR('a','a',0,NULL)",instr(literal('a'),literal('a'),literal(0),literal(null)),null,numberContract(true)),
  ];
  for(const empty of [false,true]) for(const format of formats) await published(f,sourceFor(format,'translate_instr_nulls',cases,undefined,empty),options(f,format,empty+'-'+format),cases,empty?[]:undefined);
});

test('public translate instr quoted names composition and parameter contracts retain authored calls', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  const cases=[
    valueCase('quoted',"`TRANSLATE`('ab','ab','ba')",translate(literal('ab'),literal('ab'),literal('ba')),'ba'),
    valueCase('mixed',"iNsTr(tRaNsLaTe('ab','ab','ba'),'a')",instr(translate(literal('ab'),literal('ab'),literal('ba')),literal('a')),2,numberContract()),
    valueCase('bounded',"TRANSLATE(CHR(65),'A','😀')",translate({chr:literal(65)},literal('A'),literal('😀')),'😀',{type:'string',nullable:false,max_codepoints:1}),
  ];
  for(const format of formats) await published(f,sourceFor(format,'translate_instr_names',cases),options(f,format,'names-'+format),cases);
  const declarations={s:stringContract(true),a:stringContract(true),b:stringContract(true),p:numberContract(true),o:numberContract(true)};
  for(const [i,parameters,translated,position] of [
    [0,{s:'😀a😀a',a:'😀a',b:'X',p:-1,o:2},'XX',1],
    [1,{s:null,a:'aa',b:'X',p:0,o:-1},null,null],
    [2,{s:'abc',a:'a',b:null,p:null,o:1},null,null],
    [3,{s:'a',a:'a',b:'X',p:1e100,o:1},'X',0],
  ]) {
    const values=[valueCase('translated','TRANSLATE(@s,@a,@b)',translate(...['s','a','b'].map(k=>({$param:k}))),translated,stringContract(true)),
      valueCase('position','INSTR(@s,@a,@p,@o)',instr(...['s','a','p','o'].map(k=>({$param:k}))),position,numberContract(true))];
    for(const format of formats) await published(f,sourceFor(format,'translate_instr_parameters',values,declarations),options(f,format,i+'-'+format,{parameters,...(format==='json'?{}:{parameterDeclarations:declarations})}),values);
  }
});

test('public translate instr reject arity types shapes unsafe source integers and negative zero before dispatch', {timeout:90_000}, async t=>{
  const f=await fixture(t);
  const invalid=[
    {text:'TRANSLATE()',expression:{translate:[]}},
    {text:"TRANSLATE('a','a')",expression:translate(literal('a'),literal('a'))},
    {text:"TRANSLATE('a','a','b','c')",expression:translate(...['a','a','b','c'].map(literal))},
    {text:"TRANSLATE(1,'a','b')",expression:translate(literal(1),literal('a'),literal('b'))},
    {text:"TRANSLATE('a',TRUE,'b')",expression:translate(literal('a'),literal(true),literal('b'))},
    {text:"TRANSLATE('a','a',1)",expression:translate(literal('a'),literal('a'),literal(1))},
    {text:'INSTR()',expression:{instr:[]}},
    {text:"INSTR('a')",expression:instr(literal('a'))},
    {text:"INSTR('a','a',1,1,1)",expression:instr(literal('a'),literal('a'),literal(1),literal(1),literal(1))},
    {text:"INSTR(1,'a')",expression:instr(literal(1),literal('a'))},
    {text:"INSTR('a',TRUE)",expression:instr(literal('a'),literal(true))},
    {text:"INSTR('a','a','1')",expression:instr(literal('a'),literal('a'),literal('1'))},
    {text:"INSTR('a','a',1,FALSE)",expression:instr(literal('a'),literal('a'),literal(1),literal(false))},
  ];
  for(const [i,item] of invalid.entries()) for(const format of formats) await refused(f,sourceFor(format,'translate_instr_invalid',[{name:'value',...item}]),options(f,format,'invalid-'+i+'-'+format));
  for(const [i,expression] of [{translate:{value:literal('a'),source:literal('a'),target:literal('b')}},{instr:{value:literal('a'),subvalue:literal('a')}},{TRANSLATE:[literal('a'),literal('a'),literal('b')]},{INSTR:[literal('a'),literal('a')]}].entries()) await refused(f,sourceFor('json','translate_instr_shape',[{name:'value',expression}]),options(f,'json','shape-'+i));
  for(const format of ['sql','aql-text']) {
    for(const [i,text] of ["INSTR('a','a',9007199254740992)","INSTR('a','a',-0.0)"].entries()) await refused(f,sourceFor(format,'translate_instr_source_number',[{name:'value',text}]),options(f,format,'source-number-'+i+'-'+format));
    await refused(f,sourceFor(format,'translate_instr_collation',[{name:'value',text:"INSTR(COLLATE('a','und:ci'),'A')"}]),options(f,format,'collation-'+format),'ClientProgramImplementationLimit');
  }
  assert.equal(f.dispatches(),0); assert.equal(f.advances(),0);
});

async function failed(f,source,opts) {
  const run=await f.client.startSource(source,opts);
  const state=await run.wait({signal:AbortSignal.timeout(15_000)});
  assert.equal(state.status,'failed',JSON.stringify(state));
  assert.equal(state.result_availability.answer.state,'unavailable');
  await assert.rejects(run.result('answer').all());
  const before=f.dispatches();
  assert.deepEqual((await f.client.startSource(source,opts)).ref,run.ref);
  const attached=await f.client.attach(run.ref);
  assert.equal((await attached.status()).status,'failed');
  await assert.rejects(attached.result('answer').all());
  assert.equal(f.dispatches(),before);
  return state;
}

test('public translate duplicates instr domains and strict children fail durably after dispatch', {timeout:120_000}, async t=>{
  const f=await fixture(t);
  const division={divide:[literal(1),literal(0)]};
  const textFailure={cast:{target:{type:'string'},value:division}};
  const failures=[
    ...['a',''].flatMap(s=>['aa','😀😀','ée'].map(a=>({text:`TRANSLATE(${sqlString(s)},${sqlString(a)},'x')`,expression:translate(literal(s),literal(a),literal('x'))}))),
    ...[0,-1,0.5].map(o=>({text:`INSTR('a','a',1,${o})`,expression:instr(literal('a'),literal('a'),literal(1),literal(o))})),
    ...[0,0.5,-0.5].map(p=>({text:`INSTR('a','a',${p})`,expression:instr(literal('a'),literal('a'),literal(p))})),
    {text:"TRANSLATE(NULL,CAST(1/0 AS STRING),'x')",expression:translate(literal(null),textFailure,literal('x'))},
    {text:"TRANSLATE('','aa',CAST(1/0 AS STRING))",expression:translate(literal(''),literal('aa'),textFailure)},
    {text:"INSTR(NULL,'a',1/0)",expression:instr(literal(null),literal('a'),division)},
    {text:"INSTR('','',NULL,1/0)",expression:instr(literal(''),literal(''),literal(null),division)},
  ];
  for(const [i,item] of failures.entries()) for(const format of formats) await failed(f,sourceFor(format,'translate_instr_failure',[{name:'value',...item}]),options(f,format,i+'-'+format));
});

test('public translate instr enclosing and child-local guards remain lazy', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  const division={divide:[literal(1),literal(0)]};
  const textFailure={cast:{target:{type:'string'},value:division}};
  const cases=[
    valueCase('outer',"IF(FALSE,TRANSLATE('','aa','x'),'safe')",{if:[literal(false),translate(literal(''),literal('aa'),literal('x')),literal('safe')]},'safe'),
    valueCase('coalesced',"COALESCE(7,INSTR(NULL,'a',1/0))",{coalesce:[literal(7),instr(literal(null),literal('a'),division)]},7,numberContract()),
    valueCase('guarded',"TRANSLATE(IF(TRUE,'a',CAST(1/0 AS STRING)),'a','😀')",translate({if:[literal(true),literal('a'),textFailure]},literal('a'),literal('😀')),'😀'),
    valueCase('position',"INSTR('aaaa','aa',IF(TRUE,-1,1/0),2)",instr(literal('aaaa'),literal('aa'),{if:[literal(true),literal(-1),division]},literal(2)),2,numberContract()),
  ];
  for(const format of formats) await published(f,sourceFor(format,'translate_instr_lazy',cases),options(f,format,format),cases);
});

const receiptVectors = [{"text":"TRANSLATE('A😀é','😀é','xE!')","expression":{"translate":[{"literal":"A😀é"},{"literal":"😀é"},{"literal":"xE!"}]},"expected":"AxE!","wire":"{\"value\":\"AxE!\"}\n","bytes":17,"sha256":"8b3de5c297500d962e7d54c3ce4ce3258d198282655a0ebc10707fd0b01ce02a"},{"text":"TRANSLATE('A\\u0000\\r\\n😀','\\u0000😀','Z💻')","expression":{"translate":[{"literal":"A\u0000\r\n😀"},{"literal":"\u0000😀"},{"literal":"Z💻"}]},"expected":"AZ\r\n💻","wire":"{\"value\":\"AZ\\r\\n💻\"}\n","bytes":23,"sha256":"e6b53d33982e15038be67e59976ef33b363f6a6defb271b1f7b8ed3d0e1e3240"},{"text":"INSTR('ab','',-1)","expression":{"instr":[{"literal":"ab"},{"literal":""},{"literal":-1}]},"expected":3,"wire":"{\"value\":3}\n","bytes":12,"sha256":"f07eacdbd7b52059f0e9fc2ed691570348d9d12fa2d6d2dc20e29f9bf88a48b7"}];
test('public translate instr receipts bind independently fixed Unicode escape and Number bytes', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  for(const [i,item] of receiptVectors.entries()) {
    assert.equal(Buffer.byteLength(item.wire),item.bytes);
    assert.equal(createHash('sha256').update(item.wire).digest('hex'),item.sha256);
    const cases=[valueCase('value',item.text,item.expression,item.expected,typeof item.expected==='number'?numberContract():stringContract())];
    const {run,description}=await published(f,sourceFor('json','translate_instr_receipt',cases),options(f,'json','receipt-'+i),cases);
    const before=f.dispatches();let first;
    for(const result of [run.result('answer'),(await f.client.attach(run.ref)).result('answer')]) {
      const reader=result.rows(),rows=[];
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
      if(first)assert.notEqual(reader.attemptId,first);else first=reader.attemptId;
    }
    assert.equal(f.dispatches(),before);
  }
});

function cancellationSource(tag,oversized=false) {
  const payload=oversized?'a'.repeat(512):tag==='translate'?'😀é'.repeat(64):'a'.repeat(128);
  const names=Array.from({length:tag==='translate'?9:1},(_,i)=>'value_'+i);
  const operation=tag==='translate'?translate({field:'payload'},literal(oversized?'a':'😀é'),literal(oversized?'😀':'AＢé')):instr({field:'payload'},literal('a'.repeat(32)+'b'));
  // Preflight both intermediate field count and fixed expected UTF-8 payload;
  // neither test overrides the installed Host caps.
  assert.ok(names.length+1<=10);
  const expectedBytes=Buffer.byteLength(payload)+names.length*(tag==='translate'?(oversized?2048:384):1);
  if(oversized)assert.ok(expectedBytes>10000);else assert.ok(expectedBytes<10000);
  return JSON.stringify({version:'actql/0.1',id:'translate_instr_cancel_'+tag+'_'+oversized,stages:[{
    id:'seed',inputs:{},steps:[{values:{schema:{payload:stringContract()},rows:Array.from({length:100},()=>({payload}))},as:'out'}],results:{rows:{from:'out',fields:['payload']}}},{
    id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[{from:'rows',derive:Object.fromEntries(names.map(name=>[name,operation])),as:'derived'},{select:names,as:'out'}],results:{rows:{from:'out',fields:names}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
}

for(const tag of ['translate','instr']) test(`public ${tag} cancellation waits for charged consumer progress and physical cleanup`,{timeout:60_000},async t=>{
  const reached=Promise.withResolvers(),resume=Promise.withResolvers();let completions=0;const observations=[];
  t.after(()=>resume.resolve());
  const f=await fixture(t,{onComputed(){completions++;reached.reject(new Error('completed before cancellation boundary'));},async onAdvance(_count,detail){observations.push(detail);if(detail.task===1&&BigInt(detail.progress)>0n){reached.resolve(detail);await resume.promise;}}});
  const source=cancellationSource(tag);const opts=options(f,'json',tag);
  const run=await f.client.startSource(source,opts);
  const barrier=await Promise.race([reached.promise,run.wait({signal:AbortSignal.timeout(15_000)}).then(state=>{throw new Error('Terminated before consumer progress: '+JSON.stringify({state,observations:observations.slice(-8)}));})]);
  assert.equal(barrier.task,1);assert.ok(BigInt(barrier.work)>0n);assert.ok(BigInt(barrier.progress)>0n);
  const before=f.advances();
  try{await run.cancel();const pending=await run.status();assert.equal(pending.control.cancellation_requested,true);assert.notEqual(pending.control.physical_stop,'confirmed');assert.notEqual(pending.status,'cancelled');assert.equal(completions,0);}finally{resume.resolve();}
  const stopped=await run.wait({signal:AbortSignal.timeout(15_000)});
  assert.equal(stopped.status,'cancelled',JSON.stringify(stopped));assert.equal(stopped.control.physical_stop,'confirmed');assert.equal(stopped.result_availability.answer.state,'unavailable');
  await assert.rejects(run.result('answer').all());await assert.rejects(run.result('answer').describe());
  assert.equal(completions,0);assert.equal(f.advances(),before);assert.equal(f.dispatches(),1);
  assert.deepEqual((await f.client.startSource(source,opts)).ref,run.ref);
  const attached=await f.client.attach(run.ref);assert.equal((await attached.status()).status,'cancelled');await assert.rejects(attached.result('answer').all());assert.equal(f.dispatches(),1);
});

test('public translate oversized output control fails before consumer progress without widening caps',{timeout:30_000},async t=>{
  const observations=[];let completions=0;
  const f=await fixture(t,{onComputed(){completions++;},onAdvance(_count,detail){observations.push(detail);}});
  const state=await failed(f,cancellationSource('translate',true),options(f,'json','oversized'));
  assert.equal(state.control.physical_stop,'confirmed');assert.equal(state.control.cancellation_requested,false);
  const consumer=observations.filter(item=>item.task===1);
  assert.ok(consumer.length>0);assert.ok(consumer.every(item=>BigInt(item.work)>0n&&BigInt(item.work)<=256n&&BigInt(item.progress)===0n));
  assert.equal(completions,0);assert.equal(f.dispatches(),1);
});

test('public INSTR omitted defaults remain distinct authored definitions with equal values', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  for(const format of formats) {
    const definitions=[];
    for(const [i,rest] of [[],[1],[1,1]].entries()) {
      const cases=[valueCase('value',`INSTR('banana','an'${rest.map(value=>','+value).join('')})`,instr(literal('banana'),literal('an'),...rest.map(literal)),2,numberContract())];
      const {description}=await published(f,sourceFor(format,'instr_authored_defaults',cases),options(f,format,i+'-'+format),cases);
      definitions.push(description.programDefinitionCid);
    }
    assert.equal(new Set(definitions).size,3,'omitted defaults must not be authored-tree rewrites');
  }
});

test('public translate instr retain excluded BYTES and nonfinite source refusal', {timeout:60_000}, async t=>{
  const f=await fixture(t);
  for(const format of ['sql','aql-text']) {
    for(const [i,text] of ["TRANSLATE(b'a',b'a',b'b')","INSTR(b'a',b'a')"].entries()) await refused(f,sourceFor(format,'translate_instr_bytes',[{name:'value',text}]),options(f,format,'bytes-'+i+'-'+format));
  }
  for(const format of formats) {
    const source=format==='json'?sourceFor(format,'instr_nonfinite',[{name:'value',expression:instr(literal('a'),literal('a'),literal('NONFINITE'))}]).replace('"NONFINITE"','1e309'):sourceFor(format,'instr_nonfinite',[{name:'value',text:"INSTR('a','a',1e309)"}]);
    await refused(f,source,options(f,format,'nonfinite-'+format));
  }
  assert.equal(f.dispatches(),0);assert.equal(f.advances(),0);
});
