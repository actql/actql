// Select existing authored acceptance cases, never product behavior or limits.
import assert from 'node:assert/strict';
import {compositionReleaseDirectory} from './composition-release-input.mjs';

export const sheetsPackedFixturePaths = Object.freeze([
  'adapters/site-node/https-exchange-fixture.mjs',
  ...['sheets-api.fixture.mjs', 'sheets-public-acceptance.fixture.mjs',
    'sheets-range-program.fixture.mjs', 'sheets-clear-program.fixture.mjs', 'sheets-replay.fixture.mjs',
    'sheets-replay-packed.fixture.mjs', 'sheets-packed.fixture.mjs']
    .map(name => `adapters/connectors/sheets/test/${name}`),
]);

export function sheetsPackedSelection(argv) {
  let rangeOnly = false;
  for (let index = 0; index < argv.length; index++) {
    if (argv[index] === '--range-command-only') {
      assert(!rangeOnly, 'Select the range Command cases once');
      rangeOnly = true;
    } else if (argv[index] === '--release-dir') {
      index++;
    } else {
      assert.fail('Use only --release-dir <absolute directory> and --range-command-only');
    }
  }
  const directory = compositionReleaseDirectory(argv);
  assert(!rangeOnly || directory !== undefined,
    'Range-only acceptance reuses an existing normal release; it never starts a producer');
  return Object.freeze({directory, rangeOnly, expectedTests: rangeOnly ? 2 : 18,
    testArguments: Object.freeze([
      ...(rangeOnly ? ['--test-name-pattern=^Sheets range Command'] : []),
      'adapters/connectors/sheets/test/sheets-packed.fixture.mjs',
    ])});
}
