import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, rmSync, writeFileSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {occurrences, repositoryOccurrences, violations, checkRepository} from
  './check-owned-contract-versions.mjs';
import {publicWireLanguageVectors} from './fixtures/public-wire-language-vectors.mjs';

const empty = {version: 1, baseline: '0.1', entries: []};
const future = ['0', '2'].join('.');
const source = version => `const binding = 'actql-installed-duckdb-target/${version}';`;

test('existing cross-language old-version refusals admit only their two exact negative contexts', () => {
  const path = 'scripts/fixtures/public-wire-language-vectors.mjs';
  const text = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const found = occurrences(text, path);
  assert.equal(found.length, 2);
  assert.deepEqual(found.map(value => value.token).sort(),
    ['actql-cancellation', 'actql-check-outcome'].map(value => `${value}/${['0', '0'].join('.')}`).sort());
  const selected = inventory.entries.filter(value => value.path === path);
  assert.equal(selected.length, 2);
  assert(selected.every(value => value.count === 1));
  assert.deepEqual(violations(found, inventory), []);
  assert.equal(violations(occurrences(text, 'scripts/other-writer.mjs'), inventory).length, 2);
  assert.equal(violations([...found, ...found], inventory).length, 2);
  for (const name of ['cancellation old protocol version', 'report old version']) {
    const vector = publicWireLanguageVectors.find(value => value.name === name);
    assert(vector && vector.expected === false, 'The original vector must remain a refusal');
  }
});

test('BigQuery Job format refusal admits only its original negative context once', () => {
  const path = 'adapters/connectors/bigquery/test/bigquery-node-bridge.test.mjs';
  const text = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const found = occurrences(text, path);
  assert.equal(found.length, 1);
  assert.equal(found[0].token, 'actql.bigquery-job-original/' + future);
  const selected = inventory.entries.filter(value => value.path === path);
  assert.equal(selected.length, 1);
  assert.equal(selected[0].count, 1);
  assert.deepEqual(violations(found, inventory), []);
  assert.equal(violations([...found, ...found], inventory).length, 1);
  assert.equal(violations(occurrences(text, 'adapters/connectors/bigquery/job-writer.mjs'), inventory).length, 1);
  assert.equal(violations(occurrences(text.replace('data.format=', 'data.changedFormat='), path), inventory).length, 1);
});

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

