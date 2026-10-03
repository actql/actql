// Fixed four-stage DuckDB fixture, derived from normative dependency preimages.
// No compiler, generated runtime, issuer or product Plan is consulted here.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {canonicalText} from './check-canonical-json.mjs';
import {relationFixtureContracts} from './client-values-dependency-oracle.mjs';

const hash = body => 'sha256:' + createHash('sha256')
  .update(canonicalText(body)).digest('hex');
const read = file => JSON.parse(readFileSync(new URL('../'+file,import.meta.url),'utf8'));
const rowContract = 'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c';
const valueContract = 'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d';

export function tasksDependencyOracle({legacy=false}={}) {
  const program = read('adapters/connectors/duckdb/node/examples/program.json');
  const environment = read('adapters/host-node/fixtures/query-amount-environment.json');
  const units = [];
  const gates = [];
  const imports = [];
  for (const [index,stage] of program.stages.entries()) {
    const acquired = index === 0;
    const declarations = acquired ? {minimum:program.params.minimum} : {};
    // These expressions are authored from the fixture's meaning, not parsed
    // by the compiler being tested. Keep the source spellings checked below.
    const expectedText = ['id > $minimum','id > 2','id > 0','id < 9'][index];
    if (stage.steps[0].filter !== expectedText) throw new Error('Tasks oracle fixture changed');
    const expression = {[index === 3 ? 'lt' : 'gt']:[{field:'id'},
      acquired ? {$param:'minimum'} : {literal:[null,2,0,9][index]}]};
    const local = {version:'actql-stage-semantics/0.1',binding_references:[],bindings:{},
      parameter_references:acquired ? [{name:'minimum',path:'/steps/0/filter/gt/1',
        type:declarations.minimum}] : [],parameters:declarations,
      expression_contract_cid:hash(read('spec/contracts/actql-expressions.json')),
      local_body:{effects:{},inputs:stage.inputs,results:stage.results,
        steps:[{...stage.steps[0],filter:expression},stage.steps[1]]}};
    const contracts = relationFixtureContracts({legacy,acquired});
    const gateCids = [];
    const importCids = [];
    if (acquired) {
      // Catalog contract envelopes are independently supplied fixture inputs.
      contracts.push(...environment.connector_catalogs[0].contracts.map(contract=>contract.cid));
    } else {
      const producer = stage.inputs.x.result.stage;
      importCids.push(hash({version:'actql-result-import-interface/0.1',
        availability:'stage_success',input_name:'x',producer_namespace:{
          node_id:producer,program_id:program.id},producer_result:'r',
        producer_unit_definition_cid:units[program.stages.findIndex(s=>s.id===producer)],
        value_contract_cid:rowContract}));
      // Omitted `after` is completion of the immediately preceding stage,
      // not completion of whichever stage supplies this Result input.
      gateCids.push(hash({version:'actql-graph-success-requirement/0.1',
        completion_contracts:{},completion_nodes:{},effect_contracts:{},effect_nodes:{},
        empty_items:'require-successful-computation-and-preflight',milestone:'completed',
        producer_node_id:program.stages[index-1].id}));
    }
    units.push(hash({version:'actql-local-unit-dependencies/0.1',
      import_interface_cids:importCids,incoming_gate_contract_cids:gateCids,
      local_body_cid:hash(local),used_parameter_declarations_cid:hash(declarations),
      local_contract_closure_cid:hash({version:'actql-local-contracts/0.1',contracts:contracts.sort()}),
      unit_namespace:{node_id:stage.id,program_id:program.id}}));
    gates.push(...gateCids);
    imports.push(...importCids);
  }
  const resultPlans = Object.fromEntries(Object.entries(program.results).map(([name,result])=>{
    const index = program.stages.findIndex(stage=>stage.id===result.from.stage);
    return [name,hash({version:'actql-result-plan/0.1',order:{strategy:'inherited',terms:[]},
      projection:[{input:'id',output:'id',value_contract_cid:valueContract}],
      result_name:name,unit_definition_cid:units[index],unit_result_name:'r',unit_result_ordinal:0,
      typed_output_port:{carrier:'relation',name:'r',row_contract_cid:rowContract}})];
  }));
  return {units,gates,imports,resultPlans};
}
