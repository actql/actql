// Independent report DATA for the health adapter. No executable or SDK import.
import {createHash} from 'node:crypto';
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const bytes = value => createHash('sha256').update(value).digest('hex');

export function nativeOperationsData(sourceSha, cohortSha256, milliseconds = 80) {
  const count = 100, state = '/synthetic-health-native-project';
  const environment = {platform: 'synthetic-source-fixture'};
  const historyProtocol = {selection: 'native-operations', mode: 'final', samplesPerOperation: count,
    firstQuery: {text: 'SELECT 0 AS id', expected: [{id: 0}]},
    queries: Array.from({length: count}, (_, index) => ({text: `SELECT ${index + 1} AS id`, expected: [{id: index + 1}]}))};
  const binding = {cohortSha256, environmentSha256: hash(environment), historyProtocolSha256: hash(historyProtocol)};
  const report = {sourceSha, ...binding, selection: 'native-operations', executionPath: 'native-cli', mode: 'final',
    environment, historyProtocol, initialization: {pid: 100, code: 0, wallNs: 3000000},
    cleanup: {closed: true}, packageFailure: null, installedPayloadsUnchanged: true,
    publicCallAttempts: {init: 1, run: 101, result: 100}, latency: [], functional: {...binding, rows: []}};
  const original = (value, name, pid) => {
    const publicRunId = `synthetic-run-${value}`, selected = {runId: publicRunId, resultName: 'answer', resultCid: `synthetic-result-${value}`};
    const row = {...binding, publicOperationId: 'synthetic-' + name, stateId: state, pid, publicRunId,
      runRefSha256: hash({runId: publicRunId}), resultRefSha256: hash(selected),
      queryPath: `${state}/${name}.aql`, queryFileSha256: bytes(`SELECT ${value} AS id;\n`),
      outputPath: `${state}/${name}.jsonl`, querySha256: hash(`SELECT ${value} AS id`),
      expectedSha256: hash([{id: value}]), actualSha256: hash([{id: value}]), completed: true, verified: true,
      wallNs: milliseconds * 1e6, childWallNs: (milliseconds - 1) * 1e6,
      cpuUserUs: 100, cpuSystemUs: 50, cpuScope: 'synthetic distinct CLI child',
      peakRssBytes: 1024, rssScope: 'synthetic child RSS',
      publicTiming: {kind: 'cli-result-exit', startNs: 1, exitNs: 2, observedNs: 3, endNs: 4},
      command: {pid, code: 0, wallNs: (milliseconds - 1) * 1e6, cwd: state,
        args: ['run', name + '.aql', '--output', name + '.jsonl', '--json']},
      publicResponse: {run: {run_id: publicRunId, status: 'succeeded'}, delivery_status: 'delivered',
        deliveries: [{run_id: publicRunId, status: 'delivered', request: {result: selected.resultName,
          result_cid: selected.resultCid, format: 'jsonl', path: `${state}/${name}.jsonl`}}]}};
    row.command.stdout = JSON.stringify(row.publicResponse);
    return row;
  };
  report.firstQuery = original(0, 'first', 101);
  const fresh = Array.from({length: count}, (_, index) => ({...original(index + 1, 'new-' + index, 200 + index), iteration: index}));
  const originals = fresh.slice(0, 3);
  const saved = Array.from({length: count}, (_, iteration) => {
    const original = originals[iteration % 3], pid = 400 + iteration;
    return {...binding, iteration, publicOperationId: `synthetic-saved-${iteration}`, stateId: state, pid,
      ...Object.fromEntries(['publicRunId', 'runRefSha256', 'resultRefSha256', 'expectedSha256', 'actualSha256'].map(key => [key, original[key]])),
      completed: true, verified: true, wallNs: milliseconds * 1e6, childWallNs: (milliseconds - 1) * 1e6,
      cpuUserUs: 100, cpuSystemUs: 50, cpuScope: 'synthetic distinct CLI child',
      peakRssBytes: 1024, rssScope: 'synthetic child RSS',
      publicTiming: {kind: 'cli-result-exit', startNs: 1, exitNs: 2, observedNs: 3, endNs: 4},
      command: {pid, code: 0, wallNs: (milliseconds - 1) * 1e6, cwd: state,
        args: ['result', original.publicRunId, '--result', 'answer', '--format', 'jsonl']}};
  });
  for (const [operation, samples, workload] of [
    ['cold-new-run', fresh, {kind: 'new-durable-run-result-file-rows', fixtures: historyProtocol.queries.map(row => ({
      querySha256: hash(row.text), expectedSha256: hash(row.expected)}))}],
    ['cold-result', saved, {kind: 'saved-original-result-rows', originals: originals.map(row => Object.fromEntries(
      ['runRefSha256', 'resultRefSha256', 'expectedSha256'].map(key => [key, row[key]])))}],
  ]) {
    const fixtureSha256 = hash(workload);
    for (const row of samples) row.fixtureSha256 = fixtureSha256;
    report.latency.push({...binding, operation, mode: 'final', fixtureSha256, publicWorkload: workload,
      samples, profiled: false, load: 'isolated', stoppedEarly: false});
    report.functional.rows.push({operation, fixtureSha256, completed: true,
      expectedSha256: hash(samples.map(row => row.expectedSha256)), actualSha256: hash(samples.map(row => row.actualSha256))});
  }
  return report;
}
