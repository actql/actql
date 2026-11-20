import test from 'node:test';import assert from 'node:assert/strict';
import{createElement}from'react';import{renderToStaticMarkup}from'react-dom/server';
import{CancellationPanel}from'./dist/plan-explorer.js';
const ref={namespaceId:'original',authorityScopeCid:'sha256:'+'a'.repeat(64),runDefinitionCid:'sha256:'+'b'.repeat(64),cancelId:'cancel-a',expectedRevision:4};
const original={cancelRef:ref,attemptRef:{operation:'cancel',attemptId:'attempt-a'}};
const render=extra=>renderToStaticMarkup(createElement(CancellationPanel,{original,observation:null,history:null,pending:false,canPrepare:false,canRequest:false,canLookup:true,onPrepare(){},onRequest(){},onLookup(){},...extra}));
test('shared cancellation panel keeps original references separate from physical stop and unavailable Debug',()=>{
 const html=render({observation:{state:'unknown',original}});assert.match(html,/outcome Unknown/u);
 assert.match(html,/Do not resend/u);assert.match(html,/does not confirm physical stop/u);
 assert.match(html,/Pause, step and resume remain unavailable/u);assert.match(html,/cancel-a/u);
 assert.match(html,/Request original cancellation<\/button>/u);assert(!html.includes('permission: true'));
});
test('Owner accepted and history found do not claim physical stop, cleanup or release',()=>{
 const cancellation={ref:{namespaceId:ref.namespaceId,authorityScopeCid:ref.authorityScopeCid,runDefinitionCid:ref.runDefinitionCid},cancelRef:ref,kind:'accepted',revision:5};
 const html=render({observation:{state:'observed',original,outcome:{kind:'accepted',attemptRef:original.attemptRef,cancellation}},history:{kind:'found',cancellation}});
 assert.match(html,/Owner invocation outcome: accepted/u);assert.match(html,/No physical-stop acknowledgement/u);assert.match(html,/control revision 5/u);
});
test('original cancellation IDs render as literal text and disconnected actions stay disabled',()=>{
 const html=render({original:{...original,cancelRef:{...ref,cancelId:'<script>original</script>'}},canRequest:false,canLookup:false});
 assert(!html.includes('<script>'));assert(html.includes('&lt;script&gt;'));assert.match(html,/disabled=""[^>]*>Look up original cancellation/u);
});
