import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {explicitSeedRuntime, checkPureRuntime} from './moon-runtime.mjs';

const raw = () => readFileSync(new URL(
  '../../_build/js/release/build/connectors_workers_bridge/connectors_workers_bridge.js',
  import.meta.url), 'utf8');

test('only the exact pinned physical entropy builtin can be adapted', async () => {
  const source = raw();
  assert.throws(() => checkPureRuntime(source), /GeneratedRuntimeIO/);
  const adapted = explicitSeedRuntime(source);
  checkPureRuntime(adapted);
  assert.match(adapted, /instantiate\(hostHashSeed\)/);
  assert.throws(() => explicitSeedRuntime(source.replace('Math.random()', 'Math.random() + 1')),
    /UnauditedMoonEntropyBuiltin/);
  assert.throws(() => explicitSeedRuntime('export const x = 1;'), /UnknownMoonExport/);
});

test('generated-runtime gate rejects unreviewed side channels without rejecting comments', () => {
  for (const source of [
    'fetch("https://example.invalid")',
    'const f = globalThis["fetch"];',
    'const r = Math["random"];',
    'const p = process;',
    'Date.now();',
    'import fs from "node:fs";',
    'import("node:fs");',
    'new Function("return 1")();',
  ]) assert.throws(() => checkPureRuntime(source), /GeneratedRuntime(IO|Import)/, source);
  checkPureRuntime('// fetch and process are documentation\nconst description = "node:fs";');
});
