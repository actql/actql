import assert from 'node:assert/strict';
import test from 'node:test';
import {throwSqliteInitializationFailure} from './sqlite-transaction.mjs';

function retain(database) {
  const primary=new Error('OriginalInitializationFailure');let failure;
  assert.throws(()=>throwSqliteInitializationFailure(database,primary,'same-journal'),error=>{
    failure=error;return error.primaryFailure===primary&&error.cleanupPending===true;
  });
  return failure;
}

test('initialization retries retain only first and latest close diagnostics',()=>{
  const first=new Error('FirstCloseFailure');let calls=0,allow=false,latest;
  const database={close(){calls++;if(!allow){latest=calls===1?first:new Error('CloseFailure'+calls);throw latest;}}};
  const failure=retain(database);
  for(let count=0;count<64;count++)assert.equal(failure.cleanupHandle.retry().pending,true);
  assert.equal(failure.cleanupErrors.length,2);
  assert.equal(failure.cleanupErrors[0].error,first);
  assert.equal(failure.cleanupErrors[1].error,latest);
  allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);
  assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(calls,66);
});

test('initialization cleanup retries only the captured original close receiver',()=>{
  let calls=0,allow=false;const database={close(){assert.equal(this,database);calls++;
    database.close=()=>undefined;if(!allow)throw new Error('OriginalClosePending');}};
  const failure=retain(database);
  assert.equal(failure.cleanupHandle.retry().pending,true);assert.equal(calls,2);
  allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(calls,3);
});

test('synchronous cleanup reentry only observes the existing close flight',()=>{
  let calls=0,allow=false,failure,nested;
  const database={close(){calls++;if(!allow)throw new Error('OriginalClosePending');
    if(calls===2)nested=failure.cleanupHandle.retry();}};
  failure=retain(database);allow=true;
  assert.equal(failure.cleanupHandle.retry().pending,false);
  assert.equal(nested.pending,true);assert.equal(calls,2);
});

test('a false original close observation remains pending rather than an acknowledgement',()=>{
  let calls=0,allow=false;const database={close(){calls++;return allow?undefined:false;}};
  const failure=retain(database);
  assert.equal(failure.cleanupHandle.retry().pending,true);assert.equal(calls,2);
  allow=true;assert.equal(failure.cleanupHandle.retry().pending,false);assert.equal(calls,3);
});
