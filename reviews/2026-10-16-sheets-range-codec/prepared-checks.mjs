import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, phase] = process.argv.slice(2);
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(process.version, 'v22.22.0');
assert.equal(git('rev-parse', 'HEAD'), source);
const before = git('status', '--porcelain');
const files = ['src/connectors/sheets/catalog/cells.mbt',
  'src/connectors/sheets/catalog/update_wbtest.mbt',
  'src/connectors/sheets/host_node/bridge.mbt',
  'src/connectors/sheets/host_node/update_wbtest.mbt'];
let steps;
if (phase === 'prepare') {
  steps = files.map(file => ({name: `Pinned formatter: ${file}`,
    command: 'moonfmt', args: ['-w', file]}));
  steps.push({name: 'Generate affected Sheets interfaces', command: 'moon',
    args: ['info', '--target', 'js', 'src/connectors/sheets/catalog',
      'src/connectors/sheets/host_node']});
} else {
  assert.equal(before, '');
  if (phase === 'test') {
    const run = 'import {runFocusedTests} from "./scripts/test-execution.mjs";' +
      'process.exitCode=runFocusedTests("moon",process.argv.slice(1),' +
      '{cwd:process.cwd(),timeout:30000});';
    steps = [{name: 'Original Sheets and bounded overwrite codec controls',
      command: process.execPath, args: ['--input-type=module', '-e', run, '--',
        '--target', 'js', '-j', '1', 'src/connectors/sheets/catalog',
        'src/connectors/sheets/host_node']}];
  } else {
    assert(['wasm', 'native'].includes(phase));
    steps = [{name: `Portable Sheets codec consuming check: ${phase}`,
      command: 'moon', args: ['check', '--target', phase, '-j', '1',
        'src/connectors/sheets/catalog']}];
  }
}
steps.push({name: 'Whitespace', command: 'git', args: ['diff', '--check']});
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps});
assert.equal(git('rev-parse', 'HEAD'), source);
if (phase !== 'prepare') assert.equal(git('status', '--porcelain'), before);
