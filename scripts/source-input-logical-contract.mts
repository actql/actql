import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import type {ArtifactRegistry} from './invocation-bindings-contract.mjs';

type OrderingEvidence = {
  stable: boolean;
  keys: {field: string; dir: string; nulls: string}[];
};

type LogicalInput = {
  version: string;
  logical_relation_cid: string;
  source_contract_cid: string;
  relation_schema_cid: string;
  completeness: string;
  ordering_evidence: OrderingEvidence;
};

type LogicalInputObservation = {
  logicalRelationCid: string;
  sourceContractCid: string;
  relationSchemaCid: string;
  completeness: string;
  orderingEvidence: OrderingEvidence;
};

type SourceEvidenceRegistry = {artifact_schemas: {
  source_evidence: {properties: {ordering_evidence: unknown}};
}};

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const fields = ['version', 'logical_relation_cid', 'source_contract_cid',
  'relation_schema_cid', 'completeness',
  'ordering_evidence'];

export function sourceInputLogicalSchema() {
  const registry = JSON.parse(readFileSync(path, 'utf8')) as SourceEvidenceRegistry;
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-source-input-logical-0.1.json',
    title: 'actql-source-input-logical-0.1',
    type: 'object', additionalProperties: false,
    required: [...fields, 'input_logical_cid'],
    properties: {
      version: {const: 'actql-source-input-logical/0.1'},
      logical_relation_cid: cid,
      source_contract_cid: cid,
      relation_schema_cid: cid,
      completeness: {enum: ['complete', 'partial']},
      ordering_evidence: registry.artifact_schemas.source_evidence
        .properties.ordering_evidence,
      input_logical_cid: cid,
    },
  };
}

export function sourceInputLogicalCid<Body extends LogicalInput>(body: Body) {
  assert.deepEqual(Object.keys(body).sort(), [...fields].sort());
  assert.equal(body.version, 'actql-source-input-logical/0.1');
  for (const field of ['logical_relation_cid', 'source_contract_cid',
    'relation_schema_cid'] as const) {
    assert.match(body[field], /^sha256:[0-9a-f]{64}$/u);
  }
  assert.ok(['complete', 'partial'].includes(body.completeness));
  const ordering = body.ordering_evidence;
  assert.deepEqual(Object.keys(ordering).sort(), ['keys', 'stable']);
  assert.equal(typeof ordering.stable, 'boolean');
  assert.ok(Array.isArray(ordering.keys));
  for (const key of ordering.keys) {
    assert.deepEqual(Object.keys(key).sort(), ['dir', 'field', 'nulls']);
    assert.equal(typeof key.field, 'string');
    assert.ok(key.field.length > 0);
    assert.ok(['asc', 'desc'].includes(key.dir));
    assert.ok(['first', 'last'].includes(key.nulls));
  }
  return machineCid(body);
}

export function admitSourceInputLogical(envelope: unknown, observed: LogicalInputObservation) {
  assert.ok(envelope && typeof envelope === 'object' &&
    !Array.isArray(envelope));
  const {input_logical_cid: claimed, ...body} = envelope as LogicalInput & {input_logical_cid: string};
  assert.deepEqual(Object.keys(envelope).sort(),
    [...fields, 'input_logical_cid'].sort());
  assert.equal(claimed, sourceInputLogicalCid(body));
  assert.equal(body.logical_relation_cid, observed.logicalRelationCid);
  assert.equal(body.relation_schema_cid, observed.relationSchemaCid);
  assert.equal(body.source_contract_cid, observed.sourceContractCid);
  assert.equal(body.completeness, observed.completeness);
  assert.deepEqual(body.ordering_evidence, observed.orderingEvidence);
  return claimed;
}

export function applySourceInputLogicalSchema<Registry extends ArtifactRegistry>(registry: Registry) {
  const schema = sourceInputLogicalSchema();
  registry.artifact_schemas.source_input_logical = schema;
  registry.artifact_schema_cids.source_input_logical = machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkSourceInputLogicalSchema(registry: ArtifactRegistry) {
  const schema = sourceInputLogicalSchema();
  assert.deepEqual(registry.artifact_schemas.source_input_logical, schema);
  assert.equal(registry.artifact_schema_cids.source_input_logical,
    machineCid(schema));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8')) as ArtifactRegistry;
  if (process.argv.includes('--write')) {
    applySourceInputLogicalSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkSourceInputLogicalSchema(registry);
}
