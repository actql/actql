import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';
import {admitEnvironment, prepare, compileValues, issueAllowedRun,
  issueSourceFreeRunDefinition, issueSourceFreeRunMaterials, privateRunDefinition} from '../index.mjs';

const read = path => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8').trimEnd();
const contract = JSON.parse(read('spec/contracts/actql-aoa.json'));
const environmentWire = read('packages/sdk/fixtures/values.environment.json');
const environmentCid = JSON.parse(environmentWire).evidence_bundle_cid;
export const finiteNumericProfileCid = 'sha256:' + createHash('sha256').update(
  canonicalText(JSON.parse(read('spec/contracts/actql-numeric-reduction.json')))).digest('hex');

// Test installation budgets and normative contract bytes, not expected results
// derived from the product. No conformance issuer crosses the package boundary.
export function finiteExpressionConfiguration() {
  const values = {max_nodes: 10000, max_text_bytes: 10000, max_depth: 100, max_work: 100000};
  return {
    environment: {wire: environmentWire, cid: environmentCid,
      expressions: {text_time: false, veca: false},
      operations: {rela: true, sga: false, tea: false, calendar: false, text_rank: false}},
    contracts: {registry: canonicalText(JSON.parse(read(contract.pipeline_registry_file))),
      values: canonicalText(contract.execution_contracts['REL.values']),
      grammar: canonicalText(JSON.parse(read('spec/manifests/actql-grammar-0.1.json'))),
      barriers: canonicalText(JSON.parse(read('spec/manifests/actql-barrier-contracts-0.1.json')))},
    fragments: {contract: canonicalText(contract.execution_contracts['ACTQL.expression_fragment/0.1']),
      ordered: canonicalText(contract.execution_contracts['REL.derive.ordered']),
      limits: {
        roots: {max_roots: 100, max_pointer_bytes: 10000, max_work: 100000},
        demands: {max_roots: 100, max_nodes: 10000, max_work: 100000,
          max_text_bytes: 10000, max_links: 10000},
        physical: {max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100},
        logical: {max_input_rows: 100n, max_value_bytes: 10000n,
          max_live_value_bytes: 100000n, max_work: 10000000n},
        max_input_rows: 100n, max_value_bytes: 10000n}},
    sequence: {max_steps: 10, max_rows: 100, max_cells: 1000,
      max_bindings: 10, max_name_bytes: 1000,
      expressions: {max_nodes: 100, max_work: 1000, max_depth: 10,
        max_literal_nodes: 100, max_literal_text_bytes: 1000}},
    execution: {rows: {max_rows: 100, metadata_entries: 10000,
      retained_entries: 10000, operation_entries: 10000,
      input_values: {...values}, output_values: {...values}}, max_work: 100000, max_frames: 100},
    measurement: {max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100},
    capacity: {contract_cid: 'sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f',
      max_rows: 100, max_value_bytes: 10000},
    search: {max_offers: 10, max_strategies: 10, max_work: 10000, max_revisions: 3},
    ledger: {planning_work: 10000, attempts: 10, holdings: 10,
      transfer_bytes: 300000n, retained_bytes: 32000000n, execution_bytes: 134217728n},
    milliseconds: 1n, max_work: 10000, max_entries: 100,
  };
}

export function finiteExpressionInput(document, configuration = finiteExpressionConfiguration()) {
  const environment = admitEnvironment(environmentWire, environmentCid, {rela: true,
    ...(Object.hasOwn(configuration.environment, 'numeric_profile_cid') ?
      {numericProfileCid: configuration.environment.numeric_profile_cid} : {})});
  const prepared = prepare(document, 'json', environment), compilation = compileValues(prepared);
  const allowed = issueAllowedRun(prepared, compilation,
    {executionContextCid: 'sha256:' + 'a'.repeat(64), hostPolicyCid: 'sha256:' + 'b'.repeat(64),
      expiresAt: '2099-01-01T00:00:00.000Z'});
  const definition = issueSourceFreeRunDefinition(prepared, compilation, allowed.admission,
    'finite-expression', 'original', '2026-10-01T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  return {configuration, runDefinitionCid: privateRunDefinition(definition).cid,
    wire: issueSourceFreeRunMaterials(prepared, compilation, allowed.admission, definition,
      {document, format: 'json', environment, environmentWire})};
}

export function finiteCountDocument() {
  return JSON.stringify({version: 'actql/0.1', id: 'finite-expression-count',
    stages: [{id: 'main', inputs: {}, steps: [
      {values: {schema: {region: {type: 'string', nullable: false},
        amount: {type: 'number', nullable: false}, quantity: {type: 'number', nullable: false}},
      rows: [{region: 'east', amount: 1, quantity: 2}, {region: 'east', amount: 20, quantity: 3},
        {region: 'west', amount: 30, quantity: 2}, {region: 'east', amount: 40, quantity: 1}]}, as: 'orders'},
      {from: 'orders', filter: 'amount >= 10', as: 'filtered'},
      {from: 'filtered', derive: {net: 'amount * quantity'}, as: 'derived'},
      {from: 'derived', group: {by: ['region'], aggregates: {order_count: {fn: 'count'}}}, as: 'grouped'},
      {from: 'grouped', sort: [{field: 'region', dir: 'asc', nulls: 'last'}], as: 'sorted'},
    ], results: {rows: {from: 'sorted', fields: ['region', 'order_count']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}});
}
