// Original Captured/Mapping values reach the existing vendor codec inside one
// runtime. This view prepares DATA; it supplies no installed target, permission,
// approval, overwrite guard, physical dispatch, funding or cleanup ACK.
import {types} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';

const portNames = ['clientProgramEffectCheckedProposalRow',
  'clientProgramEffectCheckedProposalRowAvailable',
  'clientProgramEffectCheckedProposalRowRetire',
  'clientProgramNotionPropertyWriteLimits',
  'clientProgramEffectNotionPropertyWrite',
  'clientProgramEffectNotionDateRangeWrite',
  'clientProgramEffectNotionWritesJson'] as const;
const rowKeys = ['maxRows', 'maxFields', 'maxWork', 'maxNodes', 'maxDepth', 'maxTextBytes'] as const;
const writeKeys = ['maxBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxItems', 'maxTextUnits', 'maxWork'] as const;
const fail: (code: string) => never = code => { throw Object.assign(new TypeError(code), {code}); };
const integer = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
function data<Key extends string>(value: unknown, keys: readonly Key[], code: string) {
  if (value === null || typeof value !== 'object' || types.isProxy(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) fail(code);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const ownKeys = Reflect.ownKeys(descriptors);
  if (ownKeys.length !== keys.length || ownKeys.some(key => !(keys as readonly PropertyKey[]).includes(key))) fail(code);
  return Object.fromEntries(keys.map(key => {
    const descriptor = descriptors[key];
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) fail(code);
    return [key, descriptor.value];
  })) as Record<Key, unknown>;
}
function limits<Key extends string>(value: unknown, keys: readonly Key[], positives: readonly Key[]) {
  const result = data(value, keys, 'InvalidNotionEffectCodecLimits');
  if (keys.some(key => !integer(result[key])) ||
      positives.some(key => result[key] === 0)) fail('InvalidNotionEffectCodecLimits');
  return Object.freeze(result) as Readonly<Record<Key, number>>;
}

type CodecPorts = Readonly<{
  clientProgramEffectCheckedProposalRow(plan: unknown, exported: unknown, row: unknown, maxFields: number,
    maxWork: number, maxNodes: number, maxDepth: number, maxTextBytes: number): unknown;
  clientProgramEffectCheckedProposalRowAvailable(original: unknown): boolean;
  clientProgramEffectCheckedProposalRowRetire(original: unknown): unknown;
  clientProgramNotionPropertyWriteLimits(maxBytes: number, maxNodes: number, maxDepth: number,
    maxProperties: number, maxItems: number, maxTextUnits: number, maxWork: number): unknown;
  clientProgramEffectNotionPropertyWrite(row: unknown, field: number, catalog: unknown, property: number, limits: unknown): unknown;
  clientProgramEffectNotionDateRangeWrite(row: unknown, start: number, end: number, catalog: unknown, property: number, limits: unknown): unknown;
  clientProgramEffectNotionWritesJson(row: unknown, catalog: unknown, properties: readonly unknown[], limits: unknown): unknown;
}>;
type RowOwner = {original: unknown; writes: Set<object>};
type WriteOriginal = Readonly<{owner: RowOwner; original: unknown}>;

