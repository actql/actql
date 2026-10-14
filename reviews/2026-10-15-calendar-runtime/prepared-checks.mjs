import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source = process.argv[2];
assert.match(source, /^[a-f0-9]{40}$/u);
const git = (...args) => execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);
assert.equal(git('status','--porcelain'),'');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests("moon",["--target","js","-j","1","src/calendar_transition"],{cwd:process.cwd(),timeout:240000});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:270,graceSeconds:5,steps:[{
    name:'Original offset-table inverse and transition admission controls',
    command:process.execPath,args:['--input-type=module','-e',runner],
  }]});
assert.equal(git('rev-parse','HEAD'),source);
assert.equal(git('status','--porcelain'),'');
