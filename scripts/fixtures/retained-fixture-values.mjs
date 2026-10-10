// Exact transport for authored test values only. Every node is tagged, so
// authored arrays/objects cannot collide with a sentinel. Never calls toJSON
// or getters, and never normalizes away an explicitly present undefined.
const fail = () => { throw new TypeError('InvalidRetainedFixtureValue'); };
export function encodeRetainedFixture(value) {
  const active = new WeakSet();
  const encode = value => {
    if (value === undefined) return ['undefined'];
    if (value === null) return ['null'];
    if (typeof value === 'string') return ['string', value];
    if (typeof value === 'boolean') return ['boolean', value];
    if (typeof value === 'number') return ['number', Object.is(value, -0) ? '-0' : String(value)];
    if (typeof value === 'bigint') return ['bigint', String(value)];
    if (typeof value !== 'object' || active.has(value)) return fail();
    const prototype = Object.getPrototypeOf(value);
    const array = Array.isArray(value);
    if (prototype !== (array ? Array.prototype : Object.prototype) &&
        !(prototype === null && !array)) return fail();
    active.add(value);
    const keys = Reflect.ownKeys(value);
    const entries = [];
    for (const key of keys) {
      if (array && key === 'length') continue;
      if (typeof key !== 'string') return fail();
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) return fail();
      entries.push([key, encode(descriptor.value)]);
    }
    active.delete(value);
    if (array) {
      if (entries.length !== value.length || entries.some(([key], index) => key !== String(index))) return fail();
      return ['array', entries.map(([, item]) => item)];
    }
    return [prototype === null ? 'null-object' : 'object', entries];
  };
  return JSON.stringify(['retained-fixture-values/0.1', encode(value)]);
}
export function decodeRetainedFixture(wire) {
  const root = JSON.parse(wire);
  if (!Array.isArray(root) || root.length !== 2 || root[0] !== 'retained-fixture-values/0.1') return fail();
  const decode = node => {
    if (!Array.isArray(node) || typeof node[0] !== 'string') return fail();
    const [tag, value] = node;
    if (tag === 'undefined' || tag === 'null') {
      if (node.length !== 1) return fail();
      return tag === 'null' ? null : undefined;
    }
    if (node.length !== 2) return fail();
    if (tag === 'string' || tag === 'boolean') {
      if (typeof value !== tag) return fail();
      return value;
    }
    if (tag === 'number') {
      if (typeof value !== 'string') return fail();
      const number = Number(value);
      if ((Object.is(number, -0) ? '-0' : String(number)) !== value) return fail();
      return number;
    }
    if (tag === 'bigint') {
      if (typeof value !== 'string' || !/^(?:0|-?[1-9][0-9]*)$/u.test(value)) return fail();
      return BigInt(value);
    }
    if (tag === 'array') {
      if (!Array.isArray(value)) return fail();
      return value.map(decode);
    }
    if (tag !== 'object' && tag !== 'null-object' || !Array.isArray(value)) return fail();
    const object = tag === 'null-object' ? Object.create(null) : {};
    for (const pair of value) {
      if (!Array.isArray(pair) || pair.length !== 2 || typeof pair[0] !== 'string' ||
          Object.hasOwn(object, pair[0])) return fail();
      Object.defineProperty(object, pair[0], {value: decode(pair[1]),
        enumerable: true, writable: true, configurable: true});
    }
    return object;
  };
  return decode(root[1]);
}
