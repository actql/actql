// Cargo chooses actual library/tool entrances; the pinned Rust AST reader
// follows their modules. Product code and execution engines are never imported.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, join, relative, resolve} from 'node:path';

export function rustInterfaceSources(root, cargo = process.env.ACTQL_CARGO ?? 'cargo') {
  root = realpathSync(root);
  const manifest = join(root, 'packages/rust/Cargo.toml');
  const run = args => execFileSync(cargo, args, {cwd: root, encoding: 'utf8',
    timeout: 120000, maxBuffer: 32 * 1024 * 1024});
  const metadata = JSON.parse(run(['metadata', '--locked', '--no-deps',
    '--format-version', '1', '--manifest-path', manifest]));
  const members = new Set(metadata.workspace_members);
  const entrances = metadata.packages.filter(value => members.has(value.id))
    .flatMap(value => value.targets.filter(target => target.kind.some(kind => ['lib', 'bin'].includes(kind)))
      .map(target => ({manifest: value.manifest_path, entry: target.src_path})));
  assert(entrances.length, 'No Cargo source entrances');
  const modules = new Map();
  for (const {entry} of entrances) {
    const child = relative(root, realpathSync(entry));
    assert(!isAbsolute(child) && child !== '..' && !child.startsWith('../'), 'Cargo entry escapes source root');
    const report = JSON.parse(run(['run', '--locked', '--quiet', '--manifest-path', manifest,
      '--package', 'actql-source-inventory', '--', root, resolve(root, child)]));
    assert.equal(report.qualification, 'rust-source-syntax-only; not compiler, ABI or runtime acceptance');
    assert(Array.isArray(report.modules) && report.modules.length, 'Empty Rust source projection');
    for (const module of report.modules) {
      const path = realpathSync(join(root, module.module)), local = relative(root, path);
      assert(!isAbsolute(local) && local !== '..' && !local.startsWith('../'), 'Rust module escapes source root');
      assert.equal(createHash('sha256').update(readFileSync(path)).digest('hex'), module.sha256,
        'Rust source changed after syntax projection');
      const previous = modules.get(module.module);
      if (previous) assert.deepEqual(previous, module, 'Conflicting Rust source mount');
      modules.set(module.module, module);
    }
  }
  return {qualification: 'rust-source-syntax-only', entrances,
    modules: [...modules.values()].sort((a, b) => a.module.localeCompare(b.module))};
}
