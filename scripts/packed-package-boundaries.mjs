// Audit actual installed package graphs, not the monorepo's dependency layout.
import assert from 'node:assert/strict';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {isBuiltin, createRequire} from 'node:module';
import {dirname, isAbsolute, join, relative, resolve} from 'node:path';
import {buildSync} from 'esbuild';

const inside = (parent, path) => {
  const child = relative(parent, path);
  return child === '' || !child.startsWith('..') && !isAbsolute(child);
};
const targets = entry => typeof entry === 'string' ? [entry]
  : Object.values(entry).flatMap(targets);
const packageName = specifier => specifier.startsWith('@')
  ? specifier.split('/').slice(0, 2).join('/') : specifier.split('/')[0];

export function auditPackedPackages(root, names) {
  const owned = realpathSync(root);
  for (const name of names) {
    const directory = join(root, 'node_modules', '@actql', name);
    assert.ok(inside(owned, realpathSync(directory)), `External package link: ${name}`);
    const manifest = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
    const exported = targets(manifest.exports);
    for (const target of exported) {
      assert.ok(target.startsWith('./'), `Nonlocal export: ${name}/${target}`);
      const path = resolve(directory, target);
      assert.ok(existsSync(path) && inside(realpathSync(directory), realpathSync(path)),
        `Missing or escaped export: ${name}/${target}`);
    }
    const entries = exported.filter(target => /\.[cm]?js$/u.test(target));
    const graph = buildSync({entryPoints: entries.map(target => join(directory, target)),
      absWorkingDir: root, bundle: true, packages: 'external', platform: 'node',
      format: 'esm', target: 'node22', metafile: true, write: false,
      outdir: join(root, 'unused-audit-output'), logLevel: 'silent'});
    for (const [input, metadata] of Object.entries(graph.metafile.inputs)) {
      const path = resolve(root, input);
      assert.ok(inside(realpathSync(directory), realpathSync(path)),
        `Source-tree fallback: ${name}/${input}`);
      for (const imported of metadata.imports.filter(item => item.external)) {
        if (isBuiltin(imported.path)) continue;
        const dependency = packageName(imported.path);
        assert.ok(Object.hasOwn(manifest.dependencies ?? {}, dependency),
          `Undeclared dependency: ${manifest.name} -> ${imported.path}`);
        const resolved = createRequire(path).resolve(imported.path);
        assert.ok(inside(owned, realpathSync(resolved)),
          `Dependency outside consumer: ${imported.path}`);
      }
    }
  }
}
