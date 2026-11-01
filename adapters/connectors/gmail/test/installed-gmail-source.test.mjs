import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile,writeFile} from 'node:fs/promises';
import {createPublicKey} from 'node:crypto';
import {checkInstalledGmailSourceProfile,installedGmailSourceIdentityParts,loadInstalledGmailSource} from '../host/installed-gmail-source.mjs';
import {installedGmailFixture} from './installed-gmail.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {join} from 'node:path';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';

test('installed Gmail labels refuses absent original initialization and credential before Source I/O',async t=>{
  const f=await installedGmailFixture(t);
  await assert.rejects(loadInstalledGmailSource(f.profile,f.options),{code:'GmailSourceInitializationUnavailable'});
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

test('installed Gmail actual text Source retains one original reader capture until shared cleanup acknowledges retirement',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedGmailFixture(t),source=await f.load();
    const preparation=await f.prepare(source,{format});
    const opened=await source.openCapture(preparation);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-gmail-label-test'));
    assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
      {id:'INBOX',name:'Inbox',type:'system'},{id:'Label_1',name:'顧客 / é 📩',type:'user'}]);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
    opened.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),
      ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']),[0n,0n,0n,0n]);
    assert.equal(f.state.requests.length,1);
  }
});

test('installed Gmail optional TLS authority is bounded original PEM before native transport',async t=>{
  const f=await installedGmailFixture(t);
  await assert.rejects(installedGmailSourceIdentityParts(f.profile,{...f.profile,
    limits:{...f.profile.limits,maxCaBytes:1}}),{message:'InvalidInstalledSourceProfile'});
  const path=join(f.root,'untrusted-ca.pem');
  await writeFile(path,Buffer.from([0xff,0x80,0x01]));
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,caPath:path}));
  await assert.rejects(installedGmailSourceIdentityParts(f.profile,f.profile),{code:'InvalidInstalledGmailTlsAuthority'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('ordinary installed Gmail entrance discovers the real factory and refuses missing normal supply',async t=>{
  const f=await installedGmailFixture(t),path=join(f.root,'source.json');
  await writeFile(path,JSON.stringify(f.profile));
  await assert.rejects(loadInstalledSource(path,{...f.options,
    runtimeUrl:new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url)}),
  error=>error.code==='InstalledHostInitializationFailed'&&
    error.primaryFailure?.code==='GmailSourceInitializationUnavailable'&&error.cause===error.primaryFailure);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail copied preparation and missing original Ledger cannot issue a physical request',async t=>{
  const f=await installedGmailFixture(t),source=await f.load(),preparation=await f.prepare(source);
  assert.throws(()=>source.ledgerCapacity({...preparation.preparedSource}),{code:'InstalledSourcePreparationMismatch'});
  await assert.rejects(source.openCapture({...preparation,ledger:undefined}),{code:'InstalledProviderSourceLedgerRequired'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail binding retains original connector identity even for the same mailbox Site and runtime',async t=>{
  const f=await installedGmailFixture(t),first=await f.load();
  f.profile.connectorId='other-mailbox';const other=await f.load();
  f.profile.connectorId='mailbox';const original=await f.load();
  assert.notEqual(first.connectorBindings[0].bindingCid,other.connectorBindings[0].bindingCid);
  assert.equal(first.connectorBindings[0].bindingCid,original.connectorBindings[0].bindingCid);
  assert.notEqual(first.sourceReadAccesses[0].sourceRef,other.sourceReadAccesses[0].sourceRef);
  assert.equal(first.sourceReadAccesses[0].sourceRef,original.sourceReadAccesses[0].sourceRef);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail actual Account deny refuses preparation before Credential or HTTP',async t=>{
  const f=await installedGmailFixture(t,{account:'deny'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail lost original reply keeps same recovery and journal Unknown without another send',async t=>{
  const f=await installedGmailFixture(t),source=await f.load(),preparation=await f.prepare(source);
  f.state.beforeResponse=request=>request.socket.destroy();let original;
  await assert.rejects(source.openCapture(preparation),error=>{
    original=error;
    let cause=error;
    for(let depth=0;cause!==undefined&&depth<8;depth++,cause=cause.cause){
      if(cause.code==='ECONNRESET')return true;
    }
    return false;
  });
  // Durable use Unknown and physical retirement are separate obligations.
  // Only actual same-reader cleanup may release these reservations; no error
  // classification or process exit is used as that acknowledgement.
  if(original.recovery!==undefined){
    await original.recovery.close();assert.notEqual(await original.recovery.cleanup(),false);
    assert.equal(original.recovery.cleanupPending(),false);
  }
  assert.deepEqual(ledgerUsageFieldsFor(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),
    ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']),[0n,0n,0n,0n]);
  await source.close();
  const publicKey=createPublicKey(await readFile(join(f.root,'credential-authority.pub')));
  const journal=openSqliteCredentialJournal(f.site.journalRoot,{credentialAuthorities:new Map([
    [f.site.credentialAuthorityId,new Map([[f.site.credentialKeyId,publicKey]])]])});
  try{const recovered=journal.recover();assert.equal(recovered.length,1);assert.equal(recovered[0].outcome,'unknown');}
  finally{journal.close();}
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
});
