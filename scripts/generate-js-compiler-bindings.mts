import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import ts from 'typescript';

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
  // Compile the authored source once. Both runtime copies and declarations come
  // from the same strict project options; ignored bootstrap emit is not input.
  const directory = fileURLToPath(root);
  const config = ts.readConfigFile(fileURLToPath(new URL('tsconfig.base.json', root)), ts.sys.readFile);
  const converted = ts.convertCompilerOptionsFromJson(config.config?.compilerOptions ?? {}, directory);
  const options: ts.CompilerOptions = {...converted.options, declaration: true, types: []};
  const source = fileURLToPath(new URL('scripts/templates/js-compiler-binding.mts', root));
  const program = ts.createProgram([source], options);
  const outputs = new Map<string, string>();
  const diagnostics = [...(config.error ? [config.error] : []), ...converted.errors,
    ...ts.getPreEmitDiagnostics(program)];
  if (!diagnostics.length) {
    const original = program.getSourceFile(source);
    if (!original) throw new Error('Missing authored private compiler binding');
    const emitted = program.emit(original, (path, text) => {
      if (path.endsWith('.mjs')) outputs.set('.mjs', text);
      if (path.endsWith('.d.mts')) outputs.set('.d.mts', text);
    });
    diagnostics.push(...emitted.diagnostics);
  }
  if (diagnostics.length) throw new Error(ts.formatDiagnostics(diagnostics, {
    getCanonicalFileName: path => path,
    getCurrentDirectory: () => directory,
    getNewLine: () => '\n',
  }));
  if (outputs.size !== 2) throw new Error('Missing private compiler binding emit');
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
