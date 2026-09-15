import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareRuntimeModules} from './moon-runtime.mjs';

const cwd = fileURLToPath(new URL('../../', import.meta.url));
function run(command, args) { execFileSync(command,args,{cwd,stdio:'inherit'}); }
run('node',['scripts/workers-composition.mjs']);
run('node',['scripts/workers-fixtures.mjs']);
run('moon',['build','--target','js','--release','src/connectors_workers_bridge']);
run('moon',['build','--target','js','--release','src/workers_conformance']);
prepareRuntimeModules();
run('node',['--test',
  'adapters/workers/runtime.test.mjs',
  'adapters/workers/moon-runtime.test.mjs',
  'adapters/workers/artifact.test.mjs',
  'adapters/workers/conformance.test.mjs',
]);
