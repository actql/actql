// Private producer geometry for the already-owned published Salesforce
// original. This module neither decodes metadata nor restores a declaration,
// reserves capacity, installs authorization, or manages a Site lifetime.
import {types} from 'node:util';

const intMax = 2_147_483_647;
const revision = 'salesforce/0.1';
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const defaultDeclarationLimits = Object.freeze({maxBytes: 4_000_000,
  maxNodes: 400_000, maxDepth: 64});
const defaultMappingLimits = Object.freeze({maxBytes: 400_000,
  maxNodes: 40_000, maxDepth: 64});
const fail = () => { throw Object.assign(new Error('InvalidSalesforceConstructionOriginal'),
  {code: 'InvalidSalesforceConstructionOriginal'}); };
const object = value => {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) fail();
  return value;
};
const own = (value, key, optional = false) => {
  const descriptor = Object.getOwnPropertyDescriptor(object(value), key);
  if (descriptor === undefined && optional) return undefined;
  if (descriptor === undefined || !Object.hasOwn(descriptor, 'value')) fail();
  return descriptor.value;
};
const string = value => { if (typeof value !== 'string') fail(); return value; };
const integer = (value, minimum = 0) => {
  if (!Number.isSafeInteger(value) || value < minimum || value > intMax) fail();
  return value;
};
const add = (a, b) => integer(a + b);
const array = value => {
  if (!Array.isArray(object(value))) fail();
  integer(own(value, 'length'));
  return value;
};
const limits = value => [integer(own(value, 'maxBytes'), 1),
  integer(own(value, 'maxNodes'), 1), integer(own(value, 'maxDepth'), 1)];

// Validate exact canonical spelling and padding bits without allocating a
// Buffer or using the provider decoder. Unavailable outcomes have null bodies.
function bodyBytes(encoded, maxBytes) {
  if (encoded === null) return 0;
  string(encoded);
  if (encoded.length % 4 !== 0 || encoded.length > 4 * Math.ceil(maxBytes / 3)) fail();
  const padding = encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0;
  for (let index = 0; index < encoded.length - padding; index += 1) {
    if (alphabet.indexOf(encoded[index]) < 0) fail();
  }
  if ((padding === 2 && (alphabet.indexOf(encoded.at(-3)) & 15) !== 0) ||
      (padding === 1 && (alphabet.indexOf(encoded.at(-2)) & 3) !== 0)) fail();
  const bytes = integer(encoded.length / 4 * 3 - padding);
  if (bytes > maxBytes) fail();
  return bytes;
}

function evidenceGeometry(generation) {
  const evidence = own(generation, 'evidence');
  const names = array(own(evidence, 'names'));
  const bodies = array(own(evidence, 'describeBodyBase64'));
  if (names.length < 1 || names.length > 200 || names.length !== bodies.length) fail();
  for (const key of ['outcomes', 'describeUseCids', 'describeResponseSha256']) {
    if (array(own(evidence, key)).length !== names.length) fail();
  }
  const describe = own(evidence, 'describeLimits');
  const describeLimits = [...limits(describe), integer(own(describe, 'maxFields'), 1),
    integer(own(describe, 'maxNameUnits'), 1)];
  const bodyLengths = [];
  const encodedBodies = [];
  const nameLengths = [];
  let encodedUnits = 0;
  for (let index = 0; index < names.length; index += 1) {
    const name = string(own(names, String(index)));
    const encoded = own(bodies, String(index));
    nameLengths.push(integer(name.length));
    bodyLengths.push(bodyBytes(encoded, describeLimits[0]));
    encodedBodies.push(encoded === null ? undefined : encoded);
    if (encoded !== null) encodedUnits = add(encodedUnits, encoded.length);
  }
  const observation = string(own(evidence, 'observationJson'));
  const maxObservationBytes = integer(own(evidence, 'maxObservationBytes'), 1);
  if (observation.length > maxObservationBytes) fail();
  return {names, bodyLengths, encodedBodies, nameLengths, encodedUnits,
    observationUnits: integer(observation.length), describeLimits, maxObservationBytes,
    connectorUnits: integer(string(own(generation, 'connector_id')).length)};
}

