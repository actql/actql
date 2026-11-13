// The compiler owns import edges. CI separates portable packages from Native
// FFI owners and every source/test importer of those owners, without a second
// hand-maintained package catalogue.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {normalizeMoonGraph} from './ci-moon-test-plan.mjs';
import {tokens} from './portable-core.mjs';

export function partitionNativeCorePlatformPackages(graph, readManifest) {
  const direct = new Set();
  for (const pkg of graph.packages) {
    const metadata = tokens(readManifest(pkg.path));
    // Retain all existing Native command/platform packages, explicit C stubs
    // and linker overrides on Darwin, including their complete test importers.
    if (/^src\/(?:platform_native|cmd)(?:\/|$)/u.test(pkg.path) ||
        metadata.some(token => token.value === 'native-stub' || token.value === 'link')) {
      direct.add(pkg.name);
    }
  }
  const differences = new Set(direct);
  let changed = true;
  while (changed) {
    changed = false;
    for (const edge of graph.edges) if (differences.has(edge.to) && !differences.has(edge.from)) {
      differences.add(edge.from); changed = true;
    }
  }
  const common = graph.packages.filter(pkg => !differences.has(pkg.name)).map(pkg => pkg.path);
  const importers = graph.packages.filter(pkg => differences.has(pkg.name) && !direct.has(pkg.name)).map(pkg => pkg.path);
  const darwin = graph.packages.filter(pkg => direct.has(pkg.name)).map(pkg => pkg.path);
  assert.equal(common.length + importers.length + darwin.length, graph.packages.length);
  assert.equal(new Set([...common, ...importers, ...darwin]).size, graph.packages.length);
  assert(common.length > 0 && darwin.length > 0, 'Both Native platform scopes must be explicit and nonempty');
  return {common, importers, darwin, graphSha256: graph.digest};
}

export function readNativeCorePlatformPackages(repository, {env = process.env,
  execute = execFileSync} = {}) {
  repository = realpathSync(repository);
  const git = args => execute('git', args, {cwd: repository, env, encoding: 'utf8',
    timeout: 15000, maxBuffer: 32 * 1024 ** 2});
  const head = git(['rev-parse', 'HEAD']).trim();
  assert(/^[a-f0-9]{40}$/u.test(head));
  const clean = () => {
    assert.equal(git(['diff', 'HEAD', '--', 'src', 'vendor', 'moon.mod']), '', 'Dirty compiler inputs');
    assert.equal(git(['ls-files', '--others', '--exclude-standard', '--', 'src', 'vendor']), '', 'Untracked compiler inputs');
  };
  clean();
  const raw = git(['ls-tree', '-rz', 'HEAD', '--', 'src']);
  assert(raw.endsWith('\0'), 'Missing complete original compiler input inventory');
  const tree = raw.slice(0, -1).split('\0').map(line => {
    const match = /^(\d{6}) blob ([a-f0-9]{40})\t(.+)$/u.exec(line);
    assert(match, 'Unsupported compiler input entry');
    return {mode: match[1], object: match[2], path: match[3]};
  });
  const compiler = JSON.parse(execute('moon', ['tree', '--package', '--json'], {
    cwd: repository, env, encoding: 'utf8', timeout: 60000, maxBuffer: 16 * 1024 ** 2,
  }));
  const graph = normalizeMoonGraph(compiler, tree, repository);
  const result = partitionNativeCorePlatformPackages(graph,
    path => readFileSync(join(repository, path, 'moon.pkg'), 'utf8'));
  assert.equal(git(['rev-parse', 'HEAD']).trim(), head, 'Source changed during platform discovery');
  clean();
  return result;
}
