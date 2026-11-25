// tsc preserves shebangs, but a fresh in-place emit does not preserve source
// executable bits. Derive this narrow post-emit step from the same compiler
// inputs; no package/bin registry or prior generated output is an input.
import assert from 'node:assert/strict';
import {chmod, lstat} from 'node:fs/promises';
import {isAbsolute, relative, resolve, sep} from 'node:path';
import ts from 'typescript';

const root = process.cwd();
const file = resolve(root, 'tsconfig.tooling.json');
const source = ts.readConfigFile(file, ts.sys.readFile);
if (source.error) throw new Error(ts.flattenDiagnosticMessageText(source.error.messageText, '\n'));
const config = ts.parseJsonConfigFileContent(source.config, ts.sys, root);
if (config.errors.length) throw new Error(config.errors.map(value =>
  ts.flattenDiagnosticMessageText(value.messageText, '\n')).join('\n'));
assert(!config.options.noEmit && !config.options.emitDeclarationOnly && !config.options.outDir,
  'Executable modes require the canonical in-place JavaScript emit');
for (const path of config.fileNames) {
  if (!path.endsWith('.mts') || path.endsWith('.d.mts')) continue;
  const inside = relative(root, path);
  assert(!isAbsolute(inside) && inside !== '..' && !inside.startsWith(`..${sep}`),
    'Executable TypeScript input must remain in its own source root');
  const original = await lstat(path);
  assert(original.isFile(), 'Executable TypeScript input must be a regular source file');
  if (!(original.mode & 0o111)) continue;
  const output = path.slice(0, -4) + '.mjs';
  const emitted = await lstat(output);
  assert(emitted.isFile(), 'Executable TypeScript output must be a regular emitted file');
  const mode = original.mode & 0o777;
  if ((emitted.mode & 0o777) !== mode) await chmod(output, mode);
}
