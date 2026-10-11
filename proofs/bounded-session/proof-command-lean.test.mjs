import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync, readFileSync, existsSync, readdirSync, readlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {runProofCommand} from './proof-command.mjs';

// Explicit Linux diagnostic: real pinned Lean, tiny independent inputs only.
// This is not acceptance of the original 54/55-theorem inventories.
const enabled = process.env.ACTQL_PROOF_CUSTODY_LEAN === '1';
const helper = fileURLToPath(new URL('proof-command.mjs', import.meta.url));
test('real pinned Lean preserves a tiny proof and actual rejection', {skip: !enabled}, async () => {
  const version = await runProofCommand('lean', ['--short-version']);
  assert.ifError(version.error);
  assert.equal(version.status, 0);
  assert.equal(version.stdout.trim(), readFileSync(new URL('../relation-chain/lean-toolchain', import.meta.url), 'utf8').trim().split(':v')[1]);
  for (const [input, status] of [['example : True := by trivial\n', 0], ['example : False := by trivial\n', 1]]) {
    const result = await runProofCommand('lean', ['-DwarningAsError=true', '--stdin'], {input, timeout: 60000});
    assert.ifError(result.error);
    assert.equal(result.status, status, result.stdout + result.stderr);
    assert.equal(result.groupClosed, true);
    assert.equal(result.outputClosed, true);
  }
});
test('real Lean child is stopped and reaped before its interrupted runner closes',
  {skip: !enabled}, async t => {
    assert.equal(process.platform, 'linux');
    const directory = mkdtempSync(join(tmpdir(), 'actql-proof-lean-stop-'));
    t.after(() => rmSync(directory, {recursive: true, force: true}));
    const resultPath = join(directory, 'result.json'), runner = join(directory, 'runner.mjs');
    writeFileSync(runner, `import {writeFileSync} from 'node:fs';
import {runProofCommand} from ${JSON.stringify(helper)};
const result=await runProofCommand('lean',['--stdin'],{input:${JSON.stringify('#eval IO.sleep 60000\n')}});
writeFileSync(${JSON.stringify(resultPath)},JSON.stringify({...result,error:result.error?.code??null}));
process.exitCode=result.error||result.signal||result.status!==0?1:0;`);
    const parent = spawn(process.execPath, [runner], {stdio: 'pipe'});
    let output = '';
    parent.stdout.on('data', b => { output += b; });
    parent.stderr.on('data', b => { output += b; });
    const closed = new Promise(resolve => parent.on('close', status => resolve(status)));
    t.after(async () => {
      if (parent.exitCode === null && parent.signalCode === null) parent.kill('SIGTERM');
      await closed;
    });
    let leanPid;
    for (let i = 0; i < 3000 && !leanPid; i++) {
      assert.equal(parent.exitCode, null, output || 'Runner exited before real Lean startup');
      for (const name of readdirSync('/proc').filter(name => /^\d+$/.test(name))) {
        try {
          const status = readFileSync(`/proc/${name}/status`, 'utf8');
          const command = readFileSync(`/proc/${name}/cmdline`, 'utf8').split('\0');
          if (new RegExp(`^PPid:\\s+${parent.pid}$`, 'm').test(status) &&
              readlinkSync(`/proc/${name}/exe`) === '/opt/lean-4.30.0-rc1-linux/bin/lean' &&
              command.includes('--stdin')) leanPid = Number(name);
        } catch {}
      }
      if (!leanPid) await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert(leanPid, 'Observe the original real Lean --stdin child before interruption');
    parent.kill('SIGTERM');
    assert.equal(await closed, 1, output);
    assert(existsSync(resultPath), 'Runner must finish custody before exiting');
    const result = JSON.parse(readFileSync(resultPath));
    assert.equal(result.error, 'EINTR');
    assert.equal(result.groupClosed, true);
    assert.equal(result.outputClosed, true);
    assert.equal(existsSync(`/proc/${leanPid}`), false, 'Original Lean child must be reaped');
    assert.throws(() => process.kill(-leanPid, 0), {code: 'ESRCH'});
    console.log(JSON.stringify({realLeanPid: leanPid, parentPid: parent.pid,
      reaped: true, groupClosed: result.groupClosed, proofAccepted: false}));
  });