function quote(common, exportName, args) {
  const callable = own(common, exportName);
  if (typeof callable !== 'function') fail();
  const capacity = Reflect.apply(callable, common, args);
  // This bridge returns Option[ExecutionCapacity], not Result. Some is the
  // exact opaque capacity; undefined is None. Do not use runtime-result.checked
  // or turn this quantity into numeric admission authority.
  if (capacity === undefined || capacity === null) fail();
  return capacity;
}

export function salesforceInitializationConstructionCapacity(common, options) {
  return initializationCapacity(common, options,
    'clientProgramSalesforceOriginalInitializationConstructionCapacity');
}

export function salesforceObservationConstructionCapacity(common, options) {
  return initializationCapacity(common, options,
    'clientProgramSalesforceObservationConstructionCapacity');
}

export function salesforceDeclarationConstructionCapacity(common, options) {
  const dimensions = array(own(options, 'dimensions'));
  const measured = [];
  for (let index = 0; index < dimensions.length; index++) {
    measured.push(integer(own(dimensions, String(index))));
  }
  return initializationCapacity(common, options,
    'clientProgramSalesforceDeclarationConstructionCapacity', measured);
}

function initializationCapacity(common,
  {generation, siteBinding, declarationLimits = defaultDeclarationLimits}, exportName, dimensions) {
  const geometry = evidenceGeometry(generation);
  // The observation's original text bounds its binding without JSON.parse.
  // Current Site string fields are independent: a mismatched binding can fail
  // after raw construction and must not rely on equal original identities.
  let bindingUnits = geometry.observationUnits;
  for (const key of Object.getOwnPropertyNames(object(siteBinding))) {
    const value = own(siteBinding, key);
    if (typeof value === 'string') bindingUnits = add(bindingUnits, value.length);
  }
  return quote(common, exportName, [
    dimensions ?? geometry.encodedBodies, geometry.observationUnits,
    geometry.nameLengths, bindingUnits, geometry.connectorUnits, revision.length,
    ...geometry.describeLimits, geometry.maxObservationBytes, ...limits(declarationLimits),
  ]);
}

export function salesforceExecutionMappingConstructionCapacity(common,
  {generation, write, mappingLimits = defaultMappingLimits}) {
  const geometry = evidenceGeometry(generation);
  const resource = string(own(write, 'resource'));
  let bodyLength;
  for (let index = 0; index < geometry.names.length; index += 1) {
    if (own(geometry.names, String(index)) === resource) {
      if (bodyLength !== undefined) fail();
      bodyLength = geometry.bodyLengths[index];
    }
  }
  if (bodyLength === undefined) fail();
  const fieldsValue = own(write, 'fields', true);
  const fields = fieldsValue === undefined ? [] : array(fieldsValue);
  let fieldUnits = 0;
  for (let index = 0; index < fields.length; index += 1) {
    fieldUnits = add(fieldUnits, string(own(fields, String(index))).length);
  }
  const sourcesValue = own(write, 'sources', true);
  const sources = sourcesValue === undefined ? [] : array(sourcesValue);
  let sourceUnits = 0;
  for (let index = 0; index < sources.length; index += 1) {
    const source = own(sources, String(index));
    for (const key of ['target', 'field', 'nullBehavior']) {
      sourceUnits = add(sourceUnits, string(own(source, key)).length);
    }
  }
  const key = own(write, 'key', true);
  const keyUnits = key === undefined ? 0 : string(key).length;
  return quote(common, 'clientProgramSalesforceExecutionMappingConstructionCapacity', [
    fields.length, fieldUnits, sources.length, sourceUnits, keyUnits,
    resource.length, geometry.connectorUnits, revision.length, bodyLength,
    geometry.describeLimits[3], ...limits(mappingLimits),
  ]);
}
