import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

// Actual consumer entry execution with inert package sentinels. These cases
// prove pre-import refusal, not package/runtime/normal Model acceptance.
for (const variant of ['linked-provider', 'redirected-public-entry', 'linked-node-modules']) {
  test(`installed Model consumer refuses ${variant} before either public package executes`, t => {
    const root = mkdtempSync(join(tmpdir(), 'actql-model-package-origin-'));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    const consumer = join(root, 'consumer'), outside = join(root, 'outside');
    mkdirSync(consumer); mkdirSync(outside);
    copyFileSync(new URL('./fixtures/normal-openai-installed.fixture.mjs', import.meta.url), join(consumer, 'case.mjs'));
    copyFileSync(new URL('./fixtures/external-rest/conformance.mjs', import.meta.url), join(consumer, 'conformance.mjs'));
    const modules = variant === 'linked-node-modules' ? join(outside, 'node_modules') : join(consumer, 'node_modules');
    mkdirSync(join(modules, '@actql'), {recursive: true});
    if (variant === 'linked-node-modules') symlinkSync(modules, join(consumer, 'node_modules'));
    for (const name of ['node', 'provider-ai-sdk']) {
      const directory = variant === 'linked-provider' && name === 'provider-ai-sdk'
        ? join(outside, name) : join(modules, '@actql', name);
      mkdirSync(directory);
      if (variant === 'linked-provider' && name === 'provider-ai-sdk') {
        symlinkSync(directory, join(modules, '@actql', name));
      }
      const entry = variant === 'redirected-public-entry' && name === 'provider-ai-sdk' ? 'other.mjs' : 'index.mjs';
      writeFileSync(join(directory, 'package.json'), JSON.stringify({name: '@actql/' + name,
        type: 'module', exports: {'.': './' + entry}}));
      writeFileSync(join(directory, entry), `import{writeFileSync}from'node:fs';
        writeFileSync(${JSON.stringify(join(root, name + '.executed'))},'unexpected');
        export function connect(){throw Error('No product execution selected');}
        export function createOpenAIChatProvider(){throw Error('No product execution selected');}`);
    }
    const result = spawnSync(process.execPath, ['case.mjs', 'warm'], {cwd: consumer,
      encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
    assert.ifError(result.error); assert.equal(result.status, 1);
    assert.match(result.stderr, /fresh installation|expected installed package entry|fresh node_modules/);
    for (const name of ['node', 'provider-ai-sdk']) assert.equal(existsSync(join(root, name + '.executed')), false);
    assert.equal(existsSync(join(consumer, '.state')), false);
    assert.equal(existsSync(join(consumer, 'actql.config.json')), false);
  });
}
