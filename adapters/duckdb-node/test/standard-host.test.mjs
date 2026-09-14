import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeHostQuery, runStrategyNativeHostQuery, runBroadHostQuery, runFixedHostCompute, runStrategyHostCompute,
  openResidentStrategyEnvironment, importResidentStrategyInput, runResidentStrategyHostCompute } from '../host.mjs';
import { exerciseOwnedFixedTransport } from './owned-fixed-transport.mjs';
import { runCapturedStrategy } from '../strategy-host.mjs';
import { checked } from '../runtime-result.mjs';
import { runExample } from '../examples/physical-strategy.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

test('standard native and broad Node Hosts own verification through real capture and consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/physical_strategy_example'], { cwd: root });
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
  const publicApi = await readFile(join(root, 'src/query_planning/pkg.generated.mbti'), 'utf8');
  assert.doesNotMatch(publicApi, /pub fn duckdb_broad_attempt_output\(/);
  assert.match(publicApi, /pub fn duckdb_broad_attempt_row_count\(/);
  // Caller-controlled transport options cannot install semantic verification,
  // replacement SQL or another MoonBit runtime into either standard entry.
  const forbidden = () => assert.fail('standard Host used caller replacement');
  const suppliedLimits = { ...limits, verifier: forbidden, verify: forbidden,
    runtime: { nativeHostOpen: forbidden, broadHostOpen: forbidden }, sql: forbidden };
  // Independent fixed setup stays in conformance. The product entry loads only
  // duckdb_host_node and cannot receive these test functions as its verifier.
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const source = await readFile(join(root, 'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
  const contracts = [...source.matchAll(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/g)].map(match => JSON.parse(match[1]));
  const args = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'), 'utf8')];
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'standard-host-'));
  try {
    for (const kind of ['valid', 'empty', 'invalid-unused']) {
      const path = join(directory, `${kind}.duckdb`);
      const db = await DuckDBInstance.create(path);
      const connection = await db.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
        if (kind !== 'empty') await connection.run(kind === 'invalid-unused'
          ? "INSERT INTO records VALUES (3,30),(1,'Infinity'::DOUBLE)"
          : 'INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      } finally { connection.closeSync(); db.closeSync(); }
      const grant = await authorizeLocalDatabase(path);
      for (const strategy of ['native', 'broad']) {
        const native = strategy === 'native';
        const create = count => native ? fixture.issuedNativeCreate(...args, count, () => true)
          : fixture.issuedBroadCreate(...args.slice(0, -1), count, () => true);
        const configure = native ? fixture.issuedNativeConfiguration : fixture.issuedBroadConfiguration;
        const close = native ? fixture.issuedNativeClose : fixture.issuedBroadClose;
        const execute = native ? runNativeHostQuery : runBroadHostQuery;
        const prepared = create(100);
        const setup = configure(prepared);
        close(prepared); // unused test issuer is not the product issuer
        if (kind === 'invalid-unused') {
          await assert.rejects(execute(grant, setup, limits), error => {
            assert.equal(error.code, 'MoonBitHostFailure');
            assert(error.cause); // Preserve the typed admission failure, not a JS ABI error.
            return true;
          });
          continue;
        }
        const captured = await execute(grant, setup, suppliedLimits);
        const expected = kind === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
        const observation = JSON.parse(captured.document());
        assert.equal(observation.output.rows_cid, hash(expected));
        assert.equal(observation.output.row_count, expected.length);
        const materialize = () => native ? captured.output()
          : captured.bindInput(fixture.issuedBroadConsumer(prepared), 0);
        const consume = native ? fixture.issuedNativeConsumeOutput : fixture.issuedBroadConsumeInput;
        const output = materialize();
        let assertFixedUnavailable;
        if (native) {
          // Only our uniquely created fixture file is moved, then restored.
          // Compute must work even when the authorized source path is absent.
          const heldPath = `${path}.held`;
          await rename(path, heldPath);
          try {
            assertFixedUnavailable = await exerciseOwnedFixedTransport(
              fixture, prepared, output, contracts, limits, kind === 'empty' ? [] : [3, 3],
            );
          } finally { await rename(heldPath, path); }
        }
        if (expected.length) assert.equal(consume(prepared, output, 0), 'null');
        assert.equal(consume(prepared, output, 100), hash(expected));
        const foreign = create(100);
        assert.equal(consume(foreign, output, 100), 'null');
        if (!native) assert.throws(() => captured.bindInput(fixture.issuedBroadConsumer(foreign), 0),
          { code: 'MoonBitHostFailure' });
        close(foreign);
        assert.equal(consume(prepared, materialize(), 100), hash(expected));
        if (native) {
          const fixed = fixture.ownedFixedCreate(prepared, output, ...contracts);
          const setup = fixture.ownedFixedConfiguration(fixed);
          const result = await runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 });
          const fixedOutput = result.output();
          const expectedFixed = hash(kind === 'empty' ? [] : [{ id: 3 }, { id: 3 }]);
          try {
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            captured.close();
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            await assert.rejects(runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 }));
          } finally { result.close(); }
          assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), 'null');
        }
        captured.close();
        assertFixedUnavailable?.();
        assert.throws(materialize, { code: 'IssuerClosed' });
        assert.equal(consume(prepared, output, 100), 'null');
        const cancelled = new AbortController();
        cancelled.abort();
        await assert.rejects(execute(grant, setup, limits, cancelled.signal));
        await assert.rejects(execute({}, setup, limits));
        const limited = create(0);
        if (expected.length) await assert.rejects(execute(grant,
          configure(limited), limits), { code: 'MoonBitHostFailure' });
        close(limited);
      }
      if (kind === 'valid') await exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

