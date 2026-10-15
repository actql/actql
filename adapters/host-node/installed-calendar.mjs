// Explicit semantic-artifact installation. Calendar parsing, canonical bytes,
// identity and boundary laws remain with the existing MoonBit profile owner.
import {createHash} from 'node:crypto';

const originals = new WeakMap();
const keysEqual = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const selectionKeys = ['version', 'tzdb_version', 'conversion_law', 'table_bytes_cid'];
const limitKeys = ['max_bytes', 'max_nodes', 'max_depth', 'max_zones', 'max_transitions'];

export function snapshotInstalledCalendar(value) {
  if (value === undefined) return undefined;
  if (!keysEqual(value, ['selection', 'tableBytes', 'limits', 'maxSelectionWork']) ||
      !keysEqual(value.selection, selectionKeys) ||
      selectionKeys.some(key => typeof value.selection[key] !== 'string' ||
        !value.selection[key] || !value.selection[key].isWellFormed()) ||
      !/^sha256:[0-9a-f]{64}$/u.test(value.selection.table_bytes_cid) ||
      !keysEqual(value.limits, limitKeys) || limitKeys.some(key => !integer(value.limits[key])) ||
      !integer(value.maxSelectionWork) || !(value.tableBytes instanceof Uint8Array) ||
      value.tableBytes.byteLength > value.limits.max_bytes) {
    throw new TypeError('InvalidInstalledCalendar');
  }
  const bytes = Uint8Array.from(value.tableBytes);
  const selection = Object.freeze(Object.fromEntries(selectionKeys.map(key => [key, value.selection[key]])));
  const limits = Object.freeze(Object.fromEntries(limitKeys.map(key => [key, value.limits[key]])));
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
