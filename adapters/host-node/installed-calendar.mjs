// Explicit semantic-artifact installation. Calendar parsing, canonical bytes,
// identity and boundary laws remain with the existing MoonBit profile owner.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

const originals = new WeakMap();
const invalid = () => { throw new TypeError('InvalidInstalledCalendar'); };
// Snapshot DATA descriptors once; never validate one read and retain another.
// Reflection may run Proxy traps. Same-process implementation code is trusted;
// this boundary does not sandbox code or reconstruct capability handles.
function snapshotRecord(value, keys) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const names = Reflect.ownKeys(descriptors);
  if (names.length !== keys.length || names.some(name => !keys.includes(name))) invalid();
  return Object.freeze(Object.fromEntries(keys.map(key => {
    const descriptor = descriptors[key];
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  })));
}
const typedArrayByteLength = Object.getOwnPropertyDescriptor(
  Object.getPrototypeOf(Uint8Array.prototype), 'byteLength').get;
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const selectionKeys = ['version', 'tzdb_version', 'conversion_law', 'table_bytes_cid'];
const limitKeys = ['max_bytes', 'max_nodes', 'max_depth', 'max_zones', 'max_transitions'];

export function snapshotInstalledCalendar(value) {
  if (value === undefined) return undefined;
  value = snapshotRecord(value, ['selection', 'tableBytes', 'limits', 'maxSelectionWork']);
  const selection = snapshotRecord(value.selection, selectionKeys);
  const limits = snapshotRecord(value.limits, limitKeys);
  if (selectionKeys.some(key => typeof selection[key] !== 'string' ||
        !selection[key] || !selection[key].isWellFormed()) ||
      !/^sha256:[0-9a-f]{64}$/u.test(selection.table_bytes_cid) ||
      limitKeys.some(key => !integer(limits[key])) ||
      !integer(value.maxSelectionWork) || !(value.tableBytes instanceof Uint8Array)) {
    invalid();
  }
  let byteLength;
  try { byteLength = typedArrayByteLength.call(value.tableBytes); }
  catch { invalid(); }
  if (byteLength > limits.max_bytes) invalid();
  // Copy the actual typed-array extent without consulting its iterator or an
  // overridden byteLength property. The owned bytes are hashed and admitted.
  const bytes = new Uint8Array(value.tableBytes);
  const selected = Object.freeze({selection, limits, maxSelectionWork: value.maxSelectionWork,
    artifactBytesCid: cid(bytes)});
  originals.set(selected, bytes);
  return selected;
}

export function installedCalendarIdentity(selected) {
  if (selected === undefined) return undefined;
  if (!originals.has(selected)) throw new TypeError('InvalidInstalledCalendar');
  return selected;
}

export function installedCalendarIdentityCid(selected) {
  const identity = installedCalendarIdentity(selected);
  return identity === undefined ? undefined : cid(Buffer.from(canonicalValueJson(identity), 'utf8'));
}

export function installedCalendarSelection(selected) {
  return installedCalendarIdentity(selected)?.selection;
}

export function admitInstalledCalendar(moon, environment, selected) {
  if (selected === undefined) return environment;
  const bytes = originals.get(selected);
  if (bytes === undefined || typeof moon?.clientProgramCheckEnvironmentWithCalendarArtifact !== 'function') {
    throw new TypeError('InvalidInstalledCalendar');
  }
  const limits = selected.limits;
  const admitted = moon.clientProgramCheckEnvironmentWithCalendarArtifact(environment,
    bytes, limits.max_bytes, limits.max_nodes, limits.max_depth,
    limits.max_zones, limits.max_transitions, selected.maxSelectionWork);
  if (admitted === undefined) throw new TypeError('InvalidInstalledCalendar');
  return admitted;
}
