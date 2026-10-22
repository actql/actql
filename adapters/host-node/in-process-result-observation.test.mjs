import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {createHostObservationConnection,installHostObservation} from '../host-common/observation.mjs';

// Actual transport constructor with explicit row/cleanup ports. This is not
// an ordinary installed Host or a nominal Core usage qualification.
const source=readFileSync(new URL('./in-process-client.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const node=ast.body.find(value=>value.type==='FunctionDeclaration'&&value.id.name==='publicResultRows');
assert(node);
const wrap=new Function('publicFailure','publicError',source.slice(node.start,node.end)+';return publicResultRows;')(
  error=>error,code=>Object.assign(new Error(code),{code}));

const trace={traceId:'1'.repeat(32),spanId:'2'.repeat(16),traceFlags:1};
const ref={namespaceId:'local',authorityScopeCid:`sha256:${'a'.repeat(64)}`,runDefinitionCid:`sha256:${'b'.repeat(64)}`};
const selected=()=>({ref,rowOwner:'request-journal',selection:'run-definition',rowKind:'run',returnedRows:1,unrelatedRows:0,coverage:'selected-returned'});
function observing(){
  const records=[];
  const observer=installHostObservation(createHostObservationConnection({deliver:r=>records.push(r),
    include:['run'],measurements:{include:['rows']},events:{level:'diagnostic'}}),
    {journal:{observationStorage:()=>({consume:()=>({accepted:true})})}});
  return{observer,records};
}

test('actual Result iterator continues the one ingress context through its original finally',async()=>{
  const{observer,records}=observing();let rows,receiver,starts=0;
  const response={frames:{async *[Symbol.asyncIterator](){
    receiver=this;starts++;
    try{await new Promise(resolve=>setImmediate(resolve));observer.diagnostic('selected_rows_observed',selected());yield 1;}
    finally{observer.diagnostic('selected_rows_observed',selected());}
  }}};
  await observer.run('read',trace,()=>{rows=wrap(response,undefined,observer.captureCurrentOperation());});
  assert.equal(observer.status().activeSegments,1);assert.equal(starts,0);
  const values=[];for await(const row of rows.frames)values.push(row);
  assert.deepEqual(values,[1]);assert.strictEqual(receiver,response.frames);assert.equal(starts,1);
  await rows.close();assert.equal(observer.status().activeSegments,0);await observer.close();
  const selectedRecords=records.filter(r=>r.event==='selected_rows_observed');
  assert.equal(selectedRecords.length,1);assert.equal(selectedRecords[0].attributes['actql.rows.returned'],2);
  assert.deepEqual(selectedRecords[0].parent,trace);assert.deepEqual(observer.status().loss,{});
});

test('failed row cleanup retains original observation until the same close-only retry confirms',async()=>{
  const{observer,records}=observing();let rows,allow=false,retries=0,usage=0;
  const handle={pending:true,status(){assert.strictEqual(this,handle);return{pending:this.pending};},
    async retry(){assert.strictEqual(this,handle);retries++;observer.diagnostic('selected_rows_observed',selected());if(allow)this.pending=false;}};
  const failure=Object.assign(new Error('OriginalCleanup'),{cleanupPending:true,cleanupHandle:handle});
  await observer.run('read',trace,()=>{
    rows=wrap({frames:{async *[Symbol.asyncIterator](){observer.diagnostic('selected_rows_observed',selected());yield 1;throw failure;}}},
      ()=>{usage++;},observer.captureCurrentOperation());
  });
  await assert.rejects(async()=>{for await(const row of rows.frames)assert.equal(row,1);},error=>error===failure);
  assert.equal(usage,0);assert.equal(observer.status().activeSegments,1);
  await assert.rejects(rows.close(),error=>error.code==='ResultReadCleanupUnknown');
  assert.equal(retries,1);assert.equal(observer.status().activeSegments,1);
  allow=true;await rows.close();assert.equal(retries,2);assert.equal(observer.status().activeSegments,0);
  await observer.close();assert.deepEqual(observer.status().loss,{});
  assert.equal(records.filter(r=>r.event==='selected_rows_observed').length,1);
});

test('partial and unopened Result responses release optional context without inventing successful usage',async()=>{
  const{observer}=observing();let partial,unopened,usage=0,returns=0,starts=0;
  await observer.run('read',trace,()=>{
    partial=wrap({frames:{async *[Symbol.asyncIterator](){try{yield 1;yield 2;}finally{returns++;}}}},()=>{usage++;},observer.captureCurrentOperation());
  });
  for await(const row of partial.frames){assert.equal(row,1);break;}
  assert.equal(returns,1);assert.equal(usage,0);assert.equal(observer.status().activeSegments,0);
  await observer.run('read',trace,()=>{
    unopened=wrap({frames:{async *[Symbol.asyncIterator](){starts++;yield 1;}}},()=>{usage++;},observer.captureCurrentOperation());
  });
  assert.equal(observer.status().activeSegments,1);await unopened.close();
  assert.equal(starts,0);assert.equal(usage,0);assert.equal(observer.status().activeSegments,0);await observer.close();
});

test('an optional context callback cannot repeat iterator work or replace its error',async()=>{
  let starts=0,releases=0;
  const marker=new Error('OriginalIterator');
  const response={frames:{[Symbol.asyncIterator](){return{next(){starts++;throw marker;}};}}};
  const wrapped=wrap(response,undefined,{run(work){try{work();}finally{work();}},release(){releases++;throw new Error('OptionalRelease');}});
  await assert.rejects(async()=>{for await(const row of wrapped.frames)assert.fail(String(row));},error=>error===marker);
  assert.equal(starts,1);assert.equal(releases,1);await wrapped.close();assert.equal(releases,1);
});

test('Result usage observation follows actual successful frame completion once',async()=>{
  const log=[];
  const response={frames:{async *[Symbol.asyncIterator](){
    try{log.push('row');yield {id:1};}finally{log.push('original cleanup');}
  }}};
  const rows=wrap(response,()=>{log.push('usage');});
  assert.deepEqual(log,[]);
  const actual=[];for await(const row of rows.frames)actual.push(row);
  assert.deepEqual(actual,[{id:1}]);assert.deepEqual(log,['row','original cleanup','usage']);
  await rows.close();assert.deepEqual(log,['row','original cleanup','usage']);
});

test('partial or failed rows never fabricate quiescent usage and observation errors preserve rows',async()=>{
  let reads=0,closes=0;
  const marker=new Error('OriginalRows');
  const partial=wrap({frames:{async *[Symbol.asyncIterator](){try{yield 1;yield 2;}finally{closes++;}}}},()=>{reads++;});
  for await(const row of partial.frames){assert.equal(row,1);break;}
  assert.equal(reads,0);assert.equal(closes,1);
  const failed=wrap({frames:{async *[Symbol.asyncIterator](){throw marker;}}},()=>{reads++;});
  await assert.rejects(async()=>{for await(const row of failed.frames)assert.fail(String(row));},error=>error===marker);
  assert.equal(reads,0);
  const successful=wrap({frames:{async *[Symbol.asyncIterator](){yield 3;}}},()=>{throw new Error('OptionalObserver');});
  const result=[];for await(const row of successful.frames)result.push(row);
  assert.deepEqual(result,[3]);await successful.close();
});
