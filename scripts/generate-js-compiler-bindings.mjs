import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

// Independently installed packages must not borrow another package's private
// module. These copies have one source and are not separate ABI authorities.
export const compilerBindingTargets = Object.freeze([
  'adapters/host-common/compiler-binding.generated.mjs',
  'packages/run-host-core/compiler-binding.generated.mjs',
  'packages/coordinator-core/compiler-binding.generated.mjs',
  'packages/transfer-core/compiler-binding.generated.mjs',
  'packages/provider-ai-sdk/_internal/compiler-binding.generated.mjs',
  'packages/provider-http/_internal/compiler-binding.generated.mjs',
]);

export function generateCompilerBindings(root, write = false) {
  const source = readFileSync(new URL('scripts/templates/js-compiler-binding.mjs', root), 'utf8');
  for (const path of compilerBindingTargets) {
    const target = new URL(path, root);
    let actual;
    try { actual = readFileSync(target, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (actual === source) continue;
    if (!write) throw new Error(`Stale private compiler binding: ${path}`);
    writeFileSync(target, source);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
    throw new Error('Usage: generate-js-compiler-bindings.mjs --check|--write');
  }
  generateCompilerBindings(new URL('../', import.meta.url), process.argv[2] === '--write');
}
