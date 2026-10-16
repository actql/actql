import {generateCompilerBindings} from './generate-js-compiler-bindings.mjs';
import {readFileSync, writeFileSync} from 'node:fs';

// One closed DATA snapshot/Common-reader connection, packaged independently.
// The SDK-free installation uses an explicit null SDK, never a fabricated one.
const source = new URL('../adapters/host-common/model-original-materials.mjs.in', import.meta.url);
const targets = [
  ['provider-ai-sdk', 'OpenAI', "sdk:shape('interface,lock_artifact_cid,package_name,version'),"],
  ['provider-http', 'HTTP', 'sdk:value => {if (value !== null) fail();return value;},'],
];
if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
  throw new Error('Usage: generate-model-original-materials.mjs --check|--write');
}
// The independently installed consumers share A's single pinned ABI binding.
generateCompilerBindings(new URL('../', import.meta.url), process.argv[2] === '--write');
const template = readFileSync(source, 'utf8');
if (!template.includes('__PROVIDER__') || template.split('__SDK_FIELD__').length !== 2) {
  throw new Error('Invalid original Model materials template');
}
for (const [name, provider, sdk] of targets) {
  const body = template.replaceAll('__PROVIDER__', provider).replace('__SDK_FIELD__', sdk);
  const target = new URL(`../packages/${name}/_internal/original-materials.mjs`, import.meta.url);
  let actual;
  try { actual = readFileSync(target, 'utf8'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (actual === body) continue;
  if (process.argv[2] === '--check') throw new Error('Original Model materials drift: ' + target.pathname);
  writeFileSync(target, body);
}
