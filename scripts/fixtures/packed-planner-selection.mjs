// Copied unchanged into the existing pack-once consumer. Only public installed
// package entry points and the shared acceptance fixture are imported.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {installPlannerSelectionFixture, exercisePlannerSelectionPublicQuery,
  plannerSelectionPlanningFor} from './planner-selection-public-query.mjs';

assert.equal(spawnSync('moon', ['version']).error?.code, 'ENOENT');
const root = resolve('planner-selection-acceptance');
const reportPath = resolve('planner-selection-packed-report.json');
const summary = {status: 'running', runtime: {client: '@actql/node',
  httpHost: '@actql/local-node/http-host', toolchainAvailable: false}, observations: []};
const persist = () => writeFile(reportPath, JSON.stringify(summary, null, 2) + '\n');
await persist();
try {
  const duckdb = createRequire(fileURLToPath(new URL(
    './node_modules/@actql/local-node/package.json', import.meta.url)))('@duckdb/node-api');
  const environment = JSON.parse(await readFile('two-source-fixtures/left.environment.json', 'utf8'));
  const tls = {key: await readFile('remote.key'), cert: await readFile('remote.crt')};
  const installation = await installPlannerSelectionFixture({root, duckdb, environment,
    acquisitionPlanningFor: plannerSelectionPlanningFor});
  summary.observations = await exercisePlannerSelectionPublicQuery({
    connect, openInstalledRemoteHttpHost, root, installation, duckdb, tls});
  summary.status = 'passed';
  summary.cases = summary.observations.length;
  console.log('Packed planner candidate selection: 22 Local/HTTPS cases passed');
} catch (error) {
  summary.status = 'failed';
  summary.error = {name: error.name, message: error.message, code: error.code};
  throw error;
} finally { await persist(); }
