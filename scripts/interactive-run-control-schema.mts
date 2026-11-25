import {readFileSync} from 'node:fs';

type SchemaData = string | number | boolean | null | undefined | SchemaData[] | SchemaObject;
interface SchemaObject {
  readonly [key: string]: SchemaData;
  readonly $ref?: string;
}

// Resolve only registered references. Preserve siblings: source/data kind
// restrictions on a referenced Sample are not annotations.
export function resolveControlSchema(schema: unknown, registry: unknown,
  ancestors: readonly string[] = []): SchemaData {
  const walk = (value: SchemaData): SchemaData => {
    if (Array.isArray(value)) return value.map(walk);
    if (!value || typeof value !== 'object') return value;
    if (value.$ref) {
      if (ancestors.includes(value.$ref)) throw new Error('ControlSchemaCycle');
      const [file, pointer] = value.$ref.split('#');
      if (!['', 'actql-client-host.json', 'actql-protocol-schemas.json']
        .includes(file)) throw new Error('ForeignControlSchemaReference');
      const document = file === '' ? registry : JSON.parse(readFileSync(
        `spec/contracts/${file}`, 'utf8'));
      const target = pointer.split('/').slice(1).reduce<SchemaData>((current, key) =>
        (current as SchemaObject | undefined)?.[key], document as SchemaData);
      if (!target) throw new Error(`MissingControlSchemaReference:${value.$ref}`);
      const resolved = resolveControlSchema(target, registry,
        [...ancestors, value.$ref]);
      const {$ref, ...siblings} = value;
      return Object.keys(siblings).length ? {
        ...((resolved as SchemaObject).type ? {type: (resolved as SchemaObject).type} : {}),
        allOf: [resolved, walk(siblings)],
      }
        : resolved;
    }
    return Object.fromEntries(Object.entries(value).map(([key, child]) =>
      [key, walk(child)]));
  };
  return walk(schema as SchemaData);
}
