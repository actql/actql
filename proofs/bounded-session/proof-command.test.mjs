import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const helper = fileURLToPath(new URL('proof-command.mjs', import.meta.url));
const pause = () => new Promise(resolve => setTimeout(resolve, 10));
async function waitFor(predicate) {
  for (let i = 0; i < 500; i++) { if (predicate()) return; await pause(); }
  assert.fail('Owned child did not reach the expected boundary');
}
function absent(pid) {
  try { process.kill(pid, 0); return false; }
  catch (error) { assert.equal(error.code, 'ESRCH'); return true; }
}
async function fixture(t, mode, options = {}, callerTimeout = false) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-proof-child-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const ready = join(directory, 'ready.json'), resultPath = join(directory, 'result.json');
  const child = join(directory, 'child.mjs'), runner = join(directory, 'runner.mjs');
  writeFileSync(child, `import {spawn} from 'node:child_process';
import {writeFileSync, renameSync, existsSync} from 'node:fs';
const mode=${JSON.stringify(mode)};
const grandchild = mode==='term'||mode==='timeout'
  ? spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'}) : null;
const grandchildClosed=grandchild?new Promise(resolve=>grandchild.once('close',resolve)):null;
if(mode==='normal'){process.stdout.write('x'.repeat(65536));process.stderr.write('tail');}
else if(mode==='nonzero'){console.log('Checked 54 theorems');process.exitCode=7;}
else if(mode==='output-close'){
  process.stdout.end();process.stderr.end();setInterval(()=>{if(existsSync(${JSON.stringify(join(directory,'release'))}))process.exit(0);},10);
}else if(mode==='overflow'){process.stdout.write('x'.repeat(8192));setInterval(()=>{},1000);}
else {
  const interval=setInterval(()=>{},1000);
  process.on('SIGTERM',()=>{
    clearInterval(interval);
    grandchildClosed.then(()=>process.stdout.write('Checked 54 theorems\\n',()=>process.exit(0)));
    grandchild.kill('SIGTERM');
  });
}
writeFileSync(${JSON.stringify(ready+'.pending')},JSON.stringify({pid:process.pid,grandchild:grandchild?.pid??null}));
renameSync(${JSON.stringify(ready+'.pending')},${JSON.stringify(ready)});
`);
  writeFileSync(runner, `import {writeFileSync, renameSync} from 'node:fs';
import {runProofCommand} from ${JSON.stringify(helper)};
const result=await runProofCommand(process.execPath,[${JSON.stringify(child)}],${JSON.stringify(options)});
writeFileSync(${JSON.stringify(resultPath+'.pending')},JSON.stringify({...result,error:result.error?.code??null}));
renameSync(${JSON.stringify(resultPath+'.pending')},${JSON.stringify(resultPath)});
process.exitCode=result.error||result.signal||result.status!==0?1:0;
`);
  if (callerTimeout) {
    const parent = spawnSync(process.execPath, [runner], {encoding: 'utf8', timeout: 60000});
    assert.equal(parent.error?.code, 'ETIMEDOUT');
    const ids = JSON.parse(readFileSync(ready));
    assert(absent(ids.pid));
    assert(absent(ids.grandchild));
    assert(absent(-ids.pid));
    const result = JSON.parse(readFileSync(resultPath));
    assert.equal(result.error, 'EINTR');
    assert.equal(result.interrupted, 'SIGTERM');
    assert.equal(result.groupClosed, true);
    return;
  }
  const parent = spawn(process.execPath, [runner], {stdio: 'pipe'});
  let output = '';
  parent.stdout.on('data', b => { output += b; });
  parent.stderr.on('data', b => { output += b; });
  const closed = new Promise(resolve => parent.on('close', (status, signal) => resolve({status, signal})));
  t.after(() => { if (parent.exitCode === null && parent.signalCode === null) parent.kill('SIGTERM'); });
  if (mode === 'timeout' || mode === 'overflow') await waitFor(() => existsSync(resultPath));
  else await waitFor(() => existsSync(ready));
  const ids = existsSync(ready) ? JSON.parse(readFileSync(ready))
    : {pid: JSON.parse(readFileSync(resultPath)).childPid, grandchild: null};
  assert(Number.isInteger(ids.pid), 'Retain the actual spawned child identity even before ready');
  if (mode === 'term') parent.kill('SIGTERM');
  if (mode === 'output-close') {
    assert.equal(absent(ids.pid), false);
    assert.equal(existsSync(resultPath), false, 'Stream completion is not physical stop');
    writeFileSync(join(directory,'release'),'release');
  }
  await waitFor(() => existsSync(resultPath));
  const terminal = await closed;
  assert.equal(terminal.signal, null, output);
  assert(absent(ids.pid), 'Original child must be reaped');
  if (ids.grandchild) assert(absent(ids.grandchild), 'Original grandchild must be reaped');
  if (process.platform !== 'win32') assert(absent(-ids.pid), 'Original group must be gone');
  const result = JSON.parse(readFileSync(resultPath));
  assert.equal(result.outputClosed, true);
  if (process.platform !== 'win32') assert.equal(result.groupClosed, true);
  return {result, terminal};
}

test('proof command preserves complete stdout/stderr through real child close', async t => {
  const {result, terminal} = await fixture(t, 'normal');
  assert.equal(terminal.status, 0);
  assert.equal(result.status, 0);
  assert.equal(result.error, null);
  assert.equal(result.stdout, 'x'.repeat(65536));
  assert.equal(result.stderr, 'tail');
});
test('proof-like output never masks a real nonzero child', async t => {
  const {result, terminal} = await fixture(t, 'nonzero');
  assert.equal(terminal.status, 1);
  assert.equal(result.status, 7);
  assert.match(result.stdout, /Checked 54/);
});
test('parent TERM forwards to the owned group and waits for reaping', {skip: process.platform === 'win32'}, async t => {
  const {result, terminal} = await fixture(t, 'term');
  assert.equal(terminal.status, 1);
  assert.equal(result.error, 'EINTR');
  assert.equal(result.interrupted, 'SIGTERM');
  assert.match(result.stdout, /Checked 54/);
});
test('finite timeout cannot adopt a terminated child as proof success', {skip: process.platform === 'win32'}, async t => {
  const {result, terminal} = await fixture(t, 'timeout', {timeout: 500});
  assert.equal(terminal.status, 1);
  assert.equal(result.error, 'ETIMEDOUT');
  assert.equal(result.outputClosed, true);
  assert.equal(result.groupClosed, true);
});
test('synchronous caller timeout forwards TERM and reaps the original child group',
  {skip: process.platform === 'win32'}, async t => fixture(t, 'timeout', {}, true));
test('closed output does not release custody of a still-running child', async t => {
  const {result, terminal} = await fixture(t, 'output-close');
  assert.equal(terminal.status, 0);
  assert.equal(result.status, 0);
});
test('bounded output overflow stops the original child without accepting it', async t => {
  const {result, terminal} = await fixture(t, 'overflow', {maxBuffer: 1024});
  assert.equal(terminal.status, 1);
  assert.equal(result.error, 'ENOBUFS');
});
