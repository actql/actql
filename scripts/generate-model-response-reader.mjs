import {readFileSync, writeFileSync} from 'node:fs';

// One physical reader source, copied into independent optional adapter
// artifacts. Neither provider depends on the other provider's package.
const source = new URL('../adapters/host-common/model-response-reader.mjs', import.meta.url);
const targets = [
  new URL('../packages/provider-ai-sdk/_internal/bounded-response.mjs', import.meta.url),
  new URL('../packages/provider-http/_internal/bounded-response.mjs', import.meta.url),
];
if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
  throw new Error('Usage: generate-model-response-reader.mjs --check|--write');
}
const body = readFileSync(source, 'utf8');
for (const target of targets) {
  let actual;
  try { actual = readFileSync(target, 'utf8'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (actual === body) continue;
  if (process.argv[2] === '--check') throw new Error('Model response reader drift: ' + target.pathname);
  writeFileSync(target, body);
}
