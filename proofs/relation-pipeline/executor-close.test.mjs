import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, copyFileSync, rmSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = fileURLToPath(new URL('../../', import.meta.url));
// No product execution is claimed: mock only the Moon transport. The actual
// executor, ownership checks, receipt persistence and live process handoff run.
function workspace() {
  const directory = mkdtempSync(join(tmpdir(), 'actql-executor-close-'));
  const put = (path, content) => {
    mkdirSync(join(directory, path, '..'), { recursive: true });
    writeFileSync(join(directory, path), content);
  };
  for (const path of ['proofs/relation-pipeline/execute.mjs', 'proofs/relation-pipeline/engine.mjs',
    'proofs/relation-pipeline/inventory.mjs', 'proofs/relation-pipeline/fixture.mjs',
    'proofs/relation-pipeline/harness.mbt', 'proofs/relation-pipeline/capacity/finish.mjs', 'proofs/bounded-session/evidence.mjs',
    'proofs/bounded-session/nest-obligations.json', 'toolchain.json']) {
    mkdirSync(join(directory, path, '..'), { recursive: true });
    copyFileSync(join(root, path), join(directory, path));
  }
  for (const path of ['src/query_integration', 'proofs/relation-chain', 'proofs/relation-capacity',
    '.artifacts/relation-pipeline/capacity'])
    mkdirSync(join(directory, path), { recursive: true });
  for (const path of ['moon.mod', 'package.json', 'package-lock.json', '.github/workflows/ci.yml',
    'docs/spec/language.md', 'docs/spec/execution.md']) put(path, '{}');
  const home = join(directory, 'tools');
  const pin = JSON.parse(readFileSync(join(directory, 'toolchain.json')));
  put('tools/bin/moonc', `#!/usr/bin/env node\nconsole.log(${JSON.stringify(pin.moonc)});\n`);
  put('tools/bin/moon', `#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
const inputs = JSON.parse(process.env.ACTQL_RELATION_PIPELINE_CASES);
const directory = '_build/js/debug/test/query_integration';
mkdirSync(directory, {recursive:true});
writeFileSync(directory+'/query_integration.whitebox_test.js', '// mock transport artifact');
for (const input of inputs) {
  console.log('ACTQL_PIPELINE_CASE:'+JSON.stringify(input.id));
  console.log('ACTQL_PIPELINE:'+JSON.stringify({...input,checked:true,registered:true,rows:[],wireRows:[],columns:[]}));
}
`);
  // .mjs transport is executable regardless of the parent's package mode.
  put('tools/package.json', '{"type":"module"}');
  chmodSync(join(home, 'bin/moon'), 0o755);
  chmodSync(join(home, 'bin/moonc'), 0o755);
  put('lifecycle.mjs', `
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync,unlinkSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {execute,executions,closeExecutor,fixture} from './proofs/relation-pipeline/execute.mjs';
import {body} from './proofs/relation-pipeline/fixture.mjs';
import {finishCapacityCampaign} from './proofs/relation-pipeline/capacity/finish.mjs';
const cases = [{id:'lifecycle',rows:[],steps:[{id:'identity',op:'identity',args:{}}]}];
const registry = [{name:'identity',admits:()=>true,contract:s=>s,syntax:()=>({select:['k']})}];
const mode = process.argv[2];
const run = () => execute(cases,registry,'js',false,'capacity-parent-lifecycle');
if (mode==='child') { run(); closeExecutor(); }
else if (mode==='foreign') {
  writeFileSync(fixture,body);
  assert.throws(run,/Another pipeline batch owns/);
  closeExecutor(); assert.equal(readFileSync(fixture,'utf8'),body);
  unlinkSync(fixture);
} else if (mode==='changed') {
  run(); writeFileSync(fixture,body+'\\n');
  assert.throws(closeExecutor,/Owned fixture was changed/);
  assert(existsSync(fixture)); writeFileSync(fixture,body); closeExecutor();
} else {
  run();
  const receipt=executions.at(-1);
  assert.deepEqual(JSON.parse(readFileSync(receipt.path)),receipt.receipt);
  const child = () => spawnSync(process.execPath,['lifecycle.mjs','child'],{encoding:'utf8'});
  const blocked=child(); assert.notEqual(blocked.status,0);
  assert.match(blocked.stderr,/Another pipeline batch owns the temporary fixture/);
  assert(existsSync(fixture));
  finishCapacityCampaign({kind:'mock transport lifecycle regression'},['js','wasm','native']);
  assert(!existsSync(fixture));
  assert.throws(run,/Execution workspace is closed/);
  assert.equal(readFileSync(receipt.receipt.fixturePath,'utf8'),body);
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
  test(name, () => {
    const w = workspace();
    try {
      const result = spawnSync(process.execPath, ['lifecycle.mjs', mode], {
        cwd: w.directory, env: { ...process.env, MOON_HOME: w.home }, encoding: 'utf8' });
      assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
    } finally { rmSync(w.directory, { recursive: true, force: true }); }
  });
}
test('handoff regression detects omitting the campaign executor close', () => {
  const w = workspace();
  try {
    const path = join(w.directory, 'proofs/relation-pipeline/capacity/finish.mjs');
    const source = readFileSync(path, 'utf8');
    assert.equal(source.split('  closeExecutor();').length, 2);
    writeFileSync(path, source.replace('  closeExecutor();', '  // Deliberately omit owner release.'));
    const result = spawnSync(process.execPath, ['lifecycle.mjs', 'handoff'], {
      cwd: w.directory, env: { ...process.env, MOON_HOME: w.home }, encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /assert\(!existsSync\(fixture\)\)/);
  } finally { rmSync(w.directory, { recursive: true, force: true }); }
});
