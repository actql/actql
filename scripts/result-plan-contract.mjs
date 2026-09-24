import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const name = {type: 'string', minLength: 1};
const portRef = {
  type: 'object', additionalProperties: false,
  required: ['node_id', 'port'],
  properties: {node_id: name, port: name},
};

function insertAfter(entries, key, inserted, value) {
  const result = {};
  for (const [entry, body] of Object.entries(entries)) {
    if (entry !== inserted) result[entry] = body;
    if (entry === key) result[inserted] = value;
  }
  if (!Object.hasOwn(result, inserted)) {
    throw new Error(`Missing predecessor: ${key}`);
  }
  return result;
}

export function resultPlanSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-result-plan-0.1.json',
    title: 'actql-result-plan-0.1',
    type: 'object', additionalProperties: false,
    required: [
      'version', 'result_name', 'unit_definition_cid', 'unit_result_name',
      'unit_result_ordinal', 'projection', 'order', 'typed_output_port',
      'result_plan_logical_cid',
    ],
    properties: {
      version: {const: 'actql-result-plan/0.1'},
      result_name: name,
      unit_definition_cid: cid,
      unit_result_name: name,
      unit_result_ordinal: {
        type: 'integer', minimum: 0, maximum: 9007199254740991,
      },
      projection: {
        type: 'array',
        items: {
          type: 'object', additionalProperties: false,
          required: ['input', 'output', 'value_contract_cid'],
          properties: {
            input: name, output: name, value_contract_cid: cid,
          },
        },
      },
      order: {
        type: 'object', additionalProperties: false,
        required: ['strategy', 'terms'],
        properties: {
          strategy: {
            enum: ['authored', 'inherited', 'candidate_key', 'projected_fields'],
          },
          terms: {
            type: 'array',
            items: {
              type: 'object', additionalProperties: false,
              required: ['field', 'direction', 'nulls', 'authored'],
              properties: {
                field: name,
                direction: {enum: ['asc', 'desc']},
                nulls: {enum: ['first', 'last']},
                authored: {type: 'boolean'},
              },
            },
          },
        },
      },
      typed_output_port: {
        type: 'object', additionalProperties: false,
        required: ['name', 'carrier', 'row_contract_cid'],
        properties: {
          name: name,
          carrier: {const: 'relation'},
          row_contract_cid: cid,
        },
      },
      result_plan_logical_cid: cid,
    },
  };
}

export function resultPlanCid(plan) {
  const {result_plan_logical_cid: _self, ...preimage} = plan;
  return machineCid(preimage);
}

export function checkResultPlanBindings(plan, resultPlans, resolveOutputPort) {
  assert.equal(typeof resolveOutputPort, 'function');
  const expectedNames = Object.keys(
    plan.execution_material.result_plan_logical_cids,
  ).sort();
  assert.deepEqual(expectedNames, Object.keys(resultPlans).sort());
  const roots = plan.root_refs.filter(root => root.role === 'requested_result');
  assert.deepEqual(roots.map(root => root.name).sort(), expectedNames);
  assert.equal(new Set(roots.map(root => root.name)).size, roots.length);
  const nodes = new Map(plan.nodes.map(node => [node.node_id, node]));
  assert.equal(nodes.size, plan.nodes.length);
  for (const root of roots) {
    const result = resultPlans[root.name];
    assert.equal(result.result_name, root.name);
    assert.equal(result.typed_output_port.name, result.unit_result_name);
    assert.equal(result.result_plan_logical_cid, resultPlanCid(result));
    assert.equal(plan.execution_material.result_plan_logical_cids[root.name],
      result.result_plan_logical_cid);
    const node = nodes.get(root.ref.node_id);
    assert.ok(node, `Missing Result root node: ${root.name}`);
    assert.equal(node.output_contracts[root.ref.port],
      result.typed_output_port.row_contract_cid);
    const checkedPort = resolveOutputPort(root.ref);
    assert.equal(checkedPort.carrier, 'relation');
    assert.equal(checkedPort.row_contract_cid,
      result.typed_output_port.row_contract_cid);
  }
}

export function applyResultPlanSchema(registry) {
  const schema = resultPlanSchema();
  for (const plan of [
    registry.artifact_schemas.executable_plan,
    registry.artifact_schemas.plan_document.properties.plan,
  ]) {
    plan.properties.root_refs.items.properties.ref = structuredClone(portRef);
  }
  registry.artifact_schemas = insertAfter(
    registry.artifact_schemas, 'executable_plan', 'result_plan', schema,
  );
  registry.artifact_schema_cids = insertAfter(
    registry.artifact_schema_cids, 'executable_plan', 'result_plan',
    machineCid(schema),
  );
  for (const key of ['executable_plan', 'result_plan', 'plan_document']) {
    registry.artifact_schema_cids[key] =
      machineCid(registry.artifact_schemas[key]);
  }
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkResultPlanSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.result_plan, resultPlanSchema());
  for (const plan of [
    registry.artifact_schemas.executable_plan,
    registry.artifact_schemas.plan_document.properties.plan,
  ]) {
    assert.deepEqual(plan.properties.root_refs.items.properties.ref, portRef);
  }
  for (const key of ['executable_plan', 'result_plan', 'plan_document']) {
    assert.equal(registry.artifact_schema_cids[key],
      machineCid(registry.artifact_schemas[key]));
  }
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyResultPlanSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkResultPlanSchema(registry);
}
