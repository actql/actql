import assert from 'node:assert/strict';
import test from 'node:test';
import {createHubSpotUpdateObservationAdapter} from './hubspot-update-observations.mjs';
// Actual adapter/caller with explicit Native/read ports. Native meaning and
// same-token reductions are separately checked by the real MoonBit cases.
function fixture({refuseAfter=false}={}){
  const originalCatalog={},freshCatalog={},target={},checks=[],outputs=[],retired=[];
  let sequence=0;
  const ok=value=>({$tag:1,_0:value});
  const native={
    hubspotRecheckAccountIdentityJson:()=>JSON.stringify({account:{portalId:'7',responseSha256:'a'.repeat(64)}}),
    hubspotProjectProperties:()=>ok(freshCatalog),
    hubspotRecheckPropertyCatalog(a,b){assert.equal(a,originalCatalog);assert.equal(b,freshCatalog);checks.push(b);if(refuseAfter&&checks.length===3)throw new Error('changed full Catalog');return ok();},
    hubspotPropertyCatalogObjectType:()=> 'companies',hubspotRecordReadBody:()=> '{}',
    hubspotRecheckRecordReadRequest:()=>ok(),hubspotProjectRecordRead:()=>ok({}),
    hubspotRecordReadWire:()=> '[{"id":"one","properties":{"name":"before"}}]',
    hubspotPreparePropertyResponseSource:()=>ok({cursor:++sequence}),
    hubspotPropertyResponseSourceGeometryData:()=> [2],hubspotConsumePropertyResponseSource:()=>ok(freshCatalog),
    hubspotRetirePropertyResponseSource:source=>{retired.push(source);},
  };
  const original=Object.freeze({catalog:originalCatalog,resource:'companies',mappingCid:'mapping',mappingRef:'ref'});
  const member={kind:'update',resource:'companies',mapping:{mappingCid:'mapping',mappingRef:'ref'}};
  const limits=Object.fromEntries(['maxResponseBytes','maxRequestBytes','maxNodes','maxDepth','maxProperties','maxNameUnits','maxRows','maxColumns','maxCursorUnits','maxValueNodes','maxValueTextBytes','maxOutputBytes','maxOutputNodes','maxOutputDepth','maxRequestNodes','maxRequestDepth'].map(x=>[x,32]));limits.maxRows=1;
  const adapter=createHubSpotUpdateObservationAdapter({moon:native,portalId:'7',installedFor:()=>original,
    requests:{requestFacts:()=>({target:'one'}),nativeTargetRead:()=>target,objectType:()=> 'companies'},limits});
  const options={member,authorizationFor:()=>({grant:{},useId:'use'}),verify:async()=>{},
    async readChild(auth,input,row,slot,consume){
      const body=Buffer.from('{}'),response={accepted:true,statusCode:200,body,headers:[]};
      consume.responsePreparation?.prepare(body);
      const result=consume(response);outputs.push({slot,result});
      if(slot==='schema-after'){assert.equal(result,undefined);consume.responsePreparation.retire();}
      return result;
    }};
  return {adapter,member,options,checks,outputs,retired,freshCatalog};
}
test('schema-after full Catalog check returns Unit while describe and schema-before keep original Catalog consumers',async()=>{
  const f=fixture(),current=await f.adapter.describe(f.options);
  assert.equal(current.catalog,f.freshCatalog);
  const rows=await f.adapter.observeTargets({...f.options,current,entries:[{request:{}}]});
  assert.equal(rows.length,1);assert.equal(f.checks.length,3);
  assert.equal(f.outputs.find(x=>x.slot==='schema-before').result,f.freshCatalog);
  assert.equal(f.outputs.find(x=>x.slot==='schema-after').result,undefined);
  assert.equal(f.retired.length,1);
});
test('schema-after full current Catalog refusal preserves original response observations and never reports disposal',async()=>{
  const f=fixture({refuseAfter:true}),current=await f.adapter.describe(f.options);
  await assert.rejects(f.adapter.observeTargets({...f.options,current,entries:[{request:{}}]}),error=>{
    assert.equal(error.cause.message,'changed full Catalog');assert.equal(error.observations.length,4);return true;
  });
  assert.equal(f.checks.length,3);assert.equal(f.retired.length,0);
});
