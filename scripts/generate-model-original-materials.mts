import {generateCompilerBindings} from './generate-js-compiler-bindings.mjs';
import {readFileSync, writeFileSync} from 'node:fs';
import {emitInterfaceTypeScript} from './typescript-interface-emit.mjs';

if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
  throw new Error('Usage: generate-model-original-materials.mjs --check|--write');
}
const root = new URL('../', import.meta.url);
const write = process.argv[2] === '--write';
generateCompilerBindings(root, write);
const source = readFileSync(new URL('adapters/host-common/model-original-materials.mts.in', root), 'utf8');
const stem = 'packages/provider-http/_internal/original-materials';
const outputs = emitInterfaceTypeScript(root, new URL(stem + '.mts', root), source);
for (const [extension, output] of outputs) {
  const target = new URL(stem + extension, root);
  let actual: string | undefined;
  try { actual = readFileSync(target, 'utf8'); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
  if (actual === output) continue;
  if (!write) throw new Error('Original Model materials drift: ' + target.pathname);
  writeFileSync(target, output);
}
