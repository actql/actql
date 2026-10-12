import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {localOutputLimits} from './local-values-plan.mjs';

const formats = ['sql','aql-text','json'];
const literal = value => ({literal:value});
const operations = ['sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','asinh','acosh','atanh','atan2'];
const apply = (op,...args) => ({[op]:op==='atan2'?args:args[0]});
const number = (name,text,expression,expected,nullable=false) => ({name,text,expression,expected,contract:{type:'number',nullable}});
const spelling = value => Number.isInteger(value) && Math.abs(value)>Number.MAX_SAFE_INTEGER ? value.toExponential() : String(value);
const controls = operations.map(op => ({op,input:op==='acosh'||op==='acos'?1:0,expected:op==='cos'||op==='cosh'?1:0}));
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
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-direct-trig-'));
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
        version: 'actql-execution-account-config/0.1', account_id: 'public-direct-trig',
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

// Approximate controls use independently frozen MPFR intervals, never
// Math.* or product output as an oracle. Exact boundary controls stay exact.
function assertRows(actual, cases) {
  assert.equal(actual.length, 1);
  assert.deepEqual(Object.keys(actual[0]).sort(), cases.map(item => item.name).sort());
  for (const item of cases) {
    const value = actual[0][item.name];
    if (item.interval) {
      assert.equal(typeof value, 'number');
      assert.ok(value >= item.interval[0] && value <= item.interval[1],
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

async function assertRefused(f, source, options, code='ClientProgramInvalidInput') {
  await assert.rejects(f.client.startSource(source, options), error => {
    assert.equal(error.code, 'SubmissionNotAccepted');
    const outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'not_accepted');
    assert.deepEqual(outcome.submissionRef, options.submissionRef);
    assert.deepEqual(outcome.problem,{code,classification:code==='ClientProgramImplementationLimit'?'implementation_limit':'invalid_input'},source);
    return true;
  });
}


const oracle = JSON.parse(readFileSync(new URL('../../scripts/fixtures/direct-trig-oracles.json',import.meta.url),'utf8'));
const divide={divide:[literal(1),literal(0)]};
const controlCase = (item,name=item.op) => number(name,`${item.op.toUpperCase()}(${item.input}${item.op==='atan2'?',1':''})`,apply(item.op,literal(item.input),...(item.op==='atan2'?[literal(1)]:[])),item.expected);
async function publishBatches(f,id,cases) {
  for(let offset=0;offset<cases.length;offset+=8) for(const format of formats) {
    const selected=cases.slice(offset,offset+8);
    await assertPublished(f,sourceFor(format,id+'_'+offset,selected),{format,submissionRef:f.client.newSubmission({nonce:id+'-'+offset+'-'+format})},selected);
  }
}
async function assertFailed(f,source,options) {
  const run=await f.client.startSource(source,options),state=await run.wait({signal:AbortSignal.timeout(15000)});
  assert.equal(state.status,'failed',JSON.stringify(state));
  assert.equal(state.control.physical_stop,'confirmed');assert.equal(state.result_availability.answer.state,'unavailable');
  await assert.rejects(run.result('answer').all());await assert.rejects(run.result('answer').describe());
  const before=f.dispatches(),attached=await f.client.attach(run.ref);
  assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);assert.equal((await attached.status()).status,'failed');
  await assert.rejects(attached.result('answer').all());await assert.rejects(attached.result('answer').describe());assert.equal(f.dispatches(),before);
}

test('public direct trig exact identities tiny results and canonical zero across SQL Pipe JSON',{timeout:90_000},async t=>{
  const f=await fixture(t),cases=controls.map(item=>controlCase(item));
  for(const op of ['sin','tan','asin','atan','sinh','tanh','asinh','atanh']) for(const [i,input] of [5e-324,-5e-324].entries()) {
    cases.push(number(op+'_tiny_'+i,`${op.toUpperCase()}(${input})`,apply(op,literal(input)),input));
  }
  cases.push(number('zero_quadrant','ATAN2(-1*0,-1*0)',apply('atan2',{multiply:[literal(-1),literal(0)]},{multiply:[literal(-1),literal(0)]}),0));
  // Each public multiply result already owns canonical +0, so the negative-x
  // quadrant is +pi even when the source arithmetic could produce IEEE -0.
  cases.push(number('negative_x','ATAN2(-1*0,-1)',apply('atan2',{multiply:[literal(-1),literal(0)]},literal(-1)),3.141592653589793));
  await publishBatches(f,'direct_trig_exact',cases);
});

test('public direct trig frozen MPFR controls cover huge reduction endpoint neighbors overflow edge and atan2 ratios',{timeout:120_000},async t=>{
  const f=await fixture(t);
  const cases=oracle.vectors.map(v=>({name:v.id,text:`${v.operation.toUpperCase()}(${v.inputs.map(spelling).join(',')})`,expression:apply(v.operation,...v.inputs.map(literal)),interval:v.acceptanceBounds,contract:{type:'number',nullable:false}}));
  await publishBatches(f,'direct_trig_mpfr',cases);
});

test('public direct trig strict NULL nullable parameters and empty schemas',{timeout:90_000},async t=>{
  let completions=0;
  const f=await fixture(t,{onComputed(){completions++;}}),declarations={n:{type:'number',nullable:true}};
  assert.equal(localOutputLimits.maxResultFields,10);
  const nulls=controls.map(({op})=>number(op,`${op.toUpperCase()}(NULL${op==='atan2'?',1':''})`,apply(op,literal(null),...(op==='atan2'?[literal(1)]:[])),null,true));
  nulls.push(number('atan2_right','ATAN2(1,NULL)',apply('atan2',literal(1),literal(null)),null,true));
  await publishBatches(f,'direct_trig_nulls',nulls);
  for(const [i,input] of [1,null].entries()) for(const format of formats) {
    const cases=[number('value','ACOSH(@n)',apply('acosh',{$param:'n'}),input===null?null:0,true)];
    await assertPublished(f,sourceFor(format,'direct_trig_parameters',cases,declarations),{format,parameters:{n:input},...(format==='json'?{}:{parameterDeclarations:declarations}),submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
  }
  const cases=controls.map(({op})=>number(op,`${op.toUpperCase()}(1/0${op==='atan2'?',1':''})`,apply(op,divide,...(op==='atan2'?[literal(1)]:[])),undefined));
  // Preserve the installed publication ceiling. All thirteen operations still
  // retain their empty/no-demand and schema controls, in disjoint 8+5 batches.
  for(let offset=0;offset<cases.length;offset+=8) for(const format of formats) {
    const selected=cases.slice(offset,offset+8);
    const source=sourceFor(format,'direct_trig_empty_'+offset,selected,undefined,true),options={format,submissionRef:f.client.newSubmission({nonce:'empty-'+offset+'-'+format})};
    const run=await f.client.startSource(source,options);
    const state=await run.wait({signal:AbortSignal.timeout(15000)});
    assert.equal(state.status,'succeeded',JSON.stringify({format,state}));
    const columns=selected.map(({name,contract})=>({name,contract}));
    assert.deepEqual(await run.result('answer').all(),[]);assert.deepEqual((await run.result('answer').describe()).columns,columns);
    const before=f.dispatches(),attached=await f.client.attach(run.ref);
    assert.deepEqual((await f.client.startSource(source,options)).ref,run.ref);
    assert.deepEqual(await attached.result('answer').all(),[]);assert.deepEqual((await attached.result('answer').describe()).columns,columns);assert.equal(f.dispatches(),before);
  }
  // Keep the original oversized fixture as a negative capacity control rather
  // than raising limits or silently dropping its failure boundary.
  for(const format of formats) {
    const before=completions;
    await assertFailed(f,sourceFor(format,'direct_trig_empty_over',cases,undefined,true),{format,submissionRef:f.client.newSubmission({nonce:'empty-over-'+format})});
    assert.equal(completions,before,'over-capacity empty output cannot publish');
  }
});

test('public direct trig rejects wrong arities malformed shapes nonnumeric and nonfinite inputs before dispatch',{timeout:90_000},async t=>{
  const f=await fixture(t);
  for(const op of operations) {
    const name=op.toUpperCase(),binary=op==='atan2';
    const invalid=[
      {text:name+'()',expression:{[op]:[]}},
      {text:name+(binary?'(1)':'(1,2)'),expression:{[op]:binary?[literal(1)]:[literal(1),literal(2)]}},
      {text:name+'(1,2,3)',expression:{[op]:[literal(1),literal(2),literal(3)]}},
      {text:`${name}('1'${binary?',1':''})`,expression:apply(op,literal('1'),...(binary?[literal(1)]:[]))},
      {text:`${name}(TRUE${binary?',1':''})`,expression:apply(op,literal(true),...(binary?[literal(1)]:[]))},
      {text:`${name}(CAST('1' AS DECIMAL(2,0))${binary?',1':''})`,expression:apply(op,{cast:{value:literal('1'),target:{type:'decimal',precision:2,scale:0}}},...(binary?[literal(1)]:[]))},
      {text:`IF(FALSE,${name}('1'${binary?',1':''}),1)`,expression:{if:[literal(false),apply(op,literal('1'),...(binary?[literal(1)]:[])),literal(1)]}},
    ];
    for(const [i,item] of invalid.entries()) for(const format of formats) await assertRefused(f,sourceFor(format,'direct_trig_invalid',[{name:'value',...item}]),{format,submissionRef:f.client.newSubmission({nonce:op+i+'-'+format})});
    const malformed=binary?[{atan2:literal(1)},{atan2:{first:literal(1),second:literal(2)}}]:[{[op]:[literal(1)]},{[op]:{value:literal(1)}}];
    malformed.push({[name]:binary?[literal(1),literal(2)]:literal(1)});
    for(const [i,expression] of malformed.entries()) await assertRefused(f,sourceFor('json','direct_trig_shape',[{name:'value',expression}]),{format:'json',submissionRef:f.client.newSubmission({nonce:op+'-shape-'+i})});
  }
  for(const text of ['ATAN2(1,TRUE)',"ATAN2(1,'1')",'SIN(-0.0)','SIN(-0)','SIN(9007199254740992)']) for(const format of ['sql','aql-text']) {
    await assertRefused(f,sourceFor(format,'direct_trig_tokens',[{name:'value',text}]),{format,submissionRef:f.client.newSubmission({nonce:text+'-'+format})});
  }
  // Qualified unsupported functions retain the existing FunctionLimit owner;
  // unlike malformed values/arity, they are not classified as author error.
  for(const text of ['SAFE.SIN(0)','ACTQL.SIN(0)']) for(const format of ['sql','aql-text']) {
    await assertRefused(f,sourceFor(format,'direct_trig_tokens',[{name:'value',text}]),{format,submissionRef:f.client.newSubmission({nonce:text+'-'+format})},'ClientProgramImplementationLimit');
  }
  for(const format of formats) {
    const source=format==='json'?sourceFor(format,'direct_trig_nonfinite',[{name:'value',expression:apply('sin',literal('NONFINITE'))}]).replace('"NONFINITE"','1e309'):sourceFor(format,'direct_trig_nonfinite',[{name:'value',text:'SIN(1e309)'}]);
    await assertRefused(f,source,{format,submissionRef:f.client.newSubmission({nonce:'nonfinite-'+format})});
  }
  assert.equal(f.dispatches(),0);assert.equal(f.advances(),0);
});

test('public direct trig domain and finite overflow failures remain durable without publication',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const inputs=[['asin',1.0000000000000002],['asin',-1.0000000000000002],['acos',1.0000000000000002],['acos',-1.0000000000000002],['acosh',0.9999999999999999],['acosh',-1],['atanh',1],['atanh',-1],['atanh',1.0000000000000002],['atanh',-1.0000000000000002],['sinh',710.475860073944],['sinh',-710.475860073944],['cosh',710.475860073944],['cosh',-710.475860073944]];
  for(const [i,[op,input]] of inputs.entries()) for(const format of formats) {
    await assertFailed(f,sourceFor(format,'direct_trig_domain',[{name:'value',text:`${op.toUpperCase()}(${input})`,expression:apply(op,literal(input))}]),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})});
  }
});

