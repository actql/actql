// Installation DATA only. The same Common initialization parent funds each
// original provider Mapping before its native constructor, then owns the
// resulting Environment. Program preparation still performs full admission.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';

const fail = code => {throw Object.assign(new TypeError(code), {code});};
const method = (receiver, name) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('HubSpotEffectMappingUnavailable');
  const field = Object.getOwnPropertyDescriptor(receiver, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
    fail('HubSpotEffectMappingUnavailable');
  }
  return (...args) => Reflect.apply(field.value, receiver, args);
};

// The installing profile must already be captured by its funded configuration
// reader. No readable field is treated as writable: the original provider
// Catalog constructor checks every selected property's exact writable type.
export function prepareInstalledHubSpotUpdateMappings({construction, moon, providerMoon,
  connectorId, declared, catalogFor, writes, limits}) {
  if (!Array.isArray(writes) || nodeTypes.isProxy(writes) || !Object.isFrozen(writes) ||
      writes.length === 0 || typeof catalogFor !== 'function' ||
      nodeTypes.isProxy(catalogFor) || nodeTypes.isAsyncFunction(catalogFor) ||
      typeof connectorId !== 'string' || !declared || nodeTypes.isProxy(declared) ||
      !Object.isFrozen(declared) || !limits || nodeTypes.isProxy(limits) ||
      !Object.isFrozen(limits)) fail('InvalidHubSpotEffectMappings');
  const manifest = Object.getOwnPropertyDescriptor(declared, 'manifest_entry_cid');
  if (!manifest || !Object.hasOwn(manifest, 'value') || typeof manifest.value !== 'string') {
    fail('InvalidHubSpotEffectMappings');
  }
  // Capture original callable receivers before any original reserve/current
  // callback can reenter and mutate a caller's export table.
  const prepareNativeInput = method(construction, 'prepareNativeInput');
  const prepareNativeMappings = method(construction, 'prepareNativeMappings');
  const capacity = method(moon, 'clientProgramHubSpotMappingConstructionCapacity');
  const prepare = method(providerMoon, 'hubspotPrepareExecutionMapping');
  const body = method(providerMoon, 'hubspotExecutionMappingBody');
  const mappingRef = method(providerMoon, 'hubspotExecutionMappingRef');
  const mappingCid = method(providerMoon, 'hubspotExecutionMappingCid');
  const names = ['maxProperties', 'maxFields', 'maxNameBytes', 'maxBytes', 'maxNodes', 'maxDepth'];
  const bounds = names.map(name => {
    const field = Object.getOwnPropertyDescriptor(limits, name);
    if (!field || !Object.hasOwn(field, 'value') || !Number.isSafeInteger(field.value) ||
        field.value < 1 || field.value > 2147483647) fail('InvalidHubSpotEffectMappingLimits');
    return field.value;
  });
  const manifestCid = manifest.value;
  const originals = [];
  for (let i = 0; i < writes.length; i++) {
    const entry = Object.getOwnPropertyDescriptor(writes, String(i));
    const write = entry?.value;
    if (!entry || !Object.hasOwn(entry, 'value') || !write || nodeTypes.isProxy(write) ||
        !Object.isFrozen(write)) fail('InvalidHubSpotEffectMappings');
    const fields = Object.getOwnPropertyDescriptors(write);
    const resource = fields.resource?.value, selected = fields.fields?.value;
    if (!Object.hasOwn(fields.resource ?? {}, 'value') || typeof resource !== 'string' ||
        !Object.hasOwn(fields.fields ?? {}, 'value') || !Array.isArray(selected) ||
        nodeTypes.isProxy(selected) || !Object.isFrozen(selected)) fail('InvalidHubSpotEffectMappings');
    let units = BigInt(connectorId.length + resource.length + manifestCid.length);
    for (let j = 0; j < selected.length; j++) {
      const field = Object.getOwnPropertyDescriptor(selected, String(j));
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
        fail('InvalidHubSpotEffectMappings');
      }
      units += BigInt(field.value.length);
    }
    const catalog = catalogFor(resource);
    originals.push(prepareNativeInput(Object.freeze({
      capacity: () => capacity(selected.length, 0, units, ...bounds),
      project() {
        const mapping = checked(prepare(catalog, connectorId, manifestCid, resource,
          1, 'id', selected, [], ...bounds));
        return Object.freeze({resource, fields: selected, mapping,
          body: body(mapping), mappingRef: mappingRef(mapping), mappingCid: mappingCid(mapping)});
      },
    })));
  }
  return Object.freeze({originals: Object.freeze(originals),
    prepared: prepareNativeMappings(declared, Object.freeze(originals))});
}
