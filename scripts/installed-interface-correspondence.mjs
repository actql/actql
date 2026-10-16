// Compose the existing member, source and Owner readers. The caller obtains
// copy bindings from the ordinary builder and validates the normal artifacts;
// syntax/reference consistency alone never admits a release or runtime result.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {projectOwnerSources} from './interface-owner-source-projection.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';

const inside = path => typeof path === 'string' && path.length && !isAbsolute(path) &&
  !path.split(/[\\/]/u).includes('..');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

export function installedInterfaceCorrespondence({repository, directory, source,
  bindings, artifacts = [], owners, generated = []}) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  const byMember = new Map();
  for (const binding of bindings) {
    assert(inside(binding.member) && inside(binding.source), 'Escaped installed interface binding');
    assert(!byMember.has(binding.member), `Duplicate installed interface binding: ${binding.member}`);
    assert(binding.transform === undefined || binding.transform === 'local-node-public-imports',
      'Unknown installed interface transformation');
    byMember.set(binding.member, binding);
  }
  for (const artifact of artifacts) assert.equal(artifact.sourceSha, source,
    `Foreign installed interface artifact source: ${artifact.module}`);
  const installed = installedInterfaceInventory(directory, {artifacts});
  const selected = installed.modules.map(module => {
    const binding = byMember.get(module.module);
    assert(binding, `Unbound installed authored interface: ${module.module}`);
    return binding.source;
  });
  const original = selected.length ? projectOwnerSources(repository,
    {source, base: source, paths: selected, all: true,
      commands: selected.filter(path => !/\.[^/]+$/u.test(path))}).modules : [];
  const bySource = new Map(original.map(module => [module.module, module]));
  const actual = installed.modules.map(module => {
    const binding = byMember.get(module.module), input = bySource.get(binding.source);
    assert(input, `Missing original authored interface: ${binding.source}`);
    const bytes = execFileSync('git', ['show', `${source}:${binding.source}`],
      {cwd: repository, maxBuffer: 16 * 1024 * 1024});
    const expected = binding.transform === 'local-node-public-imports'
      ? Buffer.from(rewriteLocalNodePackageImports(bytes.toString('utf8'), binding.source)) : bytes;
    assert.equal(module.sha256, digest(expected), `Changed installed interface bytes: ${module.module}`);
    assert.deepEqual(module.exports, input.exports, `Changed installed interface exports: ${module.module}`);
    assert.deepEqual(module.operations, input.operations, `Changed installed interface operations: ${module.module}`);
    assert.deepEqual(module.compilerFields ?? [], input.compilerFields ?? [],
      `Changed installed compiler representation: ${module.module}`);
    return input;
  });
  const coverage = interfaceOwnerCoverage({root: repository, modules: actual, owners, generated});
  return {qualification: 'installed/source/reference correspondence only; not release or runtime admission',
    source, package: installed.name, coverage, artifacts: installed.artifacts};
}
