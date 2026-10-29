// Actual pure Site adapter and explicit provider semantic ports. Native
// correlation has separate actual Catalog/bridge cases; no grant/read/ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {finalizeGitHubCommentRequest, prepareGitHubCommentLogicalRequest,
  prepareGitHubCommentConfirmation} from '../site/github-comment-create.mjs';
const tag='sha256:'+'a'.repeat(64),limits={maxRequestBytes:10000,maxResponseBytes:10000,maxNodes:1000,maxDepth:32};
function fixture() {
  const held={},calls=[];let result={kind:'Confirmed',id:'7',nodeId:'IC_7'};
  const moon={githubAddCommentRequestJson(subjectId,body){return JSON.stringify({body:JSON.stringify({query:'fixture mutation',variables:{subjectId,body}})});},
    githubPrepareCommentConfirmation(...args){assert.equal(this,moon);calls.push(args);return {$tag:1,_0:held};},
    githubCommentConfirmationRequestJson(value){assert.equal(this,moon);assert.equal(value,held);return JSON.stringify({kind:'ConfirmationRequest',body:'fixture pure point-read'});},
    githubProjectCommentConfirmationJson(value,status,body){assert.equal(this,moon);assert.equal(value,held);calls.push({status,body});return JSON.stringify(result);},
    githubRequestHeadersJson(){return '[["accept","application/vnd.github+json"]]';}};
  const request=finalizeGitHubCommentRequest({moon,request:prepareGitHubCommentLogicalRequest({origin:'https://github.invalid',subjectId:'I_1',body:''}),requestTag:tag});
  const repository=Object.freeze({nodeId:'R_1',databaseId:11,nameWithOwner:'owner/repo'}),observation={statusCode:200,body:Uint8Array.of(1)};
  return {moon,request,repository,observation,calls,setResult(value){result=value;},
    prepare(overrides={}){return prepareGitHubCommentConfirmation({moon,request,repository,observation,headers:[],limits,...overrides});}};
}

test('Comment confirmation adapter retains exact final request and original semantic receiver',()=>{
  const f=fixture(),prepared=f.prepare();
  assert.equal(f.calls.length,1);
  assert.deepEqual(f.calls[0].slice(0,7),['I_1','',tag,f.request.body,'R_1',11,'owner/repo']);
  assert.equal(f.calls[0][11],f.observation.body);assert(Object.isFrozen(prepared));
  assert.deepEqual(prepared.request,{method:'POST',path:'/graphql',body:'fixture pure point-read',headers:[['accept','application/vnd.github+json']]});
  const read={statusCode:200,body:Uint8Array.of(2)};
  f.moon.githubProjectCommentConfirmationJson=()=>assert.fail('changed method');
  f.moon.githubCommentConfirmationRequestJson=()=>assert.fail('changed method');
  const output=prepared.project(read);
  assert.equal(output.kind,'confirmed-provider-response');assert.equal(output.writeObservation,f.observation);
  assert.equal(output.observation,read);assert.deepEqual(output.result,{comment_id:'7',node_id:'IC_7'});
  assert.equal(Object.hasOwn(output,'outcome'),false);assert.equal(Object.hasOwn(output,'operation_ref'),false);
});

test('Comment confirmation preserves absent recovered headers and unknown read or mutation',()=>{
  const f=fixture(),unknown=f.prepare({observation:{statusCode:403,body:new Uint8Array()},headers:undefined});
  assert.equal(f.calls[0][7],403);assert.equal(f.calls[0][8],false);
  f.setResult({kind:'Unknown'});const read={statusCode:404,body:new Uint8Array()};
  const output=unknown.project(read);assert.equal(output.kind,'provider-response');assert.equal(output.observation,read);
  assert.equal(Object.hasOwn(output,'outcome'),false);
  f.moon.githubCommentConfirmationRequestJson=()=>JSON.stringify({kind:'NoConfirmation'});
  assert.equal(f.prepare(),undefined);
});

test('Comment confirmation rejects changed final CID accessors headers bounds and preserves original errors',()=>{
  const f=fixture();let accesses=0;
  const accessor={...f.request};Object.defineProperty(accessor,'body',{enumerable:true,get(){accesses++;throw new Error('getter');}});
  for(const request of [{...f.request,body:f.request.body+' '},{...f.request,requestTag:'new-tag'},accessor])
    assert.throws(()=>f.prepare({request}),{code:'InvalidGitHubCommentConfirmation'});
  for(const changed of [{...limits,maxRequestBytes:1},{...limits,maxDepth:0}])
    assert.throws(()=>f.prepare({limits:changed}),{code:'InvalidGitHubCommentConfirmation'});
  assert.throws(()=>f.prepare({headers:Array.from({length:17},()=>['x-rate','1'])}),{code:'InvalidGitHubCommentConfirmation'});
  const headers=[];Object.defineProperty(headers,0,{get(){accesses++;throw new Error('header getter');}});
  assert.throws(()=>f.prepare({headers}),{code:'InvalidGitHubCommentConfirmation'});
  assert.equal(accesses,0);assert.equal(f.calls.length,0);
  const cause=new Error('same original provider error');f.moon.githubPrepareCommentConfirmation=()=>{throw cause;};
  assert.throws(()=>f.prepare(),error=>error===cause);
});
