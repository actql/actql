import {types as nodeTypes} from 'node:util';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

// The selected RowRun reserves the maximum page/codec overlap before it
// starts. Emit synchronously after the last current/await fence into one owned
// buffer; no object toJSON hook or provider getter participates in this codec.
export function encodeTypedResponseJson(value: unknown, maxBytes: number) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 2147483647) fail('InvalidKeyedResponseObservation');
  const body = Buffer.allocUnsafe(maxBytes);
  let position = 0, nodes = 0;
  const byte = (value: number) => {
    if (position === maxBytes) fail('InstalledRowPageLimit');
    body[position++] = value;
  };
  const ascii = (text: string) => { for (let index = 0; index < text.length; index++) byte(text.charCodeAt(index)); };
  const quoted = (text: string) => {
    byte(34);
    for (let index = 0; index < text.length; index++) {
      let code = text.charCodeAt(index);
      if (code === 34 || code === 92) { byte(92); byte(code); }
      else if (code < 32) {
        ascii('\\u00'); byte('0123456789abcdef'.charCodeAt(code >> 4)); byte('0123456789abcdef'.charCodeAt(code & 15));
      } else if (code < 128) byte(code);
      else if (code < 2048) { byte(192 | (code >> 6)); byte(128 | (code & 63)); }
      else {
        if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
          const next = text.charCodeAt(index + 1);
          if (next >= 0xdc00 && next <= 0xdfff) { code = 0x10000 + ((code - 0xd800) << 10) + next - 0xdc00; index++; }
        }
        if (code >= 0xd800 && code <= 0xdfff) {
          ascii('\\u');
          for (let shift = 12; shift >= 0; shift -= 4) byte('0123456789abcdef'.charCodeAt((code >> shift) & 15));
        } else if (code < 0x10000) {
          byte(224 | (code >> 12)); byte(128 | ((code >> 6) & 63)); byte(128 | (code & 63));
        } else {
          byte(240 | (code >> 18)); byte(128 | ((code >> 12) & 63)); byte(128 | ((code >> 6) & 63)); byte(128 | (code & 63));
        }
      }
    }
    byte(34);
  };
  const emit = (item: unknown, depth: number): void => {
    if (++nodes > maxBytes || depth > 32) fail('InvalidKeyedResponseObservation');
    if (typeof item === 'string') return quoted(item);
    if (item === null) return ascii('null');
    if (typeof item === 'boolean') return ascii(item ? 'true' : 'false');
    if (typeof item === 'number' && Number.isFinite(item)) return ascii(String(item));
    if (typeof item !== 'object' || nodeTypes.isProxy(item)) fail('InvalidKeyedResponseObservation');
    const array = Array.isArray(item), prototype = Object.getPrototypeOf(item);
    if (array ? prototype !== Array.prototype : prototype !== Object.prototype && prototype !== null) fail('InvalidKeyedResponseObservation');
    byte(array ? 91 : 123);
    if (array) {
      if (item.length > maxBytes) fail('InstalledRowPageLimit');
      for (let index = 0; index < item.length; index++) {
        if (index) byte(44);
        const field = Object.getOwnPropertyDescriptor(item, String(index));
        if (field && !Object.hasOwn(field, 'value')) fail('InvalidKeyedResponseObservation');
        emit(field === undefined ? null : field.value, depth + 1);
      }
    } else {
      let first = true;
      for (const key in item) {
        const field = Object.getOwnPropertyDescriptor(item, key);
        if (field === undefined) continue;
        if (!Object.hasOwn(field, 'value')) fail('InvalidKeyedResponseObservation');
        if (!first) byte(44); first = false;
        quoted(key); byte(58); emit(field.value, depth + 1);
      }
    }
    byte(array ? 93 : 125);
  };
  emit(value, 0);
  // Never retain a tiny view of the maximum backing in a raw holder or
  // decoder. The prepaid phase includes this exact owned copy beside it.
  const exact = Buffer.allocUnsafeSlow(position);
  exact.set(body.subarray(0, position));
  return exact;
}
