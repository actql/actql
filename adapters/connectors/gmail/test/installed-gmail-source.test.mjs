import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {checkInstalledGmailSourceProfile,installedGmailSourceIdentityParts} from '../host/installed-gmail-source.mjs';
import {installedGmailFixture} from './installed-gmail.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

test('installed Gmail refuses absent capacity and credential material without legacy fallback or I/O',async t=>{
  const f=await installedGmailFixture(t);
  await assert.rejects(f.load({readerCapacity:undefined}),{code:'GmailReaderCapacityUnavailable'});
  await assert.rejects(f.load({resolveSecret:undefined}),{code:'GmailCredentialMaterialUnavailable'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail closed original profile rejects undeclared resources authority shortcuts and limit gaps',async t=>{
  const f=await installedGmailFixture(t);const p=checkInstalledGmailSourceProfile(f.profile);
  assert(Object.isFrozen(p)&&Object.isFrozen(p.limits));
  for(const profile of [{...f.profile,mailbox:'me'},{...f.profile,resources:['messages']},
    {...f.profile,readerCapacity:{retained:1,execution:1}},
    {...f.profile,limits:{...f.profile.limits,maxRows:0}},{...f.profile,limits:{maxRows:2}},
    {...f.profile,siteProfilePath:'relative.json'}])assert.throws(()=>checkInstalledGmailSourceProfile(profile));
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail generation retains exact mailbox bytes selected Site generation and TLS authority',async t=>{
  const f=await installedGmailFixture(t);
  const first=await installedGmailSourceIdentityParts(f.profile,{...f.profile,mailbox:'é@example.test'});
  const second=await installedGmailSourceIdentityParts(f.profile,{...f.profile,mailbox:'é@example.test'});
  assert.notEqual(first[2].mailboxBytesCid,second[2].mailboxBytesCid);
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,siteGeneration:2}));
  const next=await installedGmailSourceIdentityParts(f.profile,f.profile);
  assert.equal(next[1].siteGeneration,2);assert.equal(first[1].siteGeneration,1);
  assert.equal(typeof next[2].caSha256,'string');assert.equal(f.state.requests.length,0);
});

test('installed Gmail actual text Source retains one original reader capture and unconfirmed custody',async t=>{
  const f=await installedGmailFixture(t),source=await f.load();
  const preparation=await f.prepare(source);
  const opened=await source.openCapture(preparation);
  await f.retain(opened,preparation.ledger);
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-gmail-label-test'));
  assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
    {id:'INBOX',name:'Inbox',type:'system'},{id:'Label_1',name:'顧客 / é 📩',type:'user'}]);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
  const held=f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger);
  await assert.rejects(async()=>opened.close());
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),held);
  assert.equal(f.state.requests.length,1);
});
