// One literal projection of the existing provider-authored request asset.
// Core, not this generator, admits the request's finite GET semantics.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function generateNotionUserListReadWire(root: string, write = false) {
  const input = join(root, 'src/connectors/notion/user-list-request.json');
  const output = join(root, 'adapters/connectors/notion/site/user-list-read-wire.generated.mjs');
  const original = JSON.parse(readFileSync(input, 'utf8')) as {read?: unknown};
  assert(original.read && typeof original.read === 'object' && !Array.isArray(original.read),
    'Missing original Notion user-list request DATA');
  const wire = JSON.stringify(original.read);
  const generated = '// Generated from src/connectors/notion/user-list-request.json; edit that original asset.\n' +
    'export const notionUserListReadWire = ' + JSON.stringify(wire) + ';\n';
  if (write) writeFileSync(output, generated);
  else assert.equal(readFileSync(output, 'utf8'), generated, 'Stale original Notion user-list read wire');
  return {input, output};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 1 && ['--check', '--write'].includes(args[0]), 'Select --check or --write');
  generateNotionUserListReadWire(fileURLToPath(new URL('../', import.meta.url)), args[0] === '--write');
}
