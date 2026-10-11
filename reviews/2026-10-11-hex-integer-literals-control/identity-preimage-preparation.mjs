// Data preparation using the independent normative-preimage oracle only.
// No test registration, installed compiler, evaluator or runtime is executed.
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {valuesDependencyOracle, valuesProgramOracle} from '../../scripts/client-values-dependency-oracle.mjs';
const path='scripts/client-values-run-materials-vector.test.mjs';
const source=readFileSync(path,'utf8');
const fragment=(start,end)=>source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start)));
const declarations=fragment('const canonical =','test(\'merged Frontend')+
 fragment('const policy =','test(\'Values bridge')+
 fragment('const ceiling =','test(\'baseline preimages');
const grammar=JSON.parse(readFileSync(process.argv[3] ?? 'spec/manifests/actql-grammar-0.1.json'));
const aoa=JSON.parse(readFileSync('spec/contracts/actql-aoa.json'));
const barrier=JSON.parse(readFileSync('spec/manifests/actql-barrier-contracts-0.1.json'));
const body=`${declarations}\nconst deps=valuesDependencyOracle(), identity=valuesProgramOracle();
result={source_revision:recordedRevision, source_baseline:'599f487bbb0be365320706ad28eab972448ed75d', prepared:recordedRevision === null, grammar,
  aoa_contract_cid:cid(aoa),barrier_contract_manifest_cid:barrierInput.barrier_contract_manifest_cid,
  values_dependencies:deps,program_identity:identity,
  run_preimages:vector(grammar.grammar_manifest_cid,cid(aoa),deps,
    barrierInput.barrier_contract_manifest_cid,identity,{canonicalCandidates:true})};`;
const sandbox={createHash,readFileSync,assert,valuesDependencyOracle,valuesProgramOracle,
  grammar,aoa,barrierInput:barrier,recordedRevision:process.argv[4] ?? null,result:null};
vm.runInNewContext(body,sandbox,{timeout:10000});
const result=JSON.parse(JSON.stringify(sandbox.result));
const dest=process.argv[2];
if(dest)writeFileSync(dest,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({template:result.run_preimages.template.bound_invocation_template_cid,
 executable:result.run_preimages.executable.executable_plan_cid,
 compiled:result.run_preimages.compiled.compiled_plan_cid,
 run:result.run_preimages.run.run_definition_cid}));
