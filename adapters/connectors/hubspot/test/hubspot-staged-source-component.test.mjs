// Component only: actual portable provider and selected managed caller with
// explicit generic Reader ports. No Site/Grant/send/current or physical ACK is
// claimed. Real Common/Resource admission is a distinct MoonBit component.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/debug/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareHubSpotManagedSequence} from '../site/hubspot-managed-sequence.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';

const limits=Object.freeze({maxResponseBytes:100000,maxNodes:1000,maxDepth:16,maxProperties:8,
  maxNameUnits:100,maxPages:1,maxRows:1,maxRequests:4,perPage:1,maxColumns:2,maxCursorUnits:64,
  maxValueNodes:100,maxValueTextBytes:10000,maxRowsWireBytes:10000,maxRowsWireNodes:100,maxRowsWireDepth:16});
const schema={results:[{name:'name',type:'string',fieldType:'text'}],unknown:'日'.repeat(10000)};
const bytes=value=>Buffer.from(JSON.stringify(value));

function fixture(mode) {
  const original=checked(moon.hubspotProjectProperties(bytes(schema),'companies',100000,1000,16,8,100));
  const controller=new AbortController(),events=[];
  let count=0,total=0n,staged,legacy=0,consumed=0,retired=0;
  const primary=Object.assign(new Error('selected grow refused'),{code:'SelectedGrowRefusal'});
  const provider={...moon,
    hubspotPreparePropertyResponseSource(...args){events.push('preflight');return staged=moon.hubspotPreparePropertyResponseSource(...args);},
    hubspotConsumePropertyResponseSource(...args){consumed++;events.push('consume');return moon.hubspotConsumePropertyResponseSource(...args);},
    hubspotRetirePropertyResponseSource(...args){retired++;moon.hubspotRetirePropertyResponseSource(...args);},
    hubspotProjectProperties(...args){legacy++;return moon.hubspotProjectProperties(...args);},
  };
  let currentBody,rows;
  const sequence=prepareHubSpotManagedSequence({moon:provider,originalPortalId:'7',originalCatalog:original,
    objectType:'companies',properties:['name'],limits,
    async authorizeMetadata(operation){return {originalAuthorization:{operation},authorization:{operation},verifyCurrent(){}};},
    responseCapacity(bodies,received,geometry){
      assert.equal(received,total);assert.equal(bodies.length,count);events.push('reserve');
      if(count===2){
        assert.equal(geometry.length,mode==='http'?0:12);
        if(geometry.length){assert(geometry[11]<32);assert.equal(geometry[0],currentBody.byteLength);}
        if(mode==='grow')throw primary;
        if(mode==='mutate')currentBody[0]=0x20;
        if(mode==='cancel')controller.abort();
      }
      return {sameOriginalPrefix:bodies};
    },
  });
  const context=Object.freeze({signal:controller.signal,
    async readChild(input){
      const prepared=input.prepare();
      const body=input.operation===HUBSPOT_ACCOUNT_DETAILS_OPERATION?bytes({portalId:7}):
        input.operation===HUBSPOT_PROPERTIES_READ_OPERATION?(mode==='http'&&count===1?Buffer.from([255]):bytes(schema)):
          bytes({results:[{id:'41',archived:false,properties:{name:'Expected'}}]});
      currentBody=body;total+=BigInt(body.length);count++;events.push('charged');
      sequence.responseCapacity(body.length,body,prepared.request.path,total,count);
      // The unchanged generic Reader performs these local fences after grow.
      controller.signal.throwIfAborted();events.push('project');
      return prepared.project({accepted:mode!=='http'||count!==2,statusCode:mode==='http'&&count===2?503:200,body});
    },
    async consumeObservation(){events.push('observation');},
    async consumePage(value){rows=value;},
  });
  return {sequence,context,events,primary,counts:()=>({legacy,consumed,retired}),
    staged:()=>staged,rows:()=>rows};
}

test('staged ordinary managed caller consumes SAME Source after reserve and keeps final unknown role complete',async()=>{
  const f=fixture('ok');await f.sequence.read(f.context);
  assert.deepEqual(f.rows(),[{id:'41',name:'Expected'}]);
  assert.deepEqual(f.counts(),{legacy:1,consumed:1,retired:0});
  const i=f.events.indexOf('preflight');assert.deepEqual(f.events.slice(i,i+4),['preflight','reserve','project','consume']);
  assert.equal(f.sequence.retire(),true);assert.equal(f.sequence.retire(),true);
  assert.deepEqual(f.counts(),{legacy:1,consumed:1,retired:1});
});

test('staged grow refusal keeps original primary and unconsumed Source until SAME Reader retirement',async()=>{
  const f=fixture('grow');await assert.rejects(f.sequence.read(f.context),e=>e===f.primary);
  assert.equal(moon.hubspotPropertyResponseSourceGeometryData(f.staged()).length,12);
  assert.deepEqual(f.counts(),{legacy:0,consumed:0,retired:0});
  assert.equal(f.sequence.retire(),true);
  assert.deepEqual(moon.hubspotPropertyResponseSourceGeometryData(f.staged()),[]);
});

test('staged Unicode failure remains behind original HTTP refusal',async()=>{
  const f=fixture('http');await assert.rejects(f.sequence.read(f.context),{code:'HubSpotReadRejected'});
  assert.deepEqual(f.counts(),{legacy:0,consumed:0,retired:0});assert.equal(f.sequence.retire(),true);
});

test('staged mutation and cancellation cannot decode or fall back to replacement input',async()=>{
  const mutated=fixture('mutate');await assert.rejects(mutated.sequence.read(mutated.context),{code:'MoonBitHostFailure'});
  assert.deepEqual(mutated.counts(),{legacy:0,consumed:1,retired:0});assert.equal(mutated.sequence.retire(),true);
  const canceled=fixture('cancel');await assert.rejects(canceled.sequence.read(canceled.context),{name:'AbortError'});
  assert.deepEqual(canceled.counts(),{legacy:0,consumed:0,retired:0});assert.equal(canceled.sequence.retire(),true);
  assert.deepEqual(moon.hubspotPropertyResponseSourceGeometryData(canceled.staged()),[]);
});
