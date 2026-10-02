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
const allowed = new Set(['$schema', '$id', '$ref', 'title', 'type',
  'additionalProperties', 'required', 'properties', 'items', 'uniqueItems',
  'const', 'enum', 'pattern', 'minLength', 'maxLength', 'minimum', 'maximum', 'allOf',
  'if', 'then', 'not', 'oneOf', 'minItems', 'maxItems', 'minProperties', 'propertyNames']);

export function project(schema) {
  if (schema === null || typeof schema !== 'object' || Array.isArray(schema)) {
    throw new Error('InvalidPublicationSchema');
  }
  for (const key of Object.keys(schema)) {
    if (!allowed.has(key)) throw new Error(`UnsupportedPublicationSchema:${key}`);
  }
  if (schema.type !== undefined &&
      !['object', 'array', 'string', 'integer', 'boolean'].includes(schema.type)) {
    throw new Error(`UnsupportedPublicationType:${schema.type}`);
  }
  if (schema.uniqueItems && schema.items?.type !== 'string') {
    throw new Error('UnsupportedPublicationUniqueItems');
  }
  const result = {};
  if (schema.$ref !== undefined) {
    if (!['#/$defs/value_contract',
      'actql-protocol-schemas.json#/schemas/canonical_value_contract']
      .includes(schema.$ref)) throw new Error('UnsupportedPublicationReference');
    result.$ref = 'value_contract';
  }
  for (const key of ['type', 'required',
    'uniqueItems', 'const', 'enum', 'pattern', 'minLength', 'maxLength', 'minimum',
    'maximum', 'minItems', 'maxItems', 'minProperties']) {
    if (Object.hasOwn(schema, key)) result[key] = schema[key];
  }
  if (Object.hasOwn(schema, 'additionalProperties')) {
    result.additionalProperties = typeof schema.additionalProperties ===
      'object' ? project(schema.additionalProperties) :
      schema.additionalProperties;
  }
  if (schema.properties) result.properties = Object.fromEntries(
    Object.entries(schema.properties).map(([key, value]) =>
      [key, project(value)]));
  if (schema.items) result.items = project(schema.items);
  if (schema.allOf) result.allOf = schema.allOf.map(project);
  if (schema.oneOf) result.oneOf = schema.oneOf.map(project);
  if (schema.if) result.if = project(schema.if);
  if (schema.then) result.then = project(schema.then);
  if (schema.not) result.not = project(schema.not);
  if (schema.propertyNames) result.propertyNames = project(schema.propertyNames);
  return result;
}

export function typeOf(schema) {
  if (schema.$ref === 'value_contract') return 'WireValueContractShape';
  if (schema.oneOf) return schema.oneOf.map(typeOf).join(' | ');
  if (Object.hasOwn(schema, 'const')) return JSON.stringify(schema.const);
  if (schema.enum) return schema.enum.map(JSON.stringify).join(' | ');
  if (schema.type === 'string') return 'string';
  if (schema.type === 'integer') return 'number';
  if (schema.type === 'boolean') return 'boolean';
  if (schema.type === 'array') return `readonly ${typeOf(schema.items)}[]`;
  if (schema.type === 'object') {
    if (schema.additionalProperties &&
        typeof schema.additionalProperties === 'object' &&
        !schema.properties) {
      return `Readonly<Record<string, ${typeOf(
        schema.additionalProperties)}>>`;
    }
    const required = new Set(schema.required ?? []);
    return `Readonly<{${Object.entries(schema.properties ?? {}).map(
      ([key, value]) => `\n  ${key}${required.has(key) ? '' : '?'}: ${typeOf(value)};`
    ).join('')}\n}>`;
  }
  throw new Error('UnsupportedPublicationType');
}

export function structuralValidatorSource() {
  return `function valid(value, schema) {\n` +
`  if (schema.$ref) return valid(value, schemas[schema.$ref]);\n` +
`  if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1) return false;\n` +
`  if (schema.not && valid(value, schema.not)) return false;\n` +
`  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;\n` +
`  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;\n` +
`  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;\n` +
`  if (schema.enum && !schema.enum.includes(value)) return false;\n` +
`  if (typeof value === 'number' &&\n` +
`      (schema.minimum !== undefined && value < schema.minimum ||\n` +
`       schema.maximum !== undefined && value > schema.maximum)) return false;\n` +
`  if (typeof value === 'string' &&\n` +
`      ((schema.minLength !== undefined && [...value].length < schema.minLength) ||\n` +
`        (schema.maxLength !== undefined && value.length > schema.maxLength) ||\n` +
`        (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value))))\n` +
`    return false;\n` +
`  if (schema.type === 'string') return typeof value === 'string';\n` +
`  if (schema.type === 'integer') return Number.isSafeInteger(value) &&\n` +
`    (schema.minimum === undefined || value >= schema.minimum) &&\n` +
`    (schema.maximum === undefined || value <= schema.maximum);\n` +
`  if (schema.type === 'boolean') return typeof value === 'boolean';\n` +
`  if (schema.type === 'array') return Array.isArray(value) &&\n` +
`    (schema.minItems === undefined || value.length >= schema.minItems) &&\n` +
`    (schema.maxItems === undefined || value.length <= schema.maxItems) &&\n` +
`    value.every(item => valid(item, schema.items)) &&\n` +
`    (!schema.uniqueItems || new Set(value).size === value.length);\n` +
`  if (schema.type === 'object' || schema.properties || schema.required) {\n` +
`    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;\n` +
`    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;\n` +
`    if (schema.minProperties !== undefined &&\n` +
`        Object.keys(value).length < schema.minProperties) return false;\n` +
`    if (schema.propertyNames && Object.keys(value).some(key =>\n` +
`        !valid(key, schema.propertyNames))) return false;\n` +
`    if (schema.additionalProperties === false &&\n` +
`        Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;\n` +
`    if (schema.additionalProperties &&\n` +
`        typeof schema.additionalProperties === 'object' &&\n` +
`        Object.entries(value).some(([key, item]) =>\n` +
`          !Object.hasOwn(schema.properties ?? {}, key) &&\n` +
`          !valid(item, schema.additionalProperties))) return false;\n` +
`    return Object.entries(schema.properties ?? {}).every(([key, field]) =>\n` +
`      !Object.hasOwn(value, key) || valid(value[key], field));\n` +
`  }\n` +
`  return true;\n` +
`}\n\n`;
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
structuralValidatorSource() +
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
