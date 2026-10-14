import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source = process.argv[2];
const mode = process.argv[3] ?? 'transition';
assert(['transition', 'laws', 'api', 'lowering'].includes(mode));
assert.match(source, /^[a-f0-9]{40}$/u);
const git = (...args) => execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);
assert.equal(git('status','--porcelain'),'');
const selected = mode === 'laws' ? 'src/calendar_profile' :
  mode === 'lowering' ? 'src/lowering_relation' : 'src/calendar_transition';
const args = ['--target','js','-j','1',selected,
  ...(mode === 'lowering' ? ['--filter','selected original UTC Calendar series reaches normal lowering'] : [])];
const runner = `import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
const steps = mode === 'api' ? ['js', 'wasm', 'native'].map(target => ({
  name: `Calendar transition/profile consuming API (${target})`, command: 'moon',
  args: ['info', '--target', target, 'src/calendar_transition', 'src/calendar_profile'],
})) : [{ name: `Calendar ${mode} independent bounded controls`,
  command:process.execPath,args:['--input-type=module','-e',runner] }];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:270,graceSeconds:5,steps});
assert.equal(git('rev-parse','HEAD'),source);
if (mode !== 'api') assert.equal(git('status','--porcelain'),'');
