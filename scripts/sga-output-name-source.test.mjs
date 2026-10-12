import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, copyFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {createHash} from 'node:crypto';
import {build} from 'esbuild';
import {sgaOutputNameSuccesses, sgaOutputNameRefusals} from './fixtures/sga-output-name-source.mjs';

test('quoted OutputName source and independent JSON preserve ordinary identity projection', () => {
  const [json, source] = sgaOutputNameSuccesses;
  const steps = JSON.parse(json.text).stages[0].steps;
  assert.deepEqual(steps[2].match_nodes.bindings, {identity: 'SELECT'});
  assert.deepEqual(steps[2].match_nodes.fields, ['node_key', 'SELECT']);
  assert.deepEqual(steps[3].derive, {bound: {not: {is_null: {field: 'SELECT'}}}});
  assert.deepEqual(source.results, json.results);
  assert.deepEqual(source.results.matched, {rows: [{node_key: 1, bound: true}, {node_key: 2, bound: true}],
    columns: [{name: 'node_key', contract: {type: 'number', nullable: false}},
      {name: 'bound', contract: {type: 'boolean', nullable: false}}]});
  assert.ok(source.text.includes('bindings: {identity: `SELECT`}'));
  assert.ok(source.text.includes('`SELECT` IS NOT NULL AS bound'));
});

test('reserved unquoted OutputNames are rejected without changing original Graph values or guards', () => {
  const source = sgaOutputNameSuccesses[1];
  for (const [entry, value] of sgaOutputNameRefusals.map((entry, i) => [entry, ['SELECT', 'null'][i]])) {
    assert.equal(entry.text, source.text.replace('identity: `SELECT`', 'identity: ' + value));
    assert.equal(entry.expectedCode, 'ClientProgramInvalidInput');
    assert.equal(entry.sourceReadCount, 0);
  }
  assert.ok(sgaOutputNameSuccesses.every(c => c.sourceReadCount === 0));
});

test('supplemental OutputName controls are registered in the existing Graph MATCH cohort', () => {
  const source = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(source.includes("from './sga-output-name-source.mjs'"));
  assert.ok(source.includes('...sgaOutputNameSuccesses'));
  assert.ok(source.includes('...sgaOutputNameRefusals'));
});

test('standalone acceptance installs every directly imported root fixture', () => {
  const acceptance = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const installer = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  const installed = new Set([...installer.matchAll(
    /\['scripts\/fixtures\/[^']+',\s*'([^']+)'\]/gu,
  )].map(match => match[1]));
  const imports = [...acceptance.matchAll(
    /(?:from\s*|import\s*)['"]\.\/([^'"]+)['"]/gu,
  )].map(match => match[1]).filter(path => !path.includes('/'));
  assert.ok(imports.length > 0);
  assert.ok(imports.includes('sga-output-name-source.mjs'));
  assert.deepEqual(imports.filter(path => !installed.has(path)), [],
    'Copied acceptance must resolve its fixture imports without the checkout');
});

test('standalone copied acceptance has a closed relative module graph', async () => {
  const installer = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  const copies = [...installer.matchAll(
    /\['(scripts\/fixtures\/[^']+)',\s*'([^']+)'\]/gu,
  )].map(match => [match[1], match[2]]);
  const grouped = installer.match(/for \(const path of \[([\s\S]*?)\]\) \{\n  await writeFile\(join\(root, path\), await readFile\(join\(repository, 'scripts', path\)\)\);\n\}/u);
  assert.ok(grouped, 'Preserve the existing nested fixture-copy boundary');
  for (const match of grouped[1].matchAll(/'(fixtures\/[^']+)'/gu)) {
    copies.push(['scripts/' + match[1], match[1]]);
  }
  const root = mkdtempSync(join(tmpdir(), 'actql-fixture-copy-closure-'));
  try {
    for (const [source, destination] of copies) {
      if (!source.endsWith('.mjs')) continue;
      const path = join(root, destination);
      mkdirSync(dirname(path), {recursive: true});
      copyFileSync(source, path);
    }
    // Parse and resolve the actual isolated fixture graph without executing
    // Client/Host calls or borrowing any relative module from the checkout.
    const result = await build({absWorkingDir: root, entryPoints: ['acceptance.mjs'],
      bundle: true, platform: 'node', format: 'esm', packages: 'external',
      write: false, metafile: true, logLevel: 'silent'});
    assert.ok(Object.keys(result.metafile.inputs).some(path =>
      path === 'sga-output-name-source.mjs'));
    const inventory = Object.keys(result.metafile.inputs).sort().map(path => {
      assert.ok(!path.startsWith('../'), 'Fixture graph must stay in the isolated copy');
      return [path, createHash('sha256').update(readFileSync(join(root, path))).digest('hex')];
    });
    console.log('ACTQL_FIXTURE_COPY_CLOSURE ' + JSON.stringify({
      complete: true, modules: inventory.length, inventory,
    }));
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});
