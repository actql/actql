// The installed CLI and the physical fixtures consume the same admitted cohort.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {readConnectorConformanceInput} from '../../connector-conformance-input.mjs';
import {authoringToolkitPath, observeInstalledAuthoringToolkit} from '../../connector-authoring-toolkit.mjs';
import {inventory} from '../../package-release.mjs';
import {externalInstalledPackages, prepareExternalRestCohort, verifyExternalRestTarballs} from '../external-rest/installed-modules.mjs';

const toolkit = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
const descriptor = process.env.ACTQL_EXTERNAL_INSTALLED_CONFORMANCE_INPUT;
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

test('ordinary composed external provider bundle and original Saved', async () => {
  assert(descriptor, 'Select the exact composed external installer cohort');
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH, 'Composed external conformance requires the original package resolution');
  const selection = readConnectorConformanceInput(descriptor);
  assert(selection.kind === 'actql-external-installed-normal/0.1');
  const cohort = await prepareExternalRestCohort(selection, {external: true});
  const modules = join(await realpath(selection.consumerRoot), 'node_modules');
  assert((await lstat(modules)).isDirectory(), 'Select an ordinary installed node_modules directory');
  const host = join(modules, '@actql/local-node');
  assert.equal(await realpath(join(host, authoringToolkitPath)), toolkit,
    'The selected external Host must supply this original CLI');
  const originalToolkit = await observeInstalledAuthoringToolkit(toolkit, cohort);
  const verifyOriginal = async () => {
    for (const {name, files} of cohort.manifest.packages) {
      const installed = join(modules, name);
      assert.equal(await realpath(installed), installed, 'Ordinary installer owns this package');
      assert.deepEqual(await inventory(installed), files, `Changed composed package ${name}`);
    }
    assert.deepEqual(await observeInstalledAuthoringToolkit(toolkit, cohort), originalToolkit);
    for (const input of cohort.originalBindings) assert.equal(hash(await readFile(input.path)), input.sha256);
    await verifyExternalRestTarballs(cohort.manifest, cohort.artifactManifestPath, externalInstalledPackages);
  };
  await verifyOriginal();
  let outcome: unknown;
  try {
    const originalModule = (path: string) => import(pathToFileURL(join(host, path)).href);
    const {installedConnectors} = await originalModule('adapters/connectors-builtin/installations.generated.mjs');
    const {providerBundleUrl} = await originalModule('adapters/host-node/installed-connectors.mjs');
    const {verifyExternalInstalledFixture} = await import(new URL('./consumer.mjs', import.meta.url).href);
    await mkdir(selection.outputRoot, {mode: 0o700});
    outcome = await verifyExternalInstalledFixture({directory: join(selection.outputRoot, 'state'), installedConnectors, providerBundleUrl});
  } catch (primary) {
    try { await verifyOriginal(); }
    catch (custody) { throw new AggregateError([primary, custody], 'Composed fixture and original package check both failed', {cause: primary}); }
    throw primary;
  }
  await verifyOriginal();
  await writeFile(join(selection.outputRoot, 'qualification.json'), JSON.stringify({
    sourceSha: selection.sourceSha, sourceTree: selection.sourceTree, manifestSha256: selection.manifestSha256,
    packages: cohort.offeredTarballs, authoring: originalToolkit, outcome,
  }, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
});
