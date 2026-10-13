import assert from 'node:assert/strict';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const args=process.argv.slice(2);assert.ok(args.length<=1&&args.every(x=>x==='--focused'));
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const focused=(name,command,selection)=>({name,command:'node',args:['--input-type=module','-e',runner,command,...selection]});
const steps=[focused('Canonical literal score and unchanged alias/type/reuse controls','moon',['--target','js',
 'src/query_expression/vector_score_literal_test.mbt','src/query_program/vector_score_literal_source_test.mbt',
 'src/query_expression/vector_scalars_test.mbt','src/query_expression/scalar_function_identity_test.mbt',
 'src/query_program/vector_scalar_source_test.mbt']),
 ...(!args.includes('--focused')?[focused('Independent score/alias source and full identity vectors','node',[
 'scripts/vector-score-literal-source.test.mjs','scripts/vector-scalar-source.test.mjs',
 'scripts/vector-scalar-identity.test.mjs','scripts/compilation-manifests.test.mjs']),
 ...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json'].map(name=>({name:'Read-only '+name,command:'node',args:['scripts/'+name+'.mjs']}))]:[]),
 {name:'Whitespace check',command:'git',args:['diff','--check']}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
