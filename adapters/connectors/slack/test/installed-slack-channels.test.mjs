import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {installedSlackChannelsFixture} from './installed-slack-channels.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

test('installed Slack channels original Source captures exact typed rows under its separate resource',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedSlackChannelsFixture(t),source=await f.load(),p=await f.prepare(source,{format,selection:'id, name, member_count, created'});
    // The Common catalogue orders its originals; this control requires the
    // exact resource membership, not the declaration's authored array order.
    assert.deepEqual(source.sourceReadAccesses.map(v=>v.resource).toSorted(),['channels','messages','users']);
    const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-channels'));
    const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
    assert.deepEqual(rows,[{id:'C1',name:'one',member_count:'2',created:'1970-01-01T00:00:00.000Z'},
      {id:'C2',name:'two',member_count:'3',created:'1970-01-01T00:00:01.000Z'}]);
    assert.equal(f.state.requests.length,3);assert(f.state.requests[1].path.startsWith('/api/conversations.list?'));
    await opened.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.common.clientProgramMultiCapturedLedgerUsage(p.ledger),
      ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']),[0n,0n,0n,0n]);
  }
});

test('installed Slack channel Account denial retains no token resolution or provider send',async t=>{
  const f=await installedSlackChannelsFixture(t,{account:'deny'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});
