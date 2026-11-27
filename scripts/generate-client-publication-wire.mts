import {compileWireTemplate} from './wire-template-compiler.mjs';
import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join, resolve} from 'node:path';
import type {JSONSchema7} from 'json-schema';

// Unchecked build-time projection views over the SAME registered schemas.
// Supported-key/ref/type refusals below remain runtime checks; these types
// are not received-value admission or a second protocol schema.
type ProjectedSchema = Omit<JSONSchema7, 'properties' | 'items' | 'allOf' | 'oneOf' | 'anyOf' |
  'if' | 'then' | 'else' | 'not' | 'propertyNames' | 'additionalProperties'> & {
  properties?: Record<string, ProjectedSchema>; items?: ProjectedSchema;
  allOf?: ProjectedSchema[]; oneOf?: ProjectedSchema[]; anyOf?: ProjectedSchema[];
  if?: ProjectedSchema; then?: ProjectedSchema; else?: ProjectedSchema; not?: ProjectedSchema;
  propertyNames?: ProjectedSchema; additionalProperties?: boolean | ProjectedSchema;
};


const root = fileURLToPath(new URL('../', import.meta.url));
const sources = [
  ['spec/contracts/actql-run-publication.json',
    'schemas', ['delivery_attempt', 'delivery_record']],
  ['spec/contracts/actql-protocol-schemas.json',
    'artifact_schemas', ['result_delivery_receipt']],
] as const;
const allowed = new Set(['$schema', '$id', '$ref', 'title', 'type',
  'additionalProperties', 'required', 'properties', 'items', 'uniqueItems',
  'const', 'enum', 'pattern', 'minLength', 'maxLength', 'minimum', 'maximum', 'allOf',
  'if', 'then', 'not', 'oneOf', 'minItems', 'maxItems', 'minProperties', 'maxProperties', 'propertyNames']);

export function project(schema: unknown, {extended = false} = {}): ProjectedSchema {
  if (schema === null || typeof schema !== 'object' || Array.isArray(schema)) {
    throw new Error('InvalidPublicationSchema');
  }
  for (const key of Object.keys(schema)) {
    if (!allowed.has(key) && !(extended && ['anyOf', 'else', 'format'].includes(key))) {
      throw new Error(`UnsupportedPublicationSchema:${key}`);
    }
  }
  if ((schema as ProjectedSchema).type !== undefined &&
      !['object', 'array', 'string', 'integer', 'number', 'boolean'].includes((schema as ProjectedSchema).type as string)) {
    throw new Error(`UnsupportedPublicationType:${(schema as ProjectedSchema).type}`);
  }
  if ((schema as ProjectedSchema).uniqueItems && (schema as ProjectedSchema).items?.type !== 'string') {
    throw new Error('UnsupportedPublicationUniqueItems');
  }
  const result: ProjectedSchema = {};
  const child = (value: unknown) => project(value, {extended});
  if ((schema as ProjectedSchema).$ref !== undefined) {
    if (!['#/$defs/value_contract',
      'actql-protocol-schemas.json#/schemas/canonical_value_contract',
      'actql-protocol-schemas.json#/artifact_schemas/check_outcome',
      'actql-protocol-schemas.json#/artifact_schemas/run_state']
      .includes((schema as ProjectedSchema).$ref!)) throw new Error('UnsupportedPublicationReference');
    result.$ref = (schema as ProjectedSchema).$ref!.endsWith('/check_outcome') ? 'check_outcome' :
      (schema as ProjectedSchema).$ref!.endsWith('/run_state') ? 'run_state' : 'value_contract';
  }
  for (const key of ['type', 'required',
    'uniqueItems', 'const', 'enum', 'pattern', 'minLength', 'maxLength', 'minimum',
    'maximum', 'minItems', 'maxItems', 'minProperties', 'maxProperties']) {
    if (Object.hasOwn(schema, key)) (result as Record<string, unknown>)[key] = (schema as Record<string, unknown>)[key];
  }
  if (Object.hasOwn(schema, 'additionalProperties')) {
    result.additionalProperties = typeof (schema as ProjectedSchema).additionalProperties ===
      'object' ? child((schema as ProjectedSchema).additionalProperties) :
      (schema as ProjectedSchema).additionalProperties;
  }
  if ((schema as ProjectedSchema).properties) result.properties = Object.fromEntries(
    Object.entries((schema as ProjectedSchema).properties!).map(([key, value]) =>
      [key, child(value)]));
  if ((schema as ProjectedSchema).items!) result.items = child((schema as ProjectedSchema).items!);
  if ((schema as ProjectedSchema).allOf) result.allOf = (schema as ProjectedSchema).allOf!.map(child);
  if ((schema as ProjectedSchema).oneOf) result.oneOf = (schema as ProjectedSchema).oneOf!.map(child);
  if ((schema as ProjectedSchema).if) result.if = child((schema as ProjectedSchema).if);
  if ((schema as ProjectedSchema).then) result.then = child((schema as ProjectedSchema).then);
  if ((schema as ProjectedSchema).not) result.not = child((schema as ProjectedSchema).not);
  if ((schema as ProjectedSchema).propertyNames) result.propertyNames = child((schema as ProjectedSchema).propertyNames);
  if (extended) {
    if ((schema as ProjectedSchema).anyOf) result.anyOf = (schema as ProjectedSchema).anyOf!.map(child);
    if ((schema as ProjectedSchema).else) result.else = child((schema as ProjectedSchema).else);
    if ((schema as ProjectedSchema).format !== undefined) {
      if ((schema as ProjectedSchema).format !== 'date-time') throw new Error('UnsupportedPublicationFormat');
      result.format = (schema as ProjectedSchema).format;
    }
  }
  return result;
}

