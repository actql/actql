import assert from 'node:assert/strict';
import test from 'node:test';
import {createKintoneManagedSequence} from '../site/kintone-managed-sequence.mjs';
const ok=value=>({$tag:1,_0:value});
// Native projection and Account are explicit ports here. Real native originals
// are exercised by kintone_managed_read_wbtest; no capacity/physical claim here.
function fixture({complete=true,finalFormFailure=false}={}){
  const events=[],borrow={},declaration={},read={},formGrant={},verifyCurrent=async()=>{};
  const columns=Object.freeze(['$id']),rows=Object.freeze([Object.freeze([{}])]);
  let forms=0,pages=0,retired=0,previous={},sequence;
  const initial=previous;
  const moon={
    clientProgramKintoneAdoptManagedBorrow(original,value){assert.equal(original,declaration);assert.equal(value,borrow);return ok(read);},
    clientProgramKintoneManagedColumns(value){assert.equal(value,read);return columns;},
    clientProgramKintoneManagedFormRequest(value){assert.equal(value,read);return ok('{"app":"12"}');},
    clientProgramKintoneManagedPageRequest(value){assert.equal(value,read);return ok('{"fields":["$id"]}');},
    clientProgramKintoneManagedRecheckForm(value){assert.equal(value,read);forms++;events.push('form');
      if(finalFormFailure&&forms>1)throw new Error('FormDrift');return ok(undefined);},
    clientProgramKintoneManagedProjectPage(value){assert.equal(value,read);pages++;events.push('page');return ok(rows);},
    clientProgramKintoneManagedComplete(value){assert.equal(value,read);return complete&&pages>0&&forms>pages;},
    clientProgramKintoneManagedRetire(value){assert.equal(value,read);retired++;},
  };
  const prepare=createKintoneManagedSequence({moon,original:declaration,bounds:{page:{},values:{},form:{}},
    limits:{maxPages:1,perPage:2,maxRequestBytes:4096,maxContractPairs:100},baseCapacity:initial,
    async authorizeForm(input,signal){assert.equal(input.responseBorrow,borrow);signal.throwIfAborted();events.push('authorize-form');
      return Object.freeze({originalAuthorization:formGrant,authorization:{grant:formGrant},verifyCurrent});},
    capacityForResponse(value,kind,bytes,prior){assert.equal(value,read);assert.equal(prior,previous);assert.equal(bytes,2);
      events.push('quote-'+kind);previous={};return previous;},
  });
  const context={signal:new AbortController().signal,
    async readChild(input){const request=input.prepare();assert.equal(request.request.method,'POST');
      assert.deepEqual(request.request.headers,[['x-http-method-override','GET']]);
      if(input.operation==='kintone:form:read'){
        assert.equal(request.originalAuthorization,formGrant);assert.equal(request.verifyCurrent,verifyCurrent);
      }else assert.equal(request.originalAuthorization,undefined);
      sequence.responseCapacity(2);return request.project({statusCode:200,body:Buffer.from('{}')});
    },
    async consumeObservation(){events.push('observation');},
    async consumeValues(actualColumns,actualRows){assert.equal(actualColumns,columns);assert.equal(actualRows,rows);events.push('values');},
  };
  sequence=prepare({responseBorrow:borrow,originalAuthorization:{},columns,resource:'inquiries'});
  return {prepare,sequence,context,events,counts:()=>({forms,pages,retired})};
}
test('managed Kintone uses original borrow and generic charge/quote/consume sequence with final Form',async()=>{
  const f=fixture();await f.sequence.read(f.context);
  assert.deepEqual(f.events,['authorize-form','quote-form','form','observation','quote-page','page','values',
    'authorize-form','quote-form','form','observation']);
  assert.deepEqual(f.counts(),{forms:2,pages:1,retired:0});
  assert.equal(f.sequence.retire(),true);assert.equal(f.sequence.retire(),true);assert.equal(f.counts().retired,1);
  await assert.rejects(f.sequence.read(f.context),{code:'ForeignKintoneManagedSequence'});
});
test('managed Kintone cannot complete after final Form drift or invent another page beyond original maximum',async()=>{
  const drift=fixture({finalFormFailure:true});await assert.rejects(drift.sequence.read(drift.context),/FormDrift/);
  assert.equal(drift.counts().pages,1);assert.equal(drift.sequence.retire(),true);
  const limit=fixture({complete:false});await assert.rejects(limit.sequence.read(limit.context),{code:'KintoneReadPageLimit'});
  assert.equal(limit.counts().pages,1);assert.equal(limit.sequence.retire(),true);
});
test('managed Kintone preparer requires the genuine private borrow handoff, not only columns',()=>{
  const f=fixture();assert.throws(()=>f.prepare({columns:['$id'],originalAuthorization:{}}),{code:'KintoneManagedBorrowUnavailable'});
  assert.equal(f.sequence.retire(),true);
});
