import {generateCompilerBindings} from './generate-js-compiler-bindings.mjs';
import {readFileSync, writeFileSync} from 'node:fs';
import {emitInterfaceTypeScript} from './typescript-interface-emit.mjs';

// One closed DATA snapshot/Common-reader connection, packaged independently.
// The SDK-free installation uses an explicit null SDK, never a fabricated one.
const source = new URL('../adapters/host-common/model-original-materials.mts.in', import.meta.url);
const targets = [
  ['provider-ai-sdk', 'OpenAI', "sdk:shape('interface,lock_artifact_cid,package_name,version'),", true],
  ['provider-http', 'HTTP', 'sdk:(value: unknown) => {if (value !== null) fail();return value;},', false],
] as const;
if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
  throw new Error('Usage: generate-model-original-materials.mjs --check|--write');
}
// The independently installed consumers share A's single pinned ABI binding.
generateCompilerBindings(new URL('../', import.meta.url), process.argv[2] === '--write');
const template = readFileSync(source, 'utf8');
if (!template.includes('__PROVIDER__') ||
    [['__SDK_FIELD__', 1], ['__READ_GUARD__', 1], ['__READ_FIELD__', 2],
      ['__LAYOUT_FIELDS__', 1], ['__READ_BINDING__', 1]].some(([name, count]) =>
        template.split(name as string).length !== (count as number) + 1)) {
  throw new Error('Invalid original Model materials template');
}
const generated: [URL, string][] = [];
for (const [name, provider, sdk, recipe] of targets) {
  // Preserve each existing installation contract. OpenAI already accepts its
  // deferred recipe; the HTTP branch deliberately remains installation-only.
  const legacyLayout = "'barrier_cid,layout_artifact_cid,parameter_values_cid,program_definition_cid,runtime_artifact_cid'";
  const guard = recipe ? `  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail();
  const recipe = Object.hasOwn(value, 'originalReadRecipe');
  const readKey = recipe ? 'originalReadRecipe' : 'originalReadInstallation';
  if (recipe && Object.hasOwn(value, 'originalReadInstallation')) fail();` : '';
  const binding = recipe ? `  const {installation,rawCaptureSelection:raw} = materials;
  const readKey = Object.hasOwn(materials, 'originalReadRecipe')
    ? 'originalReadRecipe' : 'originalReadInstallation';
  const read = materials[readKey] as Extract<NonNullable<ReturnType<typeof snapshot${provider}OriginalMaterials>[string]>, {nodeInstallation: unknown}>;` : '  const {installation,originalReadInstallation:read,rawCaptureSelection:raw} = materials;';
  const body = template.replaceAll('__PROVIDER__', provider).replace('__SDK_FIELD__', sdk)
    .replace('__READ_GUARD__', guard).replaceAll('__READ_FIELD__', recipe ? '[readKey]' : 'originalReadInstallation')
    .replace('__LAYOUT_FIELDS__', recipe ? "recipe ? 'layout_artifact_cid,runtime_artifact_cid' : " + legacyLayout : legacyLayout)
    .replace('__READ_BINDING__', binding);
  const root = new URL('../', import.meta.url);
  const outputs = emitInterfaceTypeScript(root,
    new URL(`packages/${name}/_internal/original-materials.mts`, root), body);
  for (const [extension, output] of outputs) {
    generated.push([new URL(`../packages/${name}/_internal/original-materials${extension}`, import.meta.url), output]);
  }
}
// Both independently packaged variants must compile before publishing either.
for (const [target, output] of generated) {
  let actual: string | undefined;
  try { actual = readFileSync(target, 'utf8'); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
  if (actual === output) continue;
  if (process.argv[2] === '--check') throw new Error('Original Model materials drift: ' + target.pathname);
  writeFileSync(target, output);
}
