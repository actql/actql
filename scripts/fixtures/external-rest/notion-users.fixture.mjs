// Provider response/configuration DATA and independent row/wire expectations.
// The existing family TLS/process/conformance helpers own the physical fixture.
import assert from 'node:assert/strict';
import {join} from 'node:path';

const cursor='next e\u0301+東京';
const users=[
  {object:'user',id:'person-one',name:'e\u0301',type:'person',person:{email:'first@example.invalid'}},
  {object:'user',id:'bot-two',name:'東京',type:'bot',bot:{},person:{email:'not-a-bot-email@example.invalid'}},
  {object:'user',id:'partial-three'},
];
const rows=[{id:'person-one',name:'e\u0301',type:'person',email:'first@example.invalid'},
  {id:'bot-two',name:'東京',type:'bot',email:null},
  {id:'partial-three',name:null,type:null,email:null}];
const targets=['/v1/users?page_size=2',
  '/v1/users?page_size=1&start_cursor=next%20e%CC%81%2B%E6%9D%B1%E4%BA%AC'];

export function notionUsersProgram(connectorId){
  return {version:'actql/0.1',id:'notion-users-read',stages:[{id:'read',
    inputs:{users:{connector:connectorId,resource:'users'}},
    steps:[{select:['id','name','type','email'],as:'selected'}],
    results:{rows:{from:'selected',fields:['id','name','type','email']}}}],
    results:{rows:{from:{stage:'read',result:'rows'}}}};
}

export function notionUsersProvider(){
  const requests=[];
  return Object.freeze({
    handle({method,target}){
      assert.equal(method,'GET');assert.equal(target,targets[requests.length]);
      requests.push({method,target});const second=requests.length===2;
      return {statusCode:200,body:JSON.stringify({object:'list',type:'user',user:{},
        results:second?[users[2]]:users.slice(0,2),has_more:!second,next_cursor:second?null:cursor})};
    },
    requests(){return requests.map(value=>({...value}));},
    assertRequests(transport){
      assert.deepEqual(requests,targets.map(target=>({method:'GET',target})));
      assert.equal(transport.length,2);
      for(const original of transport){
        assert.equal(original.authorized,true);
        assert.equal(original.headers['notion-version'],'2026-03-11');
      }
    },
    assertRows(actual){assert.deepEqual(actual,rows);},
  });
}

export function notionUsersConfiguration(family,{connectorId}){
  assert.equal(typeof family.accountConfigurationWire,'string');assert(family.accountConfigurationWire.length>0);
  const siteProfilePath=join(family.paths.project,'notion-site.json');
  const sourceProfilePath=join(family.paths.project,'notion-source.json');
  return Object.freeze({files:{
    'notion-site.json':{version:'actql-installed-notion-site/0.1',apiOrigin:family.resourceHttps.origin,
      caPath:family.resourceHttps.caPath,credentialAuthorityId:'notion-fixture-authority',credentialKeyId:'notion-fixture-key',
      credentialPrivateKeyPath:family.keys.credentialAuthority.privateKeyPath,environment:'test',
      journalRoot:family.paths.credentialJournal,namespaceId:family.scenario.id,siteGeneration:0,siteKey:'notion-users'},
    'notion-source.json':{version:'actql-installed-notion-source/0.1',connectorId,siteProfilePath,
      accountConfigurationWire:family.accountConfigurationWire,
      limits:{maxResponseBytes:8192,maxTotalResponseBytes:24576,maxNodes:512,maxDepth:16,maxRows:2,
        maxTotalRows:3,maxPages:4,pageSize:2,maxCursorBytes:128,maxIdentityBytes:128,maxTargetBytes:1024,
        maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8,
        maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384}},
    },installation:{directory:family.paths.state,sourceProfilePath,
      authorization:{accountConfiguration:family.accountConfigurationWire}}});
}
