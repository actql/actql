import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareHubSpotManagedSequence} from '../site/hubspot-managed-sequence.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION, HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
const schema = {results: [{name:'name', type:'string', fieldType:'text'}]};
const limits = Object.freeze({maxResponseBytes:4096,maxNodes:1000,maxDepth:20,maxProperties:10,
  maxNameUnits:100,maxPages:2,maxRows:3,maxRequests:5,perPage:2,maxColumns:3,maxCursorUnits:64,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:4096,maxRowsWireNodes:100,maxRowsWireDepth:10});
const bytes = value => Buffer.from(JSON.stringify(value));
const row = id => ({id,archived:false,properties:{name:'Original '+id}});
// Explicit generic Reader ports; real provider decoder, no Site/Grant/physical
// send, Resource admission or cleanup acknowledgement is claimed by this case.
function fixture({duplicate=false, drift=false, denied=false, cancel=false}={}) {
  const catalog = checked(moon.hubspotProjectProperties(bytes(schema),'companies',4096,1000,20,10,100));
  const controller=new AbortController(),operations=[],metadata=[],events=[],rows=[];
  let total=0n,count=0,page=0,properties=0;
  const sequence=prepareHubSpotManagedSequence({moon,originalPortalId:'7',originalCatalog:catalog,
    objectType:'companies',properties:['name'],limits,
    async authorizeMetadata(operation,index,signal) {
      assert.strictEqual(signal,controller.signal);metadata.push({operation,index});
      if(denied)throw Object.assign(new Error('HubSpotMetadataReadDenied'),{code:'HubSpotMetadataReadDenied'});
      return Object.freeze({originalAuthorization:{operation},authorization:{operation},verifyCurrent(){}});
    },
    responseCapacity(bodies,received){assert.equal(received,total);assert.equal(bodies.length,count);
      events.push('reserved');return Object.freeze({sameOriginalPrefix:bodies});},
  });
  const context=Object.freeze({signal:controller.signal,
    async readChild(input) {
      const prepared=input.prepare();operations.push(input.operation);
      let body;
      if(input.operation===HUBSPOT_ACCOUNT_DETAILS_OPERATION)body=bytes({portalId:7,accountType:'STANDARD'});
      else if(input.operation===HUBSPOT_PROPERTIES_READ_OPERATION){properties++;
        body=bytes(drift&&properties===2?{results:[{...schema.results[0],hasUniqueValue:true}]}:schema);}
      else {assert.equal(input.operation,HUBSPOT_OBJECT_LIST_OPERATION);
        page++;body=bytes({results:[row(duplicate||page===1?'9007199254740993':'9007199254740994')],
          ...(page===1?{paging:{next:{after:'opaque /%+é'}}}:{})});
        if(page===2)assert(prepared.request.query.some(([key,value])=>key==='after'&&value==='opaque /%+é'));
      }
      events.push('charged');total+=BigInt(body.length);count++;
      sequence.responseCapacity(body.length,body,prepared.request.path,total,count);
      assert.equal(events.at(-1),'reserved');events.push('decode');
      return prepared.project({accepted:true,statusCode:200,body});
    },
    async consumeObservation(){events.push('observation');if(cancel)controller.abort();},
    async consumePage(values){rows.push(...values);},
  });
  return {sequence,context,operations,metadata,events,rows};
}

test('HubSpot managed protocol retains exact ids/cursors and independent metadata operations under generic response ports',async()=>{
  const f=fixture();await f.sequence.read(f.context);
  assert.deepEqual(f.rows.map(row=>row.id),['9007199254740993','9007199254740994']);
  assert.deepEqual(f.operations,[HUBSPOT_ACCOUNT_DETAILS_OPERATION,HUBSPOT_PROPERTIES_READ_OPERATION,
    HUBSPOT_OBJECT_LIST_OPERATION,HUBSPOT_OBJECT_LIST_OPERATION,HUBSPOT_PROPERTIES_READ_OPERATION]);
  assert.deepEqual(f.metadata.map(x=>x.index),[0,1,4]);
  assert.equal(f.sequence.retire(),true);assert.equal(f.sequence.retire(),true);
  await assert.rejects(f.sequence.read(f.context),{code:'ForeignHubSpotManagedSequence'});
});

test('HubSpot managed protocol keeps duplicate/schema/current refusal before successful completion',async()=>{
  const duplicate=fixture({duplicate:true});
  await assert.rejects(duplicate.sequence.read(duplicate.context),{code:'HubSpotReadDuplicateRecord'});
  assert.equal(duplicate.rows.length,1);assert.equal(duplicate.sequence.retire(),true);
  const drift=fixture({drift:true});await assert.rejects(drift.sequence.read(drift.context),{code:'MoonBitHostFailure'});
  assert.equal(drift.operations.at(-1),HUBSPOT_PROPERTIES_READ_OPERATION);assert.equal(drift.sequence.retire(),true);
  const denied=fixture({denied:true});await assert.rejects(denied.sequence.read(denied.context),{code:'HubSpotMetadataReadDenied'});
  assert.equal(denied.operations.length,0);assert.equal(denied.sequence.retire(),true);
  const cancelled=fixture({cancel:true});await assert.rejects(cancelled.sequence.read(cancelled.context),{name:'AbortError'});
  assert.deepEqual(cancelled.operations,[HUBSPOT_ACCOUNT_DETAILS_OPERATION]);assert.equal(cancelled.sequence.retire(),true);
});
