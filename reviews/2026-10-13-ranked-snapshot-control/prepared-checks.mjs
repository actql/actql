import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode=process.argv[2]??'--focused';
let steps;
if(mode==='--format') {
  steps=['src/query_program/ranking_scored_snapshot_test.mbt','src/query_program/query_script_carriers.mbt'].map(file=>({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else if(mode==='--focused') {
  steps=[{name:'Catalog score evidence through the ordinary JSON and text checkers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/ranking_scored_snapshot_test.mbt']}];
} else if(mode==='--final') {
  steps=[{name:'Scored Catalog, raw-score refusals and existing peer binding callers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/ranking_scored_snapshot_test.mbt','src/query_program/ranking_fusion_source_test.mbt','src/query_program/carrier_peer_scope_test.mbt','src/query_program/temporal_join_source_test.mbt']},{name:'Independent snapshot preimages and declared score expectations',command:'node',args:['--input-type=module','-e',runner,'node','scripts/ranking-scored-snapshot.test.mjs']},{name:'Whitespace',command:'git',args:['diff','--check']}];
} else if(mode==='--refusals') {
  steps=[{name:'Keep the existing raw-score and repeated-operand controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/ranking_fusion_source_test.mbt']}];
} else {
  throw new Error(`Unknown mode ${mode}`);
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
