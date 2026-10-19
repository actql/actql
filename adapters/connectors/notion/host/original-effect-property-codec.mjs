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
  'clientProgramEffectNotionWritesJson'];
const rowKeys = ['maxRows', 'maxFields', 'maxWork', 'maxNodes', 'maxDepth', 'maxTextBytes'];
const writeKeys = ['maxBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxItems', 'maxTextUnits', 'maxWork'];
const fail = code => { throw Object.assign(new TypeError(code), {code}); };
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
function data(value, keys, code) {
  if (value === null || typeof value !== 'object' || types.isProxy(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) fail(code);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const ownKeys = Reflect.ownKeys(descriptors);
  if (ownKeys.length !== keys.length || ownKeys.some(key => !keys.includes(key))) fail(code);
  return Object.fromEntries(keys.map(key => {
    const descriptor = descriptors[key];
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) fail(code);
    return [key, descriptor.value];
  }));
}
function limits(value, keys, positives) {
  const result = data(value, keys, 'InvalidNotionEffectCodecLimits');
  if (keys.some(key => !integer(result[key])) ||
      positives.some(key => result[key] === 0)) fail('InvalidNotionEffectCodecLimits');
  return Object.freeze(result);
}

export function createNotionOriginalEffectPropertyCodec(moon, catalog, options) {
  if (moon === null || typeof moon !== 'object' || types.isProxy(moon)) {
    fail('NotionEffectCodecRuntimeUnavailable');
  }
  const ports = Object.freeze(Object.fromEntries(portNames.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(moon, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
        typeof descriptor.value !== 'function') fail('NotionEffectCodecRuntimeUnavailable');
    return [name, descriptor.value];
  })));
  const supplied = data(options, ['rowLimits', 'writeLimits', 'assertCurrent'],
    'InvalidNotionEffectCodec');
  if (catalog === null || typeof catalog !== 'object' || types.isProxy(catalog) ||
      typeof supplied.assertCurrent !== 'function') fail('InvalidNotionEffectCodec');
  const row = limits(supplied.rowLimits, rowKeys, ['maxNodes']);
  const write = limits(supplied.writeLimits, writeKeys, ['maxBytes', 'maxNodes', 'maxDepth', 'maxWork']);
  const call = (name, ...args) => Reflect.apply(ports[name], moon, args);
  const codecLimits = call('clientProgramNotionPropertyWriteLimits',
    write.maxBytes, write.maxNodes, write.maxDepth, write.maxProperties,
    write.maxItems, write.maxTextUnits, write.maxWork);
  const rows = new WeakMap(), writes = new WeakMap(), retainedRows = new Set();
  let issued = 0, retired = false, failure;
  function current() {
    if (retired) fail('NotionEffectCodecRetired');
    if (failure !== undefined) throw failure;
    try {
      const result = Reflect.apply(supplied.assertCurrent, options, []);
      if (result !== undefined) {
        if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
        fail('InvalidNotionEffectCodecCurrentFence');
      }
      if (retired) fail('NotionEffectCodecRetired');
    } catch (cause) { failure = cause; throw cause; }
  }
  function original(handle) {
    current();
    const value = rows.get(handle);
    if (value === undefined || call('clientProgramEffectCheckedProposalRowAvailable', value.original) !== true) {
      fail('UnavailableNotionEffectRow');
    }
    current();
    if (rows.get(handle) !== value) fail('UnavailableNotionEffectRow');
    return value;
  }
  function fieldIndex(value) {
    if (!integer(value)) fail('InvalidNotionEffectField');
    return value;
  }
  function prepare(handle, field, property, end) {
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
  function retireRow(handle) {
    const owner = rows.get(handle);
    if (owner === undefined) fail('ForeignNotionEffectRow');
    call('clientProgramEffectCheckedProposalRowRetire', owner.original);
    for (const token of owner.writes) writes.delete(token);
    owner.writes.clear();
    owner.original = undefined;
    rows.delete(handle); retainedRows.delete(handle);
  }
  const view = Object.freeze({
    projectRow(plan, exported, originalRow) {
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
    property(handle, field, property) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      return prepare(handle, field, property);
    },
    dateRange(handle, start, end, property) {
      if (this !== view) fail('ForeignNotionEffectCodec');
      return prepare(handle, start, property, fieldIndex(end));
    },
    wire(handle, selected) {
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
    retireRow(handle) {
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
