import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('optional Model material loaders retain one closed DATA source and explicit SDK branches', async () => {
  const root = new URL('../', import.meta.url);
  // The actual generator checks runtime and declarations against the authored
  // template. Do not reconstruct its compiler or trust ignored bootstrap emit.
  execFileSync(process.execPath, ['scripts/generate-model-original-materials.mjs', '--check'], {
    cwd: fileURLToPath(root), stdio: 'pipe', timeout: 30_000,
  });
  const fixture = await import(new URL('../packages/provider-ai-sdk/original-materials.fixture.mjs', import.meta.url).href) as {
    originalMaterialsConfiguration(): {originalMaterials: {installation: {sdk: unknown}}};
  };
  for (const [name, provider, withoutSdk] of [
    ['provider-ai-sdk', 'OpenAI', false], ['provider-http', 'HTTP', true],
  ] as const) {
    const original = fixture.originalMaterialsConfiguration().originalMaterials;
    const input = {...original, installation: {...original.installation,
      sdk: withoutSdk ? null : original.installation.sdk}};
    const module = await import(new URL(`packages/${name}/_internal/original-materials.mjs`, root).href) as
      Record<string, (value: unknown) => unknown>;
    const snapshot = module[`snapshot${provider}OriginalMaterials`]!;
    const captured = snapshot(input);
    assert.notEqual(captured, input);
    assert(Object.isFrozen(captured));
    for (const sdk of withoutSdk ? [undefined, {}] : [undefined, null]) {
      assert.throws(() => snapshot({...input, installation: {...input.installation, sdk}}),
        {code: `Invalid${provider}OriginalMaterials`});
    }
    const read = input as typeof input & {originalReadInstallation: {nodeInstallation: {layout: Record<string, unknown>}}};
    const {originalReadInstallation, ...remaining} = read;
    const {program_definition_cid, parameter_values_cid, barrier_cid, ...deferredLayout} = originalReadInstallation.nodeInstallation.layout;
    const recipe = {...remaining, originalReadRecipe: {...originalReadInstallation,
      nodeInstallation: {...originalReadInstallation.nodeInstallation, layout: deferredLayout}}};
    if (withoutSdk) {
      assert.throws(() => snapshot(recipe), {code: 'InvalidHTTPOriginalMaterials'});
    } else {
      assert.doesNotThrow(() => snapshot(recipe));
      assert.throws(() => snapshot({...recipe, originalReadInstallation}), {code: 'InvalidOpenAIOriginalMaterials'});
      assert.throws(() => snapshot({...recipe, originalReadRecipe: {...recipe.originalReadRecipe,
        nodeInstallation: {...recipe.originalReadRecipe.nodeInstallation,
          layout: {...deferredLayout, program_definition_cid}}}}), {code: 'InvalidOpenAIOriginalMaterials'});
    }
    assert(readFileSync(new URL(`packages/${name}/_internal/original-materials.d.mts`, root), 'utf8')
      .includes(`snapshot${provider}OriginalMaterials`));
  }
});
