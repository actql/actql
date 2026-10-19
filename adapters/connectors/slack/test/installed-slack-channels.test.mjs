import assert from 'node:assert/strict';
import test from 'node:test';
import {installedSlackChannelsFixture} from './installed-slack-channels.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

test('installed Slack channels original Source captures exact typed rows under its separate resource',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedSlackChannelsFixture(t),source=await f.load(),p=await f.prepare(source,{format,selection:'id, name, member_count'});
    assert.deepEqual(source.sourceReadAccesses.map(v=>v.resource),['users','channels','messages']);
    const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-channels'));
    const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
    assert.deepEqual(rows.map(r=>[r.id,r.member_count,r.created]),[['C1','2','1970-01-01T00:00:00.000Z'],['C2','3','1970-01-01T00:00:01.000Z']]);
    assert.equal(f.state.requests.length,3);assert(f.state.requests[1].path.startsWith('/api/conversations.list?'));
    const held=f.common.clientProgramMultiCapturedLedgerUsage(p.ledger);
    await assert.rejects(async()=>opened.close(),{code:'MoonBitHostFailure'});
    assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(p.ledger),held);
  }
});

test('installed Slack channel Account denial retains no token resolution or provider send',async t=>{
  const f=await installedSlackChannelsFixture(t,{account:'deny'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});
