import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runRestoredMutation, requireMutationDetection} from './mutation-command.mjs';

const helper = new URL('./mutation-command.mjs', import.meta.url).href;
const source = Buffer.from('original\r\n\u0065\u0301\n');
const mutant = Buffer.from('mutant\n');
function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-session-mutation-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const file = join(directory, 'source.mbt');
  writeFileSync(file, source, {mode: 0o640});
  return {directory, file, mode: statSync(file).mode};
}
const options = {maxBuffer: 4 * 1024 * 1024};

test('mutation snapshot observer sees actual changed bytes before the child starts', async t => {
  const {file, mode} = fixture(t);
  let observed = false;
  const result = await runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', 'process.exit(1)'], options, () => {
      assert.deepEqual(readFileSync(file), mutant);
      observed = true;
    });
  assert.equal(observed, true);
  assert.equal(result.status, 1);
  assert.deepEqual(readFileSync(file), source);
  assert.equal(statSync(file).mode, mode);
});

test('snapshot observer failure restores bytes without starting the child', async t => {
  const {file, directory, mode} = fixture(t);
  const started = join(directory, 'child-started');
  const failure = new Error('SnapshotFailed');
  await assert.rejects(runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', `require('node:fs').writeFileSync(${JSON.stringify(started)},'started');`], options,
    () => { throw failure; }), error => error === failure);
  assert.throws(() => readFileSync(started), {code: 'ENOENT'});
  assert.deepEqual(readFileSync(file), source);
  assert.equal(statSync(file).mode, mode);
});

test('snapshot observer cannot cause foreign bytes to be compiled or overwritten', async t => {
  const {file, directory} = fixture(t);
  const started = join(directory, 'child-started');
  await assert.rejects(runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', `require('node:fs').writeFileSync(${JSON.stringify(started)},'started');`], options,
    () => { writeFileSync(file, 'foreign'); }), /changed externally/);
  assert.throws(() => readFileSync(started), {code: 'ENOENT'});
  assert.equal(readFileSync(file, 'utf8'), 'foreign');
});

for (const code of [0, 1, 7]) test(`mutation child exit ${code} restores exact bytes and mode`, async t => {
  const {file, mode} = fixture(t);
  const result = await runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', `require('node:assert/strict').deepEqual(require('node:fs').readFileSync(${JSON.stringify(file)}),Buffer.from('mutant\\n'));console.log('observed child');process.exit(${code});`], options);
  assert.equal(result.status, code);
  assert.equal(result.error, undefined);
  assert.equal(result.interrupted, undefined);
  assert.equal(result.signal, null);
  assert.match(result.stdout, /observed child/);
  assert.deepEqual(readFileSync(file), source);
  assert.equal(statSync(file).mode, mode);
});

test('missing executable restores bytes and keeps the real preparation error', async t => {
  const {file, directory} = fixture(t);
  const result = await runRestoredMutation(file, source, mutant,
    join(directory, 'does-not-exist'), [], options);
  assert.equal(result.error.code, 'ENOENT');
  assert.notEqual(result.status, 0);
  assert.deepEqual(readFileSync(file), source);
});

test('output overflow stops the real child, restores bytes and remains a failure', async t => {
  const {file} = fixture(t);
  const result = await runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', "setInterval(()=>process.stdout.write('x'.repeat(8192)),1)"], {maxBuffer: 1024});
  assert.match(result.error.message, /exceeds maxBuffer/);
  assert.notEqual(result.status, 0);
  assert.deepEqual(readFileSync(file), source);
});

test('restoration refuses to overwrite a foreign change', async t => {
  const {file} = fixture(t);
  await assert.rejects(runRestoredMutation(file, source, mutant, process.execPath,
    ['-e', `require('node:fs').writeFileSync(${JSON.stringify(file)},'foreign');`], options), /changed externally/);
  assert.equal(readFileSync(file, 'utf8'), 'foreign');
});

test('changed starting bytes refuse before any mutation or child launch', async t => {
  const {file} = fixture(t);
  writeFileSync(file, 'foreign');
  await assert.rejects(runRestoredMutation(file, source, mutant,
    process.execPath, ['-e', 'process.exit(0)'], options), /changed before execution/);
  assert.equal(readFileSync(file, 'utf8'), 'foreign');
});

for (const signal of ['SIGTERM', 'SIGINT']) test(`parent ${signal} waits for child close, restores and rejects assertion-shaped output`,
  {skip: process.platform === 'win32', timeout: 10000}, async t => {
    const {directory, file, mode} = fixture(t);
    const closed = join(directory, 'child-closed');
    const ready = join(directory, 'ready');
    const childCode = `process.on('${signal}',()=>{require('node:fs').writeFileSync(${JSON.stringify(closed)},'closed');console.log('Total tests: 1, passed: 0, failed: 1.');process.exit(1)});require('node:fs').writeFileSync(${JSON.stringify(ready + '.pending')},'ready');require('node:fs').renameSync(${JSON.stringify(ready + '.pending')},${JSON.stringify(ready)});setInterval(()=>{},1000);`;
    const parentCode = `import {runRestoredMutation} from ${JSON.stringify(helper)};
const result=await runRestoredMutation(${JSON.stringify(file)},Buffer.from(${JSON.stringify([...source])}),Buffer.from(${JSON.stringify([...mutant])}),process.execPath,['-e',${JSON.stringify(childCode)}],${JSON.stringify(options)});
console.log(JSON.stringify({status:result.status,signal:result.signal,interrupted:result.interrupted,output:result.stdout}));
// Match the production rejection: an interrupted assertion is never a kill.
process.exitCode=result.interrupted||result.signal||result.error?1:0;`;
    const actual = spawn(process.execPath, ['--input-type=module', '-e', parentCode],
      {stdio: ['ignore', 'pipe', 'pipe']});
    t.after(() => { if (actual.exitCode === null && actual.signalCode === null) actual.kill('SIGKILL'); });
    let stdout = '';
    let stderr = '';
    actual.stdout.on('data', data => { stdout += data; });
    actual.stderr.on('data', data => { stderr += data; });
    const exit = new Promise((resolve, reject) => {
      actual.once('error', reject);
      actual.once('close', (code, stopped) => resolve({code, stopped}));
    });
    // The child installs its handler before publishing a complete marker by
    // rename. The parent cannot observe the intermediate empty pending file.
    const deadline = Date.now() + 5000;
    while (true) {
      try { assert.equal(readFileSync(ready, 'utf8'), 'ready'); break; }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      assert(Date.now() < deadline, stderr || 'Signal child did not become ready');
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert(actual.kill(signal));
    assert.deepEqual(await exit, {code: 1, stopped: null}, stderr);
    const result = JSON.parse(stdout.trim());
    assert.equal(result.interrupted, signal);
    assert.match(result.output, /Total tests: 1, passed: 0, failed: 1/);
    assert.throws(() => requireMutationDetection(result, result.output), /Process failure/);
    assert.equal(readFileSync(closed, 'utf8'), 'closed');
    assert.deepEqual(readFileSync(file), source);
    assert.equal(statSync(file).mode, mode);
  });
