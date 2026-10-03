import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {minimalRepository} from './fixtures/execution-driver.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
// No product execution is claimed: mock only the Moon transport. The actual
// executor, ownership checks, receipt persistence and live process handoff run.
function workspace(t) {
  const directory = minimalRepository(t);
  const put = (path, content) => {
    mkdirSync(join(directory, path, '..'), {recursive: true});
    writeFileSync(join(directory, path), content);
  };
  const home = join(directory, '.fake-moon');
  mkdirSync(join(directory, 'proofs/relation-pipeline/capacity'), {recursive: true});
  copyFileSync(join(root, 'proofs/relation-pipeline/capacity/finish.mjs'),
    join(directory, 'proofs/relation-pipeline/capacity/finish.mjs'));
  mkdirSync(join(directory, '.artifacts/relation-pipeline/capacity'), {recursive: true});
  put('lifecycle.mjs', `
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync,unlinkSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createExecutor,execute,executions,closeExecutor,fixture} from './proofs/relation-pipeline/execute.mjs';
import {take} from './proofs/relation-pipeline/take.mjs';
import {finishCapacityCampaign} from './proofs/relation-pipeline/capacity/finish.mjs';
const cases = [{id:'lifecycle',rows:[],steps:[{id:'take',op:'take',args:{offset:0,count:1}}]}];
const registry = [take];
const mode = process.argv[2];
const run = () => execute(cases,registry,'js',false,'capacity-parent-lifecycle');
if (mode==='child') { run(); closeExecutor(); }
else if (mode==='foreign') {
  run(); const bytes=readFileSync(fixture,'utf8'); closeExecutor();
  writeFileSync(fixture,bytes); const foreign=createExecutor();
  assert.throws(()=>foreign.execute(cases,registry,'js'),/Another pipeline batch owns/);
  foreign.close(); assert.equal(readFileSync(fixture,'utf8'),bytes);
  unlinkSync(fixture);
} else if (mode==='changed') {
  run(); const bytes=readFileSync(fixture,'utf8'); writeFileSync(fixture,bytes+'\\n');
  assert.throws(closeExecutor,/Owned fixture was changed/);
  assert(existsSync(fixture)); writeFileSync(fixture,bytes); closeExecutor();
} else {
  run();
  const receipt=executions.at(-1); const bytes=readFileSync(fixture,'utf8');
  assert.deepEqual(JSON.parse(readFileSync(receipt.path)),receipt.receipt);
  const child = () => spawnSync(process.execPath,['lifecycle.mjs','child'],{encoding:'utf8'});
  const blocked=child(); assert.notEqual(blocked.status,0);
  assert.match(blocked.stderr,/Another pipeline batch owns the temporary fixture/);
  assert(existsSync(fixture));
  finishCapacityCampaign({kind:'mock transport lifecycle regression'},['js','wasm','native']);
  assert(!existsSync(fixture));
  assert.throws(run,/Execution workspace is closed/);
  assert.equal(readFileSync(receipt.receipt.fixturePath,'utf8'),bytes);
  const admitted=child(); assert.equal(admitted.status,0,admitted.stderr);
  assert(!existsSync(fixture));
  assert.deepEqual(JSON.parse(readFileSync('.artifacts/relation-pipeline/capacity/all.json')).executions,executions);
  closeExecutor(); closeExecutor();
}
`);
  return { directory, home, put };
}
for (const [mode, name] of [['handoff', 'capacity executor saves receipts and closes before a child probe in the same live checkout'],
  ['foreign', 'identical fixture bytes do not confer ownership'], ['changed', 'changed owned fixture is preserved and rejected']]) {
  test(name, t => {
    const w = workspace(t);
    try {
      const result = spawnSync(process.execPath, ['lifecycle.mjs', mode], {
        cwd: w.directory, env: { ...process.env, MOON_HOME: w.home, PATH: `${w.home}/bin:${process.env.PATH}`, CC: 'cc', CXX: 'c++',
          ACTQL_TEST_EXECUTION_CONTROL: join(w.directory, '.execution-control.json'),
          ACTQL_TEST_EXECUTION_CALLS: join(w.directory, '.execution-calls.jsonl') }, encoding: 'utf8' });
      assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
    } finally { rmSync(w.directory, { recursive: true, force: true }); }
  });
}
test('handoff regression detects omitting the campaign executor close', t => {
  const w = workspace(t);
  try {
    const path = join(w.directory, 'proofs/relation-pipeline/capacity/finish.mjs');
    const source = readFileSync(path, 'utf8');
    assert.equal(source.split('  closeExecutor();').length, 2);
    writeFileSync(path, source.replace('  closeExecutor();', '  // Deliberately omit owner release.'));
    const result = spawnSync(process.execPath, ['lifecycle.mjs', 'handoff'], {
      cwd: w.directory, env: { ...process.env, MOON_HOME: w.home, PATH: `${w.home}/bin:${process.env.PATH}`, CC: 'cc', CXX: 'c++',
          ACTQL_TEST_EXECUTION_CONTROL: join(w.directory, '.execution-control.json'),
          ACTQL_TEST_EXECUTION_CALLS: join(w.directory, '.execution-calls.jsonl') }, encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /assert\(!existsSync\(fixture\)\)/);
  } finally { rmSync(w.directory, { recursive: true, force: true }); }
});
