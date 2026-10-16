// The stdlib Python parser reads Python; JavaScript never reparses its syntax
// or setuptools TOML. Product code and runtime engines are not imported.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const reader = fileURLToPath(new URL('./python_interface_inventory.py', import.meta.url));

export function pythonInterfaceSources(root, python = 'python3') {
  const result = JSON.parse(execFileSync(python, ['-B', reader, '--source-root', root], {
    encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024}));
  assert(result.qualification === 'source-input-coverage-only' && Array.isArray(result.roots) &&
    Array.isArray(result.modules), 'Invalid Python interface source projection');
  return result;
}

export function pythonModuleInterfaces(root, modules, python = 'python3') {
  const result = JSON.parse(execFileSync(python, ['-B', reader, '--modules-root', root], {
    input: JSON.stringify(modules), encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024}));
  assert(Array.isArray(result), 'Invalid Python module projection');
  return result;
}