test('registry package version URLs remain independent from owned contract versions', () => {
  const version = '0.0.7rc1';
  const urls = [
    `https://pypi.org/pypi/actql-sdk/${version}/json`,
    `https://pypi.org/project/actql/${version}/`,
    `https://registry.npmjs.org/actql/${future}`,
    `https://registry.npmjs.org/@scope/actql-sdk/${future}`,
  ];
  for (const url of urls) assert.deepEqual(occurrences(`'${url}'`, 'source.mjs'), []);
  const owned = `actql-binding/${future}`;
  assert.deepEqual(occurrences(`${urls[0]} ${owned}`, 'source.mjs').map(item => item.token), [owned]);
  for (const url of [
    `https://other.invalid/pypi/actql-sdk/${future}/json`,
    `https://owner@pypi.org/pypi/actql-sdk/${future}/json`,
    `https://other.invalid/path/https://pypi.org/pypi/actql-sdk/${future}/json`,
    `https://pypi.org/pypi/actql-sdk/${future}/json?extra=1`,
  ]) assert.equal(occurrences(url, 'source.mjs').length, 1, url);
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

test('reviewed local verification pool admits only its exact script context once', () => {
  const path = 'scripts/local-checks-guard.mjs';
  const text = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const token = 'actql-local-heavy-pool/' + String(1);
  const found = occurrences(text, path).filter(entry => entry.token === token);
  assert.equal(found.length, 1);
  const entries = inventory.entries.filter(entry => entry.token === token);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].path, path);
  assert.equal(entries[0].count, 1);
  assert.equal(found[0].contextSha256, '82409bf7b4f8ca3f6653717eff83ab78dddb0c4a61b64114952296cbcdd6b60b');
  assert.deepEqual(violations(found, inventory), []);
  assert.equal(violations(occurrences(text, 'scripts/other-guard.mjs'), inventory).length, 1);
  assert.equal(violations(occurrences(text.replace('const poolVersion =', 'const changedPoolVersion ='), path),
    inventory).length, 1);
  const offset = text.indexOf(token);
  const context = text.slice(offset - 80, offset + token.length + 80);
  const duplicated = occurrences(context + '\n'.repeat(160) + context, path);
  assert.equal(duplicated.length, 2);
  assert(duplicated.every(entry => entry.contextSha256 === found[0].contextSha256));
  assert.equal(violations(duplicated, inventory).length, 1);
  assert.equal(violations(occurrences(text.replace(token, 'actql-local-heavy-pool/' + String(2)), path),
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

// Test exact product contexts against the real inventory. No legacy allowance
// may revive the migrated writer or authorize a fresh benchmark consumer.
test('policy candidate owner and consumers stay on the initial contract', () => {
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const current = 'actql-policy-candidates/0.1';
  const changed = current.replace('0.1', future);
  assert.equal(inventory.entries.some(entry => entry.token === changed), false);
  for (const path of ['src/physical_strategy_host/policy_consultation.mbt',
    'src/query_integration/physical_search_wbtest.mbt',
    'benchmarks/retained-results/native-owner-observations.mjs',
    'benchmarks/retained-results/native-owner-observations.test.mjs']) {
    const source = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
    assert(source.includes(current), path);
    const mutated = occurrences(source.replaceAll(current, changed), path)
      .filter(entry => entry.token === changed);
    assert(mutated.length > 0, path);
    assert.equal(violations(mutated, inventory).length, mutated.length, path);
  }
});

test('project configuration malformed-version refusal registers exactly its original negative context', () => {
  const path = 'src/run_publication_host/client_project_configuration_wbtest.mbt';
  const source = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inventory = JSON.parse(readFileSync(new URL('./owned-contract-version-legacy.json', import.meta.url)));
  const found = occurrences(source, path);
  assert.equal(found.length, 1);
  assert.equal(found[0].token, 'actql-config/' + future);
  const selected = inventory.entries.filter(value => value.path === path);
  assert.equal(selected.length, 1);
  assert.equal(selected[0].count, 1);
  assert.deepEqual(violations(found, inventory), []);
  assert.equal(violations([...found, ...found], inventory).length, 1);
  assert.equal(violations(occurrences(source, 'src/run_publication_host/project-writer.mbt'), inventory).length, 1);
  assert.equal(violations(occurrences(source.replace('"{}", "[]", "null",', '"{}", "null", "[]",'), path), inventory).length, 1);
  assert(source.includes('admit_client_project_configuration(wire) is Err(InvalidConfiguration)'));
});

// NUL-delimited discovery must reach every original path, including names
// after the child-process default output limit and paths not yet staged.
test('complete repository scan checks tracked and unstaged paths beyond one MiB', t => {
  const scratch = join(process.cwd(), '_build', 'version-gate-tests');
  mkdirSync(scratch, {recursive: true});
  const directory = mkdtempSync(join(scratch, 'wide-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  execFileSync('git', ['init', '-q', directory]);
  const relative = join('a'.repeat(200), 'b'.repeat(200), 'c'.repeat(200));
  mkdirSync(join(directory, relative), {recursive: true});
  mkdirSync(join(directory, 'scripts'));
  writeFileSync(join(directory, 'scripts/owned-contract-version-legacy.json'), JSON.stringify(empty));
  const paths = Array.from({length: 1500}, (_, i) => join(relative,
    String(i).padStart(4, '0') + '-' + 'n'.repeat(190) + '.mjs'));
  for (const path of paths.slice(0, 750)) writeFileSync(join(directory, path), source(future));
  execFileSync('git', ['add', '--', relative], {cwd: directory});
  for (const path of paths.slice(750)) writeFileSync(join(directory, path), source(future));
  const listed = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    {cwd: directory, maxBuffer: 16 * 1024 * 1024});
  assert(listed.byteLength > 1024 * 1024);
  assert.deepEqual(repositoryOccurrences(directory).map(value => value.path), paths);
  assert.throws(() => checkRepository(directory), error =>
    error.message.includes(paths[0]) && error.message.includes(paths.at(-1)));
  for (const path of paths) writeFileSync(join(directory, path), source('0.1'));
  assert.doesNotThrow(() => checkRepository(directory));
});


test('owned occurrence locations preserve LF counts and exact contexts across skipped URL and baseline tokens', () => {
  const path = 'controlled-source.mjs';
  const first = 'actql-private/' + future, second = 'urn:aoa:frame:' + future;
  const text = 'astral \u{1f642}\r\nactql-same/0.1\n' +
    "'https://pypi.org/project/actql/" + future + "/'\n" + first + '\r\n\u2028' + second + '\n';
  const expected = [[first, 4], [second, 5]].map(([token, line]) => {
    const offset = text.indexOf(token);
    return {path, token, line, contextSha256: createHash('sha256')
      .update(text.slice(Math.max(0, offset - 80), offset + token.length + 80)).digest('hex')};
  });
  assert.deepEqual(occurrences(text, path), expected);
  assert.equal(violations(expected, empty).length, 2);
});

test('owned scanner visits line and URL prefixes once per immutable input instead of once per occurrence', () => {
  for (const prefix of ['', "'https://registry.npmjs.org/actql/" + future + "'\n"]) {
    const text = prefix + Array.from({length: 160}, (_, index) =>
      'x'.repeat(1500) + ' actql-owned-' + index + '/' + future + '\n').join('');
    let inspected = 0;
    const original = {
      matchAll: expression => text.matchAll(expression),
      slice(start, end = text.length) {inspected += Math.max(0, end - start); return text.slice(start, end);},
      lastIndexOf(needle, offset) {inspected += offset + 1; return text.lastIndexOf(needle, offset);},
      indexOf(needle, offset = 0) {
        const found = text.indexOf(needle, offset);
        inspected += (found < 0 ? text.length : found + needle.length) - offset;
        return found;
      },
      toString: () => text,
    };
    const textView = new Proxy(original, {get(target, name) {
      if (typeof name === 'string' && /^(?:0|[1-9][0-9]*)$/u.test(name)) return text[name];
      return Reflect.get(target, name);
    }});
    const found = occurrences(textView, 'controlled-source.mjs');
    assert.deepEqual(found, occurrences(text, 'controlled-source.mjs'));
    assert.equal(found.length, 160);
    assert(inspected <= text.length * 5 + found.length * 200,
      `prefix inspection exceeded the linear fixture bound: ${inspected} for ${text.length} source units`);
  }
});
