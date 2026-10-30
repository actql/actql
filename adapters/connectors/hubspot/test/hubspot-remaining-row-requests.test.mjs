// Actual portable provider + complete existing JS sequencer. Authorization,
// current, body accounting and transport are explicit component ports; this is
// not a nominal RowRun, physical HTTPS/Account, normal Host or Saved fixture.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {credentialInvocationBindingKeys} from '../../../host-common/credential-scope-fields.generated.mjs';
import {readHubSpotObjects,HUBSPOT_PROPERTIES_READ_OPERATION,HUBSPOT_OBJECT_LIST_OPERATION}
  from '../site/hubspot-object-read.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
const moon=await import(process.env.ACTQL_TEST_HUBSPOT_PROVIDER_MODULE??
  new URL('../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js',import.meta.url).href);
const propertiesBody='{"results":[{"name":"amount","type":"number","fieldType":"number"},{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"a"},{"value":"b"}]}]}';
const limits=Object.freeze({maxResponseBytes:4096,maxNodes:1000,maxDepth:20,maxProperties:10,maxNameUnits:100,
  maxPages:2,maxRows:3,maxRequests:5,perPage:5,maxColumns:3,maxCursorUnits:64,maxValueNodes:100,
  maxValueTextBytes:4096,maxRowsWireBytes:4096,maxRowsWireNodes:100,maxRowsWireDepth:10});
const record=id=>({id,archived:false,properties:{amount:'0',tags:'a;b'}});
const next='opaque /%+é';
function fixture({selectedLimits=limits,selectedPages}={}){
  const originalCatalog=checked(moon.hubspotProjectProperties(Buffer.from(propertiesBody),'companies',
    limits.maxResponseBytes,limits.maxNodes,limits.maxDepth,limits.maxProperties,limits.maxNameUnits));
  const pages=selectedPages??[{results:[record('one'),record('two')],paging:{next:{after:next,link:'https://foreign.invalid/not-followed'}}},
    {results:[record('three')]}];
  const requests=[],responses=[],charges=[],spent=new Set(),observed=[],rows=[],decodeBounds=[];
  const provider={...moon,hubspotProjectObjectPage(...args){
    decodeBounds.push(args[6]);return Reflect.apply(moon.hubspotProjectObjectPage,moon,args);
  }};
  const grant=Object.freeze({componentPort:'grant'}),binding=Object.freeze({componentPort:'binding'});
  const scope=operation=>Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,'same'])),
    operation,resourceOrigin:'https://api.hubapi.com'});
  const authorization=operation=>({grant,scope:scope(operation),useId:'same-'+operation});
  const consume=charge=>{assert(charges.includes(charge));assert(!spent.has(charge));spent.add(charge);};
  const options={moon:provider,originalPortalId:'7',originalCatalog,objectType:'companies',properties:['amount','tags'],
    limits:selectedLimits,initialAuthorization:authorization(HUBSPOT_ACCOUNT_DETAILS_OPERATION),credential:{binding},
    authorizationFor({operation}){return authorization(operation);},
    current(operation){assert([HUBSPOT_ACCOUNT_DETAILS_OPERATION,HUBSPOT_PROPERTIES_READ_OPERATION,HUBSPOT_OBJECT_LIST_OPERATION].includes(operation));},
    async callResource(input){
      await input.currentBeforeSend();assert.equal(input.operations.size,1);assert.equal(input.grant,grant);
      const [operation,request]=[...input.operations][0];
      assert.equal(request.method,'GET');
      const url=new URL(request.path,'https://api.hubapi.com');
      requests.push({operation,path:request.path,url});
      let body;
      if(operation===HUBSPOT_ACCOUNT_DETAILS_OPERATION){assert.equal(url.pathname,'/account-info/v3/details');body={portalId:7};}
      else if(operation===HUBSPOT_PROPERTIES_READ_OPERATION){assert.equal(url.pathname,'/crm/v3/properties/companies');body=JSON.parse(propertiesBody);}
      else{assert.equal(operation,HUBSPOT_OBJECT_LIST_OPERATION);assert.equal(url.pathname,'/crm/v3/objects/companies');body=pages.shift();assert(body);}
      const response=Object.freeze({accepted:true,statusCode:200,body:Buffer.from(JSON.stringify(body))});
      responses.push(response);return response;
    },
    chargeResponse(body){assert(responses.some(response=>response.body===body));const charge=Object.freeze({body,index:charges.length});charges.push(charge);return charge;},
    consumeObservation(charge){consume(charge);observed.push(charge);},
    consumePage(page,{charge}){consume(charge);rows.push(...page);}
  };
  return{read:()=>readHubSpotObjects(options),requests,responses,charges,spent,observed,rows,decodeBounds};
}

test('HubSpot list request and actual decoder share the remaining row allowance on every page',async()=>{
  const f=fixture(),result=await f.read();
  assert.equal(result.pages,2);assert.equal(result.rowCount,3);
  const lists=f.requests.filter(request=>request.operation===HUBSPOT_OBJECT_LIST_OPERATION);
  assert.deepEqual(lists.map(request=>Number(request.url.searchParams.get('limit'))),[3,1]);
  assert.deepEqual(f.decodeBounds,[3,1]);
  assert.deepEqual(lists.map(request=>request.url.searchParams.get('after')),[null,next]);
  assert(lists.every(request=>request.url.searchParams.get('archived')==='false'&&request.url.searchParams.get('properties')==='amount,tags'));
  assert.deepEqual(f.rows.map(row=>row.id),['one','two','three']);
  assert(f.rows.every(row=>row.amount==='0.0000000000'&&JSON.stringify(row.tags)==='["a","b"]'));
  assert.equal(f.requests.length,5);assert.equal(f.charges.length,5);assert.equal(f.observed.length,3);assert.equal(f.spent.size,5);
  assert.deepEqual(result.observations,f.responses);
});