test('public direct trig demanded errors are eager through NULL and SAFE arithmetic',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const failures=operations.map(op=>({text:`${op.toUpperCase()}(1/0${op==='atan2'?',NULL':''})`,expression:apply(op,divide,...(op==='atan2'?[literal(null)]:[]))}));
  failures.push({text:'ATAN2(NULL,1/0)',expression:apply('atan2',literal(null),divide)},
    {text:'SAFE_DIVIDE(ASIN(2),0)',expression:{safe_divide:[apply('asin',literal(2)),literal(0)]}},
    {text:'GREATEST(NULL,ATAN2(1/0,1))',expression:{greatest:[literal(null),apply('atan2',divide,literal(1))]}});
  for(const [i,item] of failures.entries()) for(const format of formats) await assertFailed(f,sourceFor(format,'direct_trig_demanded',[{name:'value',...item}]),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})});
});

test('public direct trig lazy outer inner guards quoted spellings and composition',{timeout:90_000},async t=>{
  const f=await fixture(t),cases=[];
  for(const item of controls) {
    const {op,input,expected}=item,suffix=op==='atan2'?',1':'',args=op==='atan2'?[literal(1)]:[];
    cases.push(number(op+'_outer',`IF(FALSE,${op.toUpperCase()}(1/0${suffix}),7)`,{if:[literal(false),apply(op,divide,...args),literal(7)]},7));
    cases.push(number(op+'_coalesce',`COALESCE(7,${op.toUpperCase()}(1/0${suffix}))`,{coalesce:[literal(7),apply(op,divide,...args)]},7));
    cases.push(number(op+'_child',`${op.toUpperCase()}(IF(TRUE,${input},1/0)${suffix})`,apply(op,{if:[literal(true),literal(input),divide]},...args),expected));
  }
  cases.push(number('quoted','`sIn`(0)',apply('sin',literal(0)),0),number('nested','SIN(ACOSH(COS(0)))',apply('sin',apply('acosh',apply('cos',literal(0)))),0));
  await publishBatches(f,'direct_trig_lazy',cases);
});

