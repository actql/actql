// Test-only replay of three published local originals under their actual Git
// policy. Never imported by a production collector, reader or reuse selector.
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {gitTree} from './inputs.mjs';

const revisions = ['b34f6e5445b731584729a1f8c09ec8c2404ccde6',
  'fc2962f43431e5c4c86cb47970251aa4c7c7f98c', '8bbe08fca045be6c00a64eb5a68889295082c67c'];
const modules = ['inputs', 'package-configurations', 'isolation', 'isolated-runtime',
  'runtime', 'isolated-contract', 'mutation-inventory', 'mutation-observation']
  .map(name => `proofs/ci-evidence/${name}.mjs`).concat('proofs/bounded-session/action-inputs.mjs');

export async function historicalIsolatedFixture(root, revision) {
  assert(revisions.includes(revision), 'Only independently pinned historical local originals');
  const tree = gitTree(root, revision), directory = mkdtempSync(join(tmpdir(), 'actql-historical-isolated-fixture-'));
  try {
    tree.prefetch(modules);
    for (const path of modules) {
      const file = join(directory, path);
      mkdirSync(dirname(file), {recursive: true});
      // Exact Git bytes, no current-policy overlay or archive-supplied code.
      writeFileSync(file, tree.read(path), {flag: 'wx'});
    }
    return await import(pathToFileURL(join(directory, 'proofs/ci-evidence/isolated-runtime.mjs')).href);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
}
