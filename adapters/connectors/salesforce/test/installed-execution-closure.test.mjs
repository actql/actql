import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {adapterModuleGraph} from '../../../../scripts/adapter-module-graph.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const host = 'adapters/connectors/salesforce/host/';

test('ordinary Salesforce installation uses only shared Effect execution and vendor request recovery', () => {
  const graph = adapterModuleGraph(root, [
    `${host}installed-salesforce-source.mjs`,
    `${host}installed-salesforce-effect.mjs`,
  ]);
  for (const path of [
    `${host}salesforce-write-driver.mjs`,
    `${host}salesforce-effect-request-recovery.mjs`,
    'adapters/host-node/installed-row-source.mjs',
    'adapters/host-node/installed-row-effect.mjs',
    'adapters/host-node/effect-physical-dispatch.mjs',
    'adapters/host-node/effect-response-recovery.mjs',
  ]) assert.ok(graph.includes(path), `Missing installed owner: ${path}`);
  for (const name of ['preview', 'current-use', 'dispatch', 'route', 'write']) {
    const path = `${host}salesforce-effect-${name}.mjs`;
    assert.ok(!graph.includes(path), `Parallel execution is reachable: ${path}`);
    assert.equal(existsSync(join(root, path)), false, `Retired execution remains: ${path}`);
  }
  const installation = installedConnectors.find(entry => entry.registration === 'salesforce');
  assert.ok(installation);
  assert.deepEqual(installation.implementationFiles.map(file => file.path),
    graph.filter(path => path.startsWith('adapters/connectors/salesforce/')));
});
