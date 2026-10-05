// A fixed, small diagnostic of observer cost, not a performance gate.
// All four samples run: no resampling until a favorable difference appears.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {runRetainedComparator} from '../../adapters/connectors/duckdb/node/bench/retained-comparator.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {admitNodePlannerOwnerObservations} from './node-owner-observations.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const median = values => {
  const sorted = [...values].sort((a, b) => a - b);
  return (sorted[0] + sorted[1]) / 2;
};

test('100 rows: fixed observer on/off samples preserve planner and owner obligations',
  {timeout: 45000}, async () => {
    const fixture = retainedCase(workloads[0], 'narrow', 100);
    const directory = await mkdtemp(join(tmpdir(), 'actql-node-observation-cost-'));
    try {
      const database = join(directory, 'source.duckdb');
      const sourceStarted = performance.now();
      await promisify(execFile)(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
      {cwd: root, timeout: fixture.limits.timeoutMs});
      const sourceSetupMs = performance.now() - sourceStarted;
      const contracts = Object.fromEntries(await Promise.all([
        ['adoptedText', 'adapters/connectors/duckdb/node/contracts/adopted-relation.json'],
        ['query', 'spec/contracts/actql-query-acquisition.json'],
        ['evidence', 'spec/contracts/actql-query-process-evidence.json'],
        ['receipts', 'spec/contracts/actql-query-two-receipt.json'],
      ].map(async ([key, path]) => [key, await readFile(join(root, path), 'utf8')])));
      const samples = [];
      // Reversed second pair avoids putting the enabled observer last in
      // every pair. Source, estimates, limits and installed worker are shared.
      for (const observePlanner of [false, true, true, false]) {
        const started = performance.now();
        const report = await runRetainedComparator(fixture, contracts, database,
          directory, {resident: true, nativeMilliseconds: '1000', observePlanner});
        const wrapperElapsedMs = performance.now() - started;
        assert.equal(report.status, 'completed');
        assert.equal(report.plannerObservationEnabled, observePlanner);
        assert.deepEqual(report.tasks.map(task => task.realization),
          ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
        assert.equal(report.usage.attempts, 7);
        if (observePlanner) {
          admitNodePlannerOwnerObservations(report,
            managedCaseConfiguration(fixture, contracts, database, directory).limits);
        } else {
          assert.equal(report.plannerObservations, undefined);
          assert(report.tasks.every(task => task.plannerObserverMilliseconds === undefined));
        }
        samples.push({observePlanner, wrapperElapsedMs, ...report});
      }
      for (const sample of samples) {
        assert.equal(sample.expectedRowsCid, samples[0].expectedRowsCid);
        assert.equal(sample.selectionHash, samples[0].selectionHash);
        assert.equal(sample.programHash, samples[0].programHash);
        assert.equal(sample.parameterHash, samples[0].parameterHash);
        assert.equal(sample.environmentCid, samples[0].environmentCid);
        assert.equal(sample.sourceDefinitionHash, samples[0].sourceDefinitionHash);
      }
      const elapsed = sample => sample.executionMs + sample.cleanupMs;
      const difference = median(samples.filter(sample => sample.observePlanner).map(elapsed)) -
        median(samples.filter(sample => !sample.observePlanner).map(elapsed));
      console.log('NODE_OBSERVATION_COST:' + JSON.stringify({caseId: fixture.id,
        sourceSetupMs, order: samples.map(sample => sample.observePlanner),
        observedMedianDifferenceMs: difference,
        processCondition: 'fresh execution process per sample; shared source; OS/compile caches uncontrolled',
        residentCondition: 'new environment/import in task 1; tasks 2/3 reuse within each process',
        timing: 'execution includes Host preparation/child exit; cleanup follows it; nested phases are not summed',
        limitation: 'four finite samples, no statistical overhead bound or performance improvement claim',
        samples: samples.map(sample => ({observePlanner: sample.observePlanner,
          wrapperElapsedMs: sample.wrapperElapsedMs, executionMs: sample.executionMs,
          cleanupMs: sample.cleanupMs, hostPhases: sample.hostPhases,
          workerPreparationDetails: sample.workerPreparationDetails,
          usage: sample.usage, accounting: sample.accounting,
          selection: sample.selection, selectionHash: sample.selectionHash,
          expectedRowsCid: sample.expectedRowsCid, controlTransport: sample.controlTransport,
          tasks: sample.tasks.map(({task, realization, preparation, phases,
            taskElapsedMilliseconds, plannerObserverMilliseconds}) =>
            ({task, realization, preparation, phases,
              taskElapsedMilliseconds, plannerObserverMilliseconds})),
        })),
      }));
    } finally {await rm(directory, {recursive: true, force: true});}
  });
