import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>readFile(path.join(root,'src',p),'utf8');
async function fields(file,name){
  const body=(await read(file)).match(new RegExp(`struct ${name} \\{([\\s\\S]*?)^\\}`,'m'))?.[1];
  assert.ok(body,name);
  return [...body.matchAll(/^\s*(?:mut\s+)?([a-z_]+)\s*:/gm)].map(m=>m[1]);
}
test('arithmetic graph envelope guards original copied and linked owner fields',async()=>{
  for(const [file,name,expected] of [
    ['capacity_witness/closure.mbt','ArithmeticClaims',['witnesses','graph','references']],
    ['capacity_derivation/references.mbt','LinkedArithmetic',['arithmetic','identities','indices']],
    ['capacity_derivation/graph.mbt','CheckedArithmetic',['values','units','leaves','edges']],
    ['capacity_witness/mixed_closure.mbt','MixedClaims',['arithmetic','limits','bound','references','bytes','nodes']],
    ['capacity_witness/program_closure.mbt','ProgramClaims',['claims','mixed','proofs','references']],
    ['capacity_host_witness/claims.mbt','HostSources',['claims','sources','count','bytes','nodes','origin','dependencies','local_claims','local_limits']],
  ])assert.deepEqual(await fields(file,name),expected,name);
  assert.match(await read('capacity_witness/closure.mbt'),/witnesses: witnesses.copy\(\)/);
});
test('coverage envelope guards source-free graph and bound application ownership',async()=>{
  for(const [file,name,expected] of [
    ['capacity_graph_input/check.mbt','GraphInputs',['pipeline','sources','policy','bindings','witnesses','work','names','remaining','dependencies']],
    ['capacity_program_step/collection.mbt','Applications',['claims','entries','remaining','work','producers','input_usage','operand_usage']],
    ['capacity_graph_preflight/application_closure.mbt','ApplicationClosure',['orders','entries','policy','guards','bound_applications','proof_owners','input_owners','work']],
    ['pipeline_typing/bound_guard_closure.mbt','BoundGuardClosure',['closure','entries','work','text']],
    ['pipeline_typing/bound_guards.mbt','BoundAuthorGuards',['occurrences','bindings','values','work','text']],
  ])assert.deepEqual(await fields(file,name),expected,name);
  assert.equal((await read('capacity_graph_preflight/prepare.mbt')).match(/@input.check\(/g).length,1);
});
