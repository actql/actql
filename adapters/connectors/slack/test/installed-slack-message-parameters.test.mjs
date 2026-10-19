import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {installedSlackMessagesFixture} from './installed-slack-messages.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const parameterDeclarations='{"channel":{"type":"string"},"count":{"type":"int64"}}';
const selection='id, channel, ts, reply_count';
const predicate='channel = @channel AND reply_count = @count';
const options=(format,channel='D1',count='0')=>({format,selection,predicate,parameterDeclarations,
  parameters:JSON.stringify({channel,count})});

function request(common,prepared){
  // Request identity DATA does not supply Account authority or Source funding.
  const value=common.clientProgramRequestIdentity(prepared,`sha256:${'a'.repeat(64)}`,
    'slack-parameter-test',common.clientProgramSourceFreeInputIntentCid());
  assert.ok(value);return value;
}
function expectedParametersCid(channel,count){
  // Independent complete canonical parameter-value preimage, including the
  // distinct int64 marker. Neither Number nor a vendor string is substituted.
  const wire=`{"values":{"channel":${JSON.stringify(channel)},"count":{"$actql_value":["int64",${JSON.stringify(count)}]}},"version":"actql-parameter-values/0.1"}`;
  return `sha256:${createHash('sha256').update(wire).digest('hex')}`;
}

for(const format of ['sql','aql'])test(`installed Slack ${format} Parameters bind exact String and int64 without narrowing the original messages scan`,async t=>{
  const f=await installedSlackMessagesFixture(t),source=await f.load();
  const p=await f.prepare(source,options(format));
  assert.equal(f.common.clientRequestParametersCid(request(f.common,p.preparedProgram)),expectedParametersCid('D1','0'));
  const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-parameter-source'));
  // Common admits every original response row before applying the checked
  // Filter to the capture. This is not a published Run or vendor pushdown.
  assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(v=>{
    const row=JSON.parse(v);return[row.id,row.channel,row.reply_count];
  }),[['D1:3.000000001','D1','0']]);
  assert.equal(f.state.requests.length,8);
  for(const r of f.state.requests){
    const url=new URL(r.path,f.scope.resourceOrigin);
    if(url.pathname==='/api/conversations.history'){
      assert.equal(url.searchParams.has('oldest'),false);
      assert.equal(url.searchParams.has('latest'),false);
    }
  }
});

test('installed Slack Parameter bindings retain full signed64 values and reject invalid values before any provider exchange',async t=>{
  const f=await installedSlackMessagesFixture(t),source=await f.load(),cids=new Set();
  for(const count of ['-9223372036854775808','9223372036854775807','9007199254740992','9007199254740993']){
    const p=await f.prepare(source,options('sql','D1',count));
    const cid=f.common.clientRequestParametersCid(request(f.common,p.preparedProgram));
    assert.equal(cid,expectedParametersCid('D1',count));cids.add(cid);
  }
  assert.equal(cids.size,4);
  for(const count of ['9223372036854775808','-9223372036854775809','-0','01',0,9007199254740992,null]){
    await assert.rejects(f.prepare(source,options('sql','D1',count)),/check_invalid_input/);
  }
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack acquisition refuses copied and foreign original preparations even with equal Parameter identities',async t=>{
  const f=await installedSlackMessagesFixture(t),source=await f.load();
  const original=await f.prepare(source,options('sql'));
  const equal=await f.prepare(source,options('sql'));
  const changed=await f.prepare(source,options('sql','C1','1'));
  assert.notEqual(original.preparedProgram,equal.preparedProgram);
  const identity=request(f.common,original.preparedProgram);
  assert.equal(f.common.clientProgramMatchesRequestIdentity(equal.preparedProgram,identity),true);
  assert.equal(f.common.clientProgramMatchesRequestIdentity(changed.preparedProgram,identity),false);
  for(const mixed of [
    {...original,preparedSource:{...original.preparedSource}},
    {...original,preparedProgram:equal.preparedProgram},
    {...original,preparedProgram:changed.preparedProgram},
    {...changed,preparedSource:original.preparedSource},
  ])await assert.rejects(source.openCapture(mixed),/InstalledSourcePreparationMismatch/);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
  const opened=await source.openCapture(original);await f.retain(opened,original.ledger);
  assert.equal(f.state.requests.length,8);
});

test('installed Slack Parameter residuals cannot hide an invalid original excluded message',async t=>{
  const f=await installedSlackMessagesFixture(t);f.state.replies.C1[1].text=[];
  const source=await f.load(),p=await f.prepare(source,options('aql'));let recovery;
  await assert.rejects(source.openCapture(p),error=>{recovery=error.recovery;return recovery!==undefined;});
  await f.retain(recovery,p.ledger);
  assert.equal(f.state.requests.length,5);assert.equal(recovery.cleanupPending(),true);
});
