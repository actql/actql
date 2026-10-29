import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {types} from 'node:util';
import {parse} from 'acorn';

const source=fs.readFileSync(new URL('./installed-credential-source-reader.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const edits=[];
for(const node of tree.body){
  if(node.type==='ImportDeclaration')edits.push([node.start,node.end]);
  if(node.type==='ExportNamedDeclaration'){assert(node.declaration);edits.push([node.start,node.declaration.start]);}
}
let executable=source;
for(const [start,end]of edits.sort((a,b)=>b[0]-a[0]))executable=executable.slice(0,start)+executable.slice(end);
const unused=()=>assert.fail('preparation must not acquire, grant, send or close physical I/O');
const createReader=Function('types','ownHttpRequest','ownResponseHeaderNames',
  'ownInvocationAuthorization','invocationBindingsMatch','invokeScopedCredentialOperation',
  'openHttpsCredentialBinding','closeHttpsCredentialBinding',
  executable+'\nreturn createInstalledCredentialSourceReader;')(
  types,unused,unused,unused,unused,unused,unused,unused);

test('factory retirement cannot forget an unreturned asynchronous preparation after reentry',async()=>{
  const release=Promise.withResolvers();
  let factory,finished=false;
  const originalSite={bindRunAcquisition:unused,authorizationPurpose:unused,
    callResource:unused,referenceCurrent(){return true;}};
  factory=createReader({capacity:Object.freeze({explicitFixtureDemand:true}),originalSite,
    assertCurrent(){},operation:'fixture:read',maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,
    preparePageReader(){
      assert.equal(factory.retire(),false,'the active preparer has not handed off its owner');
      return release.promise.then(()=>{finished=true;return {fetchPage:unused,decodePage:unused};});
    }});
  assert.throws(()=>factory.prepare({resource:'records',columns:[],
    verifyRead(){},authorizationFor:unused,chargePage:unused,consumePage:unused}),
  {code:'InstalledSourceReaderFactoryClosed'});
  const retiredWhilePending=factory.retire();
  // Settle the exact original Promise even on the expected red, leaving no
  // escaped callback or physical task behind the review counter.
  release.resolve();
  await release.promise;
  for(let index=0;index<4;index++)await Promise.resolve();
  assert.equal(finished,true);
  assert.equal(retiredWhilePending,false,'a pending callback survives the rejected prepare handoff');
  assert.equal(factory.retire(),true,'the same factory can retire after its original callback settles');
});
