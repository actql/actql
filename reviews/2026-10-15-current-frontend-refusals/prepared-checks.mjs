import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2];
assert.match(source,/^[a-f0-9]{40}$/u);
const git=(...args)=>execFileSync('git',args,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);
assert.equal(git('status','--porcelain'),'');
const filter=process.argv[3];
assert.equal(typeof filter,'string');assert(filter!==''&&filter!=='*');
const target=process.argv[4]??'js';assert(['js','wasm'].includes(target));
const args=['--target',target,'-j','1',...(filter==='files'?
  ['src/query_program/composition_controls_test.mbt','src/query_program/carrier_peer_scope_test.mbt']:
  ['src/query_program','--filter',filter])];
const code=`import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('moon',${JSON.stringify(args)},{cwd:process.cwd(),timeout:240000});`;
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:270,graceSeconds:5,
  steps:[{name:'Current Frontend typed refusal control',command:process.execPath,args:['--input-type=module','-e',code]}]});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
