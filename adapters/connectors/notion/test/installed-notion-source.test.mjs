import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createPublicKey} from 'node:crypto';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ledgerUsageHasPendingResources,ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import {ledgerUsageSpentFields} from '../../../host-common/ledger-contract.generated.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {NotionUserListReadFailure} from '../site/user-list-read.mjs';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {checkInstalledNotionSourceProfile,installedNotionSourceIdentityParts,loadInstalledNotionSource} from '../host/installed-notion-source.mjs';
import {installedNotionFixture} from './installed-notion.fixture.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {installedFailureCode} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';

test('installed Notion users refuses missing original initialization or material without legacy fallback or I/O',async t=>{
  const f=await installedNotionFixture(t);
  await assert.rejects(loadInstalledNotionSource(f.profile,{...f.options,readerCapacity:{}}),
    {code:'NotionSourceInitializationUnavailable'});
  await assert.rejects(f.load({resolveSecret:undefined}),{code:'NotionCredentialMaterialUnavailable'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion closed profile rejects scope shortcuts undeclared resources and limit gaps',async t=>{
  const f=await installedNotionFixture(t);assert(Object.isFrozen(checkInstalledNotionSourceProfile(f.profile).limits));
  for(const profile of [{...f.profile,resources:['pages']},{...f.profile,readerCapacity:{retained:1,execution:1}},
    {...f.profile,siteProfilePath:'relative'},{...f.profile,limits:{...f.profile.limits,pageSize:101}},
    {...f.profile,limits:{...f.profile.limits,maxPages:0}},{...f.profile,limits:{maxRows:2}}])
    assert.throws(()=>checkInstalledNotionSourceProfile(profile),{code:'InvalidInstalledNotionSourceProfile'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion original strings Site generation and selected TLS remain distinct at metadata loading',async t=>{
  const f=await installedNotionFixture(t),a=await installedNotionSourceIdentityParts(f.profile,{...f.profile,connectorId:'é'}),
    b=await installedNotionSourceIdentityParts(f.profile,{...f.profile,connectorId:'é'});
  assert.notEqual(a[2].originalStringsCid,b[2].originalStringsCid);
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,siteGeneration:2}));
  const next=await installedNotionSourceIdentityParts(f.profile,f.profile);assert.equal(next[1].siteGeneration,2);
  assert.equal(a[1].siteGeneration,1);assert.equal(typeof next[2].caSha256,'string');assert.equal(f.state.requests.length,0);
});

test('installed Notion actual SQL and AQL retain original multi-page users and close the same Host reader',async t=>{
  for(const format of ['sql','aql']){
    const f=await installedNotionFixture(t),source=await f.load(),preparation=await f.prepare(source,{format});
    const opened=await source.openCapture(preparation);await f.retain(opened,preparation.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-notion-user-test'));
    // This is the original acquisition capture, before the query's SELECT.
    // Its complete declared row shape must remain available to the same Run.
    assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
      {email:'one@example.test',id:'U1',name:'one',type:'person'},
      {email:null,id:'U2',name:'two',type:'bot'}]);
    assert.equal(f.state.requests.length,2);assert.equal(f.state.resolutions,2);
    assert.equal(ledgerUsageHasPendingResources(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger)),true);
    await opened.close();
    assert.equal(ledgerUsageHasPendingResources(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger)),false);
    assert.equal(f.state.requests.length,2);
  }
});

test('ordinary installed Notion entrance selects the real factory and refuses missing normal supply',async t=>{
  const f=await installedNotionFixture(t),path=join(f.root,'source.json');await writeFile(path,JSON.stringify(f.profile));
  await assert.rejects(loadInstalledSource(path,{...f.options,runtimeUrl:new URL(
    '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url)}),
  installedFailureCode('NotionSourceInitializationUnavailable'));assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion copied preparation or absent original Ledger cannot dispatch users',async t=>{
  const f=await installedNotionFixture(t),source=await f.load(),p=await f.prepare(source);
  assert.throws(()=>source.ledgerCapacity({...p.preparedSource}),{code:'InstalledSourcePreparationMismatch'});
  await assert.rejects(source.openCapture({...p,ledger:undefined}),{code:'InstalledProviderSourceLedgerRequired'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion same Site and runtime retain the original connector identity',async t=>{
  const f=await installedNotionFixture(t),first=await f.load();
  f.profile.connectorId='other-workspace';const other=await f.load();
  f.profile.connectorId='workspace';const original=await f.load();
  assert.notEqual(first.connectorBindings[0].bindingCid,other.connectorBindings[0].bindingCid);
  assert.equal(first.connectorBindings[0].bindingCid,original.connectorBindings[0].bindingCid);
  assert.notEqual(first.sourceReadAccesses[0].sourceRef,other.sourceReadAccesses[0].sourceRef);
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion actual Account denial refuses preparation before a Credential use or HTTP',async t=>{
  const f=await installedNotionFixture(t,{account:'deny'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Notion lost original reply keeps Journal Unknown after original reader retirement without resend',async t=>{
  const f=await installedNotionFixture(t),source=await f.load(),preparation=await f.prepare(source);
  const before=ledgerUsageSnapshot(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger));
  f.state.beforeResponse=request=>request.socket.destroy();let original;
  await assert.rejects(source.openCapture(preparation),error=>{
    original=error;return error instanceof AcquisitionOpenError&&error.outcome==='stopped'&&
      error.recovery===undefined&&error.cause instanceof NotionUserListReadFailure;
  });
  // Physical acquisition end and the original durable attempt outcome are
  // separate. The SAME acknowledged reader may retire; it cannot turn the
  // lost reply into success, failed business evidence, or an unspent attempt.
  assert.equal(original.code,'NotionUserListReadFailed');
  assert.ok(original.cause.cause);assert.deepEqual(f.state.rows,[]);
  const retired=f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger);
  assert.equal(ledgerUsageHasPendingResources(retired),false);
  const spent=ledgerUsageSnapshot(retired);
  for(const field of ledgerUsageSpentFields){
    const key=field.replace(/_([a-z])/gu,(_match,letter)=>letter.toUpperCase());
    assert(spent[key]>=before[key]);
  }
  await source.close();
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),retired);
  const publicKey=createPublicKey(await readFile(join(f.root,'credential-authority.pub')));
  const journal=openSqliteCredentialJournal(f.site.journalRoot,{credentialAuthorities:new Map([
    [f.site.credentialAuthorityId,new Map([[f.site.credentialKeyId,publicKey]])]])});
  try{const recovered=journal.recover();assert.equal(recovered.length,1);assert.equal(recovered[0].outcome,'unknown');}
  finally{journal.close();}
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
});

test('installed Notion optional TLS authority is bounded original PEM before native transport',async t=>{
  const f=await installedNotionFixture(t);
  await assert.rejects(installedNotionSourceIdentityParts(f.profile,{...f.profile,limits:{...f.profile.limits,maxCaBytes:1}}));
  const path=join(f.root,'untrusted.pem');await writeFile(path,Buffer.from([0xff,0x80,0x01]));
  await writeFile(f.profile.siteProfilePath,JSON.stringify({...f.site,caPath:path}));
  await assert.rejects(installedNotionSourceIdentityParts(f.profile,f.profile),{code:'InvalidInstalledNotionTlsAuthority'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});
