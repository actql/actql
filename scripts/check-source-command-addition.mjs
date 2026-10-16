// Compose the existing independent connector's real owners with bounded
// discovery/refusal, approval, actual storage and same-Run recovery probes.
// The third-Compute checker remains a separate acceptance, not replaced here.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runFocusedTests} from './test-execution.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const selection = process.argv[2] ?? '--scope=all';
assert.ok(['--scope=all', '--scope=admission', '--scope=physical'].includes(selection));
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
assert.equal(git(['status', '--porcelain']), '', 'addition acceptance requires fixed clean source');
const source = git(['rev-parse', 'HEAD']);
const digests = () => {
  const result = [];
  const visit = path => {
    for (const entry of readdirSync(join(root, path), {withFileTypes: true})) {
      const file = `${path}/${entry.name}`;
      if (entry.isDirectory()) visit(file);
      else if (entry.isFile()) result.push([file,
        createHash('sha256').update(readFileSync(join(root, file))).digest('hex')]);
    }
  };
  visit('src');
  // These are the original shared execution/authorization/recovery owners;
  // the independent connector is supplied through their existing table port.
  for (const file of ['installed-row-source.mjs', 'installed-row-effect.mjs',
    'installed-connectors.mjs', 'effect-ledger.mjs', 'client-checkpoints.mjs']) {
    const path = `adapters/host-node/${file}`;
    result.push([path, createHash('sha256').update(readFileSync(join(root, path))).digest('hex')]);
  }
  return result.sort(([left], [right]) => left.localeCompare(right));
};
const before = digests();
const probes = [
  ['Explicit independent Source/Command and source capture',
    ['scripts/independent-source-command-addition.test.mjs']],
  ['Original Command selector, MIME, unknown and incomplete-driver refusals',
    ['adapters/host-node/installed-content-command-plan.test.mjs']],
  ['Independent installed Local Source -> approval -> physical Command',
    ['--test-name-pattern=^public Local program Content COMMAND waits for approval and physically stores the approved bytes$',
      'adapters/host-node/installed-content-command-public.test.mjs']],
  ['Original independent Command lost reply remains Unknown across three processes',
    ['--test-name-pattern=^public Local Content COMMAND lost reply remains unknown after process recovery without resend$',
      'adapters/host-node/installed-content-command-restart.test.mjs']],
];
const selected = selection === '--scope=all' ? probes
  : selection === '--scope=admission' ? probes.slice(0, 2) : probes.slice(2);
for (const [name, args] of selected) {
  console.log(JSON.stringify({source, name, qualification: 'actual Common owners; independent explicit fixture connector; source consumer, not packed distribution'}));
  const status = runFocusedTests('node', args, {cwd: root, timeout: 60000});
  assert.equal(status, 0, name);
}
assert.equal(git(['rev-parse', 'HEAD']), source);
assert.equal(git(['status', '--porcelain']), '');
assert.deepEqual(digests(), before, 'the addition changes no Common implementation or execution authority');
console.log(JSON.stringify({source, unchangedCommonInputs: before.length,
  independentSourceCommand: selection, thirdCompute: 'separate check-connector-addition.mjs evidence required',
  installedDistribution: 'not established by this source-only acceptance'}));
