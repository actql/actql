// Pure, audited capacity adaptation of one pinned example assembly file.
// No runtime implementation, query, claim, or performance threshold is changed.
import {createHash} from 'node:crypto';

export const baselineHostLimitsSha256 = '905a1ac2bbd1fa702b4da3a07b1ebd1a39c0b4141cc0875f00f60858dca4dc9a';
export const baselineApplicationSha256 = 'e842e7d05dba4f596f4e74e257ce55f59c50ba14a3f300168fca8f8df727478d';

export function adaptBaselineAcquisitionLedger(source, receiverBytes) {
  if (createHash('sha256').update(source).digest('hex') !== baselineApplicationSha256) {
    throw Error('UnrecognizedBaselineApplication');
  }
  if (!Number.isSafeInteger(receiverBytes) || receiverBytes < 100000 || receiverBytes > 2147483647) {
    throw Error('InvalidBaselineReceiverBytes');
  }
  // One acquisition reservation plus three unchanged 100000-byte Compute
  // reservations. This diagnostic does not alter their per-attempt envelopes.
  const bytes = Math.max(500000, receiverBytes + 300000);
  const old = '    transfer_bytes: 500000L,';
  if (source.split(old).length !== 2) throw Error('AmbiguousBaselineLedger');
  // Same physical Run ceilings as the registered managed benchmark assembly.
  // Keep native candidate envelopes unchanged; this is not an execution permit.
  const retention = '    retained_bytes: 200000000L,';
  const execution = '    execution_bytes: 268435456L,';
  const start = source.indexOf('pub fn application_ledger(');
  const end = source.indexOf('pub fn application_dispatch(', start);
  const ledger = source.slice(start, end);
  if (start < 0 || end < start || ledger.split(retention).length !== 2 ||
      ledger.split(execution).length !== 2) throw Error('AmbiguousBaselineLedger');
  const adapted = ledger.replace(old, `    transfer_bytes: ${bytes}L,`)
    .replace(retention, '    retained_bytes: 1073741824L,')
    .replace(execution, '    execution_bytes: 4294967296L,');
  return Object.freeze({source: source.slice(0, start) + adapted + source.slice(end),
    transferBytes: bytes, originalSha256: baselineApplicationSha256});
}

export function adaptBaselineAcquisitionCapacity(source, fixture) {
  if (createHash('sha256').update(source).digest('hex') !== baselineHostLimitsSha256) {
    throw Error('UnrecognizedBaselineHostLimits');
  }
  // Compute still has the original small envelope. This adapter is deliberately
  // limited to the case whose full scan grows while its capture stays two rows.
  if (fixture.workload !== 'native-acquisition-full-validation-low-selectivity' ||
      fixture.layout !== 'narrow' || fixture.cardinalities.capture !== 2) {
    throw Error('UnsupportedBaselineAcquisitionProfile');
  }
  const rows = fixture.fields.length + fixture.rows + fixture.cardinalities.capture;
  const cells = rows * fixture.fields.length;
  const bytes = Math.max(100000, fixture.limits.representationBytes * 4);
  // This fixture has flat two-scalar rows, not nested values. Do not reserve
  // the cumulative multi-task work allowance separately for every held copy.
  const nodes = Math.max(10000, (rows + 1) * (fixture.fields.length + 1));
  const work = Math.max(1000000, fixture.limits.cumulativeGuardWork);
  const text = Math.max(100000, fixture.limits.cumulativeValueTextBytes);
  if (![rows, cells, bytes, nodes, work, text].every(value =>
    Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) {
    throw Error('InvalidBaselineAcquisitionCapacity');
  }
  const changes = [];
  const between = (value, name, next) => value.slice(value.indexOf(`fn ${name}(`), value.indexOf(`fn ${next}(`));
  const originalMeasurement = between(source, 'measurement', 'native_query_limits');
  const originalTransport = between(source, 'transport', 'acquisition_limits');
  function section(name, next, fields) {
    const start = source.indexOf(`fn ${name}(`);
    const end = source.indexOf(`fn ${next}(`, start);
    if (start < 0 || end < start) throw Error('MissingBaselineCapacitySection');
    const original = source.slice(start, end);
    const recordsStart = name === 'acquisition_limits' ? original.indexOf('      records: {') : -1;
    const recordsEnd = name === 'acquisition_limits' ? original.indexOf('    retention: {') : -1;
    if (name === 'acquisition_limits' && (recordsStart < 0 || recordsEnd <= recordsStart)) {
      throw Error('MissingBaselineRecordSection');
    }
    const replaced = original.replace(/\b([a-z_]+): (\d+)(?=[, ])/g, (match, key, number, offset) => {
      // Records contain contracts/identities and the two-row capture. Scaling
      // their allowances with the source scan fabricates retention pressure.
      if (recordsStart >= 0 && offset >= recordsStart && offset < recordsEnd) return match;
      if (!(key in fields)) return match;
      const value = Math.max(Number(number), fields[key]);
      if (value !== Number(number)) changes.push({section: name, field: key, before: Number(number), after: value});
      return `${key}: ${value}`;
    });
    source = source.slice(0, start) + replaced + source.slice(end);
  }
  section('measurement', 'native_query_limits', {max_work: work, max_bytes: bytes, max_nodes: nodes});
  section('transport', 'acquisition_limits', {max_rows: rows, max_bytes: bytes,
    max_nodes: nodes, max_text_bytes: text});
  section('acquisition_limits', 'dispatch_limits', {
    max_rows: rows, max_cells: cells, max_nodes: nodes, max_text_bytes: text,
    max_work: work, max_bytes: bytes, max_received_rows: rows, max_received_bytes: bytes,
    max_retained_wire_bytes: bytes,
  });
  // The old example shares measurement/transport helpers with Compute. Keep
  // those exact defaults; only Acquisition receives the scaled copies.
  const measured = between(source, 'measurement', 'native_query_limits');
  const transported = between(source, 'transport', 'acquisition_limits');
  source = source.replace(measured, originalMeasurement).replace(transported, originalTransport);
  const acquisition = between(source, 'acquisition_limits', 'dispatch_limits');
  source = source.replace(acquisition,
    measured.replace('fn measurement(', 'fn acquisition_measurement(') +
    transported.replace('fn transport(', 'fn acquisition_transport(') +
    acquisition.replaceAll('measurement()', 'acquisition_measurement()').replaceAll('transport()', 'acquisition_transport()'));
  return Object.freeze({source, changes: Object.freeze(changes.map(Object.freeze)),
    originalSha256: baselineHostLimitsSha256,
    adaptedSha256: createHash('sha256').update(source).digest('hex'),
    receiverBytes: bytes,
    profile: fixture.id, scope: 'selective-narrow-acquisition-capacity-only'});
}
