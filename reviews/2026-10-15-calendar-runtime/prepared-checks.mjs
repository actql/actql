import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source = process.argv[2];
const mode = process.argv[3] ?? 'transition';
assert(['transition', 'laws', 'api', 'lowering', 'ranges', 'lowering-api', 'registration', 'freshness'].includes(mode));
assert.match(source, /^[a-f0-9]{40}$/u);
const git = (...args) => execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);
assert.equal(git('status','--porcelain'),'');
const selected = mode === 'laws' ? 'src/calendar_profile' :
  mode === 'lowering' ? 'src/lowering_relation' : 'src/calendar_transition';
const args = ['--target','js','-j','1',
  ...(mode === 'ranges' ? ['src/calendar_options/range_test.mbt',
    'src/pipeline_check_context/operation_ranges_test.mbt'] : [selected]),
  ...(mode === 'lowering' ? ['--filter','*Calendar*'] : [])];
const runner = `import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const steps = mode === 'registration' ? [{
  name: 'Calendar and retained pipeline registration Node controls',
  command: process.execPath, args: ['--input-type=module', '-e',
    "import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',['scripts/calendar-registration.test.mjs','scripts/pipeline-registry.test.mjs'],{cwd:process.cwd(),timeout:30000});"],
}] : mode === 'freshness' ? [
  'calendar-registration.mjs', 'update-document-metadata.mjs',
  'check-actql-spec-family.mjs', 'check-canonical-json.mjs',
  'check-owned-contract-versions.mjs',
].map(file => ({name: `Read-only ${file}`, command: process.execPath,
  args: [`scripts/${file}`]})) : mode === 'lowering-api' ? ['js', 'wasm', 'native'].map(target => ({
  name: `Calendar lowering and affected consuming API (${target})`, command: 'moon',
  args: ['info', '--target', target, 'src/lowering_relation', 'src/calendar_options',
    'src/pipeline_check_context', 'src/execution_relation', 'src/connectors/local'],
})) : mode === 'api' ? ['js', 'wasm', 'native'].map(target => ({
  name: `Calendar transition/profile consuming API (${target})`, command: 'moon',
  args: ['info', '--target', target, 'src/calendar_transition', 'src/calendar_profile'],
})) : [{ name: `Calendar ${mode} independent bounded controls`,
  command:process.execPath,args:['--input-type=module','-e',runner] }];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:['registration','freshness'].includes(mode) ? 60 : 270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);
if (!['api', 'lowering-api'].includes(mode)) assert.equal(git('status','--porcelain'),'');
