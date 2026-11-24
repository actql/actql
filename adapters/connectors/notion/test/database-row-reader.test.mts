import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createNotionDatabaseReaderFactory} from '../host/database-reader.mjs';
import {databaseRowReaderFixture,databaseReaderLimits,databaseSnapshot} from './database-row-reader.fixture.mjs';

import type {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import type {ledgerUsageHasPendingResources as hasPendingResources} from '../../../host-common/ledger-usage.mjs';

type CaptureRow = Readonly<{id:string;title:string;amount:string;resource:string;version:string}>;
type CaptureFailure = AcquisitionOpenError & {recovery?: {
  close():unknown;cleanup():unknown;cleanupPending():boolean;
}};
const {ledgerUsageHasPendingResources}:{ledgerUsageHasPendingResources:typeof hasPendingResources}=
  await import(new URL('../../../host-common/runtime-core.mjs',import.meta.url).href);

test('ordinary original database RowRun captures exact typed rows with separately issued property uses',async t=>{
  const f=await databaseRowReaderFixture(t),preparation=await f.prepare();
  const opened=await f.source.openCapture(preparation);await f.retain(opened,preparation.ledger);
  // This prepared Query selects the requirement-carrying RowRun result.
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),
    (opened as typeof opened & {requirement:unknown}).requirement,'database-row-fixture'));
  const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse as (row:string)=>CaptureRow);
  assert.deepEqual(rows.map(({id,title,amount})=>({id,title,amount})),[
    {id:'page1',title:'ab',amount:'9007199254740993.25'},
    {id:'page2',title:'cd',amount:'9007199254740993.25'}]);
  assert(rows.every(x=>x.resource===x.id&&x.version==='2026-10-18T00:00:00.000Z'));
  assert.equal(f.state.requests.length,6);assert.equal(f.state.resolutions,6);
  const uses=f.site.credential.journal.recover();assert.equal(uses.length,6);assert(uses.every(x=>x.outcome==='succeeded'));
  assert.equal(new Set(uses.map(x=>x.grantCid)).size,3,'one query grant plus two distinct original pending-property grants');
  assert.equal(ledgerUsageHasPendingResources(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger)),true,
    'the immutable capture remains funded after the response workspace retires');
  await opened.close();
  const retired=f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger);
  assert.equal(ledgerUsageHasPendingResources(retired),false);
  await opened.close();
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),retired);
  assert.equal(f.state.requests.length,6,'neither workspace retirement nor capture close may send another request');
});

test('ordinary database lost property reply retains the original RowRun and Unknown without resend',async t=>{
  const f=await databaseRowReaderFixture(t),preparation=await f.prepare();
  f.state.beforeResponse=request=>{if(request.method==='GET')request.socket.destroy();};
  let original:CaptureFailure|undefined;
  await assert.rejects(f.source.openCapture(preparation),(error:CaptureFailure)=>{original=error;return error.outcome==='unknown'&&error.recovery?.cleanupPending()===true;});
  await f.retain(original!.recovery!,preparation.ledger);
  const held=f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger);
  await original!.recovery!.close();assert.equal(await original!.recovery!.cleanup(),false);
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),held);
  assert.equal(f.state.requests.length,2);assert.equal(f.state.resolutions,2);
  assert.equal(f.site.credential.journal.recover().filter(x=>x.outcome==='unknown').length,1);
});

test('database factory refuses absent capacity and foreign snapshot before any installed read',async t=>{
  const f=await databaseRowReaderFixture(t);
  const options={moon:f.provider,snapshot:f.snapshot,site:f.site,capacity:f.capacity,resource:'tasks',limits:databaseReaderLimits,maxSecretBytes:128};
  assert.throws(()=>createNotionDatabaseReaderFactory({...options,capacity:undefined}),{code:'NotionReaderCapacityUnavailable'});
  assert.throws(()=>createNotionDatabaseReaderFactory({...options,snapshot:{...databaseSnapshot()}}));
  const p=await f.prepare();
  await assert.rejects(f.source.openCapture({...p,ledger:undefined}),{code:'InstalledProviderSourceLedgerRequired'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('ordinary database current Account replacement after query refuses dependent property grant and I/O',async t=>{
  const f=await databaseRowReaderFixture(t,{currentAccountFile:true}),p=await f.prepare();
  f.state.beforeResponse=async request=>{
    assert.equal(request.method,'POST');
    await writeFile(f.accountPath,f.accountWire.replace('"outcome":"allow"','"outcome":"deny"'),{mode:0o600});
  };
  let original:CaptureFailure|undefined;
  await assert.rejects(f.source.openCapture(p),(error:CaptureFailure)=>{original=error;return error.recovery?.cleanupPending()===true;});
  await f.retain(original!.recovery!,p.ledger);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
  assert.equal(f.site.credential.journal.recover().length,1);
  await original!.recovery!.close();assert.equal(await original!.recovery!.cleanup(),false);
  assert.equal(f.state.requests.length,1);
});
