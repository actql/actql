import assert from 'node:assert/strict';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const args=process.argv.slice(2);assert.ok(args.length<=1&&args.every(x=>['--before','--info'].includes(x)));
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const focused=(name,command,selection)=>({name,command:'node',args:['--input-type=module','-e',runner,command,...selection]});
const profile=focused('Existing WITH cutover retirement assertions','node',['scripts/frontend-profile.test.mjs']);
const steps=args.includes('--before')?[profile]:args.includes('--info')?
[{name:'Generate the current syntax interface using the pinned compiler',command:'moon',args:['info','--target','js','src/query_syntax']}]:[
 focused('Existing lexical decoding, value and Origin callers','moon',['--target','js',
 'src/query_syntax/lexer_test.mbt','src/query_syntax/string_literals_test.mbt',
 'src/query_syntax/literal_forms_test.mbt','src/query_syntax/json_literals_test.mbt',
 'src/query_syntax/quoted_source_alias_test.mbt',
 'src/query_syntax/quoted_aggregate_test.mbt','src/query_syntax/quoted_qualify_test.mbt',
 'src/query_syntax/file_glob_origin_test.mbt']),profile,
 {name:'Whitespace check',command:'git',args:['diff','--check']},
];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
