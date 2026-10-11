import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {checkBaseline,hash} from './inventory.mjs';
import './proof-runner-extension.test.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const path='proofs/relation-pipeline/baseline.json';
const baseline=JSON.parse(readFileSync(join(root,path)));
function withBaseline(value,files={}) {
 return {read:p=>p===path?Buffer.from(JSON.stringify(value)):files[p]??readFileSync(join(root,p))};
}
test('actual reviewed stop/pause extension retains all historical common law pins',()=>{
 const result=checkBaseline(root);
 assert.equal(result.modelExtension.observation.total,54);
 assert.equal(result.unchangedCommon['proofs/relation-chain/check.mjs'],'abac294b2005149066e11305c4422f1c5f619bec5a657e74a78cd8fe0c37da6c');
 assert.equal(Object.keys(result.unchangedCommon).length,8);
});
for(const [name,change] of [
 ['absent extension',b=>{delete b.modelExtension;}],
 ['omitted original Session root',b=>{delete b.unchangedCommon['proofs/bounded-session/Session.lean'];}],
 ['omitted stop claims',b=>{delete b.modelExtension.files['proofs/relation-chain/StopClaims.lean'];}],
 ['unrelated added file',b=>{b.modelExtension.files['proofs/relation-chain/README.md']='a'.repeat(64);}],
 ['old revision',b=>{b.modelExtension.revision=b.revision;}],
 ['changed historical pin',b=>{b.unchangedCommon[b.modelExtension.checker]='a'.repeat(64);b.modelExtension.priorDigest='a'.repeat(64);}],
 ['partial observation',b=>{b.modelExtension.observation.stopAndPause=14;b.modelExtension.observation.total=50;}],
 ['unrelated checker',b=>{b.modelExtension.checker='proofs/bounded-session/check.mjs';}],
]) test(`reviewed model extension refuses ${name}`,()=>{
 const changed=structuredClone(baseline);change(changed);assert.throws(()=>checkBaseline(root,withBaseline(changed)));
});
for(const file of Object.keys(baseline.modelExtension.files)) test(`model extension refuses changed ${file} even with a resealed current digest`,()=>{
 const changed=structuredClone(baseline), bytes=Buffer.concat([readFileSync(join(root,file)),Buffer.from('\n-- changed\n')]);
 assert.throws(()=>checkBaseline(root,withBaseline(changed,{[file]:bytes})),/Changed reviewed model extension/);
 changed.modelExtension.files[file]=hash(bytes);
 assert.throws(()=>checkBaseline(root,withBaseline(changed,{[file]:bytes})),/Unrelated model extension history/);
});
test('original Session laws remain required independently of the added stop model',()=>{
 const file='proofs/bounded-session/Session.lean';
 assert.throws(()=>checkBaseline(root,withBaseline(baseline,{[file]:Buffer.from('changed')})),/Changed common proof/);
});

test('resealing changed Session bytes does not replace the original model history',()=>{
 const file='proofs/bounded-session/Session.lean',changed=structuredClone(baseline),bytes=Buffer.from('changed');
 changed.unchangedCommon[file]=hash(bytes);
 assert.throws(()=>checkBaseline(root,withBaseline(changed,{[file]:bytes})),/Changed original common model history/);
});
