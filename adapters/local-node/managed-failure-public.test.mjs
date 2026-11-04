import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {ledgerUsageFields, ledgerUsageSpentFields} from '../host-common/ledger-contract.generated.mjs';

const spentFields=new Set(ledgerUsageSpentFields);
const pendingUsage=values=>ledgerUsageFields.flatMap((field,index)=>
  spentFields.has(field.name)?[]:[values[index]]);

// Exercise ordinary public wait before shutdown with a deterministic failure
// during finalization, while original scratch is still live. A load hook
// changes only this isolated test process;
// no installed runtime file or production fault policy is modified.
const root = fileURLToPath(new URL('../../', import.meta.url));
const probe = String.raw`import {registerHooks} from 'node:module';
globalThis.__cleanupAudit={failures:0,retries:0,usage:[]};
registerHooks({load(url, context, next) {
 const result=next(url,context);
 if(url.endsWith('/adapters/local-node/strategy-bundle.mjs')) {
  let source=String(result.source).replace("if (observation.complete) break;", "if (!observation.complete && observation.progress >= 512n) { globalThis.__cleanupAudit.failures++; throw Object.assign(new Error('InjectedFinalizationFailure'), {code:'InjectedFinalizationFailure'}); } if (observation.complete) break;");
  if(source===String(result.source))throw new Error('InjectionPointMissing');
  source=source.replace('export function localStrategyContribution(moon, setup, checked, configuration) {', 'export function localStrategyContribution(moon, setup, checked, configuration) { globalThis.__cleanupAudit.initialUsage ??= moon.strategyHostUsage(setup).map(String);');
  source=source.replaceAll('await continueLocalManagedFailureCleanup(stopped, operations);', 'globalThis.__cleanupAudit.readUsage = () => moon.strategyHostUsage(setup).map(String); await continueLocalManagedFailureCleanup(stopped, operations);');
  if(process.env.CLEANUP_CONTROL==='disabled')source=source.replaceAll('await continueLocalManagedFailureCleanup(stopped, operations);','/* control: original failure settlement without continuation */');
  return {...result,source};
 }
 if(url.endsWith('/adapters/local-node/managed-output-custody.mjs'))return {...result,source:String(result.source).replace('const state = await handle.retry();','globalThis.__cleanupAudit.retries++; globalThis.__cleanupAudit.usage.push(globalThis.__cleanupAudit.readUsage()); await globalThis.__cleanupAudit.onSlice?.(); const state = await handle.retry(); globalThis.__cleanupAudit.usage.push(globalThis.__cleanupAudit.readUsage());')};
 return result;
}});

import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const {open}=await import(pathToFileURL(process.env.ACTQL_CORE+'/packages/node/index.mjs'));
const stateDir=await mkdtemp('/tmp/actql-cleanup-regression-');
// Use the existing finite operator profile and enough actual rows to retain
// multiple reclamation slices; no cleanup port is replaced.
const hostCapacityPolicy=JSON.parse(readFileSync(process.env.ACTQL_CORE+'/spec/local-check-environment.json','utf8')).host_policy_profile.capacity;
const db=await open({stateDir,installation:{hostCapacityPolicy}});
let report;
try {
 const rows=Array.from({length:999},(_,k)=>({k}));
 const program={version:'actql/0.1',id:'cleanup-regression',stages:[{id:'main',inputs:{},steps:[{as:'l',values:{schema:{k:{type:'number',nullable:false}},rows}}],results:{r0:{from:'l',fields:['k'],order_by:[{k:'asc'}]}}}],results:{r0:{from:{stage:'main',result:'r0'}}}};
 const run=await db.start(program);
 let cancellation;
 if(process.env.CLEANUP_CANCEL==='1')globalThis.__cleanupAudit.onSlice=()=>{return cancellation ??= run.cancel();};
 const state=await run.wait({signal:AbortSignal.timeout(20000)});
 const disabled=process.env.CLEANUP_CONTROL==='disabled';
 if(process.env.CLEANUP_CANCEL==='1'){await cancellation; assert.equal(state.status,'cancelled'); assert.equal(state.control.cancellation_requested,true);} else assert.equal(state.status,disabled?'needs_reconciliation':'failed');
 assert.equal(state.control.physical_stop,disabled?'unknown':'confirmed');
 assert.equal(globalThis.__cleanupAudit.failures,1,'original Compute/finalization is not repeated');
 if(!disabled)assert.ok(globalThis.__cleanupAudit.retries>0);
 report={control:disabled?'disabled':'enabled',observedBeforeClose:true,stateDir,status:state.status,physicalStop:state.control.physical_stop,audit:globalThis.__cleanupAudit};
} finally {
 // The disabled negative control deliberately leaves original cleanup pending.
 // Retry that SAME Client; remove its fixture only after physical close returns.
 const end=Date.now()+20000;
 for (;;) {
  try {await db.close(); break;}
  catch(error) {if(error.code!=='ClientCleanupPending'||Date.now()>=end)throw error;}
  await new Promise(resolve=>setTimeout(resolve,0));
 }
 globalThis.__cleanupAudit.afterClose=globalThis.__cleanupAudit.readUsage();
 await rm(stateDir,{recursive:true,force:true});
}
console.log(JSON.stringify(report));
`;
for (const [mode, cancel] of [['disabled',false], ['enabled',false], ['enabled',true]]) {
  test(`failed Local finalization settles before public wait: ${mode}, cancel=${cancel}`, () => {
    const raw = execFileSync(process.execPath, ['--input-type=module','--eval',probe], {
      env:{...process.env, ACTQL_CORE:root, CLEANUP_CONTROL:mode, CLEANUP_CANCEL:cancel?'1':'0'},
      encoding:'utf8',timeout:30000,
    });
    const result=JSON.parse(raw.trim());
    assert.equal(result.observedBeforeClose,true);
    assert.equal(result.audit.failures,1);
    if(mode==='enabled') {
      assert.ok(result.audit.retries>1);
      const usage=result.audit.usage;
      assert.ok(pendingUsage(usage[0]).some(value=>value!=='0'));
      assert.deepEqual(usage[0],usage[1], 'first incomplete slice retains original reservations');
      assert.deepEqual(pendingUsage(usage.at(-1)),pendingUsage(result.audit.initialUsage), 'retire task scratch while preserving the same parent reservation');
      assert.ok(pendingUsage(result.audit.afterClose).every(value=>value==='0'), 'only confirmed parent close releases its reservation');
    }
  });
}
