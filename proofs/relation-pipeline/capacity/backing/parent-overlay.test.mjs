import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {currentOverlay,boundCurrentOverlay,currentHelper,currentFixture} from '../parent-control/current-overlay.mjs';
import {auditCurrentChain} from '../parent-control/current-audit.mjs';
import {hash} from '../../inventory.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));const read=p=>readFileSync(join(root,p));
test('borrowed observer binds current state and leaves callback bodies unchanged',()=>{
  const overlay=currentOverlay(read);
  assert(overlay[currentHelper].includes('#borrow(parent, state'));
  assert(overlay[currentFixture].includes('physical_equal(preparation.read.unwrap(), metadata)'));
  const p='src/connectors/local/selected_relation_provider.mbt';
  assert.throws(()=>currentOverlay(path=>path===p?'':read(path)));
});
test('compiled marker binds submitted source and the complete observation overlay',()=>{
  const source={sources:{},digest:hash(JSON.stringify({}))};
  const a=boundCurrentOverlay(read,source),b=boundCurrentOverlay(read,{...source,digest:hash('different source')});
  assert.notEqual(a.buildIdentity,b.buildIdentity);
  assert(a.overlay[currentFixture].includes(`ACTQL_CHAIN_BUILD:${a.buildIdentity}`));
});
test('consumer reaches independently archived log and rejects detached compiled input first',()=>{
  const source={sources:{},digest:hash(JSON.stringify({}))};
  const {overlay,boundary,buildIdentity}=boundCurrentOverlay(read,source);
  const overlayDigests=Object.fromEntries(Object.entries(overlay).map(([p,t])=>[p,hash(t)]));
  const executedSources=Object.fromEntries(Object.entries(overlayDigests).toSorted(([a],[b])=>a.localeCompare(b,'en')));
  const report={version:'actql-current-chain-native-diagnostic/0.1',revision:'1'.repeat(40),target:'native',
    authority:'local-physical-finite-correspondence',reuseAuthorized:false,unconditionalAllocationBytes:false,restored:true,
    source,boundary,buildIdentity,overlayDigests,executedSource:{sources:executedSources,digest:hash(JSON.stringify(executedSources))},
    command:['moon','test','--target','native',currentFixture,'--deny-warn'],exit:0,
    logDigest:'a'.repeat(64),logPath:'.artifacts/relation-pipeline/current-chain-native/logs/'+ 'a'.repeat(64)+'.log'};
  const reached=new Error('reached independently archived actual log');
  const audit=r=>auditCurrentChain(r,source,p=>{if(p===report.logPath)throw reached;return read(p);});
  assert.throws(()=>audit(report),e=>e===reached);
  for(const mutate of [r=>r.target='js',r=>r.boundary.sourceDigest=hash('old'),
    r=>r.buildIdentity=hash('other binary'),r=>r.restored=false,r=>r.reuseAuthorized=true,
    r=>r.executedSource.sources[currentFixture]=hash('unbound fixture')]) {
    const r=structuredClone(report);mutate(r);assert.throws(()=>audit(r),e=>e!==reached);
  }
});
