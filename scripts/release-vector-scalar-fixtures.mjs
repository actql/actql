// Test inputs only. Product/runtime files come exclusively from the fixed RC.
import {dirname, join} from 'node:path';

export function releaseVectorScalarEnvironment(base, {registry, root, node}) {
  const env = {...base, PATH: `${dirname(node)}:/usr/bin:/bin:/usr/sbin:/sbin`,
    npm_config_registry: registry, npm_config_cache: join(root, 'npm-cache'),
    npm_config_userconfig: join(root, 'npmrc'), npm_config_globalconfig: join(root, 'npmrc-global'),
    npm_config_update_notifier: 'false', npm_config_proxy: '', npm_config_https_proxy: '',
    NO_PROXY: '127.0.0.1,localhost'};
  for (const key of Object.keys(env)) {
    if (['NODE_PATH', 'NODE_OPTIONS', 'MOON_HOME'].includes(key) ||
        key.startsWith('ACTQL_') || key.startsWith('MOON_')) delete env[key];
  }
  return env;
}

export const releaseVectorScalarFixturePaths = Object.freeze([
  'scripts/fixtures/release-vector-scalar-worker.mjs',
  'scripts/fixtures/packed-vector-scalar-source.mjs',
  'scripts/fixtures/vector-scalar-installed-source.mjs',
  'scripts/fixtures/vector-scalar-source-input.mjs',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/cte-value-table-receipts.mjs',
  'scripts/fixtures/retained-fixture-values.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
]);