test('public direct trig retained receipts bind independent canonical JSONL bytes',{timeout:90_000},async t=>{
  const f=await fixture(t);
  const vectors=[
    {text:'SIN(0)',expression:apply('sin',literal(0)),expected:0,wire:'{"value":0}\n',bytes:12,sha256:'2cb5e96e08607ddbc0bd13fb3a5e75e3245b536c076ad46bf3d66fc9f69f0b28'},
    {text:'COS(0)',expression:apply('cos',literal(0)),expected:1,wire:'{"value":1}\n',bytes:12,sha256:'3a37782e8974c48eebf2a0517c866ad15641c53b3d31993188796b56aeb79624'},
    {text:'ATAN2(-1*0,-1*0)',expression:apply('atan2',{multiply:[literal(-1),literal(0)]},{multiply:[literal(-1),literal(0)]}),expected:0,wire:'{"value":0}\n',bytes:12,sha256:'2cb5e96e08607ddbc0bd13fb3a5e75e3245b536c076ad46bf3d66fc9f69f0b28'},
    {text:'ATANH(NULL)',expression:apply('atanh',literal(null)),expected:null,wire:'{"value":null}\n',bytes:15,sha256:'2e5bb0a6612ff9082a69f530010db34d0b9c459b345be114936568de2fdcfaee'},
  ];
  for(const [i,item] of vectors.entries()) for(const format of formats) {
    assert.equal(Buffer.byteLength(item.wire),item.bytes);assert.equal(createHash('sha256').update(item.wire).digest('hex'),item.sha256);
    const cases=[number('value',item.text,item.expression,item.expected,item.expected===null)];
    const {run,description}=await assertPublished(f,sourceFor(format,'direct_trig_identity',cases),{format,submissionRef:f.client.newSubmission({nonce:i+'-'+format})},cases);
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

test(`public direct_trig cancellation stops after charged math progress`,
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
    const source = JSON.stringify({version:'actql/0.1',id:'direct_trig_cancel',stages:[{
      id:'seed',inputs:{},steps:[
        {values:{schema:{x:{type:'number',nullable:false}},
          rows:Array.from({length:100},()=>({x:0}))},as:'out'}],
        results:{rows:{from:'out',fields:['x']}}},{
      id:'main',inputs:{rows:{result:{stage:'seed',result:'rows'}}},steps:[
        {from:'rows',derive:{value:apply('sin',apply('atan2',{field:'x'},literal(1)))},as:'derived'},
        {select:['value'],as:'out'}],results:{rows:{from:'out',fields:['value']}}}],
      results:{answer:{from:{stage:'main',result:'rows'}}}});
    const options = {format:'json',submissionRef:f.client.newSubmission({nonce:'direct_trig-cancel'})};
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
