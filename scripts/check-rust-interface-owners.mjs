// Selected Rust source/Owner check. It establishes no artifact or Run acceptance.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {javascriptInterface} from './interface-inventory.mjs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {rustInterfaceSources} from './rust-interface-sources.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';

export function checkRustInterfaceOwners(root) {
  root = resolve(root);
  execFileSync(process.env.ACTQL_PYTHON ?? 'python3', ['-B',
    'scripts/generate-local-wasm-abi.py', '--check'], {cwd: root, timeout: 15000, stdio: 'pipe'});
  const source = rustInterfaceSources(root);
  for (const module of ['scripts/rust-interface-sources.mjs', 'scripts/check-rust-interface-owners.mjs']) {
    const bytes = readFileSync(join(root, module));
    source.modules.push({module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...javascriptInterface(bytes.toString('utf8'))});
  }
  const owners = interfaceOwnerDeclarations(root, ['scripts/interface-owners/rust/interface-boundaries.json']);
  const result = interfaceOwnerCoverage({root, modules: source.modules, owners});
  assert(result.complete && result.primaryComplete);
  return {...result, qualification: 'Rust source/generation/Owner only; not artifact or runtime acceptance',
    cargoEntrances: source.entrances.length};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'Usage: node scripts/check-rust-interface-owners.mjs');
  console.log(JSON.stringify(checkRustInterfaceOwners(fileURLToPath(new URL('../', import.meta.url)))));
}