async function exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits) {
  const hostRuntime = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_host_node/duckdb_host_node.js')));
  const stage = (id, producer, filter) => ({ id, inputs: { x: { result: { stage: producer, result: 'r' } } },
    steps: [{ filter }, { select: ['id'], as: 'out' }],
    results: { r: { from: 'out', fields: ['id'] } } });
  const program = JSON.stringify({ version: 'actql/0.1', id: 'p',
    params: { minimum: { type: 'number', nullable: false } },
    stages: [{ id: 'a', inputs: { remote: { connector: 'crm/main', resource: 'r' } },
      steps: [{ filter: 'id > $minimum', as: 'filtered' }, { select: ['id'], as: 'captured' }],
      results: { r: { from: 'captured', fields: ['id'] } } },
    stage('compute_a', 'a', 'id > 2'), stage('compute_b', 'a', 'id > 0'), stage('compute_c', 'compute_a', 'id < 9')],
    results: { b: { from: { stage: 'compute_b', result: 'r' } }, c: { from: { stage: 'compute_c', result: 'r' } } } });
  async function replaceRows(sql) {
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try { await connection.run('DELETE FROM records'); await connection.run(sql); }
    finally { connection.closeSync(); db.closeSync(); }
  }
  // The runnable application reads user-supplied documents, not conformance
  // exports or test catalogs. Tests supply their own documents at its boundary.
  const exampleDirectory = await mkdtemp(join(root, '_build/duckdb-fixtures/example-input-'));
  try {
    const environment = join(exampleDirectory, 'environment.json');
    const programFile = join(exampleDirectory, 'program.json');
    const parameters = join(exampleDirectory, 'parameters.json');
    const exampleProgram = await readFile(join(root, 'adapters/duckdb-node/examples/program.json'), 'utf8');
    await Promise.all([writeFile(environment, args[0]), writeFile(programFile, exampleProgram),
      writeFile(parameters, '{"minimum":1}')]);
    for (const [estimate, expected] of [['1', ['duckdb', 'duckdb', 'duckdb']],
      ['20', ['local', 'local', 'local']], ['5', ['duckdb', 'duckdb', 'local']]]) {
      const result = await runExample({ database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate });
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.equal(result.report.program_success, false);
        assert.deepEqual(result.report.completed.map(item => item.realization), expected);
        assert.equal(result.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
        assert(BigInt(result.report.explanation.ledger.transferred_bytes) > 0n);
      } finally { result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    const residentExample = await runExample({ database: path, environment, environmentCid: args[1],
      program: programFile, parameters, nativeMilliseconds: '20', resident: true });
    try {
      assert.equal(residentExample.report.status, 'host-tasks-completed');
      assert.deepEqual(residentExample.report.completed.map(item => item.realization),
        ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
      assert.equal(residentExample.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
      assert.equal(residentExample.report.cleanup_pending, false);
      assert.equal(residentExample.report.explanation.selection.dispatch_authorized, false);
      assert.equal(residentExample.report.explanation.selection.tasks[0].resident_profile.database_bytes, '134217728');
    } finally { residentExample.close(); }
    // Statically unsupported native expressions must never win on price.
    const arithmeticProgram = JSON.parse(exampleProgram);
    arithmeticProgram.stages[1].steps[0].filter = 'id + 0 > 2';
    await writeFile(programFile, JSON.stringify(arithmeticProgram));
    for (const estimate of ['1', '20']) {
      const result = await runExample({ database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate });
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.equal(result.report.completed[0].realization, 'local');
        assert.equal(result.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
        assert(result.report.explanation.excluded_realizations.some(item =>
          item.task === 1 && item.reason === 'unsupported_predicate'));
      } finally { result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    await writeFile(programFile, exampleProgram);
    const cli = await promisify(execFile)(process.execPath, [
      'adapters/duckdb-node/examples/physical-strategy.mjs', '--database', path,
      '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '5',
    ], { cwd: root, maxBuffer: 1000000 });
    assert.equal(JSON.parse(cli.stdout).status, 'host-tasks-completed');
    await assert.rejects(runExample({ database: path, environment,
      environmentCid: 'sha256:' + '0'.repeat(64), program: programFile,
      parameters, nativeMilliseconds: '5' }));
    const applicationSource = await readFile(join(root, 'src/physical_strategy_example/moon.pkg'), 'utf8');
    assert.doesNotMatch(applicationSource, /conformance|query_integration/);
    const script = await readFile(join(root, 'adapters/duckdb-node/examples/physical-strategy.mjs'), 'utf8');
    assert.doesNotMatch(script, /duckdb_conformance|query_integration/);
  } finally { await rm(exampleDirectory, { recursive: true, force: true }); }
  // Inspect the product bridge's reservation phases without issuing execution
  // evidence: no native task is run, and its deliberately absent result fails.
  const phaseFixture = fixture.strategyFixtureCreate(...args, program);
  for (const transferCost of [1n, 20n]) {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      assert.equal(fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f))), true);
      assert.equal(fixture.strategyFixtureReplan(f, transferCost), true);
      execution = await runCapturedStrategy(fixture.strategyFixtureDispatch(f), suppliedLimits,
        { maxRows: 100, maxCells: 1000 });
      assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
      // The 300000-byte ledger already contains acquisition traffic. Three
      // 100000-byte native transfer reservations cannot fit; equal-cost mixed
      // strategies follow the fixture's fixed enumeration priority.
      assert.deepEqual(execution.completed.map(item => [item.task, item.realization]),
        [1, 2, 3].map(task => [task, transferCost === 1n && task !== 1 ? 'duckdb' : 'local']));
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      const spent = BigInt(capture.usage.transportBytes) + execution.completed.reduce(
        (sum, item) => sum + BigInt(item.transport?.transportBytes ?? 0), 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      const explanation = execution.explain();
      assert.equal(explanation.program_success, false);
      assert.equal(explanation.assessment_complete, true);
      assert.equal(explanation.selection.reason, 'estimated_fastest');
      assert.equal(explanation.selection.remaining_at_selection.estimated_milliseconds,
        transferCost === 1n ? '14' : '30');
      assert.equal(explanation.selection.ledger_at_selection.transferred_bytes,
        String(capture.usage.transportBytes));
      assert.equal(explanation.ledger.transferred_bytes, String(spent));
      assert.deepEqual(explanation.available_root_statistics, { rows: '3', canonical_wire_bytes: '28' });
      assert(explanation.assessed_strategies.some(item => item.rejection === 'transfer_limit'));
      assert(explanation.selection.tasks.every(item => item.completed));
      assert.deepEqual(explanation.selection.tasks[0].work_estimates,
        [{ slots: [0, 1, 2, 3, 4], milliseconds: '10' }]);
      assert.throws(() => execution.explain(1, 10000));
      assert.throws(() => execution.explain(-1, 10000), { code: 'InvalidExplanationLimit' });
      assert.notEqual(execution.output(3), undefined);
      capture.close();
      assert.equal(execution.explain().available_root_statistics, null);
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      assert.throws(() => execution.output(3), { code: 'ReleasedStrategy' });
    } finally { execution?.close(); capture.close(); }
  }
  // Product dispatch automatically refreshes unstarted choices after actual
  // completion. A's observed two rows replace its three-row forecast for C.
  {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      assert.equal(fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f))), true);
      const setup = fixture.strategyFixtureAdaptiveDispatch(f);
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 0), 'LDD');
      execution = await runCapturedStrategy(setup, suppliedLimits, { maxRows: 100, maxCells: 1000 });
      assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
      assert.deepEqual(execution.completed.map(item => item.realization), ['local', 'duckdb', 'local']);
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 1), 'LDL');
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 2), 'LDL');
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      const spent = BigInt(capture.usage.transportBytes) + execution.completed.reduce(
        (sum, item) => sum + BigInt(item.transport?.transportBytes ?? 0), 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      assert.equal(execution.explain().selection.remaining_at_selection.estimated_milliseconds, '4');
      capture.close();
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().transferredBytes, spent);
    } finally { execution?.close(); capture.close(); }
  }
  const smallFixture = fixture.strategyFixtureCreate(...args, program);
  for (const selected of [false, true]) {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f)));
      if (selected) assert.equal(fixture.strategyFixtureReplan(f, 1n), true);
      execution = await runCapturedStrategy(fixture.strategyFixtureDispatch(f), suppliedLimits,
        { maxRows: 0, maxCells: 0 });
      assert.equal(execution.status, 'host-tasks-failed');
      assert(execution.failure);
      assert.deepEqual(execution.completed.map(item => item.task), selected ? [1] : []);
      assert.equal(fixture.strategyFixtureCid(f, 2), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 3), 'null');
      assert.equal(execution.usage().reservedTransferBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
      capture.close();
      if (selected) assert.equal(fixture.strategyFixtureCid(f, 1), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
    } finally { execution?.close(); capture.close(); }
  }
  await assert.rejects(runStrategyNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(smallFixture),
    fixture.strategyFixtureLedger(smallFixture), suppliedLimits));
  for (const field of [0, 1, 2, 3, 4, 5]) {
    assert.equal(fixture.strategyFixtureUsage(smallFixture, field), 0n);
  }
  for (const mode of ['unauthorized', 'cancelled', 'transfer']) {
    const failed = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const abort = new AbortController();
    if (mode === 'cancelled') abort.abort();
    await assert.rejects(runStrategyNativeHostQuery(mode === 'unauthorized' ? {} : grant,
      fixture.strategyFixtureAcquisition(failed), fixture.strategyFixtureLedger(failed),
      mode === 'transfer' ? { ...suppliedLimits, maxTransportBytes: 0 } : suppliedLimits, abort.signal));
    for (const field of [0, 1, 2, 4, 5]) {
      assert.equal(fixture.strategyFixtureUsage(failed, field), 0n);
    }
    // The chosen attempt was frozen before even a source-open failure, and
    // releasing unused capacity never refunds that bounded attempt record.
    assert.equal(fixture.strategyFixtureUsage(failed, 3), 1n);
  }
  const accountedFixture = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
  const accounted = await runStrategyNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(accountedFixture),
    fixture.strategyFixtureLedger(accountedFixture), suppliedLimits);
  const accountedComputes = [];
  try {
    assert.equal(accounted.output, undefined);
    assert.equal(accounted.source, undefined);
    const graph = fixture.strategyFixtureGraph(accountedFixture);
    const dag = accounted.openDAG(graph);
    assert.equal(fixture.strategyFixtureAttach(accountedFixture, dag), true);
    assert.throws(() => accounted.openDAG(graph));
    const rootBytes = accounted.physicalCapacity.retentionBytes;
    assert.equal(rootBytes, 139926400n);
    assert.equal(accounted.physicalCapacity.receiverScratchBytes, 14475520n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), BigInt(accounted.usage.transportBytes));
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), rootBytes);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 2), 0n);
    for (const task of [1, 2, 3]) {
      accountedComputes.push(await runStrategyHostCompute(
        fixture.strategyFixtureCompute(accountedFixture, task), suppliedLimits,
        { maxRows: 100, maxCells: 1000 }));
    }
    const spent = BigInt(accounted.usage.transportBytes)
      + accountedComputes.reduce((sum, result) => sum + BigInt(result.usage.transportBytes), 0n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), spent);
    accounted.close();
    assert.throws(() => accounted.openDAG(graph), { code: 'IssuerClosed' });
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), rootBytes + 3n * 2771200n);
    assert.equal(fixture.strategyFixtureCid(accountedFixture, 3), hash([{ id: 3 }, { id: 3 }]));
    for (const result of accountedComputes) result.close();
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), 0n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), spent);
  } finally {
    for (const result of accountedComputes) result.close();
    accounted.close();
  }
  const phaseCapture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(phaseFixture), suppliedLimits);
  const bridge = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_host_node/duckdb_host_node.js')));
  let phaseRun;
  const accepted = result => { assert.equal(result.$tag, 1); return result._0; };
  try {
    assert.equal(fixture.strategyFixtureOpen(phaseFixture, phaseCapture.source()), true);
    const setup = fixture.strategyFixtureCompute(phaseFixture, 1);
    assert.equal(accepted(bridge.computeStrategyScratchCapacity(setup)), 11708160n);
    phaseRun = accepted(bridge.computeStrategyHostOpen(setup, () => false, 100000n, 134217728n));
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 145925888n);
    accepted(bridge.computeHostPhysicalSettle(phaseRun, true));
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 11708160n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 5), 2771200n);
    assert.equal(bridge.computeHostComplete(phaseRun).$tag, 0);
    bridge.computeHostAbort(phaseRun);
    bridge.computeHostClose(phaseRun);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 0n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 5), 0n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 4), 0n);
  } finally {
    if (phaseRun) { bridge.computeHostAbort(phaseRun); bridge.computeHostClose(phaseRun); }
    phaseCapture.close();
  }
  let freshDuckDBTransfer;
  for (const layout of [[true, true, true], [true, false, true], [false, true, false]]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const held = [];
    let transferred = 0n;
    let retained = 0n;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      // A and B must consume one immutable observation, not read this mutation.
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (let task = 1; task <= 3; task++) {
        if (task === 3) capture.close();
        if (layout[task - 1]) {
          const setup = fixture.strategyFixtureCompute(f, task);
          if (task === 2) {
            // An unstarted oversized reservation cannot erase already spent A
            // transfer or create a DB. Retrying this unstarted configuration is
            // explicit test orchestration, not automatic failed-attempt fallback.
            const attempts = fixture.strategyFixtureUsage(f, 3);
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxTransportBytes: 300001 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            // DB memory alone fits, but the bounded transport containers do not.
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxCells: 2000000 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          }
          const completed = await runStrategyHostCompute(setup, suppliedLimits, { maxRows: 100, maxCells: 1000 });
          transferred += BigInt(completed.usage.transportBytes);
          assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
          assert.equal(fixture.strategyFixtureUsage(f, 1), 0n);
          assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          held.push([task, completed]);
          retained += 2771200n;
          assert.equal(completed.physicalCapacity.retentionBytes, 2771200n);
          assert.equal(completed.physicalCapacity.receiverScratchBytes, 11708160n);
          assert.equal(completed.physicalCapacity.executionBytes,
            completed.physicalCapacity.databaseBytes + completed.physicalCapacity.scratchBytes + 11708160n);
          assert.equal(fixture.strategyFixtureUsage(f, 4), retained);
          assert.equal(fixture.strategyFixtureUsage(f, 5), 0n);
          // Each task really imports into a fresh DB, including DuckDB A -> C.
          assert.equal(completed.importedRows, task === 3 ? 2 : 3);
        } else {
          assert.equal(fixture.strategyFixtureLocal(f, task), true);
          retained += 7760000n;
          assert.equal(fixture.strategyFixtureUsage(f, 4), retained);
        }
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      const beforeParentClose = fixture.strategyFixtureUsage(f, 4);
      held.find(([task]) => task === 1)?.[1].close();
      // C's completed input anchors still retain A, even after A's port closes.
      assert.equal(fixture.strategyFixtureUsage(f, 4), beforeParentClose);
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
      const last = held.find(([task]) => task === 3)?.[1];
      if (last) {
        last.close();
        assert.equal(fixture.strategyFixtureCanBind(f, 3), false);
      }
      fixture.strategyFixtureCloseOutput(f, 3); // includes a Local C
      fixture.strategyFixtureCloseOutput(f, 2);
      fixture.strategyFixtureCloseOutput(f, 1);
      assert.equal(fixture.strategyFixtureUsage(f, 4), 0n);
      assert.equal(fixture.strategyFixtureNext(f), -1); // release is not an unexecuted task
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred); // close never refunds transfer
      if (layout.every(Boolean)) freshDuckDBTransfer = transferred;
    } finally {
      capture.close();
      for (const [, result] of held) result.close();
    }
  }
  // Shared X is imported once; both branches read that exact capture, and C
  // consumes A's retained native table without importing A from the Host again.
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const firstTask = checked(hostRuntime.strategyHostNext(dispatch));
      const beforeProvision = fixture.strategyFixtureUsage(f, 3);
      await assert.rejects(openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1,
        { ...suppliedLimits, memoryBytes: suppliedLimits.memoryBytes / 2 }));
      assert.equal(fixture.strategyFixtureUsage(f, 3), beforeProvision);
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1, suppliedLimits);
      const mapping = { maxEntries: 1000, maxNameBytes: 10000 };
      const imported = await importResidentStrategyInput(environment, 0, 4000000n, suppliedLimits, mapping);
      assert.equal(imported.importedRows, 3);
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (let task = 1; task <= 3; task++) {
        const table = environment.table(task === 3 ? 1 : 0);
        const selected = task === 1 ? firstTask : checked(hostRuntime.strategyHostNext(dispatch));
        const compute = checked(hostRuntime.strategyHostTakeNative(selected));
        if (task === 1) {
          await assert.rejects(runResidentStrategyHostCompute(compute, environment, table,
            { ...suppliedLimits, threads: 2 }, mapping), { code: 'ResidentProfileMismatch' });
        }
        const output = await runResidentStrategyHostCompute(compute,
          environment, table, suppliedLimits, mapping);
        outputs.push(output);
        assert.equal(output.importedRows, 0);
        assert.equal(environment.hasTable(0), task === 1,
          'X remains through A and is removed only after B commits its last use');
        assert.equal(environment.hasTable(1), task < 3,
          'A remains until C commits its read; its Host result stays independent');
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      const residentTransfer = BigInt(imported.usage.transportBytes) +
        outputs.reduce((sum, output) => sum + BigInt(output.usage.transportBytes), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), residentTransfer);
      assert(residentTransfer < freshDuckDBTransfer,
        `resident ${residentTransfer} must transfer less than fresh ${freshDuckDBTransfer}`);
      await environment.close();
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
    } finally {
      if (environment) await environment.close();
      for (const output of outputs) output.close();
      capture.close();
    }
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const cancelledFixture = fixture.strategyFixtureCreate(...args, program);
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      checked(hostRuntime.strategyHostNext(dispatch));
      environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1, suppliedLimits);
      await assert.rejects(importResidentStrategyInput(environment, 0, 4000000n,
        { ...suppliedLimits, maxTransportBytes: 20 }, { maxEntries: 1000, maxNameBytes: 10000 }));
      assert.equal(fixture.strategyFixtureNext(f), -1, 'failed import stops the common DAG even without its driver');
      assert.equal(environment.hasTable(0), false);
      assert.equal(fixture.strategyFixtureCid(f, 1), 'null');
      assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes));
      await environment.close();
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      assert.equal(fixture.strategyFixtureNext(f), -1, 'cleanup does not authorize fallback');
    } finally { if (environment) await environment.close(); capture.close(); }
  }
  for (const failure of ['received-row-limit', 'cancelled']) {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    let environment;
    let a;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const graph = fixture.strategyFixtureRun(f);
      const selectedA = checked(hostRuntime.strategyHostNext(dispatch));
      environment = await openResidentStrategyEnvironment(graph, 1, suppliedLimits);
      const mapping = { maxEntries: 1000, maxNameBytes: 10000 };
      await importResidentStrategyInput(environment, 0, 4000000n, suppliedLimits, mapping);
      a = await runResidentStrategyHostCompute(checked(hostRuntime.strategyHostTakeNative(selectedA)),
        environment, environment.table(0), suppliedLimits, mapping);
      const before = fixture.strategyFixtureUsage(f, 0);
      const selectedB = checked(hostRuntime.strategyHostNext(dispatch));
      const abort = new AbortController();
      if (failure === 'cancelled') abort.abort();
      await assert.rejects(runResidentStrategyHostCompute(checked(hostRuntime.strategyHostTakeNative(selectedB)),
        environment, environment.table(0),
        { ...suppliedLimits, maxRows: failure === 'received-row-limit' ? 2 : 100 }, mapping, abort.signal));
      assert.equal(fixture.strategyFixtureNext(f), -1, 'failed B cannot authorize unstarted C');
      assert.equal(fixture.strategyFixtureCid(f, 2), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 3), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 1), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(environment.hasTable(1), true, 'B rollback does not remove committed A');
      assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
      assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes),
        'settling B does not settle the shared database');
      assert(fixture.strategyFixtureUsage(f, 0) >= before);
      const spent = fixture.strategyFixtureUsage(f, 0);
      await environment.close();
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
      assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
    } finally {
      if (environment) await environment.close();
      a?.close();
      capture.close();
    }
  }
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const graph = fixture.strategyFixtureRun(f);
      for (let index = 1; index <= 3; index++) {
        const task = checked(hostRuntime.strategyHostNext(dispatch));
        assert.equal(hostRuntime.strategyHostTask(task), index);
        if (index === 2) {
          // Two new imports plus both task envelopes exceed the remaining
          // transfer budget. Reselection must choose Local B, not erase A's
          // spent transfer to retain the old all-resident placement.
          assert.equal(hostRuntime.strategyHostNative(task), false);
          checked(hostRuntime.strategyHostExecuteLocal(task));
          capture.close();
          continue;
        }
        assert.equal(hostRuntime.strategyHostResident(task), true, `resident task ${index}`);
        const [producer, bytes, entries, names] = checked(hostRuntime.strategyHostResidentInput(dispatch, index));
        const mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
        environment ??= await openResidentStrategyEnvironment(graph, index, suppliedLimits);
        if (!environment.hasTable(Number(producer))) {
          const imported = await importResidentStrategyInput(environment, Number(producer), bytes,
            suppliedLimits, mapping);
          assert.equal(imported.importedRows, index === 3 ? 2 : 3);
        }
        const result = await runResidentStrategyHostCompute(
          checked(hostRuntime.strategyHostTakeNative(task)), environment, environment.table(Number(producer)),
          suppliedLimits, mapping);
        outputs.push(result);
        if (index === 1) {
          const spent = fixture.strategyFixtureUsage(f, 0);
          await environment.close();
          assert.equal(environment.status().pending, false);
          assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
          assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
          environment = undefined;
        }
        if (index === 2) capture.close();
      }
      assert.equal(outputs.length, 2, 'only A and C execute on DuckDB; completed A is not retried');
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally {
      if (environment) await environment.close();
      for (const output of outputs) output.close();
      capture.close();
    }
  }
  {
    const selectedFixture = fixture.strategyFixtureCreate(...args, program);
    const selectedCapture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(selectedFixture), suppliedLimits);
    let result;
    try {
      assert.equal(fixture.strategyFixtureOpen(selectedFixture, selectedCapture.source()), true);
      const setup = fixture.strategyFixtureResidentDispatch(selectedFixture);
      result = await runCapturedStrategy(setup, suppliedLimits, { maxRows: 100, maxCells: 1000 });
      assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
      assert.equal(result.cleanupPending(), false);
      assert.equal(await result.cleanup(), true);
      assert.deepEqual(result.completed.map(task => task.realization), ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
      assert.equal(fixture.strategyFixtureCid(selectedFixture, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally { result?.close(); selectedCapture.close(); }
  }
  const captured = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(cancelledFixture), suppliedLimits);
  let first;
  try {
    assert.equal(fixture.strategyFixtureOpen(cancelledFixture, captured.source()), true);
    first = await runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 1), suppliedLimits,
      { maxRows: 100, maxCells: 1000 });
    const cancellation = new AbortController();
    cancellation.abort();
    await assert.rejects(runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 2), suppliedLimits,
      { maxRows: 100, maxCells: 1000 }, cancellation.signal));
    assert.equal(fixture.strategyFixtureNext(cancelledFixture), -1);
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 1), hash([{ id: 3 }, { id: 3 }]));
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 2), 'null');
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 3), 'null');
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 0), BigInt(first.usage.transportBytes));
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 1), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 2), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 5), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 4), 2771200n);
  } finally { captured.close(); first?.close(); }
  for (const initialTransferCost of [1n, 20n]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost), true);
      const firstPlacement = initialTransferCost === 1n ? 'duckdb' : 'local';
      assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 6n : 30n);
      for (let task = 1; task <= 3; task++) {
        if (task === 2) {
          const spent = fixture.strategyFixtureUsage(f, 0);
          assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost === 1n ? 20n : 1n), true);
          assert.equal(fixture.strategyFixturePlacement(f, 1), firstPlacement);
          assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
          assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 20n : 4n);
        }
        if (task === 3) capture.close();
        const placement = fixture.strategyFixturePlacement(f, task);
        assert.equal(placement, task === 1 ? firstPlacement : firstPlacement === 'local' ? 'duckdb' : 'local');
        if (placement === 'duckdb') outputs.push(await runStrategyHostCompute(
          fixture.strategyFixtureCompute(f, task), suppliedLimits, { maxRows: 100, maxCells: 1000 }));
        else assert.equal(fixture.strategyFixtureLocal(f, task), true);
      }
      assert.equal(fixture.strategyFixtureCid(f, 2), hash([{ id: 3 }, { id: 2 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally { capture.close(); for (const output of outputs) output.close(); }
  }
}
