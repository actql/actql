import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Actual transport constructor with explicit row/cleanup ports. This is not
// an ordinary installed Host or a nominal Core usage qualification.
const source=readFileSync(new URL('./in-process-client.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const node=ast.body.find(value=>value.type==='FunctionDeclaration'&&value.id.name==='publicResultRows');
assert(node);
const wrap=new Function('publicFailure','publicError',source.slice(node.start,node.end)+';return publicResultRows;')(
  error=>error,code=>Object.assign(new Error(code),{code}));

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
