import { readFile, stat } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { authorizeLocalDatabase } from '../session.mjs';
import { runStrategyNativeHostQuery } from '../host.mjs';
import { runCapturedStrategy } from '../../host-node/entry.mjs';
import { checked } from '../runtime-result.mjs';

const root = new URL('../../../', import.meta.url);
const runtimeUrl = new URL('_build/js/release/build/physical_strategy_example/physical_strategy_example.js', root);
const limits = Object.freeze({ maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 });

async function boundedText(path) {
  if ((await stat(path)).size > 1000000) throw new Error('Example input exceeds 1000000 bytes');
  const bytes = await readFile(path);
  if (bytes.length > 1000000) throw new Error('Example input exceeds 1000000 bytes');
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

// Application settings select the source file; Program/Catalog text cannot grant
// filesystem access. Preparation and semantic decisions stay in MoonBit.
export async function runExample({ database, environment, environmentCid, program,
  parameters, schema = 'main', table = 'records', nativeMilliseconds = '5', resident = false, signal }) {
  if (!/^\d{1,18}$/.test(nativeMilliseconds)) throw new Error('Invalid native estimate');
  const app = await import(runtimeUrl);
  const [programText, environmentText, parameterText, adoptedText, query, evidence, receipts] =
    await Promise.all([program, environment, parameters,
      new URL('../contracts/adopted-relation.json', import.meta.url),
      new URL('spec/contracts/actql-query-acquisition.json', root),
      new URL('spec/contracts/actql-query-process-evidence.json', root),
      new URL('spec/contracts/actql-query-two-receipt.json', root)].map(boundedText));
  const adopted = JSON.parse(adoptedText);
  let prepared;
  try {
    prepared = checked(app.prepareApplication(programText, environmentText, environmentCid,
      parameterText, JSON.stringify(adopted.registry), JSON.stringify(adopted.values),
      JSON.stringify(adopted.fragment), query, evidence, receipts, schema, table));
  } catch (cause) {
    throw new Error('Example preparation rejected: check the filter or join/count profile, Environment CID, Parameters and selected contracts', { cause });
  }
  const grant = await authorizeLocalDatabase(database);
  const capture = await runStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
    app.applicationLedger(), limits, signal);
  let execution;
  try {
    const graph = capture.openDAG(app.applicationGraph(prepared));
    const setup = checked(app.applicationDispatch(prepared, graph, BigInt(nativeMilliseconds), resident));
    execution = await runCapturedStrategy(setup, {duckdb: {transportLimits: limits, importLimits: { maxRows: 100, maxCells: 1000 }}}, signal);
    const explanation = execution.explain();
    const report = Object.freeze({ status: execution.status, program_success: false,
      estimate_model: 'supplied example estimates, not measured speed',
      completed: execution.completed,
      internal_output_cids: execution.completed.map(({ task }) => ({ task, cid: app.applicationOutputCid(graph, task) ?? null })),
      failure: execution.failure?.code ?? (execution.failure ? 'HostFailure' : null),
      cleanup_pending: execution.cleanupPending(),
      explanation });
    // The caller owns both handles, including any pending failure cleanup handle.
    return Object.freeze({ report, execution, capture, close() { execution.close(); capture.close(); } });
  } catch (error) {
    execution?.close();
    capture.close();
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let result;
  try {
    const { values } = parseArgs({ options: {
      database: { type: 'string' }, environment: { type: 'string' },
      'environment-cid': { type: 'string' }, program: { type: 'string' },
      parameters: { type: 'string' }, schema: { type: 'string', default: 'main' },
      table: { type: 'string', default: 'records' }, 'native-ms': { type: 'string', default: '5' },
      resident: { type: 'boolean', default: false },
    } });
    for (const key of ['database', 'environment', 'environment-cid', 'program', 'parameters']) {
      if (!values[key]) throw new Error(`Required --${key}`);
    }
    result = await runExample({ ...values, environmentCid: values['environment-cid'], nativeMilliseconds: values['native-ms'] });
    console.log(JSON.stringify(result.report, (_, value) => typeof value === 'bigint' ? value.toString() : value, 2));
    if (result.execution.failure) {
      // Cleanup only: this cannot retry a query or turn failure into success.
      if (result.execution.cleanupPending()) await result.execution.cleanup();
      if (result.execution.cleanupPending()) console.error('Cleanup remains pending; no release or durable recovery is claimed.');
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(error);
    if (error.cleanupHandle?.status().pending) await error.cleanupHandle.retry();
    process.exitCode = 1;
  } finally { result?.close(); }
}
