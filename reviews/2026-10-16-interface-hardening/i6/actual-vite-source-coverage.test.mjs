import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {repositoryFiles} from '../../../scripts/distribution-interface-roots.mjs';
import {viteInterfaceInventory} from '../../../scripts/vite-interface-inventory.mjs';

test('normal OSS Vite builds expose their actual UI modules and Worker source assets without writing output', async () => {
  const lock = JSON.parse(readFileSync('package-lock.json', 'utf8'));
  assert.equal(lock.packages['node_modules/vite'].version,
    JSON.parse(readFileSync('node_modules/vite/package.json', 'utf8')).version);
  const configs = repositoryFiles(process.cwd()).filter(path => /(?:^|\/)vite\.config\.[cm]?[jt]s$/u.test(path));
  assert(configs.length);
  const result = await viteInterfaceInventory(process.cwd(), configs);
  for (const name of ['packages/explorer-ui/plan-explorer.tsx', 'packages/explorer/app/main.tsx',
    'packages/explorer-ui/flow-layout-worker.mjs', 'packages/explorer-ui/flow-layout-engine.mjs']) {
    assert(result.modules.some(value => value.module === name), `Missing actual Vite source: ${name}`);
  }
  assert(result.generated.some(value => value.file === 'plan-explorer.js'));
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  writeFileSync('/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/i6-actual-vite-source-coverage.json',
    JSON.stringify({...result, readerSource}, null, 2) + '\n');
  console.log(JSON.stringify({modules: result.modules.length, assets: result.assets.length,
    configs: configs.length, generated: result.generated.length, qualification: result.qualification}));
});
