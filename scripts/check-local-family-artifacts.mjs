import { createHash } from 'node:crypto';
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const moduleName = 'actql/actql';
const sourceRoot = path.join(root, 'src');

function packageName(directory) {
  const relative = path.relative(sourceRoot, directory).split(path.sep).join('/');
  return `${moduleName}/${relative}`;
}

function packageDirectories(directory, result = new Map()) {
  const manifest = path.join(directory, 'moon.pkg');
  if (existsSync(manifest)) result.set(packageName(directory), directory);
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) packageDirectories(path.join(directory, entry.name), result);
  }
  return result;
}

const packages = packageDirectories(sourceRoot);

function importsOf(name) {
  const directory = packages.get(name);
  if (directory === undefined) throw new Error(`unknown package: ${name}`);
  const manifest = readFileSync(path.join(directory, 'moon.pkg'), 'utf8');
  return [...manifest.matchAll(/^\s*"([^"]+)"(?:\s+@[A-Za-z0-9_]+)?[,]?$/gmu)]
    .map(match => match[1])
    .filter(imported => imported.startsWith(`${moduleName}/`));
}

function importClosure(entry) {
  const reached = new Set();
  const pending = [entry];
  while (pending.length > 0) {
    const current = pending.pop();
    if (reached.has(current)) continue;
    reached.add(current);
    for (const imported of importsOf(current)) pending.push(imported);
  }
  return reached;
}

const familyPackages = {
  sga: new Set([
    `${moduleName}/local_sga`,
    `${moduleName}/local_sga_provider`,
  ]),
  tea: new Set([
    `${moduleName}/local_tea`,
    `${moduleName}/local_tea_provider`,
  ]),
  veca: new Set([
    `${moduleName}/local_veca`,
    `${moduleName}/local_veca_provider`,
  ]),
};

const configurations = [{
  name: 'rela',
  entry: `${moduleName}/connectors_builtin_node`,
  forbidden: ['sga', 'tea', 'veca'],
}, {
  name: 'sga',
  entry: `${moduleName}/local_sga_provider`,
  forbidden: ['tea', 'veca'],
}, {
  name: 'tea',
  entry: `${moduleName}/local_tea_provider`,
  forbidden: ['sga', 'veca'],
}, {
  name: 'veca',
  entry: `${moduleName}/local_veca_provider`,
  forbidden: ['sga', 'tea'],
}];

for (const configuration of configurations) {
  const closure = importClosure(configuration.entry);
  for (const family of configuration.forbidden) {
    for (const forbidden of familyPackages[family]) {
      if (closure.has(forbidden)) {
        throw new Error(
          `${configuration.name} imports unselected package ${forbidden}`,
        );
      }
    }
  }
  configuration.closure = closure;
}

if (!process.env.MOON_HOME) {
  throw new Error('Set MOON_HOME to the pinned MoonBit toolchain directory');
}
const moon = path.join(process.env.MOON_HOME, 'bin', 'moon');
const build = spawnSync(moon, [
  'build',
  '--target',
  'js',
  '--release',
  '--deny-warn',
  'src/connectors_builtin_node',
  'src/local_sga_provider',
  'src/local_tea_provider',
  'src/local_veca_provider',
], {
  cwd: root,
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024,
});
if (build.status !== 0) {
  if (build.stdout) process.stderr.write(build.stdout);
  if (build.stderr) process.stderr.write(build.stderr);
  if (build.error) process.stderr.write(`${build.error.message}\n`);
  throw new Error(`family artifact build failed with status ${build.status}`);
}

function artifactFor(name) {
  return path.join(
    root,
    '_build/js/release/build',
    name,
    `${name}.core`,
  );
}

const artifacts = new Map([
  ['rela', path.join(
    root,
    '_build/js/release/build/connectors_builtin_node/',
    'connectors_builtin_node.js',
  )],
  ['sga', artifactFor('local_sga_provider')],
  ['tea', artifactFor('local_tea_provider')],
  ['veca', artifactFor('local_veca_provider')],
]);

function digest(file) {
  if (!existsSync(file) || statSync(file).size === 0) {
    throw new Error(`missing generated artifact: ${file}`);
  }
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

const relaResponse = path.join(
  root,
  '_build/js/release/build/connectors_builtin_node/',
  'connectors_builtin_node.js.rsp',
);
const linkedCores = new Set(
  readFileSync(relaResponse, 'utf8')
    .split(/\r?\n/u)
    .filter(line => line.endsWith('.core'))
    .map(line => path.basename(line, '.core')),
);
for (const family of ['sga', 'tea', 'veca']) {
  for (const forbidden of familyPackages[family]) {
    const shortName = forbidden.slice(moduleName.length + 1).replaceAll('/', '_');
    if (linkedCores.has(shortName)) {
      throw new Error(`RelA artifact links unselected package ${forbidden}`);
    }
  }
}
for (const required of ['driver', 'managed_carrier_runtime']) {
  if (!linkedCores.has(required)) {
    throw new Error(`RelA artifact is missing required runtime core ${required}`);
  }
}

const report = configurations.map(configuration => {
  const artifact = artifacts.get(configuration.name);
  return {
    name: configuration.name,
    imports: configuration.closure.size,
    artifact: path.relative(root, artifact),
    bytes: statSync(artifact).size,
    sha256: digest(artifact),
  };
});
process.stdout.write(`${JSON.stringify(report)}\n`);
