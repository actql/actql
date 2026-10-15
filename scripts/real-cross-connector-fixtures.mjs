// Authored harness/oracle closure only. Product modules and worker assets must
// resolve from normal installed packages, never from these copied inputs.
import {tablePublicFixturePaths} from './table-public-acceptance-cases.mjs';
export const realCrossConnectorFixturePaths = Object.freeze([
  ...tablePublicFixturePaths.filter(path => ![
    'adapters/host-node/table-public-commit.test.mjs',
    'adapters/host-node/fixtures/table-text-restart.mjs',
    'adapters/host-node/fixtures/table-ctas-result-control.mjs',
  ].includes(path)),
  'adapters/host-node/real-cross-connector-installed.test.mjs',
  'scripts/fixtures/real-cross-connector-control.mjs',
  'scripts/fixtures/real-cross-connector-observation.mjs',
  'scripts/fixtures/real-cross-connector-restart.mjs',
  'scripts/gcs-files-content-credential.mjs',
  'scripts/gcs-files-content-environment.mjs',
]);
