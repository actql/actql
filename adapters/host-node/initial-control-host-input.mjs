import {types} from 'node:util';

const isProxy = types.isProxy, isArray = Array.isArray;
const prototype = Object.getPrototypeOf, descriptor = Object.getOwnPropertyDescriptor;
const ownKeys = Reflect.ownKeys, define = Object.defineProperty;
const create = Object.create, freeze = Object.freeze, hasOwn = Object.hasOwn;
const safeInteger = Number.isSafeInteger, NativeArray = Array;
const objectPrototype = Object.prototype, arrayPrototype = Array.prototype;
const NativeMap = Map, NativeSet = Set, NativeError = Error;
const mapHas = Map.prototype.has, mapGet = Map.prototype.get, mapSet = Map.prototype.set;
const setHas = Set.prototype.has, setAdd = Set.prototype.add, setDelete = Set.prototype.delete;
const apply = Reflect.apply;
const limitNames = freeze(['maxProperties', 'maxNodes', 'maxDepth',
  'maxStringCodeUnits', 'maxTotalStringCodeUnits', 'maxArrayItems',
  'maxOpaqueAliases', 'maxWork']);

// These existing Host fields retain an original Owner, not a replacement DATA
// copy. This list classifies copying only: a field name or alias count never
// authenticates the referenced backing, currentness, custody or permission.
const originalInstallationFields = new NativeSet(['authorization', 'connectorTable',
  'modelInstallation', 'calendarArtifact', 'resultDataPolicy', 'inferEvidence',
  'observation']);
const unavailable = () => {
  const error = new NativeError('NodeInitialControlInputUnavailable');
  error.code = 'NodeInitialControlInputUnavailable';
  throw error;
};

// Pure bounded snapshot, not an operational admission or a public validator.
// The actual selected startup MUST already own finite raw acquisition and the
// FIRST ownKeys/descriptor workspace, including rejection, before invoking this
// captured reader. Measuring after ownKeys cannot supply that missing coverage.
// The same supplier must separately admit every original reference's backing
// and extended lifetime; this function neither walks nor certifies that graph.
// Missing supported coverage remains Unavailable, not an invalid public value.
export function snapshotInitialControlHostInput(input, limits) {
  const selected = create(null);
  if (limits === null || typeof limits !== 'object' || isProxy(limits)) unavailable();
  for (let index = 0; index < limitNames.length; index++) {
    const name = limitNames[index], field = descriptor(limits, name);
    if (field === undefined || !hasOwn(field, 'value') ||
        !safeInteger(field.value) || field.value <
          (name === 'maxNodes' || name === 'maxWork' ? 1 : 0)) unavailable();
    selected[name] = field.value;
  }
  if (input === null || typeof input !== 'object' || isArray(input) || isProxy(input)) unavailable();
  const inputPrototype = prototype(input);
  if (inputPrototype !== objectPrototype && inputPrototype !== null) unavailable();
  const usage = {properties: 0, nodes: 0, depth: 0, stringCodeUnits: 0,
    arrayItems: 0, opaqueAliases: 0, work: 0};
  const copies = new NativeMap(), active = new NativeSet(), originals = [], frames = [];
  function work(amount = 1) {
    if (amount > selected.maxWork - usage.work) unavailable();
    usage.work += amount;
  }
  function string(text) {
    if (text.length > selected.maxStringCodeUnits ||
        text.length > selected.maxTotalStringCodeUnits - usage.stringCodeUnits) unavailable();
    work(text.length);
    usage.stringCodeUnits += text.length;
    return text;
  }
  function borrow(value, path) {
    if (usage.opaqueAliases === selected.maxOpaqueAliases) unavailable();
    work(path.length);
    usage.opaqueAliases++;
    originals[originals.length] = freeze({path: freeze(path), original: value});
    return value;
  }
  function childPath(path, key) {
    work(path.length + 1);
    const result = new NativeArray(path.length + 1);
    for (let index = 0; index < path.length; index++) result[index] = path[index];
    result[path.length] = key;
    return result;
  }
  function visit(value, path, depth) {
    work();
    if (usage.nodes === selected.maxNodes || depth > selected.maxDepth) unavailable();
    usage.nodes++;
    if (depth > usage.depth) usage.depth = depth;
    if (typeof value === 'string') return string(value);
    if (typeof value === 'bigint' || typeof value === 'symbol') return borrow(value, path);
    if (value === null || typeof value !== 'object' && typeof value !== 'function') return value;
    if (isProxy(value)) unavailable();
    if (typeof value === 'function' || path.length === 2 && path[0] === 'installation' &&
        apply(setHas, originalInstallationFields, [path[1]])) return borrow(value, path);
    const array = isArray(value), originalPrototype = prototype(value);
    if (originalPrototype !== (array ? arrayPrototype : objectPrototype) &&
        !(originalPrototype === null && !array)) return borrow(value, path);
    if (apply(setHas, active, [value])) unavailable();
    if (apply(mapHas, copies, [value])) return apply(mapGet, copies, [value]);
    let length;
    if (array) {
      const field = descriptor(value, 'length');
      if (field === undefined || !hasOwn(field, 'value') ||
          !safeInteger(field.value) || field.value < 0 ||
          field.value > selected.maxArrayItems - usage.arrayItems) unavailable();
      length = field.value;
      usage.arrayItems += length;
      work(length);
    }
    const keys = ownKeys(value);
    if (keys.length > selected.maxProperties - usage.properties) unavailable();
    usage.properties += keys.length;
    work(keys.length);
    const result = array ? new NativeArray(length) : create(originalPrototype);
    apply(mapSet, copies, [value, result]);
    apply(setAdd, active, [value]);
    // The supplier's envelope includes these traversal frames and key/path
    // arrays. Do not borrow the VM call stack as an unbounded depth allowance.
    frames[frames.length] = {value, result, path, depth, keys, array, index: 0};
    return result;
  }
  const packet = visit(input, [], 0);
  while (frames.length !== 0) {
    const frame = frames[frames.length - 1];
    if (frame.index === frame.keys.length) {
      apply(setDelete, active, [frame.value]);
      freeze(frame.result);
      frames.length--;
      continue;
    }
    const key = frame.keys[frame.index++];
    if (typeof key !== 'string') unavailable();
    string(key);
    const field = descriptor(frame.value, key);
    if (field === undefined || !hasOwn(field, 'value')) unavailable();
    if (frame.array && key === 'length') continue;
    if (frame.depth === selected.maxDepth) unavailable();
    define(frame.result, key, {
      value: visit(field.value, childPath(frame.path, key), frame.depth + 1),
      enumerable: field.enumerable, configurable: true, writable: true});
  }
  return freeze({packet, originalReferences: freeze(originals), usage: freeze(usage)});
}
