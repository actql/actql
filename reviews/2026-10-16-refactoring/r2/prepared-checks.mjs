import {fileURLToPath} from 'node:url';
import {runLocalCheck} from '../../../scripts/local-checks-guard.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const selection = process.argv.slice(2);
if (selection.length !== 1 || !['boundaries', 'mutations', 'graph'].includes(selection[0])) {
  throw new Error('Select boundaries, mutations or graph');
}
const tests = selection[0] === 'boundaries' ? [
  'scripts/query-dependency-boundary.test.mjs',
  'adapters/host-common/sqlite-transaction.test.mjs',
  'adapters/host-node/completion-custody.test.mjs',
] : selection[0] === 'mutations'
  ? ['reviews/2026-10-16-refactoring/r2/mutation-controls.test.mjs']
  : ['--test-name-pattern',
    'actual adapter import closure|packaging retains|common serial adapter closure|connector host manifests generate',
    'scripts/query-dependency-boundary.test.mjs'];
process.exitCode = await runLocalCheck({root, heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps: [{name: `R2 ${selection[0]}`,
    command: process.execPath, args: ['--input-type=module', '-e',
      'import {runFocusedTests} from "./scripts/test-execution.mjs"; ' +
      'process.exitCode=runFocusedTests("node",process.argv.slice(1),' +
      '{cwd:process.cwd(),timeout:30000});', '--', ...tests]}]});
