import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {occurrences, repositoryOccurrences, violations} from
  './check-owned-contract-versions.mjs';

const empty = {version: 1, baseline: '0.1', entries: []};
const future = ['0', '2'].join('.');
const source = version => `const binding = 'actql-installed-duckdb-target/${version}';`;

test('owned namespaces, schema URNs and law versions reject advances', () => {
  for (const prefix of ['actql/', 'actql-private-target/', 'aoa-pipeline/',
    'aoa.pipeline.effect.v', 'actql.private.v', 'urn:actql:expression:',
    'urn:aoa:node:']) {
    assert.equal(occurrences(prefix + '0.1', 'source.mjs').length, 0);
    for (const version of [future, '1', '1.0', '0.1.1', '0.1-beta']) {
      const found = occurrences(prefix + version, 'source.mjs');
      assert.equal(found.length, 1, prefix + version);
      assert.equal(violations(found, empty).length, 1);
    }
  }
  assert.equal(occurrences('duckdb/1.4 https://json-schema.org/draft/2020-12 ' +
    '{"version":"2.3.4","node":"22.22.0"}', 'package.json').length, 0);
});

test('legacy inventory cannot authorize another file, context or duplicate', () => {
  const original = source(future);
  const [entry] = occurrences(original, 'old.mjs');
  const inventory = {...empty, entries: [{...entry, count: 1,
    reason: 'Historical fixture, not authorization for new writers.'}]};
  assert.equal(violations([entry], inventory).length, 0);
  assert.equal(violations([], inventory).length, 0); // Removing legacy is fine.
  assert.equal(violations([entry, entry], inventory).length, 1);
  assert.equal(violations(occurrences(original, 'new.mjs'), inventory).length, 1);
  assert.equal(violations(occurrences('export ' + original, 'old.mjs'),
    inventory).length, 1);
  assert.equal(violations(occurrences(source('1.0'), 'old.mjs'),
    inventory).length, 1);
});

test('repository scan catches a real tracked mutation and a new untracked writer', t => {
  const scratch = join(process.cwd(), '_build', 'version-gate-tests');
  mkdirSync(scratch, {recursive: true});
  const directory = mkdtempSync(join(scratch, 'repo-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  execFileSync('git', ['init', '-q', directory]);
  const file = join(directory, 'writer.mjs');
  writeFileSync(file, source('0.1'));
  execFileSync('git', ['add', 'writer.mjs'], {cwd: directory});
  assert.equal(repositoryOccurrences(directory).length, 0);
  writeFileSync(file, source(future));
  assert.equal(violations(repositoryOccurrences(directory), empty).length, 1);
  writeFileSync(join(directory, 'new.mbt'), source(future));
  assert.equal(violations(repositoryOccurrences(directory), empty).length, 2);
  writeFileSync(join(directory, 'package.json'), '{"version":"9.0.0"}');
  assert.equal(violations(repositoryOccurrences(directory), empty).length, 2);
});
