import assert from 'node:assert/strict';
import test from 'node:test';
import {installedSlackChannelsFixture} from './installed-slack-channels.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const parameterDeclarations='{"count":{"type":"int64"},"skip":{"type":"int64","nullable":true}}';
const text=format=>format==='sql'
  ?'SELECT id, name FROM slack.channels WHERE TRUE ORDER BY member_count DESC LIMIT @count OFFSET @skip'
  :'FROM slack.channels |> WHERE TRUE |> ORDER BY member_count DESC |> LIMIT @count OFFSET @skip |> SELECT id, name';

test('public Slack SQL and Pipe retain int64 LIMIT and OFFSET Parameters through original Source acquisition',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedSlackChannelsFixture(t),source=await f.load();
    const p=await f.prepare(source,{format,text:text(format),parameterDeclarations,
      parameters:'{"count":"1","skip":"0"}'});
    const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-limit-parameters'));
    const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
    // Acquisition admits the full original scan before downstream sort/take.
    // A selecting LIMIT never shrinks the physical request's admission extent.
    assert.deepEqual(rows.map(row=>row.id),['C1','C2']);
    assert.equal(f.state.requests.length,3);
    assert.equal(f.state.requests[1].path,'/api/conversations.list?types=public_channel%2Cprivate_channel&exclude_archived=false&limit=10');
  }
});

test('public Slack LIMIT int64 domains refuse zero overflow and nullable values before provider I/O',async t=>{
  for(const [count,skip] of [['0','0'],['-1','0'],['9007199254740992','0'],['1','-1'],['1',null]]){
    const f=await installedSlackChannelsFixture(t),source=await f.load();
    await assert.rejects(f.prepare(source,{text:text('sql'),parameterDeclarations,
      parameters:JSON.stringify({count,skip})}),{message:'check_invalid_input'});
    assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
  }
});

test('public Slack LIMIT retains the existing Number Parameter form',async t=>{
  const f=await installedSlackChannelsFixture(t),source=await f.load();
  const p=await f.prepare(source,{text:text('sql'),
    parameterDeclarations:'{"count":{"type":"number"},"skip":{"type":"number"}}',
    parameters:'{"count":1,"skip":0}'});
  const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
  assert.equal(f.state.requests.length,3);
});
