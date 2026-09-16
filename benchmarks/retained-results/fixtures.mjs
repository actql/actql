// Independent deterministic benchmark data and expected values. This module
// never imports the product evaluator, canonical encoder or query compiler.
import {createHash} from 'node:crypto';

export const workloads = Object.freeze([
  'native-acquisition-full-validation-low-selectivity',
  'fixed-join-count-shrinking-intermediate',
  'retained-large-output-downstream-reuse',
]);
const layouts = Object.freeze(['narrow', 'numeric-64', 'text-1024']);

export function retainedCase(workload, layout, rows) {
  if (!workloads.includes(workload) || !layouts.includes(layout) ||
      !Number.isSafeInteger(rows) || rows < 100 || rows > 1000000 || rows % 2) {
    throw new TypeError('InvalidRetainedBenchmarkCase');
  }
  const fields = ['id', ...(layout === 'numeric-64'
    ? Array.from({length: 63}, (_, index) => `c${index + 1}`) : ['payload'])];
  const text = layout === 'text-1024' ? 'x'.repeat(1024) : undefined;
  const grouped = workload === workloads[1];
  const selective = workload === workloads[0];
  const captureRows = selective ? 2 : rows;
  const peakRows = grouped ? rows * 2 : captureRows;
  const cells = rows * fields.length;
  // Physical and logical ceilings are explicit, not runtime-derived estimates.
  // They apply equally to baseline/equivalent-obligations/new implementations.
  const limits = Object.freeze({
    sourceRows: rows, intermediateRows: peakRows, sourceCells: cells,
    maxColumns: fields.length, maxValueBytes: 2048,
    cumulativeValueNodes: cells * 16 + peakRows * 16,
    cumulativeValueTextBytes: layout === 'text-1024' ? rows * 2048 : cells * 16,
    cumulativeGuardWork: layout === 'text-1024' ? rows * 8192 : cells * 128,
    representationBytes: layout === 'text-1024' ? rows * 2048 : cells * 32,
    rowFrameBytes: 16384, batchBytes: 1048576,
    executionMemoryBytes: 4294967296,
    timeoutMs: rows < 10000 ? 120000 : 600000,
    cleanupTimeoutMs: 60000,
  });
  if (Object.entries(limits).some(([key, value]) => !Number.isSafeInteger(value) || value <= 0 ||
      (!['executionMemoryBytes'].includes(key) && value > 2147483647))) {
    throw new TypeError('BenchmarkLimitRequiresWiderCounter');
  }
  const sourceRow = index => {
    if (!Number.isSafeInteger(index) || index < 0 || index >= rows) throw new RangeError('SourceRow');
    const row = {id: grouped ? Math.floor(index / 2) : index};
    if (layout === 'numeric-64') {
      for (let column = 1; column < 64; column++) row[`c${column}`] = (index + column) % 1024;
    } else row.payload = text ?? (index % 1024);
    return row;
  };
  const outputCount = grouped ? 1 : captureRows;
  const outputRow = index => {
    if (!Number.isSafeInteger(index) || index < 0 || index >= outputCount) throw new RangeError('OutputRow');
    if (grouped) return {n: rows * 2, present: rows * 2};
    // Pure filter/select keeps source order. Wide retained-reuse preserves all
    // columns; low-selectivity acquisition projects id only after validation.
    return selective ? {id: rows - 2 + index} : sourceRow(index);
  };
  const identity = () => {
    const hash = createHash('sha256');
    let bytes = 0;
    const append = value => { bytes += Buffer.byteLength(value); hash.update(value); };
    append('[');
    for (let index = 0; index < outputCount; index++) {
      if (index) append(',');
      const row = outputRow(index);
      // These fixtures use finite exact integers and ASCII keys/text only.
      // UTF-16 key order is sufficient here, not a generic ActQL encoder.
      append(JSON.stringify(Object.fromEntries(Object.keys(row).sort().map(key => [key, row[key]]))));
    }
    append(']');
    return Object.freeze({rows: outputCount, bytes, rowsCid: `sha256:${hash.digest('hex')}`});
  };
  const sqlColumns = [grouped ? 'CAST(floor(i / 2) AS DOUBLE) AS id' : 'CAST(i AS DOUBLE) AS id'];
  if (layout === 'numeric-64') {
    for (let column = 1; column < 64; column++) sqlColumns.push(`CAST((i + ${column}) % 1024 AS DOUBLE) AS c${column}`);
  } else sqlColumns.push(layout === 'text-1024' ? "repeat('x', 1024) AS payload" : 'CAST(i % 1024 AS DOUBLE) AS payload');
  const program = () => {
    const selected = workload === workloads[2] ? [...fields] : ['id'];
    const from = stage => ({result: {stage, result: 'r'}});
    const result = columns => ({r: {from: 'out', fields: [...columns]}});
    const stages = [{id: 'acquire', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{filter: 'id > $minimum'}, {select: [...selected], as: 'out'}], results: result(selected)}];
    for (const id of ['compute_a', 'compute_b']) stages.push({id, inputs: {x: from('acquire')},
      steps: [{filter: 'id >= 0'}, {select: [...selected], as: 'out'}], results: result(selected)});
    if (grouped) {
      stages.push({id: 'joined', inputs: {l: from('compute_a'), r: from('compute_b')},
        steps: [{from: 'l', join: {with: 'r', kind: 'inner',
          on: [{left: 'id', right: 'id'}], select: {id: 'left.id'}}, as: 'out'}], results: result(['id'])});
      stages.push({id: 'counted', inputs: {x: from('joined')}, steps: [{group: {by: [],
        aggregates: {n: {fn: 'count'}, present: {fn: 'count', field: 'id'}}}, as: 'out'}], results: result(['n', 'present'])});
    } else stages.push({id: 'compute_c', inputs: {x: from('compute_a')},
      steps: [{filter: 'id >= 0'}, {select: [...selected], as: 'out'}], results: result(selected)});
    return {version: 'actql/0.1', id: `retained-benchmark-${workloads.indexOf(workload)}-${layout}-${rows}`,
      params: {minimum: {type: 'number', nullable: false}}, stages,
      results: {out: {from: {stage: stages.at(-1).id, result: 'r'}}}};
  };
  return Object.freeze({id: `${workload}/${layout}/${rows}`, workload, layout, rows,
    fields: Object.freeze(fields), limits, sourceRow, outputRow, identity, program,
    minimum: selective ? rows - 3 : -1,
    cardinalities: Object.freeze({source: rows, capture: captureRows, a: captureRows, b: captureRows,
      ...(grouped ? {join: rows * 2, count: 1} : {c: captureRows})}),
    createSourceSql: `CREATE TABLE records AS SELECT ${sqlColumns.join(', ')} FROM range(${rows}) source(i) ORDER BY i`,
  });
}

export function retainedMatrix() {
  return Object.freeze(workloads.flatMap(workload => [
    ...[100, 1000, 10000, 100000, 1000000].map(rows => retainedCase(workload, 'narrow', rows)),
    ...['numeric-64', 'text-1024'].flatMap(layout => [10000, 100000].map(rows => retainedCase(workload, layout, rows))),
  ]));
}
