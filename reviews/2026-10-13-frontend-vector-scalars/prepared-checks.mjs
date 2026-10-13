import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const focused=(name,target,args)=>({name,command:'node',args:['--input-type=module','-e',runner,target,...args]});
const remaining=process.argv.slice(2).includes('--remaining');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
  ...(remaining?[]:[focused('Vector scalar source, registry and existing reuse identity controls','moon',['--target','js','src/query_expression/vector_scalars_test.mbt','src/query_expression/scalar_function_identity_test.mbt','src/query_program/vector_scalar_source_test.mbt']),
  focused('Independent vector scalar fixtures and grammar-bound preimages','node',['scripts/vector-scalar-source.test.mjs','scripts/vector-scalar-identity.test.mjs','scripts/frontend-profile.test.mjs','scripts/compilation-manifests.test.mjs'])]),
  ...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json'].map(name=>({name:'Read-only '+name,command:'node',args:['scripts/'+name+'.mjs']})),
  {name:'Whitespace check',command:'git',args:['diff','--check']},
]});
