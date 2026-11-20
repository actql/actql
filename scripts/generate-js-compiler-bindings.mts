import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {emitInterfaceTypeScript} from './typescript-interface-emit.mjs';

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

export function generateCompilerBindings(root: URL, write = false): void {
  const outputs = emitInterfaceTypeScript(root, new URL('scripts/templates/js-compiler-binding.mts', root));
  for (const path of compilerBindingTargets) {
    for (const [extension, output] of outputs) {
      const relative = path.replace(/\.mjs$/u, extension);
      const target = new URL(relative, root);
      let actual: string | undefined;
      try { actual = readFileSync(target, 'utf8'); }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
      if (actual === output) continue;
      if (!write) throw new Error(`Stale private compiler binding: ${relative}`);
      writeFileSync(target, output);
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.length !== 3 || !['--check', '--write'].includes(process.argv[2])) {
    throw new Error('Usage: generate-js-compiler-bindings.mjs --check|--write');
  }
  generateCompilerBindings(new URL('../', import.meta.url), process.argv[2] === '--write');
}
