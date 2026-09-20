// Connector-private physical transport. This does not grant completion, own
// resource cleanup or replace MoonBit value/guard admission.
import {bindPhysicalValue, physicalType, PhysicalValueError} from './physical-values.mjs';

const suffixes = ['Null', 'Boolean', 'Varchar', 'Float', 'Double', 'Date', 'Decimal',
  'TinyInt', 'SmallInt', 'Integer', 'BigInt', 'HugeInt',
  'UTinyInt', 'USmallInt', 'UInteger', 'UBigInt', 'UHugeInt',
  'Timestamp', 'TimestampTZ', 'TimestampSeconds', 'TimestampMilliseconds', 'TimestampNanoseconds'];

export function createPhysicalAppender(appender, maxColumns) {
  if (!Number.isSafeInteger(maxColumns) || maxColumns < 1 ||
      !Number.isSafeInteger(appender.columnCount) || appender.columnCount < 1 ||
      appender.columnCount > maxColumns) throw new PhysicalValueError('ImportColumns');
  const types = Object.freeze(Array.from({length: appender.columnCount}, (_, i) =>
    physicalType(appender.columnType(i))));
  let pending, live = true;
  // Reuse the same conversion/range rules as prepared-parameter binding. Stage
  // the complete row first so a bad later cell cannot partially append a row.
  const staging = Object.freeze(Object.fromEntries(suffixes.map(suffix =>
    [`bind${suffix}`, (index, value) => { pending[index - 1] = [`append${suffix}`, value]; }])));
  return Object.freeze({
    types,
    invalidate() { live = false; },
    append(parameters) {
      if (!live || pending) throw new PhysicalValueError('AppenderUnavailable');
      if (!Array.isArray(parameters) || parameters.length !== types.length) {
        throw new PhysicalValueError('ImportColumns');
      }
      pending = [];
      try {
        for (let i = 0; i < types.length; i++) {
          const parameter = parameters[i];
          const expected = types[i];
          if (!parameter?.type || parameter.type.id !== expected.id ||
              parameter.type.precision !== expected.precision || parameter.type.scale !== expected.scale) {
            throw new PhysicalValueError('ImportPhysicalType');
          }
          bindPhysicalValue(staging, i + 1, parameter);
        }
        try {
          for (const [method, value] of pending) appender[method](value);
          appender.endRow();
        } catch (error) {
          // A partial native row is not correctable by resending another row.
          // The owning attempt must stop and reclaim its native resources.
          live = false;
          throw error;
        }
      } finally { pending = undefined; }
    },
  });
}
