import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {build, resolveConfig} from 'vite';
import {repositoryFiles} from '../../../scripts/distribution-interface-roots.mjs';
import {viteInterfaceInventory} from '../../../scripts/vite-interface-inventory.mjs';

test('normal OSS Vite inputs include the library dependency, browser modules and Worker source assets', async () => {
  const lock = JSON.parse(readFileSync('package-lock.json', 'utf8'));
  assert.equal(lock.packages['node_modules/vite'].version,
    JSON.parse(readFileSync('node_modules/vite/package.json', 'utf8')).version);
  const configs = repositoryFiles(process.cwd()).filter(path => /(?:^|\/)vite\.config\.[cm]?[jt]s$/u.test(path));
  assert(configs.length);
  // The normal app resolves the normal workspace library export. Prepare that
  // library with its unchanged production build, not an alias to unbuilt TSX.
  for (const configFile of configs) {
    const config = await resolveConfig({configFile, configLoader: 'native', logLevel: 'silent'}, 'build');
    if (config.build.lib) await build({configFile, configLoader: 'native', logLevel: 'silent'});
  }
  const result = await viteInterfaceInventory(process.cwd(), configs);
  for (const name of ['packages/explorer-ui/plan-explorer.tsx', 'packages/explorer/app/main.tsx',
    'packages/explorer-ui/flow-layout-worker.mjs', 'packages/explorer-ui/flow-layout-engine.mjs']) {
    assert(result.modules.some(value => value.module === name), `Missing actual Vite source: ${name}`);
  }
  assert(result.generated.some(value => value.file === 'plan-explorer.js'));
  assert(result.consumedCompiled.some(value => value.module === 'packages/explorer-ui/dist/plan-explorer.js'));
  assert(!result.modules.some(value => value.module.includes('/dist/')));
  assert(result.sourceCopies.some(value => value.source === 'packages/explorer-ui/flow-layout-worker.mjs'));
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  writeFileSync('/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/i6-actual-vite-source-coverage.json',
    JSON.stringify({...result, readerSource}, null, 2) + '\n');
  console.log(JSON.stringify({modules: result.modules.length, assets: result.assets.length,
    configs: configs.length, generated: result.generated.length, qualification: result.qualification}));
});
