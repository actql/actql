// Diagnostic DATA for one fresh fixture app, never a write/receipt/cleanup ACK.
// No provider, Core, permission, status call or executable payload is observed.
import {opendir} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {performance} from 'node:perf_hooks';

export function projectFileStoreProgressObservation({stateDir, destinationRoot,
  expectedFiles, instrumented = false}) {
  const data = {qualification: 'Fresh fixture app only; durable counts are not physical write acknowledgements',
    instrumentedProgress: instrumented,
    performanceQualification: instrumented ? 'Instrumented diagnosis, not formal performance' : 'Scalar phase observations',
    wallUnits: 'milliseconds', cpuUnits: 'microseconds', stages: [], milestones: [], errors: []};
  let origin, cpuOrigin;
  const issue = (operation, error) => {
    if (data.errors.length < 4) data.errors.push({operation,
      code: typeof error?.code === 'string' ? error.code : 'DiagnosticUnavailable'});
  };
  try {origin = performance.now(); cpuOrigin = process.cpuUsage();}
  catch (error) {issue('clock', error);}
  const clock = () => {
    if (origin === undefined || cpuOrigin === undefined) throw new Error('DiagnosticClockUnavailable');
    const cpu = process.cpuUsage(cpuOrigin);
    return {wallMs: performance.now() - origin,
      userCpuUs: cpu.user, systemCpuUs: cpu.system};
  };
  const stamp = stage => {
    try {if (data.stages.length < 20) data.stages.push({stage, ...clock()});}
    catch (error) {issue('stamp', error);}
  };
  const counts = () => {
    let database;
    try {
      // This fixture has exactly one fresh Run. A read-only connection cannot
      // create a missing Ledger, and the single SELECT observes one SQL cut.
      database = new DatabaseSync(join(stateDir, 'state', 'effects', 'ledger',
        'effect-ledger.sqlite3'), {readOnly: true});
      const row = database.prepare(`SELECT
        (SELECT COUNT(*) FROM (SELECT 1 FROM effect_ledger_responses LIMIT ?)) AS responses,
        (SELECT COUNT(*) FROM (SELECT 1 FROM effect_ledger_outcomes LIMIT ?)) AS outcomes`)
        .get(expectedFiles.length + 1, expectedFiles.length + 1);
      if (![row.responses, row.outcomes].every(value => Number.isSafeInteger(value) &&
          value >= 0 && value <= expectedFiles.length)) throw new Error('DiagnosticCountOutsideFixture');
      return {available: true, durableResponses: row.responses, recordedOutcomes: row.outcomes};
    } catch (error) {issue('ledger-count', error); return {available: false};}
    finally {
      try {database?.close();} catch (error) {issue('ledger-close', error);}
    }
  };
  const files = async () => {
    let directory;
    try {
      // Both authored cases use flat destination paths. Keep an explicit
      // finite directory prefix even if an unrelated entry appears there.
      const expected = new Set(expectedFiles.map(file => file.path));
      let entries = 0, regularFiles = 0, expectedFilesPresent = 0;
      directory = await opendir(destinationRoot);
      while (entries <= expectedFiles.length + 1) {
        const entry = await directory.read();
        if (entry === null) return {available: true, complete: true,
          entries, regularFiles, expectedFilesPresent};
        entries++;
        if (entry.isFile()) {
          regularFiles++;
          if (expected.has(entry.name)) expectedFilesPresent++;
        }
      }
      return {available: true, complete: false, entries, regularFiles, expectedFilesPresent};
    } catch (error) {issue('file-count', error); return {available: false};}
    finally {
      try {await directory?.close();} catch (error) {issue('directory-close', error);}
    }
  };
  let previous = 0;
  const poll = () => {
    if (!instrumented || data.milestones.length === 12) return;
    try {
      const count = counts();
      if (!count.available || count.durableResponses === 0) return;
      const n = count.durableResponses;
      if (previous === 0 || Math.floor(n / 10) > Math.floor(previous / 10) ||
          n === expectedFiles.length && n !== previous) {
        data.milestones.push({...clock(), ...count}); previous = n;
      }
    } catch (error) {issue('progress', error);}
  };
  const failure = async () => {
    stamp('failure-observed');
    // Run only after the primary failure/deadline, before the first close.
    // Partial response/outcome/file counts neither prove success nor replay.
    try {data.failure = {...clock(), ledger: counts(), files: await files()};}
    catch (error) {issue('failure-count', error);}
  };
  return Object.freeze({data, instrumented, stamp, poll, failure});
}
