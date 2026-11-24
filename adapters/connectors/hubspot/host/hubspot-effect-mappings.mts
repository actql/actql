// Installation DATA only. The same Common initialization parent funds each
// original provider Mapping before its native constructor, then owns the
// resulting Environment. Program preparation still performs full admission.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';

type Bounds = readonly [maxProperties: number, maxFields: number, maxNameBytes: number,
  maxBytes: number, maxNodes: number, maxDepth: number];
type NativeMapping = Readonly<{resource: string; fields: readonly string[]; mapping: unknown;
  body: string; mappingRef: string; mappingCid: string}>;
type NativeInput = Readonly<{capacity(): unknown; project(): NativeMapping}>;
type Options = Readonly<{construction: unknown; moon: unknown; providerMoon: unknown;
  connectorId: string; declared: unknown; catalogFor(resource: string): unknown; writes: unknown; limits: unknown}>;

const fail: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};
const method = <Args extends readonly unknown[], Value>(receiver: unknown, name: string) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('HubSpotEffectMappingUnavailable');
  const field = Object.getOwnPropertyDescriptor(receiver, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
    fail('HubSpotEffectMappingUnavailable');
  }
  return (...args: Args): Value => Reflect.apply(field.value, receiver, args);
};

// The installing profile must already be captured by its funded configuration
// reader. No readable field is treated as writable: the original provider
// Catalog constructor checks every selected property's exact writable type.
export function prepareInstalledHubSpotUpdateMappings({construction, moon, providerMoon,
  connectorId, declared, catalogFor, writes, limits}: Options) {
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
  const prepareNativeInput = method<[projection: NativeInput], NativeMapping>(construction, 'prepareNativeInput');
  const prepareNativeMappings = method<[declared: unknown, originals: readonly NativeMapping[]], unknown>(construction, 'prepareNativeMappings');
  const capacity = method<[fields: number, sources: number, units: bigint, ...Bounds], unknown>(moon, 'clientProgramHubSpotMappingConstructionCapacity');
  const prepare = method<[catalog: unknown, connectorId: string, manifestCid: string, resource: string,
    kind: number, key: string, fields: readonly string[], sources: readonly unknown[], ...Bounds], unknown>(
    providerMoon, 'hubspotPrepareExecutionMapping');
  const body = method<[mapping: unknown], string>(providerMoon, 'hubspotExecutionMappingBody');
  const mappingRef = method<[mapping: unknown], string>(providerMoon, 'hubspotExecutionMappingRef');
  const mappingCid = method<[mapping: unknown], string>(providerMoon, 'hubspotExecutionMappingCid');
  const names = ['maxProperties', 'maxFields', 'maxNameBytes', 'maxBytes', 'maxNodes', 'maxDepth'];
  const bounds = names.map(name => {
    const field = Object.getOwnPropertyDescriptor(limits, name);
    if (!field || !Object.hasOwn(field, 'value') || !Number.isSafeInteger(field.value) ||
        field.value < 1 || field.value > 2147483647) fail('InvalidHubSpotEffectMappingLimits');
    return field.value;
  }) as unknown as Bounds;
  const manifestCid = manifest.value;
  const originals: NativeMapping[] = [];
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
