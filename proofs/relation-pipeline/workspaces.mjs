// Two source-only, process-owned workspaces. Build outputs are never copied.
import assert from 'node:assert/strict';
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createOwnedScratch } from '../../scripts/owned-scratch.mjs';
import { hash, snapshot } from './inventory.mjs';

function rejectLinks(path) {
  const entry = lstatSync(path);
  assert(!entry.isSymbolicLink(), 'Linked source or build path is not isolated');
  if (entry.isDirectory()) for (const child of readdirSync(path)) rejectLinks(join(path, child));
}
const sourceDirectories = ['src', 'vendor', 'proofs/bounded-session', 'proofs/relation-chain', 'proofs/relation-capacity', 'proofs/relation-pipeline'];
export function workspaceIdentity(root, role, expectedSource = null) {
  const path = realpathSync(root);
  const identity = lstatSync(path);
  const id = randomUUID();
  let buildRoot = null;
  return Object.freeze({ root: path, role, id,
    check() {
      const current = lstatSync(path);
      assert(!current.isSymbolicLink() && current.isDirectory() && current.dev === identity.dev && current.ino === identity.ino
        && realpathSync(root) === path, 'Execution workspace was replaced');
      for (const directory of sourceDirectories) rejectLinks(join(path, directory));
      const build = join(path, '_build');
      if (existsSync(build)) {
        rejectLinks(build);
        const currentBuild = lstatSync(build);
        assert(currentBuild.isDirectory(), 'Build root is not a directory');
        if (buildRoot) assert(currentBuild.dev === buildRoot.dev && currentBuild.ino === buildRoot.ino,
          'Execution build workspace was replaced');
        else buildRoot = currentBuild;
      } else assert(!buildRoot, 'Execution build workspace was removed');
      const source = snapshot(path);
      for (const input of Object.keys(source.sources)) {
        const components = input.split('/');
        for (let end = 1; end <= components.length; end++) {
          assert(!lstatSync(join(path, ...components.slice(0, end))).isSymbolicLink(), 'Linked inventoried source input');
        }
      }
      if (expectedSource) assert.deepEqual(source, expectedSource, 'Pristine execution source changed');
      return source;
    },
  });
}

export async function mutationWorkspaces(root) {
  const source = workspaceIdentity(root, 'normal').check();
  const scratch = await createOwnedScratch({ parent: join(root, '.artifacts/relation-pipeline/workspaces'),
    prefix: 'mutation-', label: 'relation-pipeline workspaces' });
  const materialize = role => {
    const directory = join(scratch.path, role);
    mkdirSync(directory);
    for (const [path, expected] of Object.entries(source.sources)) {
      assert(!path.split('/').some(part => part === '..' || part === '.') && !path.startsWith('/'), 'Invalid snapshot path');
      const from = join(root, path);
      assert(lstatSync(from).isFile() && !lstatSync(from).isSymbolicLink(), 'Non-regular workspace input');
      const bytes = readFileSync(from);
      assert.equal(hash(bytes), expected, 'Source changed during workspace materialization');
      const to = resolve(directory, path);
      mkdirSync(dirname(to), { recursive: true });
      writeFileSync(to, bytes, { flag: 'wx', mode: lstatSync(from).mode & 0o777 });
    }
    assert.deepEqual(snapshot(directory), source, 'Materialized source differs');
    return workspaceIdentity(directory, role, role === 'pristine' ? source : null);
  };
  const pristine = materialize('pristine'), mutable = materialize('mutable');
  assert.notEqual(pristine.root, mutable.root);
  assert.deepEqual(snapshot(root), source, 'Original source changed during materialization');
  return Object.freeze({ pristine, mutable, source,
    evidence: { pristine: { id: pristine.id, root: pristine.root }, mutable: { id: mutable.id, root: mutable.root } },
    passed() {
      assert.deepEqual(pristine.check(), source, 'Pristine source not retained');
      assert.deepEqual(mutable.check(), source, 'Mutable source not restored exactly');
      assert.deepEqual(snapshot(root), source, 'Original source not retained');
      scratch.passed();
    },
  });
}