export function createNotionOriginalEffectPropertyCodec(moon: unknown, catalog: unknown, options: unknown) {
  if (moon === null || typeof moon !== 'object' || types.isProxy(moon)) {
    fail('NotionEffectCodecRuntimeUnavailable');
  }
  const ports = Object.freeze(Object.fromEntries(portNames.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(moon, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
        typeof descriptor.value !== 'function') fail('NotionEffectCodecRuntimeUnavailable');
    return [name, descriptor.value];
  }))) as CodecPorts;
  const supplied = data(options, ['rowLimits', 'writeLimits', 'assertCurrent'],
    'InvalidNotionEffectCodec');
  if (catalog === null || typeof catalog !== 'object' || types.isProxy(catalog) ||
      typeof supplied.assertCurrent !== 'function') fail('InvalidNotionEffectCodec');
  const row = limits(supplied.rowLimits, rowKeys, ['maxNodes']);
  const write = limits(supplied.writeLimits, writeKeys, ['maxBytes', 'maxNodes', 'maxDepth', 'maxWork']);
  const call = <Name extends keyof CodecPorts>(name: Name, ...args: Parameters<CodecPorts[Name]>) => Reflect.apply(ports[name], moon, args);
  const codecLimits = call('clientProgramNotionPropertyWriteLimits',
    write.maxBytes, write.maxNodes, write.maxDepth, write.maxProperties,
    write.maxItems, write.maxTextUnits, write.maxWork);
  const rows = new WeakMap<object, RowOwner>(), writes = new WeakMap<object, WriteOriginal>(), retainedRows = new Set<object>();
  let issued = 0, retired = false, failure: unknown;
  function current() {
    if (retired) fail('NotionEffectCodecRetired');
    if (failure !== undefined) throw failure;
    try {
      const result = Reflect.apply(supplied.assertCurrent as () => unknown, options, []);
      if (result !== undefined) {
        if (typeof (result as {then?: unknown} | null)?.then === 'function') void Promise.resolve(result).catch(() => {});
        fail('InvalidNotionEffectCodecCurrentFence');
      }
      if (retired) fail('NotionEffectCodecRetired');
    } catch (cause) { failure = cause; throw cause; }
  }
  function original(handle: unknown) {
    current();
    const value = rows.get(handle as object);
    if (value === undefined || call('clientProgramEffectCheckedProposalRowAvailable', value.original) !== true) {
      fail('UnavailableNotionEffectRow');
    }
    current();
    if (rows.get(handle as object) !== value) fail('UnavailableNotionEffectRow');
    return value;
  }
  function fieldIndex(value: unknown) {
    if (!integer(value)) fail('InvalidNotionEffectField');
    return value;
  }
  function prepare(handle: unknown, field: unknown, property: unknown, end?: number) {
    const owner = original(handle);
    if (owner.writes.size >= write.maxProperties) fail('NotionEffectPropertyLimit');
    const prepared = checked(end === undefined
      ? call('clientProgramEffectNotionPropertyWrite', owner.original,
        fieldIndex(field), catalog, fieldIndex(property), codecLimits)
      : call('clientProgramEffectNotionDateRangeWrite', owner.original,
        fieldIndex(field), fieldIndex(end), catalog, fieldIndex(property), codecLimits));
    if (original(handle) !== owner) fail('UnavailableNotionEffectRow');
    const token = Object.freeze({});
    writes.set(token, {owner, original: prepared});
    owner.writes.add(token);
    return token;
  }
  function retireRow(handle: unknown) {
    const owner = rows.get(handle as object);
    if (owner === undefined) fail('ForeignNotionEffectRow');
    call('clientProgramEffectCheckedProposalRowRetire', owner.original);
    for (const token of owner.writes) writes.delete(token);
    owner.writes.clear();
    owner.original = undefined;
    rows.delete(handle as object); retainedRows.delete(handle as object);
  }
  const view = Object.freeze({
    projectRow(plan: unknown, exported: unknown, originalRow: unknown) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      current();
      if (issued >= row.maxRows) fail('NotionEffectRowLimit');
      const prepared = checked(call('clientProgramEffectCheckedProposalRow',
        plan, exported, originalRow, row.maxFields, row.maxWork,
        row.maxNodes, row.maxDepth, row.maxTextBytes));
      try { current(); }
      catch (cause) {
        call('clientProgramEffectCheckedProposalRowRetire', prepared);
        throw cause;
      }
      const token = Object.freeze({});
      rows.set(token, {original: prepared, writes: new Set()});
      retainedRows.add(token); issued++;
      return token;
    },
    property(handle: unknown, field: unknown, property: unknown) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      return prepare(handle, field, property);
    },
    dateRange(handle: unknown, start: unknown, end: unknown, property: unknown) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      return prepare(handle, start, property, fieldIndex(end));
    },
    wire(handle: unknown, selected: unknown) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      const owner = original(handle);
      if (!Array.isArray(selected) || types.isProxy(selected) ||
          selected.length > write.maxProperties) fail('InvalidNotionEffectWrites');
      const originals = [];
      for (let index = 0; index < selected.length; index++) {
        const descriptor = Object.getOwnPropertyDescriptor(selected, index);
        if (!descriptor || !Object.hasOwn(descriptor, 'value')) fail('InvalidNotionEffectWrites');
        const value = writes.get(descriptor.value);
        if (value?.owner !== owner) fail('ForeignNotionEffectWrite');
        originals.push(value.original);
      }
      const wire = checked(call('clientProgramEffectNotionWritesJson', owner.original,
        catalog, originals, codecLimits));
      if (original(handle) !== owner) fail('UnavailableNotionEffectRow');
      return wire;
    },
    retireRow(handle: unknown) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      retireRow(handle);
    },
    retire() {
      if (this !== view) fail('ForeignNotionEffectCodec');
      for (const handle of retainedRows) retireRow(handle);
      retired = true;
    },
  });
  current();
  return view;
}
