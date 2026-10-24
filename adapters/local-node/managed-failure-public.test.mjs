import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Exercise ordinary public wait before shutdown with a deterministic failure
// after finalization. A load hook changes only this isolated test process;
// no installed runtime file or production fault policy is modified.
const root = fileURLToPath(new URL('../../', import.meta.url));
const probe = String.raw`import {registerHooks} from 'node:module';
globalThis.__cleanupAudit={failures:0,retries:0,usage:[]};
registerHooks({load(url, context, next) {
 const result=next(url,context);
 if(url.endsWith('/adapters/local-node/strategy-bundle.mjs')) {
  let source=String(result.source).replace("if (observation.complete) break;", "if (observation.complete) { globalThis.__cleanupAudit.failures++; throw Object.assign(new Error('InjectedFinalizationFailure'), {code:'InjectedFinalizationFailure'}); }");
  if(source===String(result.source))throw new Error('InjectionPointMissing');
  source=source.replaceAll('await continueLocalManagedFailureCleanup(stopped, operations);', 'globalThis.__cleanupAudit.readUsage = () => moon.strategyHostUsage(setup).map(String); await continueLocalManagedFailureCleanup(stopped, operations);');
  if(process.env.CLEANUP_CONTROL==='disabled')source=source.replaceAll('await continueLocalManagedFailureCleanup(stopped, operations);','/* control: original failure settlement without continuation */');
  return {...result,source};
 }
 if(url.endsWith('/adapters/local-node/managed-output-custody.mjs'))return {...result,source:String(result.source).replace('const state = await handle.retry();','globalThis.__cleanupAudit.retries++; globalThis.__cleanupAudit.usage.push(globalThis.__cleanupAudit.readUsage()); await globalThis.__cleanupAudit.onSlice?.(); const state = await handle.retry(); globalThis.__cleanupAudit.usage.push(globalThis.__cleanupAudit.readUsage());')};
 return result;
}});

import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {open}=await import(pathToFileURL(process.env.ACTQL_CORE+'/packages/node/index.mjs'));
const stateDir=await mkdtemp('/tmp/actql-cleanup-regression-');
const db=await open({stateDir});
try {
 const rows=Array.from({length:99},(_,k)=>({k}));
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
 console.log(JSON.stringify({control:disabled?'disabled':'enabled',observedBeforeClose:true,stateDir,status:state.status,physicalStop:state.control.physical_stop,audit:globalThis.__cleanupAudit}));
} finally {await db.close(); await rm(stateDir,{recursive:true,force:true});}
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
      assert.ok(usage[0].slice(4).some(value=>value!=='0'));
      assert.deepEqual(usage[0],usage[1], 'first incomplete slice retains original reservations');
      assert.ok(usage.at(-1).slice(4).every(value=>value==='0'), 'only completion releases reservations');
    }
  });
}
