// Explicit Native-only acceptance. Requires a binary built in this checkout;
// ordinary portable unit tests must not discover this diagnostic implicitly.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, mkdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct,
  admitNativeDirectProduct} from './native-direct-product.mjs';
import {nativeOwnerObservations} from './native-owner-observations.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exec = promisify(execFile);
const fixture = retainedCase(workloads[0], 'narrow', 100);
const capacity = ['heldBytes', 'reservedExecutionBytes', 'reservedRetentionBytes',
  'reservedTransferBytes', 'uncertainTransferBytes'];
function closed(observations) {
  const [before, after, twice] = observations.owners.slice(-3);
  assert.equal(before.boundary, 'before-close');
  assert.equal(after.boundary, 'after-close');
  assert.equal(twice.boundary, 'duplicate-close');
  for (const key of capacity) assert.equal(after[key], 0, key);
  assert.equal(after.attempts, before.attempts);
  assert.equal(after.holdings, before.holdings);
  assert.deepEqual(twice, {...after, boundary: 'duplicate-close'});
}

test('100 rows: actual resident/fresh/Local choices, cheaper capacity refusal and close',
  {timeout: 60000}, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-native-owner-'));
    try {
      const database = join(directory, 'source.duckdb');
      await exec(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
      {cwd: root, timeout: fixture.limits.timeoutMs});
      for (const [label, settings] of [
        // Exercise the registered default, rather than an explicit diagnostic
        // resident override. Other settings below keep their stated controls.
        ['resident', {phaseObserver: true}],
        ['resident-profiled', {residentPolicy: true, phaseObserver: true,
          residentEstimates: {preparationMilliseconds: '2', cleanupMilliseconds: '3',
            taskMilliseconds: ['4', '5', '6'], importMilliseconds: ['7', '8', '9', null]}}],
        ['resident-unknown', {residentPolicy: true, phaseObserver: true,
          residentEstimates: {preparationMilliseconds: '2', cleanupMilliseconds: '3',
            taskMilliseconds: ['4', '5', '6'], importMilliseconds: [null, null, null, null]}}],
        ['fresh', {residentPolicy: false, phaseObserver: true}],
        ['local', {residentPolicy: false, phaseObserver: true, localRates: ['1', '1', '1'],
          nativeRates: ['2147483647', '2147483647', '2147483647']}],
        ['fresh-then-resident', {residentPolicy: true, phaseObserver: true,
          localRates: ['1000000', '1000000', '1000000'], nativeRates: ['1', '1', '1000000'],
          residentEstimates: {preparationMilliseconds: '1', cleanupMilliseconds: '1',
            taskMilliseconds: ['1000000', '1000000', '1'], importMilliseconds: ['1', '1', '1', null]}}],
        ['local-then-resident', {residentPolicy: true, phaseObserver: true,
          localRates: ['1', '1000000', '1000000'], nativeRates: ['1000000', '1000000', '1000000'],
          residentEstimates: {preparationMilliseconds: '1', cleanupMilliseconds: '1',
            taskMilliseconds: ['1000000', '1', '1'], importMilliseconds: ['1', '1', '1', null]}}],
        // Three Compute attempts fit; resident preparation/import would need
        // five. Its lower estimate must not override the actual attempt cap.
        ['bounded', {residentPolicy: true, attemptCap: 4}],
        ['stop', {residentPolicy: true, stopAfterTask: 1}],
        ['reject', {residentPolicy: true, attemptCap: 1}],
      ]) {
        const child = join(directory, label);
        await mkdir(child);
        const invocation = await prepareNativeDirectProduct({root, fixture,
          database, directory: child,
          localRates: ['1000', '1000', '1000'], nativeRates: ['1000', '1000', '1000'],
          ...settings});
        if (label === 'reject' || label === 'resident-unknown') {
          let failure;
          try {await exec(invocation.binary, invocation.arguments,
            {cwd: root, timeout: fixture.limits.timeoutMs});}
          catch (error) {failure = error;}
          assert(failure, 'InsufficientAttemptsAccepted');
          assert.match(failure.stdout, /strategy-terminal:no-strategy/);
          if (label === 'reject') {
            assert.match(failure.stdout, /strategy-rejection:[0-9]+:attempt:/);
          } else {
            // Unknown candidate durations defer offline ranking. Do not
            // replace missing import observations with invented rates.
            assert.match(failure.stdout, /compute-candidates:/);
          }
          const observations = nativeOwnerObservations(failure.stdout);
          assert(observations.owners.every(owner => owner.attempts === 0 &&
            owner.holdings === 0), 'RejectedPlanEnteredCompute');
          assert.equal(observations.choices.length, 0);
          closed(observations);
        } else if (label === 'stop') {
          const {stdout} = await exec(invocation.binary, invocation.arguments,
            {cwd: root, timeout: fixture.limits.timeoutMs});
          assert.deepEqual(JSON.parse(stdout.trim().split('\n').at(-1)),
            {status: 'stopped-between-tasks', completed_tasks: 1});
          const observations = nativeOwnerObservations(stdout);
          assert.equal(observations.choices.length, 1);
          assert(observations.choices[0].resident);
          assert.equal(observations.owners.at(-3).attempts, 3);
          assert(observations.owners.at(-3).heldBytes > 0);
          assert(observations.owners.at(-3).reservedExecutionBytes > 0);
          closed(observations);
        } else {
          const execution = await executeNativeDirectProduct(invocation,
            {root, timeoutMs: fixture.limits.timeoutMs});
          const product = admitNativeDirectProduct(fixture, invocation, execution);
          const residentSelected = label === 'resident' || label === 'resident-profiled';
          assert.deepEqual(product.ownerCorrespondence.observations.choices.map(choice => choice.resident),
            label === 'fresh-then-resident' ? [false, false, true] :
              label === 'local-then-resident' ? [false, true, true] : Array(3).fill(residentSelected));
          assert.deepEqual(product.selected, label === 'local-then-resident'
            ? ['local', 'duckdb', 'duckdb'] : Array(3).fill(label === 'local' ? 'local' : 'duckdb'),
          JSON.stringify({label, explanations: product.ownerCorrespondence.observations.explanations}));
          if (label === 'bounded') {
            assert(product.ownerCorrespondence.observations.explanations.every(
              ({body}) => body.assessed_strategies.some(assessment =>
                assessment.rejection === 'attempt_limit' &&
                assessment.estimated_milliseconds !== null &&
                body.selection.remaining_at_selection.estimated_milliseconds !== null &&
                BigInt(assessment.estimated_milliseconds) <
                  BigInt(body.selection.remaining_at_selection.estimated_milliseconds))),
            'MissingCheaperCandidateCapacityRefusal');
          }
          assert.deepEqual(product.ownerCorrespondence.attempts.map(attempt =>
            attempt.physicalAttempts), label === 'fresh-then-resident' ? [1, 1, 3] :
              label === 'local-then-resident' ? [1, 3, 2] : residentSelected ? [3, 1, 1] : [1, 1, 1]);
          if (label === 'fresh-then-resident' || label === 'local-then-resident') {
            assert.deepEqual(product.physicalPhases.intervals.filter(item => item.phase === 'import')
              .map(item => item.producer), label === 'fresh-then-resident' ? [1] : [0, 1]);
            const phases = product.physicalPhases.intervals.map(item => [item.task, item.phase]);
            assert.deepEqual(phases, label === 'fresh-then-resident'
              ? [[3, 'environment'], [3, 'import'], [3, 'compute']]
              : [[2, 'environment'], [2, 'import'], [2, 'compute'], [3, 'import'], [3, 'compute']]);
          }
          if (residentSelected) {
            assert.deepEqual(product.physicalPhases.intervals.map(item => item.phase),
              ['environment', 'import', 'compute', 'compute', 'compute']);
            assert.equal(product.physicalPhases.intervals[1].producer, 0);
          }
          if (settings.phaseObserver) {
            assert.deepEqual(product.physicalPhases.taskExecutionIntervals.map(item => item.task), [1, 2, 3]);
            assert.deepEqual(product.physicalPhases.taskReleaseIntervals.map(item => item.task)
              .sort((a, b) => a - b), [1, 2, 3]);
          }
          if (label === 'resident-profiled') {
            // Compare independently supplied rates with the actual serialized
            // pre-execution offers, not with selectionInput echoed by the probe.
            const offers = product.ownerCorrespondence.observations.candidates[0].body[5]
              .flatMap(candidate => candidate[5].filter(Boolean))
              .filter(offer => offer[9] !== null);
            assert.deepEqual([...new Set(offers.map(offer => offer[0]))].sort(), [1, 2, 3]);
            for (const offer of offers) {
              assert.equal(offer[8][0][1], settings.residentEstimates.taskMilliseconds[offer[0] - 1],
                'ResidentTaskEstimateNotBoundToActualOffer');
              const profile = offer[9];
              assert.equal(profile[1].lines[0].milliseconds,
                settings.residentEstimates.preparationMilliseconds);
              assert.equal(profile[2].lines[0].milliseconds,
                settings.residentEstimates.cleanupMilliseconds);
              assert.deepEqual(profile[3].map(item => item[0].lines[0].milliseconds),
                settings.residentEstimates.importMilliseconds,
                'ResidentImportEstimatesNotBoundToActualOffer');
            }
          }
          // Exact independent rows/CID and per-stage cardinalities are checked by
          // product admission; this observer only adds the owner correspondence.
          closed(product.ownerCorrespondence.observations);
        }
      }
    } finally {await rm(directory, {recursive: true, force: true});}
  });
