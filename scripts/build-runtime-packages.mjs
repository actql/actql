// Build from this checkout, never from committed runtime output. Package users
// receive these files in the tarball and do not need MoonBit or install hooks.
import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync} from 'node:fs';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {occurrences, violations} from './check-owned-contract-versions.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const packages = {
  'run-host-core': {sources: ['client_values_host_abi'],
    script: 'build-run-host-core-package', args: ['--runtime-only'],
    files: ['packages/run-host-core/dist/client_values_host_abi.js']},
  'coordinator-core': {sources: ['remote_coordinator_abi'],
    script: 'build-remote-coordinator-package',
    files: ['packages/coordinator-core/dist/remote_coordinator_abi.js']},
  'transfer-core': {sources: ['remote_transfer_abi'],
    script: 'build-remote-transfer-package',
    files: ['packages/transfer-core/dist/remote_transfer_abi.js']},
  get 'local-node'() {
    const local = localNodePackageInputs(root);
    return {sources: local.runtimePackages, script: 'build-local-node-assets',
      files: local.runtimeFiles.map(path => `packages/local-node/_build/js/release/build/${path}`)};
  },
};
// A resolved external Host compiles only the inventory's exact package
// targets. Its workspace is supplied by the trusted build harness; this
// function never resolves modules from a registry or rewrites Core inputs.
export async function buildExternalLocalNodeRuntime({inputs, destination, compiledDirectory}) {
  const {buildLocalNodeAssets} = await import('./build-local-node-assets.mjs');
  const resolved = inputs.buildInputs;
  if (resolved === undefined || existsSync(compiledDirectory)) {
    throw new Error('ExternalLocalNodeBuildNeedsFreshOutput');
  }
  resolved.outputPath(relative(resolved.host.root, join(compiledDirectory, 'sentinel')));
  const byModule = new Map();
  for (const entry of inputs.runtimeInputs) {
    const targets = byModule.get(entry.moduleRoot) ?? [];
    targets.push(entry.target);
    byModule.set(entry.moduleRoot, targets);
  }
  for (const [moduleRoot, targets] of byModule) {
    execFileSync('moon', ['build', '--frozen', '--target', 'js', '--release',
      '--target-dir', compiledDirectory, ...targets], {cwd: moduleRoot, stdio: 'inherit'});
  }
  buildLocalNodeAssets({root: resolved.host.root, inputs, destination, compiledDirectory});
  buildLocalNodeAssets({root: resolved.host.root, inputs, destination, compiledDirectory, check: true});
  const inventory = JSON.parse(readFileSync(join(inputs.coreRoot,
    'scripts/owned-contract-version-legacy.json'), 'utf8'));
  const rejected = violations(inputs.runtimeFiles.flatMap(path => {
    const file = join(destination, '_build/js/release/build', path);
    return occurrences(readFileSync(file, 'utf8'), file);
  }), inventory);
  if (rejected.length) throw new Error('Generated external runtime contract versions must remain at 0.1');
}

function main(requested) {
for (const name of requested) {
  if (!Object.hasOwn(packages, name)) throw new Error(`Unknown runtime package: ${name}`);
}
const selected = new Set(requested.length ? requested : Object.keys(packages));
const entries = [...selected].map(name => packages[name]);
execFileSync('moon', ['build', '--target', 'js', '--release',
  ...new Set(entries.flatMap(item => item.sources.map(path => `src/${path}`)))],
{cwd: root, stdio: 'inherit'});
for (const item of entries) {
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, ...(item.args ?? [])],
    {cwd: root, stdio: 'inherit'});
  // Tracked wrapper copies still have to match their source; preparation must
  // not repair them silently and hide a source/wrapper mismatch from CI.
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, '--check'],
    {cwd: root, stdio: 'inherit'});
}
const inventory = JSON.parse(readFileSync(join(root,
  'scripts/owned-contract-version-legacy.json'), 'utf8'));
const rejected = violations(entries.flatMap(item => item.files.flatMap(path =>
  occurrences(readFileSync(join(root, path), 'utf8'), path))), inventory);
if (rejected.length) throw new Error('Generated runtime contract versions must remain at 0.1:\n' +
  rejected.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2));
}
