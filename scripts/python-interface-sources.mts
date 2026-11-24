// The stdlib Python parser reads Python; JavaScript never reparses its syntax
// or setuptools TOML. Product code and runtime engines are not imported.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
// Unchecked stdlib-reader DATA views; the original subprocess parsing,
// result-shape assertions and consuming coverage checks remain authoritative.
type PythonModule = {module: string; sha256: string; exports: string[]; imports: string[];
  operations: {name: string; parameters: string[]; async: boolean}[]};
type PythonRoot = {kind: string; name: string; manifest: string; entrances: string[];
  scripts: Record<string, string>; bindings: Record<string, string>; entry_points: Record<string, Record<string, string>>};
type PythonProjection = {qualification: unknown; roots: PythonRoot[]; modules: PythonModule[]};

const reader = fileURLToPath(new URL('./python_interface_inventory.py', import.meta.url));

export function pythonInterfaceSources(root: string, python = 'python3') {
  const result = JSON.parse(execFileSync(python, ['-B', reader, '--source-root', root], {
    encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024})) as PythonProjection;
  assert(result.qualification === 'source-input-coverage-only' && Array.isArray(result.roots) &&
    Array.isArray(result.modules), 'Invalid Python interface source projection');
  return result;
}

export function pythonModuleInterfaces(root: string, modules: readonly string[], python = 'python3') {
  const result = JSON.parse(execFileSync(python, ['-B', reader, '--modules-root', root], {
    input: JSON.stringify(modules), encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024})) as PythonModule[];
  assert(Array.isArray(result), 'Invalid Python module projection');
  return result;
}

export function pythonSourceBlobInterfaces(values: readonly {module: string; source: string}[], python = 'python3') {
  const result = JSON.parse(execFileSync(python, ['-B', reader, '--source-blobs'], {
    input: JSON.stringify(values), encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024})) as PythonModule[];
  assert(Array.isArray(result), 'Invalid Python source blob projection');
  return result;
}
