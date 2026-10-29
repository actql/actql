// One fresh pure provider ABI connection. Actual Catalog/Node exports and Site
// helper, no Host/Account/Credential/network/Store/Run or terminal receipt.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareGitHubCommentLogicalRequest,finalizeGitHubCommentRequest,
  prepareGitHubCommentConfirmation} from '../site/github-comment-create.mjs';
const url=process.env.ACTQL_TEST_GITHUB_CONFIRMATION_URL ?? new URL(
  '../../../../_build/js/release/build/connectors/github/host_node/host_node.js',import.meta.url).href;
const provider=await import(url);
const bytes=value=>Buffer.from(JSON.stringify(value));
const tag='sha256:'+'a'.repeat(64);
const repository=Object.freeze({nodeId:'R_1',databaseId:11,nameWithOwner:'owner/repo'});
const limits=Object.freeze({maxRequestBytes:10000,maxResponseBytes:10000,maxNodes:1000,maxDepth:32});

test('actual provider exports and Site confirmation retain the same final request and read correspondence',()=>{
  const logical=prepareGitHubCommentLogicalRequest({origin:'https://github.invalid',subjectId:'I_1',body:'cafe\u0301\r\n東京'});
  const request=finalizeGitHubCommentRequest({moon:provider,request:logical,requestTag:tag});
  assert.equal(JSON.parse(request.body).variables.body,'cafe\u0301\r\n東京\n\n<!-- actql:effect:'+tag+' -->');
  const write=Object.freeze({statusCode:200,body:bytes({data:{addComment:{commentEdge:{node:{id:'IC_7',databaseId:7}},subject:{__typename:'Issue',id:'I_1'}}}})});
  const prepared=prepareGitHubCommentConfirmation({moon:provider,request,repository,observation:write,headers:[],limits});
  assert(prepared);assert.equal(prepared.request.method,'POST');assert.equal(prepared.request.path,'/graphql');
  const query=JSON.parse(prepared.request.body);assert.deepEqual(query.variables,{id:'IC_7'});
  assert(query.query.startsWith('query ActqlConfirmCreatedIssueComment('));assert(!query.query.includes('mutation'));
  const repo={__typename:'Repository',id:'R_1',databaseId:11,nameWithOwner:'owner/repo'};
  const readValue={data:{node:{__typename:'IssueComment',id:'IC_7',fullDatabaseId:'7',
    body:'cafe\u0301\r\n東京\n\n<!-- actql:effect:'+tag+' -->',repository:repo,
    issue:{__typename:'Issue',id:'I_1',repository:repo},pullRequest:null}}};
  const read=Object.freeze({statusCode:200,body:bytes(readValue)}),confirmed=prepared.project(read);
  assert.equal(confirmed.kind,'confirmed-provider-response');assert.equal(confirmed.writeObservation,write);
  assert.equal(confirmed.observation,read);assert.deepEqual(confirmed.result,{comment_id:'7',node_id:'IC_7'});
  assert.equal(Object.hasOwn(confirmed,'outcome'),false);assert.equal(Object.hasOwn(confirmed,'operation_ref'),false);
  const changed=structuredClone(readValue);changed.data.node.body='same text without original marker';
  assert.equal(prepared.project({statusCode:200,body:bytes(changed)}).kind,'provider-response');
  assert.equal(prepareGitHubCommentConfirmation({moon:provider,request,repository,
    observation:{statusCode:403,body:bytes({})},headers:undefined,limits}),undefined);
  assert.equal(prepareGitHubCommentConfirmation({moon:provider,request,repository,
    observation:{statusCode:200,body:bytes({data:null,errors:[{message:'partial'}]})},headers:[],limits}),undefined);
  assert.throws(()=>prepareGitHubCommentConfirmation({moon:provider,
    request:{...request,logicalBody:'different original'},repository,observation:write,headers:[],limits}));
});
