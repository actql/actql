// Tiny real Git DAGs: no Git identity, source bytes or digest checks are mocked.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {composeFoundation} from './foundation.mjs';
import {occurrences} from '../../scripts/check-owned-contract-versions.mjs';
import {FoundationRepository,PROTECTED_PATHS,PACKAGE,CI,RENAME,DECLARATION_DIRECTORY,packageBytes,ciBytes,sha256} from './fixtures/foundation-repository.mjs';
const encode=v=>`${JSON.stringify(v,null,2)}\n`;
const compose=repo=>composeFoundation(repo.root,{checkpoint:repo.checkpoint,paths:PROTECTED_PATHS});
function incomplete(t,{extra=false,sameIntroduction=false}={}) {
 const repo=new FoundationRepository(t);
 const source=repo.source({[PACKAGE]:packageBytes({left:'node left.mjs'}),[CI]:ciBytes(['left']),...(extra?{[RENAME]:'export const rename="changed";\n'}:{})});
 const original=repo.declaration('partial-source',source,[PACKAGE]);
 const raw=Buffer.from(encode(original)),path=`${DECLARATION_DIRECTORY}-supplements/complete-source.json`;
 const completion={version:'actql-foundation-change-completion/0.1',id:'complete-source',target:{id:original.id,digest:sha256(raw)},
  changes:repo.declaration('missing',source,[CI]).changes,reason:'Record the omitted actual source path without changing earlier bytes'};
 let introduced;
 if(sameIntroduction)repo.writeDeclaration(original);else introduced=repo.record(original);
 const record=(value=completion)=>{repo.write(path,encode(value));return repo.commit('Append missing source path');};
 return {repo,source,original,raw,path,completion,introduced,record};
}
test('missing-only completion retains raw original bytes and requires complete actual source paths',t=>{
 const f=incomplete(t);assert.throws(()=>compose(f.repo),/Incomplete foundation changed paths/);
 const intro=f.record(),report=compose(f.repo),original=report.declarations.find(d=>d.id===f.original.id);
 assert.deepEqual(original.changes,f.original.changes);assert.equal(original.digest,sha256(f.raw));assert.deepEqual(original.introductions,[f.introduced]);
 assert.deepEqual(readFileSync(join(f.repo.root,f.repo.declarationPath(f.original.id))),f.raw);
 assert.deepEqual(report.changeCompletions[0].changes.map(c=>c.path),[CI,PACKAGE].sort());
 assert.deepEqual(report.supplements[0].introductions,[intro]);
 f.repo.write('note.txt','unrelated\n');f.repo.commit('Unrelated descendant');
 assert.deepEqual(compose(f.repo).changeCompletions,report.changeCompletions);
});
for(const [name,edit,pattern] of [
 ['unknown target',f=>f.completion.target.id='missing',/supplement target/],
 ['wrong raw original digest',f=>f.completion.target.digest='0'.repeat(64),/Changed foundation supplement original/],
 ['empty paths',f=>f.completion.changes=[],/Empty foundation completion/],
 ['duplicate added path',f=>f.completion.changes.push(f.completion.changes[0]),/Noncanonical foundation completion/],
 ['original path repeated',f=>f.completion.changes=[f.original.changes[0]],/Redundant foundation completion/],
 ['unknown path',f=>f.completion.changes[0].path='unprotected',/Unknown foundation completion/],
 ['protected unchanged path',f=>f.completion.changes=f.repo.declaration('unused',f.source,[RENAME]).changes,/Unchanged foundation completion/],
 ['wrong before revision',f=>f.completion.changes[0].before[0].revision=f.source,/prior identity/],
 ['wrong before digest',f=>f.completion.changes[0].before[0].digest='0'.repeat(64),/prior identity/],
 ['wrong before mode',f=>f.completion.changes[0].before[0].mode='100755',/prior identity/],
 ['wrong after digest',f=>f.completion.changes[0].afterDigest='0'.repeat(64),/current digest/],
 ['wrong after mode',f=>f.completion.changes[0].afterMode='100755',/current mode/],
 ['invalid mode',f=>f.completion.changes[0].afterMode='120000',/completion mode/],
 ['empty change reason',f=>f.completion.changes[0].reason=' ',/completion rationale/],
 ['empty record reason',f=>f.completion.reason=' ',/supplement rationale/],
 ['parent override',f=>f.completion.parents=[f.source],/supplement fields/],
 ['source override',f=>f.completion.revision=f.source,/supplement fields/],
 ['kind override',f=>f.completion.kind='resolution',/supplement fields/],
 ['merge-base override',f=>f.completion.mergeBases=[f.source],/supplement fields/],
 ['input override',f=>f.completion.inputs=[],/supplement fields/],
 ['acceptance override',f=>f.completion.ignore=true,/supplement fields/],
 ['unknown version',f=>f.completion.version='unknown-completion-format',/supplement fields|ERR_ASSERTION/],
])test(`missing-only completion rejects ${name}`,t=>{const f=incomplete(t);edit(f);f.record();assert.throws(()=>compose(f.repo),pattern);});
test('completion must cover every remaining changed path',t=>{const f=incomplete(t,{extra:true});f.record();assert.throws(()=>compose(f.repo),/Incomplete foundation changed paths/);});
test('completion must be introduced after its original record',t=>{const f=incomplete(t,{sameIntroduction:true});f.record();assert.throws(()=>compose(f.repo),/must follow its original/);});
test('completion from a non-descendant branch is rejected',t=>{
 const f=incomplete(t);f.repo.branch('early',f.source);f.repo.checkout('early');f.record();f.repo.checkout('main');f.repo.merge('early');
 assert.throws(()=>compose(f.repo),/must follow its original/);
});
test('later modification of raw original is not excused by completion',t=>{
 const f=incomplete(t);f.original.changes[0].reason='Edited original';f.repo.record(f.original);f.completion.target.digest=sha256(encode(f.original));f.record();
 assert.throws(()=>compose(f.repo),/Changed or removed foundation declaration/);
});
test('later modification or removal of completion remains forbidden',t=>{
 const f=incomplete(t);f.record();f.completion.reason='Changed completion';f.record();assert.throws(()=>compose(f.repo),/Changed or removed foundation declaration/);
});
test('removing an introduced completion remains forbidden',t=>{
 const f=incomplete(t);f.record();f.repo.remove(f.path);f.repo.commit('Remove completion');assert.throws(()=>compose(f.repo),/Changed or removed foundation declaration/);
});
test('duplicate path across independently named completions is rejected',t=>{
 const f=incomplete(t);f.record();const other={...f.completion,id:'duplicate-source'};f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${other.id}.json`,encode(other));f.repo.commit('Redundant completion');
 assert.throws(()=>compose(f.repo),/Redundant foundation completion path/);
});
test('a complete alias cannot excuse another incomplete unsupplemented record',t=>{
 const f=incomplete(t);f.repo.record(f.repo.declaration('full-alias',f.source,[PACKAGE,CI]));assert.throws(()=>compose(f.repo),/Incomplete foundation changed paths/);
});
test('completion of one alias does not repair a second incomplete alias',t=>{
 const f=incomplete(t);f.repo.record({...f.original,id:'other-partial'});f.record();assert.throws(()=>compose(f.repo),/Incomplete foundation changed paths/);
});
test('completed source binding equals an independently complete alias',t=>{
 const f=incomplete(t);f.repo.record(f.repo.declaration('full-alias',f.source,[PACKAGE,CI]));f.record();assert.doesNotThrow(()=>compose(f.repo));
});
function overlap(t,omit=false) {
 const f=incomplete(t);f.repo.branch('right',f.repo.checkpoint);f.record();f.repo.checkout('right');
 const rightSource=f.repo.source({[CI]:ciBytes(['right'])});const right=f.repo.declaration('right-source',rightSource,[CI]);f.repo.record(right);
 f.repo.checkout('main');const merge=f.repo.merge('right',{[CI]:ciBytes(['left','right'])});
 const resolution=f.repo.declaration('resolve-overlap',merge,[CI],{kind:'resolution',inputs:(omit?[right.id]:[f.original.id,right.id]).sort()});f.repo.record(resolution);
 return {...f,resolution};
}
test('later merge sees a source dependency through its newly completed path',t=>{const f=overlap(t);assert.doesNotThrow(()=>compose(f.repo));});
test('later merge cannot omit dependency whose only overlap is completed path',t=>{const f=overlap(t,true);assert.throws(()=>compose(f.repo),/Incomplete or ambiguous foundation resolution inputs/);});
test('change completion cannot target a resolution record',t=>{
 const f=overlap(t);const raw=readFileSync(join(f.repo.root,f.repo.declarationPath(f.resolution.id)));
 const value={...f.completion,id:'wrong-kind',target:{id:f.resolution.id,digest:sha256(raw)}};
 f.repo.write(`${DECLARATION_DIRECTORY}-supplements/${value.id}.json`,encode(value));f.repo.commit('Invalid resolution completion');
 assert.throws(()=>compose(f.repo),/supplement target/);
});

test('completion negative fixtures introduce no nonbaseline owned contract version',()=>{
 assert.deepEqual(occurrences(readFileSync(new URL('./foundation-change-completion.test.mjs',import.meta.url),'utf8'),
  'proofs/relation-pipeline/foundation-change-completion.test.mjs'),[]);
});
