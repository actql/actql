import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
// The ordinary chain proof-check imports this file. Keep real child/source
// custody and interruption refusals beside the existing recipe observations.
import '../bounded-session/mutation-command.test.mjs';
import '../bounded-session/mutation-detection.test.mjs';
import {retirementCases, selectCases, retirementWitness, requireRetirementDetection, normalLifetimeCases, requireNormalLifetime} from './mutation-retirement.mjs';
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

const normalFixture = read(retirementCases[0][4]);
// Synthetic validator inputs only. The actual normal runner still executes
// Moon and binds the unchanged Source snapshot before and after the child.
const normalOutput = 'Total tests: 11, passed: 11, failed: 0.\n';
test('current lifetime fixture changes only same-sequence binding fragment preparation', () => {
  const before = '      @lower.kernel_body(kernel) is @lower.Filter(_) {';
  const after = '      (\n        @lower.kernel_body(kernel) is @lower.Filter(_) ||\n        @lower.kernel_bindings(kernel) is Some(_)\n      ) {';
  assert.equal(normalFixture.split(after).length, 2, 'Reach the one reviewed fragment selection');
  const previous = normalFixture.replace(after, before);
  // Independently retained complete preimage: this single reversal includes
  // every original case, limit, current check and cleanup assertion unchanged.
  assert.equal(createHash('sha256').update(previous).digest('hex'),
    '3ff093fd2c959c5ebcd4027ddc2bbcdf56fc351c86dfe1e1c85a750353ce4e3a');
  assert.throws(() => requireNormalLifetime({status: 0}, normalOutput, previous),
    /requires a new independent review/);
  const foreign = normalFixture.replace('@lower.kernel_bindings(kernel) is Some(_)',
    '@lower.kernel_bindings(kernel) is None');
  assert.notEqual(foreign, normalFixture);
  assert.throws(() => requireNormalLifetime({status: 0}, normalOutput, foreign),
    /requires a new independent review/);
});
test('normal lifetime census admits exactly the independently reviewed eleven cases', () => {
  assert.equal(normalLifetimeCases.length, 11);
  assert.equal(requireNormalLifetime({status: 0}, normalOutput, normalFixture), 11);
});
for (const [label, fixture] of [
  ['missing', normalFixture.replace(`test "${normalLifetimeCases[0]}" {`, 'fn missing_case() {')],
  ['renamed', normalFixture.replace(normalLifetimeCases[0], 'renamed case')],
  ['added', `${normalFixture}\ntest "unreviewed case" {}\n`],
  ['changed assertion', normalFixture.replace('assert_eq(count, 3)', 'assert_eq(count, 2)')],
]) test(`normal census refuses ${label} authored case`, () => {
  assert.throws(() => requireNormalLifetime({status: 0}, normalOutput, fixture));
});
for (const [label, result, output] of [
  ['zero', {status: 0}, 'Total tests: 0, passed: 0, failed: 0.'],
  ['missing summary', {status: 0}, ''],
  ['duplicate summary', {status: 0}, normalOutput.repeat(2)],
  ['missing case', {status: 0}, 'Total tests: 10, passed: 10, failed: 0.'],
  ['failed case', {status: 1}, 'Total tests: 11, passed: 10, failed: 1.'],
  ['process error', {status: 0, error: new Error('failed')}, normalOutput],
  ['signal', {status: 0, signal: 'SIGTERM'}, normalOutput],
]) test(`normal census refuses ${label}`, () => {
  assert.throws(() => requireNormalLifetime(result, output, normalFixture));
});
