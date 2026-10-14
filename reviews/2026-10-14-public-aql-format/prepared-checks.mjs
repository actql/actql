import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [source, selection] = process.argv.slice(2);
const git=(...args)=>execFileSync('git',args,{encoding:'utf8'}).trim();
assert.match(source,/^[a-f0-9]{40}$/u);assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
if (selection === 'validation') {
 process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:120,graceSeconds:5,steps:[
  {name:'Public AQL types, Python wire and generator freshness',command:process.execPath,args:['reviews/2026-10-14-public-aql-format/validate.mjs']},
 ]});
 assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
 process.exit(process.exitCode);
}
const choices={
 callers:['node',['--test','--test-name-pattern','^(?!.*short-query public types)','packages/client-wire/index.test.mjs','packages/client-wire/public-aql-format.test.mjs','packages/sdk/source-query.test.mjs','adapters/host-node/public-source-preparation.test.mjs','scripts/release-sourcefree-query-cases.test.mjs','scripts/generate-python-client-wire.test.mjs']],
 source:['moon',['--target','js','-j','1','src/source_frontend/lower_test.mbt']],
 node:['node',['--test','--test-name-pattern','public aql','packages/client-wire/public-aql-format.test.mjs','packages/sdk/source-query.test.mjs']],
 moon:['moon',['--target','js','-j','1','src/source_frontend/lower_test.mbt','--filter','*public aql spelling*']],
};
assert.ok(Object.hasOwn(choices,selection));
const [kind,args]=choices[selection];
const runner=`import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests(${JSON.stringify(kind)},${JSON.stringify(args)},{cwd:process.cwd(),timeout:90000});`;
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:120,graceSeconds:5,
 steps:[{name:`Public aql ${selection}`,command:process.execPath,args:['--input-type=module','-e',runner]}]});
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
