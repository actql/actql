// Private local-IPC accounting, not ActQL identity or completion evidence.
// Exact primitive fields are copied before an await; no provider payload lives
// here. The common MoonBit ledger enforces cumulative relationships and limits.
import {ledgerLimitsFields, ledgerUsageFields} from './ledger-contract.generated.mjs';

function copy(value, fields, wire) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidProcessAccounting');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== fields.length || keys.some(key =>
    typeof key !== 'string' || !fields.some(field => field.name === key))) {
    throw new TypeError('InvalidProcessAccounting');
  }
  const result = {};
  for (const {name, bits} of fields) {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) throw new TypeError('InvalidProcessAccounting');
    let item = descriptor.value;
    const maximum = (1n << BigInt(bits - 1)) - 1n;
    if (bits <= 53) {
      if (!Number.isInteger(item) || item < 0 || item > Number(maximum)) throw new TypeError('InvalidProcessAccounting');
    } else if (wire) {
      if (typeof item !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(item)) throw new TypeError('InvalidProcessAccounting');
      item = BigInt(item);
    }
    if (bits > 53 && (typeof item !== 'bigint' || item < 0n || item > maximum)) throw new TypeError('InvalidProcessAccounting');
    result[name] = item;
  }
  return Object.freeze(result);
}
const encode = value => Object.freeze(Object.fromEntries(Object.entries(value)
  .map(([key, item]) => [key, typeof item === 'bigint' ? item.toString() : item])));
export const snapshotProcessLimits = value => copy(value, ledgerLimitsFields, false);
export const encodeProcessLimits = value => encode(snapshotProcessLimits(value));
export const decodeProcessLimits = value => copy(value, ledgerLimitsFields, true);
export const snapshotProcessUsage = value => copy(value, ledgerUsageFields, false);
export const encodeProcessUsage = value => encode(snapshotProcessUsage(value));
export const decodeProcessUsage = value => copy(value, ledgerUsageFields, true);
export const emptyProcessUsage = () => Object.freeze(Object.fromEntries(
  ledgerUsageFields.map(({name, bits}) => [name, bits <= 53 ? 0 : 0n]),
));
