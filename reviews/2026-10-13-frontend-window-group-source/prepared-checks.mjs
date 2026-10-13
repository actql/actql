import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const command=(name,kind,args)=>({name,command:'node',args:['--input-type=module','-e',runner,kind,...args]});
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
 command('Window expressions common aggregates and original Sequence consumers','moon',['--target','js','src/query_syntax/window_group_expression_test.mbt','src/query_syntax/sequence_predicate_test.mbt','src/query_syntax/sga_output_name_test.mbt','src/query_syntax/sga_role_contract_test.mbt','src/query_program/window_group_source_test.mbt','src/query_program/sequence_source_test.mbt','src/query_program/sga_output_name_lowering_test.mbt']),
 command('Independent registered window matrix and containing Run identities','node',['scripts/window-group-source-input.test.mjs','scripts/sequence-source-input.test.mjs','scripts/sequence-identity.test.mjs','scripts/compilation-manifests.test.mjs','scripts/public-query-profiles.test.mjs','scripts/client-values-run-materials-vector.test.mjs']),
 ...['scripts/compilation-manifests.mjs','scripts/update-document-metadata.mjs','scripts/check-actql-spec-family.mjs','scripts/check-canonical-json.mjs'].map(path=>({name:'Read-only freshness '+path,command:'node',args:[path]})),
 {name:'Whitespace integrity',command:'git',args:['diff','--check']},
]});
