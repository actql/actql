// Private local-IPC accounting, not ActQL identity or completion evidence.
// Exact primitive fields are copied before an await; no provider payload lives
// here. The common MoonBit ledger enforces cumulative relationships and limits.
import {ledgerLimitsFields, ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';

type LedgerField = (typeof ledgerLimitsFields)[number] | (typeof ledgerUsageFields)[number];
type ProcessLedger<Fields extends readonly LedgerField[]> = Readonly<{
  [Field in Fields[number] as Field['name']]: Field['bits'] extends 32 ? number : bigint
}>;
type EncodedLedger<Value> = Readonly<{[Key in keyof Value]: Value[Key] extends bigint ? string : Value[Key]}>;

function copy<Fields extends readonly LedgerField[]>(value: unknown, fields: Fields, wire: boolean): ProcessLedger<Fields> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('InvalidProcessAccounting');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== fields.length || keys.some(key =>
    typeof key !== 'string' || !fields.some(field => field.name === key))) {
    throw new TypeError('InvalidProcessAccounting');
  }
  const result: Record<string, number | bigint> = {};
  for (const {name, bits} of fields) {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) throw new TypeError('InvalidProcessAccounting');
    let item: unknown = descriptor.value;
    const maximum = (1n << BigInt(bits - 1)) - 1n;
    if (bits <= 53) {
      if (!Number.isInteger(item) || (item as number) < 0 || (item as number) > Number(maximum)) throw new TypeError('InvalidProcessAccounting');
    } else if (wire) {
      if (typeof item !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(item)) throw new TypeError('InvalidProcessAccounting');
      item = BigInt(item);
    }
    if (bits > 53 && (typeof item !== 'bigint' || item < 0n || item > maximum)) throw new TypeError('InvalidProcessAccounting');
    result[name] = item as number | bigint;
  }
  return Object.freeze(result) as ProcessLedger<Fields>;
}
const encode = <Value extends Readonly<Record<string, number | bigint>>>(value: Value) => Object.freeze(Object.fromEntries(Object.entries(value)
  .map(([key, item]) => [key, typeof item === 'bigint' ? item.toString() : item]))) as EncodedLedger<Value>;
export const snapshotProcessLimits = (value: unknown) => copy(value, ledgerLimitsFields, false);
export const encodeProcessLimits = (value: unknown) => encode(snapshotProcessLimits(value));
export const decodeProcessLimits = (value: unknown) => copy(value, ledgerLimitsFields, true);
export const snapshotProcessUsage = (value: unknown) => copy(value, ledgerUsageFields, false);
export const encodeProcessUsage = (value: unknown) => encode(snapshotProcessUsage(value));
export const decodeProcessUsage = (value: unknown) => copy(value, ledgerUsageFields, true);
export const emptyProcessUsage = () => Object.freeze(Object.fromEntries(
  ledgerUsageFields.map(({name, bits}) => [name, bits <= 53 ? 0 : 0n]),
)) as ProcessLedger<typeof ledgerUsageFields>;
