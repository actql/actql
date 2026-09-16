// Benchmark assembly over old public APIs, not a modified baseline runtime.
// Only the acquisition receiver envelope is supplied by this diagnostic.
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function baselinePublicEntry(baselineRoot) {
  const root = pathToFileURL(resolve(baselineRoot) + '/');
  const load = path => import(new URL(path, root));
  const [app, session, host, driver, configuration, runtime] = await Promise.all([
    load('_build/js/release/build/physical_strategy_example/physical_strategy_example.js'),
    load('adapters/duckdb-node/session.mjs'), load('adapters/duckdb-node/host.mjs'),
    load('adapters/host-node/entry.mjs'), load('adapters/duckdb-node/configuration.mjs'),
    load('adapters/duckdb-node/runtime-result.mjs'),
  ]);
  const text = path => readFile(new URL(path, root), 'utf8');
  const [adoptedText, query, evidence, receipts] = await Promise.all([
    'adapters/duckdb-node/contracts/adopted-relation.json',
    'spec/contracts/actql-query-acquisition.json', 'spec/contracts/actql-query-process-evidence.json',
    'spec/contracts/actql-query-two-receipt.json',
  ].map(text));
  const adopted = JSON.parse(adoptedText);
  return async ({database, program, environment, environmentCid, parameters,
    nativeMilliseconds, signal, receivedRows, receivedCells = 1000,
    receivedBytes = 100000}) => {
    if (!Number.isSafeInteger(receivedRows) || receivedRows < 100 || receivedRows > 2147483647) {
      throw TypeError('InvalidBaselineReceivedRows');
    }
    if (!Number.isSafeInteger(receivedCells) || receivedCells < 1000 ||
        !Number.isSafeInteger(receivedBytes) || receivedBytes < 100000) {
      throw TypeError('InvalidBaselineReceivedEnvelope');
    }
    // Only the explicitly supplied receiver envelope differs from the example.
    const limits = {maxRows: receivedRows, maxCells: receivedCells, maxTransportBytes: receivedBytes,
      maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
      memoryBytes: 128 * 1024 * 1024, threads: 1};
    // Acquisition may scan much more than it captures. Keep Compute's original
    // declared envelope; increasing acquisition transport must not silently
    // enlarge a selected Compute offer or bypass its capacity check.
    const computeLimits = {...limits, maxRows: 100, maxCells: 1000, maxTransportBytes: 100000};
    const [programText, environmentText, parameterText] = await Promise.all(
      [program, environment, parameters].map(path => readFile(path, 'utf8')));
    const prepared = runtime.checked(app.prepareApplication(programText, environmentText, environmentCid,
      parameterText, JSON.stringify(adopted.registry), JSON.stringify(adopted.values),
      JSON.stringify(adopted.fragment), query, evidence, receipts, 'main', 'records'));
    const grant = await session.authorizeLocalDatabase(database);
    const capture = await host.runStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
      app.applicationLedger(), limits, signal);
    let execution;
    try {
      const graph = capture.openDAG(app.applicationGraph(prepared));
      const setup = runtime.checked(app.applicationDispatch(prepared, graph, BigInt(nativeMilliseconds), false));
      execution = await driver.runCapturedStrategy(setup,
        {duckdb: configuration.prepareDuckDBStrategyConfiguration({transportLimits: computeLimits,
          importLimits: {maxRows: 100, maxCells: 1000}})}, signal);
      return {execution, capture, report: {status: execution.status, completed: execution.completed,
        failure: execution.failure?.code ?? (execution.failure ? 'HostFailure' : null),
        internal_output_cids: execution.completed.map(({task}) =>
          ({task, cid: app.applicationOutputCid(graph, task) ?? null}))},
        close() { execution.close(); capture.close(); }};
    } catch (error) {
      execution?.close(); capture.close();
      throw error;
    }
  };
}
