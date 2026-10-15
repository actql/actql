import assert from 'node:assert/strict';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
const root = process.cwd();
const [phase, source] = process.argv.slice(2);
const before = checkoutState(root);
if (phase !== 'format') { assert(before.clean); assert.equal(before.revision, source); }
const format = `import {readFileSync,writeFileSync} from 'node:fs';import {execFileSync} from 'node:child_process';for(const p of ['src/run_publication_host/client_effect_imported_evidence.mbt','src/run_publication_host/client_effect_local_table_artifact.mbt','src/connectors_builtin_node/client_program_bridge.mbt'])writeFileSync(p,execFileSync(process.env.MOON_HOME+'/bin/moonfmt',['-'],{input:readFileSync(p),timeout:30000}));`;
const focus = `import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd(),timeout:30000});`;
const step = (name, command, args) => ({name, command, args});
const phases = {
  format: [step('Format changed Common and bridge source', process.execPath, ['--input-type=module','-e',format]), step('Generate existing RelA mirror', process.execPath, ['scripts/connector-node-bundles.mjs','--write'])],
  api: [step('Affected JS API generation', 'moon', ['info','--target','js','src/run_publication_host','src/connectors_builtin_node','src/connectors_builtin_node_rela'])],
  build: [step('Affected JS Node runtime', 'moon', ['build','--frozen','--target','js','--release','-j','1','src/connectors_builtin_node'])],
  regression: [step('Existing Result exports, exact producers and cleanup', process.execPath, ['--input-type=module','-e',focus,'--','--test-name-pattern=Effect source set shares exact owners|two Effect members hold|source-free Effect dependency retains|Effect sources retain exact physical producers|one acquired Effect Program captures','adapters/host-node/client-program-bridge.test.mjs'])],
  existing: [step('Existing captured Result lifetime and imported scope', process.execPath, ['--input-type=module','-e',focus,'--','--test-name-pattern=^(two Effect members hold|source-free Effect dependency retains|Effect sources retain exact physical producers)','adapters/host-node/client-program-bridge.test.mjs'])],
  freshness: [step('Existing Node and RelA assembly freshness', process.execPath, ['scripts/connector-node-bundles.mjs']), step('Whitespace', 'git', ['diff','--check'])],
  counter: [step('Private Table imported occurrence counter', process.execPath, ['--input-type=module','-e',focus,'--','--test-name-pattern=^(dependent private Table members retain|source-free private Table dependency control)','adapters/host-node/table-dependent-input.test.mjs'])],
};
assert(Object.hasOwn(phases, phase));
process.exitCode = await runLocalCheck({root, heavy:phase==='build', timeoutSeconds:phase==='build'?180:60, graceSeconds:5,
  ...(phase==='build'?{heavyResources:{memoryBytes:2147483648,diskBytes:2147483648,cpuThreads:1}}:{}), steps:phases[phase]});
if (!['format','api'].includes(phase)) assert.deepEqual(checkoutState(root),before);
