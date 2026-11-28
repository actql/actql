import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {httpMaterialsConfiguration} from '../packages/provider-http/original-materials.fixture.mjs';
import {snapshotHTTPOriginalMaterials} from '../packages/provider-http/_internal/original-materials.mjs';

test('the independent HTTP material generator emits its closed DATA reader', () => {
  const root = new URL('../', import.meta.url);
  execFileSync(process.execPath, ['scripts/generate-model-original-materials.mjs', '--check'], {
    cwd: fileURLToPath(root), stdio: 'pipe', timeout: 30_000,
  });
  const input = httpMaterialsConfiguration().originalMaterials;
  const captured = snapshotHTTPOriginalMaterials(input);
  assert.notEqual(captured, input);
  assert(Object.isFrozen(captured));
  for (const sdk of [undefined, {}]) {
    assert.throws(() => snapshotHTTPOriginalMaterials({...input, installation: {...input.installation, sdk}}),
      {code: 'InvalidHTTPOriginalMaterials'});
  }
  const {originalReadInstallation, ...remaining} = input;
  const {program_definition_cid, parameter_values_cid, barrier_cid, ...layout} = originalReadInstallation.nodeInstallation.layout;
  assert.throws(() => snapshotHTTPOriginalMaterials({...remaining, originalReadRecipe: {...originalReadInstallation,
    nodeInstallation: {...originalReadInstallation.nodeInstallation, layout}}}), {code: 'InvalidHTTPOriginalMaterials'});
  assert(readFileSync(new URL('packages/provider-http/_internal/original-materials.d.mts', root), 'utf8')
    .includes('snapshotHTTPOriginalMaterials'));
  assert.equal(existsSync(new URL('packages/provider-ai-sdk/_internal/original-materials.mjs', root)), false);
});
