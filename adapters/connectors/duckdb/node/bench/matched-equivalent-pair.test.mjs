import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {runMatchedEquivalentPair} from './matched-equivalent-pair.mjs';

const checkout = fileURLToPath(new URL('../../../../../', import.meta.url));

test('matched legs receive separate empty compile caches', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-pair-cache-'));
  try {
    const database = join(directory, 'source.duckdb');
    await writeFile(database, 'fixed source');
    const roots = [];
    const fixture = {
      id: 'cache-control',
      workload: 'fixture',
      layout: 'narrow',
      rows: 1,
      limits: {timeoutMs: 100, cleanupTimeoutMs: 100},
      createSourceSql: 'select 1',
      program: () => ({}),
    };
    const report = await runMatchedEquivalentPair({
      fixture,
      checkout,
      database,
      directory,
      index: 0,
      inspectCheckout: async () => ({revision: 'a'.repeat(40), dirty: false}),
      inspectReleaseArtifacts: async () => 'b'.repeat(64),
      runChild: async (_label, _args, _timeout, _script, environment) => {
        const root = environment.NODE_COMPILE_CACHE;
        assert.equal(environment.NODE_DISABLE_COMPILE_CACHE, undefined);
        assert.deepEqual(await readdir(root), []);
        roots.push(root);
        await writeFile(join(root, 'compiled'), 'simulated cache');
        return {status: 'failed'};
      },
    });
    assert.equal(report.status, 'failed');
    assert.equal(report.provenance.nodeCompileCache,
      'empty private cache for each leg of each pair');
    assert.equal(roots.length, 2);
    assert.notEqual(roots[0], roots[1]);
    assert.deepEqual(await readdir(directory), ['source.duckdb']);
    assert.equal((await readFile(database, 'utf8')), 'fixed source');
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
