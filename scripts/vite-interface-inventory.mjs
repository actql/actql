// Use the configured production bundler's resolved module and asset metadata.
// This read-only build does not qualify a normal prepacked or installed RC.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, relative, resolve} from 'node:path';
import {build} from 'vite';
import {javascriptInterface} from './interface-inventory.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

export async function viteInterfaceInventory(root, configs) {
  root = realpathSync(root);
  const modules = new Map(), assets = new Map(), generated = [], external = new Set();
  const inside = path => {
    const name = relative(root, path);
    return !isAbsolute(name) && name !== '..' && !name.startsWith('../');
  };
  function source(path) {
    const original = realpathSync(path);
    if (!inside(original)) {
      external.add(original);
      return;
    }
    const module = relative(root, original);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest)\./u.test(module),
      `Test authority in Vite interface: ${module}`);
    const bytes = readFileSync(original), sha256 = createHash('sha256').update(bytes).digest('hex');
    if (/\.[cm]?[jt]sx?$/u.test(module)) {
      modules.set(module, {module, sha256, ...(/\.[cm]?tsx?$/u.test(module)
        ? typescriptInterface(bytes.toString('utf8'), module) : javascriptInterface(bytes.toString('utf8')))});
    } else assets.set(module, {module, sha256, qualification: 'resolved-vite-source-asset'});
  }
  for (const config of configs) {
    const configPath = resolve(root, config);
    assert(inside(realpathSync(configPath)), `Escaped Vite config: ${config}`);
    source(configPath);
    const virtual = new Set();
    const result = await build({configFile: configPath, configLoader: 'native', logLevel: 'silent',
      build: {write: false, emptyOutDir: false, reportCompressedSize: false},
      plugins: [{name: 'actql-resolved-interface-inputs', generateBundle() {
        for (const id of this.getModuleIds()) {
          if (id.includes('\0')) {virtual.add(id); continue;}
          const path = id.split('?', 1)[0];
          if (isAbsolute(path) && existsSync(path)) source(path);
          else virtual.add(id);
        }
      }}]});
    const outputs = (Array.isArray(result) ? result : [result]).flatMap(value => value.output);
    for (const output of outputs) {
      assert(output, 'Vite watch results are not interface inventory');
      if (output.type === 'chunk') {
        generated.push({config, file: output.fileName,
          sourceModules: Object.keys(output.modules).filter(id => !id.includes('\0') && inside(id))
            .map(id => relative(root, id)).sort(),
          qualification: 'read-only-vite-output; not-installed-artifact'});
      } else {
        for (const path of output.originalFileNames ?? []) {
          const absolute = isAbsolute(path) ? path : resolve(root, path);
          if (existsSync(absolute)) source(absolute);
        }
      }
    }
    generated.push({config, virtualModules: virtual.size, qualification: 'bundler-generated-module-count'});
  }
  return {qualification: 'configured-vite-input-coverage-only',
    modules: [...modules.values()].sort((a, b) => a.module.localeCompare(b.module)),
    assets: [...assets.values()].sort((a, b) => a.module.localeCompare(b.module)),
    externalModuleCount: external.size, generated};
}
