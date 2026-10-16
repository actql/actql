// Authored harness/oracle closure only. Product modules and worker assets must
// resolve from normal installed packages, never from these copied inputs.
import assert from 'node:assert/strict';
import {dirname, join} from 'node:path';
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
  'scripts/fixtures/real-cross-connector-preview.mjs',
  'scripts/fixtures/real-cross-connector-restart.mjs',
  'scripts/fixtures/real-cross-connector-transport.mjs',
  'scripts/gcs-files-content-credential.mjs',
  'scripts/gcs-files-content-environment.mjs',
]);

export function realCrossConnectorFormat(args) {
  return realCrossConnectorSelection(args).format;
}

export function realCrossConnectorSelection(args) {
  const selection = {format: 'sql', transport: 'local'}, seen = new Set();
  const choices = new Map([['--format', ['format', ['sql', 'aql']]],
    ['--transport', ['transport', ['local', 'https']]]]);
  for (let index = 0; index < args.length; index += 2) {
    const [field, values] = choices.get(args[index]) ?? [];
    assert(field && !seen.has(field) && values.includes(args[index + 1]),
      'Use one optional --format sql|aql and --transport local|https; no extra physical scenarios');
    seen.add(field); selection[field] = args[index + 1];
  }
  return Object.freeze(selection);
}

export function realCrossConnectorEnvironment(base, {root, node}) {
  const env = {...base};
  for (const key of Object.keys(env)) {
    if (key.startsWith('ACTQL_') || key.startsWith('MOON_') ||
        key.toLowerCase().startsWith('npm_config_') ||
        ['MOON_HOME', 'NODE_PATH', 'NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'NODE_TEST_CONTEXT'].includes(key)) delete env[key];
  }
  return {...env, PATH: `${dirname(node)}:/usr/bin:/bin:/usr/sbin:/sbin`,
    npm_config_registry: 'https://registry.npmjs.org/',
    npm_config_cache: join(root, 'npm-cache'), npm_config_userconfig: join(root, 'npmrc'),
    npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_update_notifier: 'false',
    npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost'};
}
