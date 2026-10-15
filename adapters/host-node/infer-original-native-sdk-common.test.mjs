import test from 'node:test';
import assert from 'node:assert/strict';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// Independent original answer aliases: native Choice rounding/tie, fractional
// Score and Boolean. Actual Common/SDK/SQLite/encrypted raw Store; explicit
// synthetic physical profile, quantity/fee/layout and fetch, never public/live.
const responseWire='{"usage":{"input_tokens":3,"output_tokens":2},"answers":'+
  '{"q0000000000":{"type":"choice","choice":"o0000000001","probabilities":'+
  '{"o0000000000":0.33,"o0000000001":0.33,"o0000000002":0.33}},'+
  '"q0000000001":{"type":"score","score":1.5,"probabilities":{"0":0,"1":0.5,"2":0.5}},'+
  '"q0000000002":{"type":"noul","noul":0.25}},"opaque":{"text":"é\\r\\n"}}';

function readOriginalSettlement(settlement) {
  const exporter=checked(moon.clientProgramStartInferCallSettlementExport(settlement,4096,10000));
  let complete=false,wire='';
  try {
    for(let count=0;count<100&&!complete;count++) {
      const progress=checked(moon.clientProgramAdvanceInferCaptureExport(exporter,256));
      wire+=progress._1;
      complete=progress._0;
    }
    assert.equal(complete,true,'same bounded original response export must finish');
    return JSON.parse(wire);
  } finally {
    if(!complete) moon.clientProgramCancelInferCaptureExport(exporter);
    let retired=false;
    for(let count=0;count<10&&!retired;count++) retired=checked(moon.clientProgramCleanupInferCaptureExport(exporter));
    assert.equal(retired,true,'diagnostic exporter must return its original output use');
  }
}

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
  const capture=readOriginalSettlement(boundary.settlement);
  assert.equal(capture.captures.length,1,'a failed Slot settlement is not a successful native answer');
  assert.deepEqual(capture.captures[0].structured_response,JSON.parse(
    '{"__proto__":{"choice":"__proto__","probabilities":[{"option":"toString","probability":0.33},'+
    '{"option":"__proto__","probability":0.33},{"option":"constructor","probability":0.33}]},'+
    '"constructor":{"score":1.5,"probabilities":[{"level":0,"probability":0},{"level":1,"probability":0.5},'+
    '{"level":2,"probability":0.5}]},"enabled":{"probability":0.25}}'));
  const evidence=capture.captures[0].evidence;
  assert.equal(evidence.input_tokens,3);
  assert.equal(evidence.output_tokens,2);
  assert.equal(evidence.provider_reported_model_id,null);
  assert.equal(evidence.provider_request_id,null);
  assert.equal(evidence.finish_reason,null);
  assert.equal(evidence.provider_metadata,null);
  assert.equal(evidence.response_complete,true);
  assert.match(evidence.raw_response_artifact_cid,/^sha256:[0-9a-f]{64}$/u);
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
