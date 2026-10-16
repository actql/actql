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
  const modules = new Map(), assets = new Map(), generated = [], external = new Map();
  const compiled = new Map(), copied = new Map(), consumed = new Set();
  // Vite remains the module resolver. These are installed roots from the
  // selected ordinary lock, not a second import resolver or a name-based
  // exemption for arbitrary checkout-external source. Workspace links remain
  // authored inputs. Archive integrity is still the normal release audit's job.
  const lockPath = resolve(root, 'package-lock.json');
  const lockBytes = existsSync(lockPath) ? readFileSync(lockPath) : undefined;
  const lock = lockBytes ? JSON.parse(lockBytes) : {packages: {}};
  const installed = Object.entries(lock.packages ?? {}).flatMap(([installation, pin]) => {
    const match = /(?:^|\/)node_modules\/((?:@[^/]+\/)?[^/]+)$/u.exec(installation);
    const path = resolve(root, installation);
    if (!match || pin.link || !pin.version || !pin.integrity || !pin.resolved || !existsSync(path)) return [];
    return [{installation, directory: realpathSync(path), name: pin.name ?? match[1], pin}];
  }).sort((a, b) => b.directory.length - a.directory.length);
  const contains = (parent, path) => {
    const name = relative(parent, path);
    return !isAbsolute(name) && name !== '..' && !name.startsWith('../');
  };
  const inside = path => {
    const name = relative(root, path);
    return !isAbsolute(name) && name !== '..' && !name.startsWith('../');
  };
  function source(path) {
    const original = realpathSync(path);
    if (copied.has(original)) {
      const sourcePath = copied.get(original);
      assert(readFileSync(original).equals(readFileSync(sourcePath)),
        `Mixed configured Vite source asset: ${relative(root, original)}`);
      source(sourcePath);
      return;
    }
    if (compiled.has(original)) {
      assert.equal(createHash('sha256').update(readFileSync(original)).digest('hex'), compiled.get(original).sha256,
        `Mixed configured Vite dependency: ${relative(root, original)}`);
      consumed.add(original);
      return;
    }
    const dependency = installed.find(value => contains(value.directory, original));
    if (dependency) {
      const manifest = JSON.parse(readFileSync(resolve(dependency.directory, 'package.json'), 'utf8'));
      assert.equal(manifest.name, dependency.name, `Mixed installed Vite dependency: ${dependency.installation}`);
      assert.equal(manifest.version, dependency.pin.version, `Mixed installed Vite dependency: ${dependency.installation}`);
      external.set(original, {installation: dependency.installation, name: manifest.name, version: manifest.version,
        resolved: dependency.pin.resolved, integrity: dependency.pin.integrity,
        member: relative(dependency.directory, original),
        sha256: createHash('sha256').update(readFileSync(original)).digest('hex')});
      return;
    }
    const module = relative(root, original);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest)\./u.test(module),
      `Test authority in Vite interface: ${module}`);
    assert(inside(original) && !module.split('/').includes('node_modules'),
      `Unregistered Vite source outside authored checkout or pinned installation: ${module}`);
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
    let outputDirectory;
    const result = await build({configFile: configPath, configLoader: 'native', logLevel: 'silent',
      build: {write: false, emptyOutDir: false, reportCompressedSize: false},
      plugins: [{name: 'actql-resolved-interface-inputs', configResolved(config) {
        outputDirectory = resolve(config.root, config.build.outDir);
      }, generateBundle() {
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
        compiled.set(resolve(outputDirectory, output.fileName), {config, file: output.fileName,
          sha256: createHash('sha256').update(output.code).digest('hex')});
        generated.push({config, file: output.fileName,
          sha256: compiled.get(resolve(outputDirectory, output.fileName)).sha256,
          sourceModules: Object.keys(output.modules).filter(id => !id.includes('\0') && inside(id))
            .map(id => relative(root, id)).sort(),
          qualification: 'read-only-vite-output; not-installed-artifact'});
      } else {
        const sha256 = createHash('sha256').update(output.source).digest('hex');
        compiled.set(resolve(outputDirectory, output.fileName), {config, file: output.fileName, sha256});
        generated.push({config, file: output.fileName, sha256,
          qualification: 'configured-vite-asset; not-installed-artifact'});
        for (const path of output.originalFileNames ?? []) {
          const absolute = isAbsolute(path) ? path : resolve(root, path);
          if (existsSync(absolute)) {
            source(absolute);
            if (/\.[cm]?js$/u.test(absolute)) {
              assert(Buffer.from(output.source).equals(readFileSync(absolute)),
                `Changed copied Vite source asset: ${relative(root, absolute)}`);
              copied.set(resolve(outputDirectory, output.fileName), absolute);
            }
          }
        }
      }
    }
    generated.push({config, virtualModules: virtual.size, qualification: 'bundler-generated-module-count'});
  }
  return {qualification: 'configured-vite-input-coverage-only',
    modules: [...modules.values()].sort((a, b) => a.module.localeCompare(b.module)),
    assets: [...assets.values()].sort((a, b) => a.module.localeCompare(b.module)),
    externalModuleCount: external.size,
    externalModules: [...external.values()].sort((a, b) =>
      `${a.installation}/${a.member}`.localeCompare(`${b.installation}/${b.member}`)),
    dependencyLockSha256: lockBytes && createHash('sha256').update(lockBytes).digest('hex'), generated,
    sourceArtifacts: [...compiled].sort(([a], [b]) => a.localeCompare(b)).map(([path, value]) => ({
      module: relative(root, path), sha256: value.sha256, build: value.config, sourcePackages: [],
      qualification: 'configured-vite-output; requires-normal-artifact-admission'})),
    consumedCompiled: [...consumed].sort().map(path => ({module: relative(root, path), ...compiled.get(path),
      qualification: 'configured-output-digest-only; not-normal-release-admission'})),
    sourceCopies: [...copied].map(([output, source]) => ({output: relative(root, output), source: relative(root, source)}))};
}
