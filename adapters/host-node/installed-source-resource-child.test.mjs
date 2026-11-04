import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';

// Actual generic reader; explicit Site, grant, binding and charge ports. These
// tests establish owner sequencing, not native quantities or installed authority.
function fixture({undeclared=false, foreign=false, pendingClose=false, denyCurrent=false,
  changedGrant=false, badClose=false}={}) {
  const root=Object.freeze({grant:{},scope:Object.freeze({operation:'records'})});
  const form=Object.freeze({grant:{},scope:Object.freeze({operation:'form'})});
  const response=Object.freeze({accepted:true,statusCode:200,body:Buffer.from('{}')});
  const charge={}, events=[];let sends=0, bindings=0, allowClose=!pendingClose, formChecks=0;
  const parent=Object.freeze({credential:Object.freeze({}),close(){events.push('root-close');return 'closed';}});
  const child=Object.freeze({credential:Object.freeze({}),close:badClose?undefined:function(){
    events.push('child-close');return allowClose?'closed':'pending';},retire(){events.push('child-retire');return true;}});
  let childCurrent;
  const site={};
  const originalSite=Object.freeze({site,referenceCurrent(){return true;},
    authorizationPurpose(value){assert.ok(value===root||value===form);return {kind:'read',resource:value===root?'records':'form'};},
    bindRunAcquisition(value,current){assert.equal(value,root);current.assertCurrent();return parent;},
    readChildCredential(){assert.fail('A separately bound child must not use shared-root credentials');},
    bindReadResourceChild(actual,original,current){assert.equal(actual,parent);assert.equal(original,form);
      current.assertCurrent();childCurrent=current;bindings++;return child;},
    readResourceChildCredential(actual,bound,original){assert.equal(actual,parent);assert.equal(bound,child);assert.equal(original,form);
      return foreign?parent.credential:child.credential;},
    async callResource(input){assert.equal(this,site);assert.equal(input.grant,form.grant);
      await input.currentBeforeSend();sends++;input.responseCustody.retain(response);return response;},
  });
  const verifyCurrent=async()=>{formChecks++;if(denyCurrent)throw new Error('FormDenied');};
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent(){},
    resourceChildren:Object.freeze(undeclared?['other']:['form']),maxResponses:2,maxResponseBytes:128,
    prepareReadSequence(){return Object.freeze({async read(context){for(let i=0;i<2;i++){
      const authorization=Object.freeze({...form,useId:`form-${i}`});
      await context.readChild({operation:'form',prepare(){return Object.freeze({original:{},originalAuthorization:form,
        authorization,verifyCurrent:changedGrant&&i===1?async()=>{}:verifyCurrent,
        request:Object.freeze({method:'GET',path:'/form'}),project(value){assert.equal(value,response);}});}});
      await context.consumeObservation();
    }},retire(){events.push('protocol-retire');return true;}});},
  });
  const reader=factory.prepare(Object.freeze({originalAuthorization:root,columns:['id'],verifyRead(){},
    authorizationFor(){return {...root,useId:'root'};},
    authorizeReadChild(_operation,_index,_occurrence,supplied){return supplied;},
    chargePage(body){assert.equal(body,response.body);events.push('charge');return charge;},
    consumeObservation(value){assert.equal(value,charge);},consumePage(){assert.fail('No metadata rows');},
  }));
  return {factory,reader,events,allowClose(){allowClose=true;},counts:()=>({sends,bindings,formChecks}),
    observeChild:()=>childCurrent.observeCurrent()};
}

test('resource child is bound once under the same reader and joins its own close and retirement',async()=>{
  const f=fixture({pendingClose:true});assert.deepEqual(await f.reader.read(),{pages:2,rowCount:0});
  assert.equal(f.counts().bindings,1);assert.equal(f.counts().sends,2);assert.ok(f.counts().formChecks>=4);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,false);
  assert.equal(f.reader.observe().transportClosed,false);assert.equal(f.factory.retire(),false);
  f.allowClose();f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  assert.equal(f.factory.retire(),true);assert.ok(f.events.includes('child-retire'));
});
test('undeclared or foreign resource child credentials refuse before physical send',async()=>{
  for(const options of [{undeclared:true},{foreign:true}]){
    const f=fixture(options);await assert.rejects(f.reader.read(),{code:'ForeignInstalledSourceReadResourceChild'});
    assert.equal(f.counts().sends,0);f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
    assert.equal(f.factory.retire(),true);
  }
});
test('original Form current failure and callback replacement cannot send another request',async()=>{
  const denied=fixture({denyCurrent:true});await assert.rejects(denied.reader.read(),/FormDenied/);
  assert.equal(denied.counts().sends,0);denied.reader.requestStop();assert.equal(denied.factory.retire(),true);
  const changed=fixture({changedGrant:true});await assert.rejects(changed.reader.read(),{code:'ForeignInstalledSourceReadResourceChild'});
  assert.equal(changed.counts().sends,1);changed.reader.requestStop();assert.equal(changed.factory.retire(),true);
});
test('returned resource child with no close method cannot supply cleanup acknowledgement',async()=>{
  const f=fixture({badClose:true});await assert.rejects(f.reader.read(),{code:'InstalledSourceReaderMethodUnavailable'});
  assert.equal(f.counts().sends,0);f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,false);
  assert.equal(f.factory.retire(),false);
});
