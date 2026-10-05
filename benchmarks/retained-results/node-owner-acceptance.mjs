// Explicit 100-row real Node benchmark boundary. This is development
// correspondence, not calibrated performance acceptance or a full matrix.
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
const read = path => readFile(join(root, path), 'utf8');

test('100 rows: Node managed benchmark observes actual planner before Compute',
  {timeout: 60000}, async () => {
    const fixture = retainedCase(workloads[0], 'narrow', 100);
    const directory = await mkdtemp(join(tmpdir(), 'actql-node-owner-'));
    try {
      const database = join(directory, 'source.duckdb');
      await promisify(execFile)(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
      {cwd: root, timeout: fixture.limits.timeoutMs});
      const contracts = {
        adoptedText: await read('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
        query: await read('spec/contracts/actql-query-acquisition.json'),
        evidence: await read('spec/contracts/actql-query-process-evidence.json'),
        receipts: await read('spec/contracts/actql-query-two-receipt.json'),
      };
      const report = await runRetainedComparator(fixture, contracts, database,
        directory, {resident: true, nativeMilliseconds: '1000'});
      assert.equal(report.status, 'completed');
      assert.equal(report.rows, fixture.identity().rows);
      assert.deepEqual(report.plannerObservations.map(value =>
        [value.boundary, value.task]), [1, 2, 3].flatMap(task =>
        [['before-task', task], ['after-task', task]]));
      const before = report.plannerObservations.filter(value => value.boundary === 'before-task');
      assert(before.every(value => value.explanation.selection_state === 'selected' &&
        value.explanation.selection.dispatch_authorized &&
        value.explanation.selection.tasks.some(task => task.task === value.task &&
          task.completed === false)));
      assert(report.tasks.every(task => Number.isFinite(task.plannerObserverMilliseconds) &&
        task.plannerObserverMilliseconds >= 0));
      const correspondence = admitNodePlannerOwnerObservations(report,
        managedCaseConfiguration(fixture, contracts, database, directory).limits);
      assert.deepEqual(correspondence.attempts.map(value => value.physicalAttempts), [3, 1, 1]);
      for (const [change, issue] of [
        [copy => {copy.plannerObservations[0].explanation.selection.tasks[0].completed = true;},
          /NodePlannerTaskMismatch/],
        [copy => {copy.plannerObservations[1].usage.attempts++;},
          /UnattributedNodePhysicalAttempt/],
        [copy => {copy.plannerObservations[1].usage.reserved_execution_bytes = '0';},
          /NodeResidentReservationReleasedEarly/],
      ]) {
        const copy = structuredClone(report);
        change(copy);
        assert.throws(() => admitNodePlannerOwnerObservations(copy,
          managedCaseConfiguration(fixture, contracts, database, directory).limits), issue);
      }
      console.log('NODE_PLANNER_OWNER:' + JSON.stringify({
        correspondence,
        observations: report.plannerObservations,
        tasks: report.tasks.map(({task, realization, preparation, plannerObserverMilliseconds}) =>
          ({task, realization, preparation, plannerObserverMilliseconds})),
        hostPhases: report.hostPhases, usage: report.usage, cleanupMs: report.cleanupMs,
      }));
      // Independent result CID, stage descriptors, actual process exit,
      // retained custody and confirmed final close remain in the comparator.
    } finally {await rm(directory, {recursive: true, force: true});}
  });
