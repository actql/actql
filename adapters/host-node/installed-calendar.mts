// Explicit semantic-artifact installation. Calendar parsing, canonical bytes,
// identity and boundary laws remain with the existing MoonBit profile owner.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

type CalendarSelection = Readonly<Record<(typeof selectionKeys)[number], string>>;
type CalendarLimits = Readonly<Record<(typeof limitKeys)[number], number>>;
type InstalledCalendar = Readonly<{
  selection: CalendarSelection;
  limits: CalendarLimits;
  maxSelectionWork: number;
  artifactBytesCid: string;
}>;
type CalendarAdmission<Environment, Admitted> = {
  clientProgramCheckEnvironmentWithCalendarArtifact?(environment: Environment, bytes: Uint8Array,
    maxBytes: number, maxNodes: number, maxDepth: number, maxZones: number,
    maxTransitions: number, maxSelectionWork: number): Admitted | undefined;
};

const originals = new WeakMap<InstalledCalendar, Uint8Array>();
const invalid: () => never = () => { throw new TypeError('InvalidInstalledCalendar'); };
// Snapshot DATA descriptors once; never validate one read and retain another.
// Reflection may run Proxy traps. Same-process implementation code is trusted;
// this boundary does not sandbox code or reconstruct capability handles.
function snapshotRecord<Key extends string>(value: unknown, keys: readonly Key[]) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const names = Reflect.ownKeys(descriptors);
  if (names.length !== keys.length || names.some(name => !(keys as readonly PropertyKey[]).includes(name))) invalid();
  return Object.freeze(Object.fromEntries(keys.map(key => {
    const descriptor = descriptors[key];
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  }))) as Readonly<Record<Key, unknown>>;
}
const typedArrayByteLength = Object.getOwnPropertyDescriptor(
  Object.getPrototypeOf(Uint8Array.prototype), 'byteLength')!.get!;
const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
const cid = (bytes: NodeJS.ArrayBufferView) => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const selectionKeys = ['version', 'tzdb_version', 'conversion_law', 'table_bytes_cid'] as const;
const limitKeys = ['max_bytes', 'max_nodes', 'max_depth', 'max_zones', 'max_transitions'] as const;

export function snapshotInstalledCalendar(value: undefined): undefined;
export function snapshotInstalledCalendar(value: object): InstalledCalendar;
export function snapshotInstalledCalendar(value: unknown): InstalledCalendar | undefined;
export function snapshotInstalledCalendar(value: unknown) {
  if (value === undefined) return undefined;
  const original = snapshotRecord(value, ['selection', 'tableBytes', 'limits', 'maxSelectionWork']);
  const selection = snapshotRecord(original.selection, selectionKeys);
  const limits = snapshotRecord(original.limits, limitKeys);
  if (selectionKeys.some(key => typeof selection[key] !== 'string' ||
        !selection[key] || !selection[key].isWellFormed()) ||
      !/^sha256:[0-9a-f]{64}$/u.test(selection.table_bytes_cid as string) ||
      limitKeys.some(key => !integer(limits[key])) ||
      !integer(original.maxSelectionWork) || !(original.tableBytes instanceof Uint8Array)) {
    invalid();
  }
  let byteLength: number;
  try { byteLength = typedArrayByteLength.call(original.tableBytes); }
  catch { invalid(); }
  if (byteLength > (limits.max_bytes as number)) invalid();
  // Copy the actual typed-array extent without consulting its iterator or an
  // overridden byteLength property. The owned bytes are hashed and admitted.
  const bytes = new Uint8Array(original.tableBytes);
  const selected = Object.freeze({selection, limits, maxSelectionWork: original.maxSelectionWork,
    artifactBytesCid: cid(bytes)}) as InstalledCalendar;
  originals.set(selected, bytes);
  return selected;
}

export function installedCalendarIdentity(selected: undefined): undefined;
export function installedCalendarIdentity(selected: InstalledCalendar): InstalledCalendar;
export function installedCalendarIdentity(selected: InstalledCalendar | undefined): InstalledCalendar | undefined;
export function installedCalendarIdentity(selected: InstalledCalendar | undefined) {
  if (selected === undefined) return undefined;
  if (!originals.has(selected)) throw new TypeError('InvalidInstalledCalendar');
  return selected;
}

export function installedCalendarIdentityCid(selected: InstalledCalendar | undefined) {
  const identity = installedCalendarIdentity(selected);
  return identity === undefined ? undefined : cid(Buffer.from(canonicalValueJson(identity), 'utf8'));
}

export function installedCalendarSelection(selected: undefined): undefined;
export function installedCalendarSelection(selected: InstalledCalendar): CalendarSelection;
export function installedCalendarSelection(selected: InstalledCalendar | undefined): CalendarSelection | undefined;
export function installedCalendarSelection(selected: InstalledCalendar | undefined) {
  return installedCalendarIdentity(selected)?.selection;
}

export function admitInstalledCalendar<Environment, Admitted = Environment>(
  moon: CalendarAdmission<Environment, Admitted>, environment: Environment, selected: InstalledCalendar | undefined) {
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
