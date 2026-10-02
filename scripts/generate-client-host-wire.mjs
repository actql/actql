import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join, resolve} from 'node:path';
import {project, structuralValidatorSource, typeOf} from
  './generate-client-publication-wire.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = 'spec/contracts/actql-client-host.json';
const runStateSource = 'spec/contracts/actql-protocol-schemas.json';
const names = ['run_ref', 'connection', 'profile', 'admission',
  'lookup_found', 'lookup_not_found', 'lookup_unknown', 'held',
  'checkpoint_summary', 'checkpoint_review', 'resolve_item',
  'resolve_result', 'submit_preparation_error', 'cancellation',
  'request_cancellation', 'resource_listing', 'resource_inspection',
  'resource_peek', 'result_description'];
const exports = ['RunRef', 'Connection', 'Profile', 'Admission',
  'LookupFound', 'LookupNotFound', 'LookupUnknown', 'Held',
  'CheckpointSummary', 'CheckpointReview', 'ResolveItem', 'ResolveResult',
  'SubmitPreparationError', 'Cancellation', 'RequestCancellation',
  'ResourceListing', 'ResourceInspection', 'ResourcePeek', 'ResultDescription'];

export function buildClientHostWire(registry, protocol) {
  if (registry.version !== 'actql-client-host/0.1' ||
      registry.operations === null ||
      typeof registry.operations !== 'object' ||
      Array.isArray(registry.operations)) {
    throw new Error('InvalidClientHostRegistry');
  }
  const operations = Object.entries(registry.operations);
  if (operations.length === 0 || operations.some(([name, keys]) =>
    !/^[a-z][a-z-]*$/u.test(name) || !Array.isArray(keys) ||
    keys.length === 0 || new Set(keys).size !== keys.length ||
    keys.some(key => !/^[a-zA-Z][a-zA-Z]*$/u.test(key)))) {
    throw new Error('InvalidClientHostOperations');
  }
  const schemas = Object.fromEntries(names.map(name => {
    if (!registry.schemas?.[name]) throw new Error(`MissingClientHostSchema:${name}`);
    return [name, project(registry.schemas[name])];
  }));
  if (protocol?.artifact_schemas?.run_state === undefined) {
    throw new Error('MissingRunStateSchema');
  }
  schemas.run_state = project(protocol.artifact_schemas.run_state);
  if (protocol?.artifact_schemas?.check_outcome === undefined) {
    throw new Error('MissingCheckOutcomeSchema');
  }
  schemas.check_outcome = project(protocol.artifact_schemas.check_outcome);
  schemas.value_contract = project(
    protocol.schemas.canonical_value_contract.$defs.value_contract);
  const module = `// Generated from the registered Client–Host machine contract.\n` +
    `// Run: node scripts/generate-client-host-wire.mjs --write\n` +
    `const schemas = ${JSON.stringify(schemas, null, 2)};\n` +
    `const operationKeys = ${JSON.stringify(registry.operations, null, 2)};\n\n` +
    structuralValidatorSource() +
    `export const clientHostOperations = Object.freeze(` +
    `Object.keys(operationKeys));\n` +
    `export const clientHostRequestKeys = operation => ` +
    `(Object.hasOwn(operationKeys, operation) ? operationKeys[operation] : ` +
    `undefined);\n` +
    names.map((name, index) =>
      `export const valid${exports[index]}Shape = value => ` +
      `valid(value, schemas.${name});\n`).join('') +
    `export const validRunStateShape = value => ` +
    `valid(value, schemas.run_state);\n` +
    `export const validCheckOutcomeShape = value => ` +
    `valid(value, schemas.check_outcome);\n`;
  const types = `// Generated from the registered Client–Host machine contract.\n` +
    `export type ClientHostOperation = ${operations.map(([name]) =>
      JSON.stringify(name)).join(' | ')};\n` +
    `export type WireValueContractShape = ${typeOf(schemas.value_contract)};\n` +
    names.map((name, index) =>
      `export type Wire${exports[index]}Shape = ${typeOf(schemas[name])};\n`
    ).join('\n') +
    `\nexport type WireRunStateShape = ${typeOf(schemas.run_state)};\n` +
    `export type WireCheckOutcomeShape = ${typeOf(schemas.check_outcome)};\n`;
  return {module, types};
}

async function main() {
  const registry = JSON.parse(await readFile(join(root, source), 'utf8'));
  const protocol = JSON.parse(await readFile(join(root, runStateSource),
    'utf8'));
  const outputs = buildClientHostWire(registry, protocol);
  const files = [
    ['packages/client-wire/client-host.generated.js', outputs.module],
    ['packages/client-wire/client-host.generated.d.ts', outputs.types],
  ];
  for (const [path, content] of files) {
    if (process.argv.includes('--write')) {
      await writeFile(join(root, path), content);
    } else if (await readFile(join(root, path), 'utf8') !== content) {
      throw new Error(`StaleClientHostWire:${path}`);
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) ===
    resolve(process.argv[1])) {
  await main();
}
