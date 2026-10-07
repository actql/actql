// Test-only resolution: packed acceptance loads every product module from the
// installed application. The copied tests/oracles never supply a runtime overlay.
import assert from 'node:assert/strict';
import {realpath} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {dirname, isAbsolute, join, relative} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const application = process.env.ACTQL_TEST_TABLE_PACKED_APPLICATION;
let installation;
const inside = (root, path) => {
  const child = relative(root, path);
  return child === '' || !child.startsWith('..') && !isAbsolute(child);
};
async function installed() {
  installation ??= (async () => {
    assert.ok(isAbsolute(application), 'Packed Table application must be absolute');
    const root = await realpath(application);
    const require = createRequire(join(root, 'package.json'));
    const local = await realpath(dirname(require.resolve('@actql/local-node')));
    assert.ok(inside(join(root, 'node_modules'), local), 'External Local package link');
    return {root, local, require};
  })();
  return installation;
}

export async function tableTestModule(source, specifier) {
  if (application === undefined) return import(source.href);
  const {root, local, require} = await installed();
  const path = await realpath(specifier.startsWith('@actql/')
    ? require.resolve(specifier) : join(local, specifier));
  assert.ok(inside(join(root, 'node_modules'), path), `External Table product module: ${specifier}`);
  if (!specifier.startsWith('@actql/')) assert.ok(inside(local, path));
  return import(pathToFileURL(path).href);
}

export async function tableTestAsset(source, path) {
  if (application === undefined) return fileURLToPath(source);
  const {local} = await installed();
  const resolved = await realpath(join(local, path));
  assert.ok(inside(local, resolved), `External Table product asset: ${path}`);
  return resolved;
}
