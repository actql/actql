import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const [source, phase] = process.argv.slice(2);
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trim();
assert.equal(process.version, 'v22.22.0');
assert.equal(git('rev-parse', 'HEAD'), source);
assert.equal(git('status', '--porcelain'), '');
let steps;
if (phase === 'generate') {
  steps = [{name: 'Normal connector installation/import inventories',
    command: process.execPath, args: ['scripts/connector-node-bundles.mjs', '--write']}];
} else if (phase === 'prepare') {
  const bounded = 'import {spawnSync} from "node:child_process";' +
    'const r=spawnSync("moon",["build","--target","js","--release","-j","1",' +
    '"src/connectors_builtin_node","src/connectors/sheets/host_node",' +
    '"src/checkpoint_runtime_node"],' +
    '{stdio:"inherit",timeout:30000,killSignal:"SIGTERM"});' +
    'if(r.error)console.error(r.error.code);process.exitCode=r.status??1;';
  steps = [{name: 'Affected common, Sheets and existing Checkpoint runtime modules only',
    command: process.execPath, args: ['--input-type=module', '-e', bounded]}];
} else {
  assert(['node', 'host', 'aggregate', 'regression', 'freshness'].includes(phase));
  const focused = 'import{runFocusedTests}from"./scripts/test-execution.mjs";' +
    'process.exitCode=runFocusedTests("node",process.argv.slice(1),' +
    '{cwd:process.cwd(),timeout:30000});';
  const selections = {
    host: ['--test-name-pattern=^Sheets range Command',
      'adapters/connectors/sheets/test/sheets-standard-host.integration.test.mjs'],
    node: ['adapters/connectors/sheets/test/sheets-range-command.test.mjs',
      'adapters/host-common/captured-effect-dependency-schemas.test.mjs'],
    aggregate: ['--test-name-pattern=^(captured Effect|Sheets range (?!Command))',
      'adapters/connectors/sheets/test/sheets-standard-host.integration.test.mjs'],
    regression: ['--test-name-pattern=^Sheets Local append|^Sheets read uses',
      'adapters/connectors/sheets/test/sheets-standard-host.integration.test.mjs'],
  };
  steps = phase === 'freshness' ? [{name: 'Read-only normal connector inventory freshness',
    command: process.execPath, args: ['scripts/connector-node-bundles.mjs']}] : [
    {name: 'Installed range declaration, exact request and recovery controls',
    command: process.execPath, args: ['--input-type=module', '-e', focused, '--',
      ...selections[phase]]}];
}
steps.push({name: 'Whitespace', command: 'git', args: ['diff', '--check']});
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps});
assert.equal(git('rev-parse', 'HEAD'), source);
if (phase !== 'generate') assert.equal(git('status', '--porcelain'), '');
