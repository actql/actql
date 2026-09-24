import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {operationInventory} from './bound-transfer-laws.mjs';
import {canonicalText} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const grammarPath = 'spec/manifests/actql-grammar-0.1.json';
const barrierPath = 'spec/manifests/actql-barrier-contracts-0.1.json';
const contractPath = 'spec/contracts/actql-compilation-manifests.json';
const moonPath = 'src/check_environment/compilation_manifests.generated.mbt';

function grammarBody() {
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const program = protocol.artifact_schemas.executable_plan.properties
    .execution_material.properties.program;
  const expression = read('spec/contracts/actql-expressions.json');
  const language = readFileSync('docs/spec/language.md', 'utf8');
  const start = language.indexOf('<a id="expression-text"></a>');
  const end = language.indexOf('<a id="predicates"></a>', start);
  assert.ok(start >= 0 && end > start);
  const rules = language.slice(start, end);
  const grammarBytes = readFileSync(expression.grammar);
  assert.equal(digest(grammarBytes), expression.grammar_sha256);
  const body = {
    version: 'actql-grammar-manifest/0.1',
    source_grammar_cid: machineCid(program),
    operations: operationInventory(language),
    expression_contract_cid: machineCid(expression),
    expression_text_grammar_sha256: expression.grammar_sha256,
    expression_text_rules_sha256: digest(Buffer.from(rules, 'utf8')),
  };
  return {...body, grammar_manifest_cid: machineCid(body)};
}

function barrierBody() {
  const registry = read('spec/contracts/actql-production-profile-schemas.json');
  const names = Object.keys(registry.schemas).filter(name =>
    name.endsWith('_barrier')).sort();
  assert.deepEqual(names, ['artifact_barrier', 'lookup_barrier',
    'text_time_evaluation_barrier']);
  const contracts = names.map(name => {
    const contractCid = machineCid(registry.schemas[name]);
    assert.equal(contractCid, registry.schema_cids[name]);
    return {name, contract_cid: contractCid};
  });
  const body = {
    version: 'actql-barrier-contract-manifest/0.1',
    production_profile_registry_cid: machineCid(registry),
    contracts,
  };
  return {...body, barrier_contract_manifest_cid: machineCid(body)};
}

function contractBody() {
  const sha256 = {type: 'string', pattern: '^[0-9a-f]{64}$'};
  const grammarManifest = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-grammar-manifest-0.1.json',
    title: 'actql-grammar-manifest-0.1', type: 'object',
    additionalProperties: false,
    required: ['version', 'source_grammar_cid', 'operations',
      'expression_contract_cid', 'expression_text_grammar_sha256',
      'expression_text_rules_sha256', 'grammar_manifest_cid'],
    properties: {
      version: {const: 'actql-grammar-manifest/0.1'},
      source_grammar_cid: cid,
      operations: {type: 'array', minItems: 1, uniqueItems: true,
        items: {type: 'string', pattern: '^[a-z][a-z0-9_]*$'}},
      expression_contract_cid: cid,
      expression_text_grammar_sha256: sha256,
      expression_text_rules_sha256: sha256,
      grammar_manifest_cid: cid,
    },
  };
  const barrierManifest = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-barrier-contract-manifest-0.1.json',
    title: 'actql-barrier-contract-manifest-0.1', type: 'object',
    additionalProperties: false,
    required: ['version', 'production_profile_registry_cid', 'contracts',
      'barrier_contract_manifest_cid'],
    properties: {
      version: {const: 'actql-barrier-contract-manifest/0.1'},
      production_profile_registry_cid: cid,
      contracts: {type: 'array', minItems: 1, items: {type: 'object',
        additionalProperties: false, required: ['name', 'contract_cid'],
        properties: {name: {type: 'string', pattern: '^[a-z][a-z0-9_]*$'},
          contract_cid: cid}}},
      barrier_contract_manifest_cid: cid,
    },
  };
  return {
    version: 'actql-compilation-manifests/0.1',
    schema_cids: {
      grammar_manifest: machineCid(grammarManifest),
      barrier_contract_manifest: machineCid(barrierManifest),
    },
    schemas: {grammar_manifest: grammarManifest,
      barrier_contract_manifest: barrierManifest},
  };
}

export function expectedCompilationManifests() {
  return {grammar: grammarBody(), barrier: barrierBody(),
    contract: contractBody()};
}

function checkOrWrite(path, body, write) {
  const serialized = JSON.stringify(body, null, 2) + '\n';
  if (write) writeFileSync(path, serialized);
  assert.equal(readFileSync(path, 'utf8'), serialized,
    `Stale compilation manifest: ${path}`);
}

export function verifyCompilationManifests(write = false) {
  const values = expectedCompilationManifests();
  const aoaContractCid = machineCid(read('spec/contracts/actql-aoa.json'));
  checkOrWrite(grammarPath, values.grammar, write);
  checkOrWrite(barrierPath, values.barrier, write);
  checkOrWrite(contractPath, values.contract, write);
  const moon = [
    '// Generated by scripts/compilation-manifests.mjs; do not edit.',
    '', '///|', 'pub fn compiler_grammar_manifest_cid() -> String {',
    `  ${JSON.stringify(values.grammar.grammar_manifest_cid)}`, '}',
    '', '///|', 'pub fn compiler_grammar_manifest_wire() -> String {',
    `  ${JSON.stringify(canonicalText(values.grammar))}`, '}',
    '', '///|', 'pub fn compiler_barrier_contract_manifest_cid() -> String {',
    `  ${JSON.stringify(values.barrier.barrier_contract_manifest_cid)}`, '}',
    '', '///|', 'pub fn compiler_barrier_contract_manifest_wire() -> String {',
    `  ${JSON.stringify(canonicalText(values.barrier))}`, '}', '',
    '///|', 'pub fn compiler_aoa_contract_cid() -> String {',
    `  ${JSON.stringify(aoaContractCid)}`, '}', '',
  ].join('\n');
  if (write) writeFileSync(moonPath, moon);
  assert.equal(readFileSync(moonPath, 'utf8'), moon,
    'Stale compiler manifest pins');
  return values;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const values = verifyCompilationManifests(process.argv.includes('--write'));
  console.log(JSON.stringify({grammar_manifest_cid:
    values.grammar.grammar_manifest_cid, barrier_contract_manifest_cid:
    values.barrier.barrier_contract_manifest_cid}));
}
