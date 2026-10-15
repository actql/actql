import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
// The ordinary chain proof-check imports this file. Keep real child/source
// custody and interruption refusals beside the existing recipe observations.
import '../bounded-session/mutation-command.test.mjs';
import '../bounded-session/mutation-detection.test.mjs';
import {retirementCases, selectCases, retirementWitness, requireRetirementDetection} from './mutation-retirement.mjs';
const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const old = ['reset-consumed-budget','omit-handoff-accounting','fresh-budget-for-next-child','cleanup-reenters-advance','handoff-failure-drops-children','pending-cleanup-reported-complete','cancel-not-forwarded-to-session','row-adapter-cumulative-as-delta','premature-chain-terminal'].map(id => [id]);
const all = [...old, ...retirementCases];
test('default mutation plan retains nine original and all three retirement obligations', () => {
  assert.deepEqual(selectCases(all, []), all);
  assert.deepEqual(selectCases(all, ['all']), all);
  for (const [id] of old) assert(read('proofs/relation-chain/mutations.mjs').includes(`['${id}',`));
});
test('explicit local retirement selection cannot become an empty or partial campaign', () => {
  assert.deepEqual(selectCases(all, ['retirement']), retirementCases);
  for (const args of [['unknown'], ['retirement','extra']]) assert.throws(() => selectCases(all,args));
  assert.throws(() => selectCases(all.slice(0,-1),['retirement']));
  assert.throws(() => selectCases([...all,all[0]],[]));
});
for (const recipe of retirementCases) test(`recipe and assertion use current authored source: ${recipe[0]}`, () => {
  assert.equal(read(recipe[1]).split(recipe[2]).length, 2);
  assert(retirementWitness(recipe, read(recipe[4])).line > 0);
});
const witness = retirementWitness(retirementCases[0], read(retirementCases[0][4]));
const output = `[actql/actql] test connectors/local/relation_chain_lifetime_wbtest.mbt:258 ("${witness.test}") failed: ${witness.suite}:${witness.line}:3-1:2@actql/actql FAILED: 0 is not 1\nTotal tests: 1, passed: 0, failed: 1.\n`;
test('controlled expected assertion record admits exact case and source location', () => {
  requireRetirementDetection({status:1},output,witness);
});
for(const [label,result,text] of [
  ['compile failure',{status:1},`Error: [3001] invalid source\n${output}`],
  ['timeout',{status:null,error:new Error('timeout')},output],
  ['signal',{status:null,signal:'SIGTERM'},output],
  ['zero execution',{status:1},output.replace('Total tests: 1, passed: 0, failed: 1.','Total tests: 0, passed: 0, failed: 0.')],
  ['unrelated assertion',{status:1},output.replace(`${witness.suite}:${witness.line}:`,`${witness.suite}:${witness.line+1}:`)],
  ['unwrap failure',{status:1},output.replace('FAILED:','panicked:')],
  ['successful process',{status:0},output],
]) test(`controlled retirement observation refuses ${label}`,()=>assert.throws(()=>requireRetirementDetection(result,text,witness)));
