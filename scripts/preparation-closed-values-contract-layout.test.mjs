import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>readFile(path.join(root,'src',p),'utf8');
async function fields(file,name) {
  const source=await read(file);
  const body=source.match(new RegExp(`struct ${name} \\{([\\s\\S]*?)^\\}`,'m'))?.[1];
  assert.ok(body,name);
  return [...body.matchAll(/^\s*(?:mut\s+)?([a-z_]+)\s*:/gm)].map(m=>m[1]);
}
test('contract envelope follows original retained and builder fields',async()=>{
  assert.deepEqual(await fields('pipeline_check_context/core_contracts.mbt','CoreContractInventory'),[
    'identity','roots','bodies','sources','profile_checks','numeric_slots','analytic_numeric_slots',
    'pivot_numeric_slots','incoming','stages','work','edges','hash_bytes','hash_nodes']);
  assert.deepEqual(await fields('pipeline_check_context/core_contracts.mbt','CoreContractBuilder'),[
    'limits','roots','bodies','seen','dependencies','work','edges','hash_limits','hash_bytes','hash_nodes']);
  assert.deepEqual(await fields('pipeline_check_context/core_contracts.mbt','CoreContractDependencies'),['targets','seen']);
  assert.deepEqual(await fields('pipeline_check_context/core_contracts.mbt','CoreContractRoot'),['site','body']);
});
test('contract closure remains iterative and enum payload depth remains bounded',async()=>{
  const stages=await read('pipeline_check_context/core_contract_stages.mbt');
  assert.match(stages,/while cursor < stage.targets.length\(\)/);
  const dependencies=await read('pipeline_check_context/core_contract_shared.mbt');
  assert.match(dependencies,/while index < b.bodies.length\(\)/);
  const expression=await read('check_environment/expression_dependencies.mbt');
  const body=expression.match(/enum ExpressionContractBody \{([\s\S]*?)\}/)[1];
  assert.deepEqual(body.trim().split('\n').map(x=>x.trim()),[
    'ExpressionRoot','RegexRepresentation','RegexRepresentationSchema','ConsumerCapacity','Inherited(InheritedTextTimeContract)']);
  const catalog=await read('check_environment/catalog_grammar.mbt');
  assert.match(catalog,/ExpressionGrammar\(ExpressionContractBody\)/);
});