export function typeOf(schema: ProjectedSchema): string | undefined {
  if (schema.$ref === 'value_contract') return 'WireValueContractShape';
  if (schema.$ref === 'check_outcome') return 'WireCheckOutcomeShape';
  if (schema.$ref === 'run_state') return 'WireRunStateShape';
  if (schema.allOf && schema.type === undefined && !schema.oneOf) {
    return schema.allOf.map(rule => `(${typeOf(rule)})`).join(' & ');
  }
  if (schema.oneOf) return schema.oneOf.map(typeOf).join(' | ');
  if (Object.hasOwn(schema, 'const')) return JSON.stringify(schema.const);
  if (schema.enum) return schema.enum.map(JSON.stringify as unknown as (value: unknown, index: number) => string | undefined).join(' | ');
  if (schema.type === 'string') return 'string';
  if (schema.type === 'integer' || schema.type === 'number') return 'number';
  if (schema.type === 'boolean') return 'boolean';
  if (schema.type === 'array') {
    const item = typeOf(schema.items!);
    return schema.items!.oneOf ? `readonly (${item})[]` : `readonly ${item}[]`;
  }
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

export function buildClientPublicationWire(registries: unknown) {
  const schemas: Record<string, ProjectedSchema> = {};
  for (const [path, collection, keys] of sources) {
    const registry = (registries as Record<string, Record<string, Record<string, unknown>>>)[path];
    if (registry?.[collection] === undefined) throw new Error('MissingRegistry');
    for (const key of keys) {
      if (!registry[collection][key]) {
        throw new Error(`MissingPublicationSchema:${key}`);
      }
      schemas[key] = project(registry[collection][key]);
    }
  }
  const header = '// Generated from registered ActQL publication schemas.\n' +
    '// Run: node scripts/generate-client-publication-wire.mjs --write\n';
  const bindings = `const schemas: Readonly<Record<string, WireSchema>> = ${JSON.stringify(schemas, null, 2)};\n` +
    `export type WireDeliveryAttempt = ${typeOf(schemas.delivery_attempt)};\n` +
    `export type WireDeliveryRecord = ${typeOf(schemas.delivery_record)};\n` +
    `export type WireHostReleaseReceipt = ${typeOf(schemas.result_delivery_receipt)};\n`;
  return compileWireTemplate('client-publication-wire', bindings, header);
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
