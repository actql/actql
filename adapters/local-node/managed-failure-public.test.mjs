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
globalThis.__cleanupAudit={failures:0,retries:0,slices:[],beforeContinuation:[],
 disabled:process.env.CLEANUP_CONTROL==='disabled',closeCalls:0};
function replaceOnce(source, before, after) {
 if(source.split(before).length!==2)throw new Error('CleanupObservationPointMissing');
 return source.replace(before,after);
}
registerHooks({load(url, context, next) {
 const result=next(url,context);
 if(url.endsWith('/adapters/local-node/strategy-bundle.mjs')) {
  let source=replaceOnce(String(result.source),"if (observation.complete) break;", "if (!observation.complete && observation.progress >= 512n) { globalThis.__cleanupAudit.failures++; const failure=Object.assign(new Error('InjectedFinalizationFailure'), {code:'InjectedFinalizationFailure'}); globalThis.__cleanupAudit.originalFailure=failure; throw failure; } if (observation.complete) break;");
  source=replaceOnce(source,'export function localStrategyContribution(moon, setup, checked, configuration) {', 'export function localStrategyContribution(moon, setup, checked, configuration) { globalThis.__cleanupAudit.readUsage = () => moon.strategyHostUsage(setup).map(String); globalThis.__cleanupAudit.initialUsage ??= globalThis.__cleanupAudit.readUsage();');
  const continuation='await continueLocalManagedFailureCleanup(stopped, operations);';
  if(!source.includes(continuation))throw new Error('CleanupContinuationPointMissing');
  source=source.replaceAll(continuation, 'if ((stopped.primaryFailure ?? stopped) === globalThis.__cleanupAudit.originalFailure) { globalThis.__cleanupAudit.primaryPreserved=true; globalThis.__cleanupAudit.beforeContinuation.push({pending:stopped.cleanupHandle?.status().pending,usage:globalThis.__cleanupAudit.readUsage()}); } if (!globalThis.__cleanupAudit.disabled) await continueLocalManagedFailureCleanup(stopped, operations);');
  return {...result,source};
 }
 if(url.endsWith('/adapters/local-node/managed-output-custody.mjs'))return {...result,source:replaceOnce(String(result.source),'const state = await handle.retry();','globalThis.__cleanupAudit.retries++; const state = await handle.retry();')};
 if(url.endsWith('/adapters/host-common/managed-failure.mjs')) {
  let source=replaceOnce(String(result.source),'const value = operations.cleanup_local_continuation();','const value = operations.cleanup_local_continuation(); if (globalThis.__cleanupAudit.disabled) return undefined;');
  source=replaceOnce(source,'const retryOnce = async () => {','const retryOnce = async () => { const slice={before:globalThis.__cleanupAudit.readUsage()}; globalThis.__cleanupAudit.slices.push(slice); await globalThis.__cleanupAudit.onSlice?.();');
  source=replaceOnce(source,'drive();\n    return status();','drive();\n    const observed=status(); Object.assign(slice,{after:globalThis.__cleanupAudit.readUsage(),pending:observed.pending,errors:observed.errors.length}); return observed;');
  return {...result,source};
 }
 return result;
}});

import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const {open}=await import(pathToFileURL(process.env.ACTQL_CORE+'/packages/node/index.mjs'));
const stateDir=await mkdtemp('/tmp/actql-cleanup-regression-');
// Use the existing finite operator profile and enough actual rows to retain
// multiple reclamation slices. The negative suppresses automatic continuation
// both outside and inside the SAME handle, leaving its bounded retry intact.
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
 assert.equal(globalThis.__cleanupAudit.primaryPreserved,true);
 if(disabled)assert.equal(globalThis.__cleanupAudit.beforeContinuation[0].pending,true);
 globalThis.__cleanupAudit.beforeClose=globalThis.__cleanupAudit.readUsage();
 report={control:disabled?'disabled':'enabled',observedBeforeClose:true,stateDir,status:state.status,physicalStop:state.control.physical_stop,audit:globalThis.__cleanupAudit};
} finally {
 // Restore only this test's continuation observation after the negative's
 // Unknown/pending result. Never repeat Compute or hide a first-close failure.
 globalThis.__cleanupAudit.disabled=false;
 globalThis.__cleanupAudit.closeCalls++;
 await db.close();
 globalThis.__cleanupAudit.firstCloseReturned=true;
 globalThis.__cleanupAudit.afterClose=globalThis.__cleanupAudit.readUsage();
 if(report!==undefined)await rm(stateDir,{recursive:true,force:true});
}
console.log(JSON.stringify(report));
`;
for (const [mode, cancel] of [['disabled',false], ['enabled',false], ['enabled',true]]) {
  test(`failed Local finalization settles before public wait: ${mode}, cancel=${cancel}`, t => {
    const raw = execFileSync(process.execPath, ['--input-type=module','--eval',probe], {
      env:{...process.env, ACTQL_CORE:root, CLEANUP_CONTROL:mode, CLEANUP_CANCEL:cancel?'1':'0'},
      encoding:'utf8',timeout:30000,
    });
    const result=JSON.parse(raw.trim());
    assert.equal(result.observedBeforeClose,true);
    assert.equal(result.audit.failures,1);
    assert.equal(result.audit.primaryPreserved,true);
    assert.equal(result.audit.closeCalls,1);
    assert.equal(result.audit.firstCloseReturned,true);
    assert.ok(pendingUsage(result.audit.afterClose).every(value=>value==='0'),
      'only confirmed parent close releases its reservation');
    if(mode==='enabled') {
      const slices=result.audit.slices;
      assert.ok(slices.length>1,'observe actual bounded slices inside the original handle');
      const pending=slices.find(slice=>slice.pending);
      assert.ok(pending,'an incomplete inner slice must be observed');
      assert.ok(pendingUsage(pending.before).some(value=>value!=='0'));
      assert.deepEqual(pending.before,pending.after,'an incomplete slice retains original reservations');
      assert.ok(slices.every(slice=>slice.errors===0));
      assert.equal(slices.at(-1).pending,false);
      assert.deepEqual(pendingUsage(slices.at(-1).after),pendingUsage(result.audit.initialUsage),
        'retire task scratch while preserving the same parent reservation');
      assert.ok(pendingUsage(result.audit.beforeClose).every(value=>value==='0'),
        'confirmed dispatch stop retires its original parent before public wait returns');
    } else {
      assert.equal(result.status,'needs_reconciliation');
      assert.equal(result.physicalStop,'unknown');
      assert.equal(result.audit.retries,0,'outer continuation is disabled too');
      assert.notDeepEqual(pendingUsage(result.audit.beforeClose),pendingUsage(result.audit.initialUsage),
        'the Unknown result still holds original task scratch before close');
    }
    t.diagnostic(JSON.stringify({mode,cancel,status:result.status,physicalStop:result.physicalStop,
      primaryPreserved:result.audit.primaryPreserved,outerRetries:result.audit.retries,
      innerSlices:result.audit.slices.length,pendingInnerSlices:result.audit.slices.filter(slice=>slice.pending).length,
      firstCloseCalls:result.audit.closeCalls,firstCloseReturned:result.audit.firstCloseReturned}));
  });
}
