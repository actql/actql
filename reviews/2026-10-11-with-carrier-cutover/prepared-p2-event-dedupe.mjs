import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_syntax/event_dedupe_call_test.mbt','src/query_program/event_dedupe_source_test.mbt'];
const product=['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_program/query_script_carriers.mbt','src/query_program/query_script_inputs.mbt','src/query_program/traversal_nodes_program.mbt'];
const generators=['compilation-manifests','event-dedupe-identity-oracle','update-document-metadata','check-actql-spec-family','check-canonical-json'];
const steps=process.argv.includes('--inventory-write')
  ? [{name:'Independent declared public inventory only',command:'node',args:['--input-type=module','-e',`import{readFileSync,writeFileSync}from'node:fs';import{registeredPublicQueryInventory}from'./scripts/public-query-inventory.mjs';const path='scripts/fixtures/public-query-inventory.json';const old=JSON.parse(readFileSync(path,'utf8'));const actual=await registeredPublicQueryInventory();writeFileSync(path,JSON.stringify({...old,...actual},null,2)+'\\n');console.log(JSON.stringify(actual));`]}]
  : process.argv.includes('--normative-write')
  ? generators.map(name=>({name:'Existing generator or independent oracle '+name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : process.argv.includes('--info')
  ? [{name:'Generate affected syntax interface',command:'moon',args:['info','--target','js','src/query_syntax']}]
  : process.argv.includes('--format')
  ? [{name:'Format authored dedupe controls',command:'moon',args:['fmt',...product,...files]}]
  : [{name:'Independent event dedupe controls and source counterexamples',command:'node',args:[
    '--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
