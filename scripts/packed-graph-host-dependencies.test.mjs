import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {basename, dirname, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('packed Graph Host consumers retain their transitive local module imports', async () => {
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  const pending = ['graph-public-host.test.mjs', 'graph-source-snapshot.test.mjs'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.ok(driver.includes(`'${name}'`), `Packed consumer dependency is not copied: ${name}`);
    const body = await readFile(resolve(scripts, name), 'utf8');
    for (const match of body.matchAll(/\bfrom\s+['"]([^'"]+)['"]/gu)) {
      if (!match[1].startsWith('.')) continue;
      const dependency = relative(scripts, resolve(scripts, dirname(name), match[1]));
      assert.ok(!dependency.startsWith('..'), 'Static test imports must stay within scripts');
      pending.push(dependency);
    }
  }
});

test('packed Graph predicate source fixtures retain their flattened transitive imports', async () => {
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  const pending = ['fixtures/graph-property-predicate-source-input.mjs'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.ok(driver.includes(`['scripts/${name}', '${basename(name)}']`),
      `Packed source fixture dependency is not staged: ${name}`);
    const body = await readFile(resolve(scripts, name), 'utf8');
    for (const match of body.matchAll(/\bfrom\s+['"]([^'"]+)['"]/gu)) {
      if (!match[1].startsWith('.')) continue;
      const dependency = relative(scripts, resolve(scripts, dirname(name), match[1]));
      assert.equal(dirname(dependency), 'fixtures', 'Flattened fixture imports stay in one directory');
      pending.push(dependency);
    }
  }
});
