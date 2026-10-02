import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { generatedObservers, installGeneratedObservers, restoreGeneratedObservers } from '../instrument.mjs';
test('temporary ABI observers preserve foreign files and remove only this invocation ownership', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-observer-ownership-'));
  const paths = Object.keys(generatedObservers);
  mkdirSync(join(root, 'src/execution_relation'), { recursive: true });
  try {
    writeFileSync(join(root, paths[1]), 'another task owns this file');
    assert.throws(() => installGeneratedObservers(root), /Another task owns/);
    restoreGeneratedObservers(root);
    assert.equal(readFileSync(join(root, paths[1]), 'utf8'), 'another task owns this file');
    assert.equal(existsSync(join(root, paths[0])), false);
    rmSync(join(root, paths[1]));
    installGeneratedObservers(root); installGeneratedObservers(root);
    for (const p of paths) assert.equal(readFileSync(join(root, p), 'utf8'), generatedObservers[p]);
    restoreGeneratedObservers(root);
    assert(paths.every(p => !existsSync(join(root, p))));
  } finally { restoreGeneratedObservers(root); rmSync(root, { recursive: true }); }
});
