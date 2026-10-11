import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const helper = fileURLToPath(new URL('native-command.mjs', import.meta.url));

test('proof stack preparation preserves parent, hard limit, arguments and non-Native children',
  {skip: process.platform === 'win32'}, t => {
    const directory = mkdtempSync(join(tmpdir(), 'actql-proof-stack-'));
    t.after(() => rmSync(directory, {recursive: true, force: true}));
    const child = join(directory, 'observed child.mjs');
    writeFileSync(child, `import {spawnSync} from 'node:child_process';
const limits = spawnSync('bash', ['-c', 'printf "%s:%s" "$(ulimit -S -s)" "$(ulimit -H -s)"'], {encoding:'utf8'});
if (limits.status !== 0) process.exit(limits.status ?? 1);
console.log(JSON.stringify({args:process.argv.slice(2), limits:limits.stdout}));
`);
    for (const target of ['model', 'js', 'wasm', 'native']) {
      const args = [child, 'literal space', '$(touch forbidden)', '--target', target];
      const program = `import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {spawnProofCommand} from ${JSON.stringify(helper)};
const limits=()=>spawnSync('bash',['-c','printf "%s:%s" "$(ulimit -S -s)" "$(ulimit -H -s)"'],{encoding:'utf8'}).stdout;
const before=limits();
const result=spawnProofCommand(process.execPath,${JSON.stringify(args)},${JSON.stringify(target)},{cwd:${JSON.stringify(directory)},encoding:'utf8',timeout:5000});
assert.equal(result.status,0,result.stderr);
assert.equal(limits(),before);
console.log(JSON.stringify({before,observed:JSON.parse(result.stdout)}));`;
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c',
        'ulimit -S -s 8192\nexec "$@"', 'proof-stack-test', process.execPath,
        '--input-type=module', '-e', program], {encoding: 'utf8', timeout: 10000});
      assert.equal(result.status, 0, result.stderr);
      const {before, observed} = JSON.parse(result.stdout);
      const hard = before.slice(before.indexOf(':') + 1);
      assert.equal(before, `8192:${hard}`);
      const expected = process.platform === 'linux' && target === 'native' ? 65536 : 8192;
      assert.equal(observed.limits, `${expected}:${hard}`);
      assert.deepEqual(observed.args, args.slice(1));
    }
    // The literal shell syntax above must remain an argument, never execute.
    assert.equal(existsSync(join(directory, 'forbidden')), false);
  });

test('proof stack wrapper preserves a real child failure and termination',
  {skip: process.platform === 'win32'}, async () => {
    const {spawnProofCommand} = await import('./native-command.mjs');
    const args = ['-c', 'exit 7', 'failure', '--target', 'native'];
    const failed = spawnProofCommand('bash', args, 'native', {encoding: 'utf8'});
    assert.equal(failed.status, 7);
    assert.equal(failed.signal, null);
    const stopped = spawnProofCommand('bash',
      ['-c', 'kill -TERM $$', 'termination', '--target', 'native'], 'native', {encoding: 'utf8'});
    assert.equal(stopped.status, null);
    assert.equal(stopped.signal, 'SIGTERM');
  });

test('Linux Native preparation refuses a mislabeled JS command',
  {skip: process.platform !== 'linux'}, async () => {
    const {spawnProofCommand} = await import('./native-command.mjs');
    assert.throws(() => spawnProofCommand('unused', ['test', '--target', 'js'],
      'native', {}), /explicit Native target/u);
  });
