import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const generators=['compilation-manifests','row-watermark-identity-oracle','update-document-metadata','check-actql-spec-family','check-canonical-json'];
const steps=process.argv.includes('--normative-write')
  ? generators.map(name=>({name:'Existing generator or independent oracle '+name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : process.argv.includes('--inventory-write')
  ? [{name:'Independent declared public inventory',command:'node',args:['--input-type=module','-e',`import{readFileSync,writeFileSync}from'node:fs';import{registeredPublicQueryInventory}from'./scripts/public-query-inventory.mjs';const path='scripts/fixtures/public-query-inventory.json';const old=JSON.parse(readFileSync(path,'utf8'));const actual=await registeredPublicQueryInventory();writeFileSync(path,JSON.stringify({...old,...actual},null,2)+'\\n');console.log(JSON.stringify(actual));`]}]
  : process.argv.includes('--format')
  ? [{name:'Pinned authored-file formatting',command:'node',args:['--input-type=module','-e',`import{execFileSync}from'node:child_process';import{writeFileSync}from'node:fs';for(const path of process.argv.slice(1))writeFileSync(path,execFileSync('moonfmt',[path],{maxBuffer:4194304}));`,'src/query_program/row_watermark_source_test.mbt','src/query_program/query_script_carriers.mbt','src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt']}]
  : [{name:'Independent row watermark control and source connection',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/row_watermark_source_test.mbt']}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
