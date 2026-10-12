import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_syntax/event_dedupe_call_test.mbt','src/query_program/event_dedupe_source_test.mbt'];
const product=['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_program/query_script_carriers.mbt','src/query_program/query_script_inputs.mbt','src/query_program/traversal_nodes_program.mbt'];
const generators=['compilation-manifests','event-dedupe-identity-oracle','update-document-metadata','check-actql-spec-family','check-canonical-json'];
const steps=process.argv.includes('--fixture-only')
  ? [{name:'Current and immutable refusal fixture policies',command:'node',args:['--input-type=module','-e',runner,'node','scripts/graph-refusal-classification-source-input.test.mjs','scripts/public-query-refusal-classifications.test.mjs','scripts/event-dedupe-source.test.mjs']} ]
  : process.argv.includes('--inventory-write')
  ? [{name:'Independent declared public inventory only',command:'node',args:['--input-type=module','-e',`import{readFileSync,writeFileSync}from'node:fs';import{registeredPublicQueryInventory}from'./scripts/public-query-inventory.mjs';const path='scripts/fixtures/public-query-inventory.json';const old=JSON.parse(readFileSync(path,'utf8'));const actual=await registeredPublicQueryInventory();writeFileSync(path,JSON.stringify({...old,...actual},null,2)+'\\n');console.log(JSON.stringify(actual));`]}]
  : process.argv.includes('--normative-write')
  ? generators.map(name=>({name:'Existing generator or independent oracle '+name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : process.argv.includes('--info')
  ? [{name:'Generate affected syntax interface',command:'moon',args:['info','--target','js','src/query_syntax']}]
  : process.argv.includes('--format')
  ? [{name:'Format authored dedupe controls',command:'moon',args:['fmt',...product,...files]}]
  : [{name:'Independent dedupe and affected Carrier callers',command:'node',args:[
    '--input-type=module','-e',runner,'moon','--target','js',...files,
    'src/query_program/event_window_source_test.mbt','src/query_program/with_vectors_events_test.mbt',
    'src/query_program/vector_pool_source_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']},
    {name:'Current grammar canonical consumer',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
      'src/canonical_json/identity_vectors.generated_test.mbt','--filter','contract spec/manifests/actql-grammar-0.1.json#']},
    {name:'Independent dedupe public fixtures and retained identity history',command:'node',args:[
      '--input-type=module','-e',runner,'node','scripts/event-dedupe-source.test.mjs',
      'scripts/event-dedupe-identity.test.mjs','scripts/event-window-identity.test.mjs',
      'scripts/vector-pool-identity.test.mjs','scripts/sga-signature-role-identity.test.mjs',
      'scripts/client-values-run-materials-vector.test.mjs','scripts/compilation-manifests.test.mjs',
      'scripts/frontend-profile.test.mjs','scripts/public-query-profiles.test.mjs']},
    ...generators.filter(name=>name!=='event-dedupe-identity-oracle').map(name=>({name:'Read-only '+name,command:'node',args:['scripts/'+name+'.mjs']})),
    {name:'Read-only changed authored MoonBit formatting',command:'moon',args:['fmt','--check',...product,...files,
      'src/run_publication_host/client_values_run_materials_wbtest.mbt']},
    {name:'Product and specification whitespace',command:'git',args:['diff','--check','26521e7d8','HEAD','--','.',':(exclude)reviews/**']}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
