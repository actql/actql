// Included in the strictly compiled wire templates. The supplied schema is
// projected from the registered contract before a received value reaches this code.
interface WireSchema {
  readonly $ref?: string;
  readonly $schema?: string;
  readonly $id?: string;
  readonly title?: string;
  readonly description?: string;
  readonly type?: unknown;
  readonly properties?: Readonly<Record<string, WireSchema>>;
  readonly items?: WireSchema;
  readonly allOf?: readonly WireSchema[];
  readonly oneOf?: readonly WireSchema[];
  readonly anyOf?: readonly WireSchema[];
  readonly not?: WireSchema;
  readonly if?: WireSchema;
  readonly then?: WireSchema;
  readonly else?: WireSchema;
  readonly format?: string;
  readonly propertyNames?: WireSchema;
  readonly additionalProperties?: boolean | WireSchema;
  readonly required?: readonly string[];
  readonly const?: unknown;
  readonly enum?: readonly unknown[];
  readonly uniqueItems?: boolean;
  readonly minimum?: number;
  readonly maximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
  readonly minItems?: number;
  readonly maxItems?: number;
  readonly minProperties?: number;
  readonly maxProperties?: number;
  readonly pattern?: string;
}

type WireValidationOptions = Readonly<{
  schemas?: Readonly<Record<string, WireSchema>>;
  extended?: boolean;
  compositeConstants?: boolean;
}>;

function wireObject(value: unknown): value is Readonly<Record<string, unknown>> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function sameConstant(value: unknown, expected: unknown): boolean {
  if (value === expected) return true;
  if (Array.isArray(expected)) {
    return Array.isArray(value) && value.length === expected.length &&
      expected.every((item, index) => sameConstant(value[index], item));
  }
  return wireObject(expected) && wireObject(value) &&
    Object.keys(value).length === Object.keys(expected).length &&
    Object.keys(expected).every(key => Object.hasOwn(value, key) && sameConstant(value[key], expected[key]));
}

function structuralWireValidator({schemas, extended, compositeConstants}: WireValidationOptions = {}) {
  return function valid(value: unknown, schema: WireSchema): boolean {
    if (typeof value === 'number' && (!Number.isFinite(value) || Object.is(value, -0))) return false;
    if (typeof value === 'string' && !value.isWellFormed()) return false;
    if (extended) {
      if (schema.anyOf && !schema.anyOf.some(rule => valid(value, rule))) return false;
      if (schema.if && !valid(value, schema.if) && schema.else && !valid(value, schema.else)) return false;
      if (schema.type === 'null') return value === null;
      if (schema.format === 'date-time' && (typeof value !== 'string' ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value) || Number.isNaN(Date.parse(value)))) return false;
    }
    if (schemas && schema.$ref) return valid(value, schemas[schema.$ref]);
    if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1) return false;
    if (schema.not && valid(value, schema.not)) return false;
    if (schema.if && valid(value, schema.if) && !valid(value, schema.then!)) return false;
    if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
    if (Object.hasOwn(schema, 'const') &&
        (compositeConstants ? !sameConstant(value, schema.const) : value !== schema.const)) return false;
    if (schema.enum && !schema.enum.includes(value)) return false;
    if (typeof value === 'number' &&
        (schema.minimum !== undefined && value < schema.minimum ||
         schema.maximum !== undefined && value > schema.maximum)) return false;
    if (typeof value === 'string' &&
        ((schema.minLength !== undefined && [...value].length < schema.minLength) ||
         (schema.maxLength !== undefined && (extended ? [...value].length : value.length) > schema.maxLength) ||
         (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value)))) return false;
    if (schema.type === 'string') return typeof value === 'string';
    if (schema.type === 'number') return typeof value === 'number';
    if (schema.type === 'integer') return typeof value === 'number' && Number.isSafeInteger(value) &&
      (schema.minimum === undefined || value >= schema.minimum) &&
      (schema.maximum === undefined || value <= schema.maximum);
    if (schema.type === 'boolean') return typeof value === 'boolean';
    if (schema.type === 'array') return Array.isArray(value) &&
      (schema.minItems === undefined || value.length >= schema.minItems) &&
      (schema.maxItems === undefined || value.length <= schema.maxItems) &&
      value.every(item => valid(item, schema.items!)) &&
      (!schema.uniqueItems || new Set(value).size === value.length);
    if (wireObject(value) &&
        ((schema.minProperties !== undefined && Object.keys(value).length < schema.minProperties) ||
         (schema.maxProperties !== undefined && Object.keys(value).length > schema.maxProperties))) return false;
    if (schema.type === 'object' || schema.properties || schema.required) {
      if (!wireObject(value)) return false;
      if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
      const {propertyNames, properties, additionalProperties} = schema;
      if (propertyNames && Object.keys(value).some(key => !valid(key, propertyNames))) return false;
      if (additionalProperties === false && Object.keys(value).some(key => !Object.hasOwn(properties!, key))) return false;
      if (additionalProperties && typeof additionalProperties === 'object' &&
          Object.entries(value).some(([key, item]) => !Object.hasOwn(properties ?? {}, key) &&
            !valid(item, additionalProperties))) return false;
      return Object.entries(properties ?? {}).every(([key, field]) =>
        !Object.hasOwn(value, key) || valid(value[key], field));
    }
    return true;
  };
}

/* @wire-validator-export */
export {structuralWireValidator};
