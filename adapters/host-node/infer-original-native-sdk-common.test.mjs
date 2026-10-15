import test from 'node:test';
import assert from 'node:assert/strict';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';

// Independent original answer aliases: native Choice rounding/tie, fractional
// Score and Boolean. Actual Common/SDK/SQLite/encrypted raw Store; explicit
// synthetic physical profile, quantity/fee/layout and fetch, never public/live.
const responseWire='{"usage":{"input_tokens":3,"output_tokens":2},"answers":'+
  '{"q0000000000":{"type":"choice","choice":"o0000000001","probabilities":'+
  '{"o0000000000":0.33,"o0000000001":0.33,"o0000000002":0.33}},'+
  '"q0000000001":{"type":"score","score":1.5,"probabilities":{"0":0,"1":0.5,"2":0.5}},'+
  '"q0000000002":{"type":"noul","noul":0.25}},"opaque":{"text":"é\\r\\n"}}';

test('original native Common request joins the pinned SDK and actual raw Store with the same probability original',async t=>{
  const f=await originalSdkCommonFixture(t,moon,{responseWire,nativeDecision:true,modelId:'jev-latest'});
  assert.equal(f.sends(),0);
  assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
  assert.equal(f.sends(),0);
  await f.opened.prepareOriginalResourcesForDispatch();
  assert.equal(f.sends(),0,'same original cut is not a transport start');
  const boundary=await f.operation.run();
  assert.equal(boundary.status,'settling');
  assert.equal(f.sends(),1);
  assert.equal(f.originalReads(),2);
  assert.equal(f.operation.settlementSlot(boundary.settlement),0);
  const request=JSON.parse(f.requests[0].body);
  assert.equal(f.requests[0].url,'https://fixture.invalid/systemone');
  assert.equal(request.model,'jev-latest');
  assert.equal(request.state,null);
  assert.deepEqual(Object.keys(request.questions),['q0000000000','q0000000001','q0000000002']);
  assert.deepEqual(Object.keys(request).sort(),['model','questions','state']);
  assert.equal(request.questions.q0000000000.type,'choice');
  assert.equal(request.questions.q0000000001.type,'score');
  assert.equal(request.questions.q0000000002.type,'noul');
  t.diagnostic('Actual Common native projection/Plan/Entry/raw receipt/child; synthetic installation/fetch/funding. NamedResult/public0.');
});
