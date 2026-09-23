// Independent fixed-fixture assembly. This is NOT yet an accepted timing leg:
// the explicit remaining obligations below must close before paired acceptance.
import assert from 'node:assert/strict';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';
import {physicalType, exportPhysicalValue} from '../physical-values.mjs';
import {assertBoundedVectorRuntime, boundedVectorItem} from '../bounded-vector.mjs';
import {checked} from '../runtime-result.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {settleObligationRun} from './obligation-settlement.mjs';
import {equivalentExecutionCapacity} from './equivalent-capacity.mjs';
import {equivalentAcquisitionMetadata} from
  './equivalent-acquisition-metadata.mjs';

const runtime = new URL('../../../../../_build/js/release/build/benchmark_obligations/benchmark_obligations.js',
  import.meta.url);

export async function runEquivalentObligations(fixture, database, directory, suppliedSignal) {
  const f = retainedCase(fixture.workload, fixture.layout, fixture.rows);
  const l = f.limits;
  const started = performance.now();
  const moon = await import(runtime.href);
  const retention = checked(moon.obligationRetention(1073741824n));
  const executionCapacity = equivalentExecutionCapacity(f);
  const execution = checked(moon.obligationExecution(
    executionCapacity.limitBytes,
    executionCapacity.databaseBytes,
    executionCapacity.scratchBytes,
    f.workload === workloads[1] ? 4 : 3,
  ));
  const accounting = {
    nativeSemanticRows: 0,
    nativeSemanticCells: 0,
    nativeSemanticBytes: 0,
    jsMaterializedCells: 0,
    identityPasses: 0,
    identityPreimageBytes: 0,
    retainedStoreBytes: 0,
    measuredGuardWork: 0,
    measuredGuardBytes: 0,
    measuredGuardNodes: 0,
    reusedGuardWork: 0,
    reusedGuardBytes: 0,
    reusedGuardNodes: 0,
    comparisonWork: 0,
    comparisonBytes: 0,
    comparisonNodes: 0,
  };
  const ledgerReport = () => Object.fromEntries(Object.entries(moon.obligationRetentionUsage(retention))
    .map(([key, value]) => [key, typeof value === 'bigint' ? value.toString() : value]));
  const executionLedgerReport = () => Object.fromEntries(Object.entries(
    moon.obligationExecutionUsage(execution),
  ).map(([key, value]) => [key,
    typeof value === 'bigint' ? value.toString() : value]));
  assertBoundedVectorRuntime();
  const signal = suppliedSignal ? AbortSignal.any([suppliedSignal, AbortSignal.timeout(l.timeoutMs)])
    : AbortSignal.timeout(l.timeoutMs);
  let store, instance, connection, transaction = false, primary, report;
  let acquisitionEvidenceMetadata;
  const stages = [], completed = new Map();
  const run = Object.freeze({});
  const check = () => signal.throwIfAborted();
  const interrupt = () => connection?.interrupt();
  const budget = () => checked(moon.obligationBudget(l.cumulativeGuardWork,
    l.representationBytes * 4, l.cumulativeValueNodes, 64, l.maxValueBytes));
  const wire = {max_columns: l.maxColumns, max_order_work: l.cumulativeGuardWork,
    max_bytes: l.representationBytes, max_nodes: l.cumulativeValueNodes, max_depth: 64};
  const transport = {max_bytes: l.batchBytes, max_nodes: l.batchBytes,
    max_columns: l.maxColumns, max_rows: 2048, max_text_bytes: l.batchBytes};
  const physical = {max_rows: l.intermediateRows, max_cells: l.intermediateRows * l.maxColumns,
    max_nodes: l.cumulativeValueNodes, max_text_bytes: l.cumulativeValueTextBytes};
  const kind = name => name === 'payload' && f.layout === 'text-1024' ? 1 : 0;
  // The registered field names are ASCII. The product's receipt order is the
  // canonical UTF-16 field order, which JavaScript's default sort shares here.
  const sourceFields = [...f.fields].sort();
  const quote = name => '"' + name.replaceAll('"', '""') + '"';
  const list = names => names.map(quote).join(', ');
  const boundedSql = sql => {
    assert(Buffer.byteLength(sql) <= executionCapacity.maxSqlBytes,
      'equivalent SQL exceeds admitted scratch');
    return sql;
  };
  const exec = async sql => {
    check();
    await connection.run(boundedSql(sql));
    check();
  };
  async function scan(sql, names, guardBudget, {retain = false, identity = true, records = false,
    maxRows = l.intermediateRows, comparisons = [], outputReservation} = {}) {
    check();
    const stream = checked(moon.obligationBegin(names, names.map(kind), names.map(() => false),
      {...physical, max_rows: maxRows, max_cells: maxRows * names.length}, wire, transport,
      guardBudget, records, retain, identity, l.batchBytes));
    const demands = new Map(comparisons.map(({
      consumer, rhs, chargeFieldResolution = true,
    }) => [consumer,
      checked(moon.obligationComparison(stream, 'id',
        JSON.stringify([[exportPhysicalValue(rhs, {id: 'DOUBLE'})]]), l.maxValueBytes,
        {max_work: l.cumulativeGuardWork, max_bytes: l.representationBytes * 4,
          max_nodes: l.cumulativeValueNodes, max_depth: 64},
        chargeFieldResolution))]));
    if (retain) assert(outputReservation, 'output capacity must precede native execution');
    const writer = retain ? store.reserve(l.representationBytes) : undefined;
    if (writer) await writer.start();
    const result = await connection.stream(boundedSql(sql));
    assert.deepEqual(result.columnNames(), names);
    const types = names.map((name, index) => {
      const type = physicalType(result.columnType(index));
      assert.equal(type.id, kind(name) === 1 ? 'VARCHAR' : 'DOUBLE'); return type;
    });
    let chunks = 0;
    for (;;) {
      check();
      const chunk = await result.fetchChunk();
      if (!chunk || !chunk.rowCount) break;
      assert(chunk.rowCount <= 2048, 'unbounded native chunk');
      // Bounds are per chunk, not a full-result JS object representation.
      const count = Math.max(1, Math.min(executionCapacity.maxChunkRows,
        Math.floor(l.batchBytes /
        (names.length * (f.layout === 'text-1024' ? 1100 : 40) + 64))));
      for (let start = 0; start < chunk.rowCount; start += count) {
        check();
        const rows = Math.min(count, chunk.rowCount - start);
        const columns = names.map((_, column) => {
          const vector = chunk.getColumnVector(column).slice(start, rows);
          return Array.from({length: rows}, (_, row) => exportPhysicalValue(
            boundedVectorItem(vector, row, types[column], l.maxValueBytes), types[column]));
        });
        const transportText = JSON.stringify(columns);
        assert(Buffer.byteLength(transportText) <= l.batchBytes,
          'equivalent transport exceeds admitted scratch');
        accounting.nativeSemanticRows += rows;
        accounting.nativeSemanticCells += rows * names.length;
        accounting.nativeSemanticBytes += Buffer.byteLength(transportText);
        accounting.jsMaterializedCells += rows * names.length;
        const text = checked(moon.obligationAppend(stream, rows, transportText));
        if (writer && text) await writer.append(text);
        chunks++;
      }
    }
    const receipt = checked(moon.obligationFinish(stream));
    accounting.measuredGuardWork += receipt._5.work;
    accounting.measuredGuardBytes += receipt._5.bytes;
    accounting.measuredGuardNodes += receipt._5.nodes;
    if (identity) {
      accounting.identityPasses++;
      accounting.identityPreimageBytes += receipt._2;
    }
    if (retain) accounting.retainedStoreBytes += receipt._2;
    if (writer && receipt._0) await writer.append(receipt._0);
    const body = writer ? await writer.seal({cid: receipt._1, bytes: receipt._2}) : undefined;
    return Object.freeze({run, cid: receipt._1, bytes: receipt._2, rows: receipt._4,
      fields: Object.freeze([...names]),
      measurement: receipt._5, body, chunks, demands});
  }
  let sourceValidation;
  async function stage(name, query, names, inputs) {
    const before = performance.now(), ownBudget = budget();
    if (name !== 'capture') checked(moon.obligationExecutionTaskBegin(execution));
    // Declared bounded metadata allowance, not an observation of heap/RSS.
    // Reserve it with the independent file before this stage performs SQL.
    const metadataBytes = 4096 + names.reduce((sum, field) => sum + 256 + Buffer.byteLength(field) * 8, 0);
    const outputReservation = checked(moon.obligationReserveOutput(retention, l.representationBytes, metadataBytes));
    let reusedMeasurements = 0;
    for (const input of inputs) {
      const producer = completed.get(input);
      assert(producer?.run === run && producer.body.available(), 'foreign or expired input');
      assert(producer.rows <= l.intermediateRows, 'input row guard');
      // Same immutable table and successful initial content admission; do not
      // import it again or recompute its content hash for the new consumer.
      if (moon.obligationReuseMeasurement(producer.measurement, ownBudget)) {
        reusedMeasurements++;
        accounting.reusedGuardWork += producer.measurement.work;
        accounting.reusedGuardBytes += producer.measurement.bytes;
        accounting.reusedGuardNodes += producer.measurement.nodes;
      }
      else await scan(`SELECT ${list(producer.names)} FROM bench_${input} ORDER BY rowid`,
        producer.names, ownBudget, {identity: false});
    }
    if (name === 'join') {
      // Preflight the complete intermediate occurrence, not the final count.
      const result = await connection.runAndReadAll('SELECT COALESCE(SUM(l.n * r.n), 0)::HUGEINT AS pairs FROM (SELECT id, COUNT(*)::HUGEINT n FROM bench_a GROUP BY id) l JOIN (SELECT id, COUNT(*)::HUGEINT n FROM bench_b GROUP BY id) r USING (id)');
      check();
      assert(result.getRowObjects()[0].pairs <= BigInt(l.intermediateRows), 'join output guard');
    }
    await exec(`CREATE TEMP TABLE bench_${name} AS ${query}`);
    const comparisons = name === 'capture' ? [{consumer: 'a', rhs: 0}, {consumer: 'b', rhs: 0}]
      : name === 'a' && f.workload !== workloads[1] ? [{consumer: 'c', rhs: 0}] : [];
    const output = await scan(`SELECT ${list(names)} FROM bench_${name} ORDER BY rowid`, names,
      ownBudget, {retain: true, comparisons, outputReservation,
        records: name === 'capture'});
    const demandInput = name === 'capture' ? sourceValidation
      : ['a', 'b', 'c'].includes(name) ? completed.get(inputs[0]) : undefined;
    let demand;
    if (demandInput) {
      assert(demandInput.run === run && demandInput.demands.has(name), 'missing exact input demand');
      demand = checked(moon.obligationComparisonFinish(demandInput.demands.get(name), output.rows));
      accounting.comparisonWork += demand.physical_work;
      accounting.comparisonBytes += demand.physical_bytes;
      accounting.comparisonNodes += demand.physical_nodes;
    }
    const comparisonDemand = demand && Object.fromEntries(
      Object.entries(demand).map(([key, value]) =>
        [key, typeof value === 'bigint' ? value.toString() : value]),
    );
    const metadata = JSON.stringify({
      version: 'actql-benchmark-retained-completion/0.1',
      stage: name,
      inputs,
      fields: names,
      rows: output.rows,
      rows_cid: output.cid,
      bytes: output.bytes,
      measurement: output.measurement,
      comparison_demand: comparisonDemand ?? null,
    });
    const metadataActualBytes = Buffer.byteLength(metadata);
    assert(metadataActualBytes <= metadataBytes,
      'completion metadata exceeds pre-admitted allowance');
    checked(moon.obligationHoldOutput(
      outputReservation,
      output.bytes,
      metadataActualBytes,
    ));
    check();
    completed.set(name, Object.freeze({
      ...output,
      names: Object.freeze([...names]),
      metadata,
    }));
    if (name !== 'capture') checked(moon.obligationExecutionTaskFinish(execution));
    stages.push({stage: name, rows: output.rows, cid: output.cid, bytes: output.bytes,
      milliseconds: performance.now() - before, parameterInsertRows: 0,
      reusedMeasurements, metadataAllowanceBytes: metadataBytes,
      metadataActualBytes, comparisonDemand});
  }
  try {
    check();
    store = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 1073741824, maxFrameBytes: l.batchBytes,
      maxEntries: 16});
    instance = await DuckDBInstance.create(database, {access_mode: 'READ_ONLY', threads: '1',
      memory_limit: `${executionCapacity.databaseBytes}B`, max_temp_directory_size: '0B',
      preserve_insertion_order: 'true', enable_external_access: 'false',
      autoinstall_known_extensions: 'false', autoload_known_extensions: 'false'});
    connection = await instance.connect();
    signal.addEventListener('abort', interrupt, {once: true});
    await exec('BEGIN TRANSACTION'); transaction = true;
    const validationStarted = performance.now();
    const validation = await scan(`SELECT ${list(sourceFields)} FROM records ORDER BY rowid`,
      sourceFields, budget(), {records: true, maxRows: l.sourceRows,
        comparisons: [{consumer: 'capture', rhs: f.minimum,
          chargeFieldResolution: false}]});
    sourceValidation = validation;
    const validationMs = performance.now() - validationStarted;
    const names = f.workload === workloads[2] ? sourceFields : ['id'];
    await stage('capture', `SELECT ${list(names)} FROM records WHERE id > ${f.minimum} ORDER BY rowid`, names, []);
    acquisitionEvidenceMetadata = equivalentAcquisitionMetadata(
      f,
      validation,
      completed.get('capture'),
    );
    await stage('a', `SELECT ${list(names)} FROM bench_capture WHERE id >= 0 ORDER BY rowid`, names, ['capture']);
    await stage('b', `SELECT ${list(names)} FROM bench_capture WHERE id >= 0 ORDER BY rowid`, names, ['capture']);
    await exec('DROP TABLE bench_capture');
    let final;
    if (f.workload === workloads[1]) {
      await stage('join', 'SELECT l.id FROM bench_a l JOIN bench_b r ON l.id = r.id ORDER BY l.rowid, r.rowid', ['id'], ['a', 'b']);
      await exec('DROP TABLE bench_a'); await exec('DROP TABLE bench_b');
      await stage('count', 'SELECT COUNT(*)::DOUBLE AS n, COUNT(id)::DOUBLE AS present FROM bench_join', ['n', 'present'], ['join']);
      final = completed.get('count');
    } else {
      await exec('DROP TABLE bench_b');
      await stage('c', `SELECT ${list(names)} FROM bench_a WHERE id >= 0 ORDER BY rowid`, names, ['a']);
      final = completed.get('c');
    }
    const executionMs = performance.now() - started;
    const warmMs = stages.filter(stage => stage.stage !== 'capture')
      .reduce((sum, stage) => sum + stage.milliseconds, 0);
    const expected = f.identity(); // Independent oracle is not execution work.
    assert.equal(final.cid, expected.rowsCid); assert.equal(final.rows, expected.rows);
    report = {caseId: f.id, status: 'diagnostic-completed', acceptanceEligible: false,
      comparator: 'independent-obligation-assembly', executionMs, validationMs,
      warmMs,
      validationRows: validation.rows, validationCid: validation.cid, stages,
      acquisitionEvidenceMetadata,
      holding: store.status(), retentionLedger: ledgerReport(),
      executionLedger: executionLedgerReport(),
      accounting: Object.freeze({
        ...accounting,
        logicalGuardWork: accounting.measuredGuardWork +
          accounting.reusedGuardWork,
        logicalGuardBytes: accounting.measuredGuardBytes +
          accounting.reusedGuardBytes,
        logicalGuardNodes: accounting.measuredGuardNodes +
          accounting.reusedGuardNodes,
        domains: Object.freeze({
          nativeSemanticBytes: 'JSON transport actually supplied to bounded semantic admission',
          retainedStoreBytes: 'canonical row-array bytes written to independent holdings',
          logicalGuard: 'measured values plus charged reuse for each consumer',
          comparison: 'predicate measurement for exact input and consumer occurrence',
          identity: 'canonical row-array preimages actually hashed',
        }),
      }),
      capacity: {
        independentRetention: {limitBytes: 1073741824, fileReservedBytes: store.status().reservedBytes,
          metadataAllowanceBytes: stages.reduce((sum, stage) =>
            sum + stage.metadataAllowanceBytes, 0),
          metadataActualBytes: stages.reduce((sum, stage) =>
            sum + stage.metadataActualBytes, 0),
          scope: 'file bytes plus actual serialized completion metadata'},
        execution: {
          limitBytes: Number(executionCapacity.limitBytes),
          configuredEngineBytes: Number(executionCapacity.databaseBytes),
          scratchBytes: Number(executionCapacity.scratchBytes),
          admittedBytes: Number(executionCapacity.admittedBytes),
          scope: 'one DB reservation plus simultaneous bounded transport, semantic, container, and SQL scratch',
        },
        conformance: 'registered-fixture-bounded',
      },
      missing: ['matched process/cold timing boundaries']};
  } catch (error) { primary = error; }
  finally {
    signal.removeEventListener('abort', interrupt);
    const cleanupStarted = performance.now();
    await settleObligationRun(primary, [
      ['rollback', async () => { if (transaction) await connection.run('ROLLBACK'); }],
      ['connection-close', () => connection?.closeSync()],
      ['instance-close', () => {
        instance?.closeSync();
        checked(moon.obligationExecutionReleased(execution));
        if (report) report.releasedExecutionLedger = executionLedgerReport();
      }],
      ['store-revoke', () => store?.close()],
      ['store-cleanup', async () => {
        if (store) {
          await store.cleanup();
          assert.equal(store.status().cleanupPending, false);
        }
        completed.clear();
        sourceValidation = undefined;
        checked(moon.obligationRetentionReleased(retention));
        if (report) report.releasedRetentionLedger = ledgerReport();
      }],
    ]);
    if (report) report.cleanupMs = performance.now() - cleanupStarted;
  }
  return Object.freeze(report);
}
