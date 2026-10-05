import assert from 'node:assert/strict';

// A trusted experiment supplies duration estimates only. Limits, owner and
// activation facts continue to come from the ordinary configured Host.
export function nativeResidentEstimateArguments(estimates, tasks) {
  if (estimates === undefined) return [];
  const rate = value => typeof value === 'string' && /^[1-9][0-9]*$/.test(value) &&
    BigInt(value) <= 2147483647n;
  assert(estimates && typeof estimates === 'object' && !Array.isArray(estimates),
    'InvalidNativeResidentEstimates');
  assert.deepEqual(Object.keys(estimates).sort(),
    ['cleanupMilliseconds', 'importMilliseconds', 'preparationMilliseconds', 'taskMilliseconds'],
    'IncompleteNativeResidentEstimates');
  assert(rate(estimates.preparationMilliseconds) && rate(estimates.cleanupMilliseconds),
    'InvalidNativeResidentSharedRate');
  assert(Array.isArray(estimates.taskMilliseconds) &&
    estimates.taskMilliseconds.length === tasks && estimates.taskMilliseconds.every(rate),
  'InvalidNativeResidentTaskRates');
  assert(Array.isArray(estimates.importMilliseconds) &&
    estimates.importMilliseconds.length === tasks + 1 &&
    estimates.importMilliseconds.every(value => value === null || rate(value)),
  'InvalidNativeResidentImportRates');
  return ['--resident-prepare-ms', estimates.preparationMilliseconds,
    '--resident-cleanup-ms', estimates.cleanupMilliseconds,
    '--resident-task-ms', estimates.taskMilliseconds.join(','),
    '--resident-import-ms', estimates.importMilliseconds.map(value => value ?? '?').join(',')];
}
