import {readFileSync, writeFileSync} from 'node:fs';
import {emitInterfaceTypeScript} from './typescript-interface-emit.mjs';

// One authored physical reader, packaged independently. Runtime and declarations
// come from the same strict compilation, never an ignored bootstrap output.
const root = new URL('../', import.meta.url);
const source = new URL('adapters/host-common/model-response-reader.mts', root);
const targets = ['provider-ai-sdk', 'provider-http'] as const;
if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2]!)) {
  throw new Error('Usage: generate-model-response-reader.mjs --check|--write');
}
const outputs = emitInterfaceTypeScript(root, source);
const generated: [URL, string][] = [];
for (const name of targets) for (const [extension, body] of outputs) {
  generated.push([new URL(`packages/${name}/_internal/bounded-response${extension}`, root), body]);
}
// Compilation of both outputs succeeds before any package copy is published.
for (const [target, body] of generated) {
  let actual: string | undefined;
  try { actual = readFileSync(target, 'utf8'); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
  if (actual === body) continue;
  if (process.argv[2] === '--check') throw new Error('Model response reader drift: ' + target.pathname);
  writeFileSync(target, body);
}
