import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {ledgerUsageHasPendingResources} from '../host-common/runtime-core.mjs';

// Actual cleanup source with explicit child/Scope observations. A fixture
// reservation models ordering only; it supplies no Core or physical capacity.
const source=readFileSync(new URL('./installed-composed-infer-run.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const owner=tree.body.find(node=>node.type==='ExportNamedDeclaration'&&
  node.declaration?.id?.name==='runInstalledComposedInfers').declaration;
const cleanup=owner.body.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='cleanup');
assert(cleanup);

function fixture(children=[]){
  const setup={},calls=[];
  let held=10n,scopeReady=true;
  const moon={strategyHostStop(value){assert.strictEqual(value,setup);calls.push('stop-setup');},
    strategyHostCloseOutputs(value){assert.strictEqual(value,setup);calls.push('close-outputs');},
    strategyHostUsage(value){assert.strictEqual(value,setup);calls.push('usage');return[0n,0n,0n,0n,0n,0n,0n,0n,0n,held,0n,0n,0n];}};
  const originalPreparation={async retire(){calls.push('retire-scope');
    if(!scopeReady)return false;held=0n;return true;}};
  const api=new Function('moon','children','originalPreparation','setup','checked','ledgerUsageHasPendingResources',
    'let execution,pendingSetup=setup,issuance,publication,holding,sourceContinuation,restoredSource;'+
    'let closeAttempted=false,released=false;'+source.slice(cleanup.start,cleanup.end)+
    ';return{cleanup,pending:()=>pendingSetup!==undefined,released:()=>released};')(
      moon,children,originalPreparation,setup,value=>value,ledgerUsageHasPendingResources);
  return{...api,calls,setScopeReady(value){scopeReady=value;}};
}

test('composed cleanup drains its original Scope before requiring whole-parent zero usage',async()=>{
  const f=fixture();
  assert.equal(await f.cleanup(),true);
  assert(f.calls.indexOf('close-outputs')<f.calls.indexOf('retire-scope'));
  assert(f.calls.indexOf('retire-scope')<f.calls.indexOf('usage'));
  assert.equal(f.pending(),false);
  assert.equal(await f.cleanup(),true);
  assert.equal(f.calls.filter(value=>value==='retire-scope').length,1);
});

test('composed cleanup keeps the original setup while a Model child or same Scope is pending',async()=>{
  let closed=false,closes=0;
  const child={operation:{close(){closes++;return closed;},cleanup(){closes++;return closed;},
    cleanupPending:()=>!closed}};
  const f=fixture([child]);
  assert.equal(await f.cleanup(),false);
  assert.equal(f.pending(),true);
  assert.equal(f.calls.includes('retire-scope'),false);
  closed=true;f.setScopeReady(false);
  assert.equal(await f.cleanup(),false);
  assert.equal(f.pending(),true);
  const childCloses=closes;
  f.setScopeReady(true);
  assert.equal(await f.cleanup(),true);
  assert.equal(closes,childCloses);
  assert.equal(f.pending(),false);
});
