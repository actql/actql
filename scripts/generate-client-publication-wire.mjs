import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join, resolve} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const sources = [
  ['spec/contracts/actql-run-publication.json',
    'schemas', ['delivery_attempt', 'delivery_record']],
  ['spec/contracts/actql-protocol-schemas.json',
    'artifact_schemas', ['result_delivery_receipt']],
];
const allowed = new Set(['$schema', '$id', 'title', 'type',
  'additionalProperties', 'required', 'properties', 'items', 'uniqueItems',
  'const', 'enum', 'pattern', 'minLength', 'minimum', 'maximum', 'allOf',
  'if', 'then']);

function project(schema) {
  if (schema === null || typeof schema !== 'object' || Array.isArray(schema)) {
    throw new Error('InvalidPublicationSchema');
  }
  for (const key of Object.keys(schema)) {
    if (!allowed.has(key)) throw new Error(`UnsupportedPublicationSchema:${key}`);
  }
  if (schema.type !== undefined &&
      !['object', 'array', 'string', 'integer'].includes(schema.type)) {
    throw new Error(`UnsupportedPublicationType:${schema.type}`);
  }
  if (schema.uniqueItems && schema.items?.type !== 'string') {
    throw new Error('UnsupportedPublicationUniqueItems');
  }
  const result = {};
  for (const key of ['type', 'additionalProperties', 'required',
    'uniqueItems', 'const', 'enum', 'pattern', 'minLength', 'minimum',
    'maximum']) {
    if (Object.hasOwn(schema, key)) result[key] = schema[key];
  }
  if (schema.properties) result.properties = Object.fromEntries(
    Object.entries(schema.properties).map(([key, value]) =>
      [key, project(value)]));
  if (schema.items) result.items = project(schema.items);
  if (schema.allOf) result.allOf = schema.allOf.map(project);
  if (schema.if) result.if = project(schema.if);
  if (schema.then) result.then = project(schema.then);
  return result;
}

function typeOf(schema) {
  if (Object.hasOwn(schema, 'const')) return JSON.stringify(schema.const);
  if (schema.enum) return schema.enum.map(JSON.stringify).join(' | ');
  if (schema.type === 'string') return 'string';
  if (schema.type === 'integer') return 'number';
  if (schema.type === 'array') return `readonly ${typeOf(schema.items)}[]`;
  if (schema.type === 'object') {
    const required = new Set(schema.required ?? []);
    return `Readonly<{${Object.entries(schema.properties ?? {}).map(
      ([key, value]) => `\n  ${key}${required.has(key) ? '' : '?'}: ${typeOf(value)};`
    ).join('')}\n}>`;
  }
  throw new Error('UnsupportedPublicationType');
}

export function buildClientPublicationWire(registries) {
  const schemas = {};
  for (const [path, collection, keys] of sources) {
    const registry = registries[path];
    if (registry?.[collection] === undefined) throw new Error('MissingRegistry');
    for (const key of keys) {
      if (!registry[collection][key]) {
        throw new Error(`MissingPublicationSchema:${key}`);
      }
      schemas[key] = project(registry[collection][key]);
    }
  }
  const module = `// Generated from registered ActQL publication schemas.\n` +
`// Run: node scripts/generate-client-publication-wire.mjs --write\n` +
`const schemas = ${JSON.stringify(schemas, null, 2)};\n\n` +
`function valid(value, schema) {\n` +
`  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;\n` +
`  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;\n` +
`  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;\n` +
`  if (schema.enum && !schema.enum.includes(value)) return false;\n` +
`  if (schema.type === 'string') return typeof value === 'string' &&\n` +
`    (schema.minLength === undefined || [...value].length >= schema.minLength) &&\n` +
`    (schema.pattern === undefined || new RegExp(schema.pattern, 'u').test(value));\n` +
`  if (schema.type === 'integer') return Number.isSafeInteger(value) &&\n` +
`    (schema.minimum === undefined || value >= schema.minimum) &&\n` +
`    (schema.maximum === undefined || value <= schema.maximum);\n` +
`  if (schema.type === 'array') return Array.isArray(value) &&\n` +
`    value.every(item => valid(item, schema.items)) &&\n` +
`    (!schema.uniqueItems || new Set(value).size === value.length);\n` +
`  if (schema.type === 'object' || schema.properties || schema.required) {\n` +
`    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;\n` +
`    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;\n` +
`    if (schema.additionalProperties === false &&\n` +
`        Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;\n` +
`    return Object.entries(schema.properties ?? {}).every(([key, field]) =>\n` +
`      !Object.hasOwn(value, key) || valid(value[key], field));\n` +
`  }\n` +
`  return true;\n` +
`}\n\n` +
`export const validDeliveryAttempt = value => valid(value, schemas.delivery_attempt);\n` +
`export const validDeliveryRecord = value => valid(value, schemas.delivery_record);\n` +
`export const validHostReleaseReceipt = value =>\n` +
`  valid(value, schemas.result_delivery_receipt);\n`;
  const types = `// Generated from registered ActQL publication schemas.\n` +
`export type WireDeliveryAttempt = ${typeOf(schemas.delivery_attempt)};\n\n` +
`export type WireDeliveryRecord = ${typeOf(schemas.delivery_record)};\n\n` +
`export type WireHostReleaseReceipt = ${typeOf(
  schemas.result_delivery_receipt)};\n`;
  return {module, types};
}

async function main() {
  const registries = Object.fromEntries(await Promise.all(sources.map(
    async ([path]) => [path, JSON.parse(await readFile(join(root, path),
      'utf8'))])));
  const outputs = buildClientPublicationWire(registries);
  const files = [
    ['packages/client-wire/publication.generated.js', outputs.module],
    ['packages/client-wire/publication.generated.d.ts', outputs.types],
  ];
  if (process.argv.includes('--write')) {
    for (const [path, content] of files) {
      await writeFile(join(root, path), content);
    }
  } else {
    for (const [path, content] of files) {
      if (await readFile(join(root, path), 'utf8') !== content) {
        throw new Error(`StaleClientPublicationWire:${path}`);
      }
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) ===
    resolve(process.argv[1])) {
  await main();
}
