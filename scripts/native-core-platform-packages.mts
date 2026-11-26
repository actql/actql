// The compiler owns import edges. CI separates portable packages from Native
// FFI owners and every source/test importer of those owners, without a second
// hand-maintained package catalogue.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {normalizeMoonGraph} from './ci-moon-test-plan.mjs';
import {tokens} from './portable-core.mjs';
import {nativeCorePhysicalDirectories} from './native-core-test-selection.mjs';

type PlatformGraph = {
  packages: readonly {path: string; name: string}[];
  edges: readonly {from: string; to: string}[];
  digest: string;
};
type DiscoveryOptions = {env?: NodeJS.ProcessEnv; execute?: typeof execFileSync};

// MoonBit declares a foreign function only as `extern "<abi>" fn`. An unknown
// ABI is refused rather than treated as portable.
function declaresNativeFunction(sources: readonly string[]) {
  let native = false;
  for (const source of sources) for (const [, abi] of source.matchAll(/\bextern\s+"([^"]*)"/gu)) {
    assert(['c', 'js', 'wasm'].includes(abi.toLowerCase()), 'Unknown foreign function ABI');
    if (abi.toLowerCase() === 'c') native = true;
  }
  return native;
}

export function partitionNativeCorePlatformPackages(graph: PlatformGraph, readManifest: (path: string) => string,
  readSources: (path: string) => readonly string[], physicalDirectories: readonly string[] = nativeCorePhysicalDirectories) {
  const direct = new Set<string>();
  for (const pkg of graph.packages) {
    const metadata = tokens(readManifest(pkg.path));
    // Explicit C stubs, command/platform packages that declare a C function
    // themselves, and packages with a case that needs a physical fixture
    // retain Darwin. Keep their complete source/test
    // importers as a distinct compiler-owned group for the matching Linux
    // ordinary profile. Neither a linker override nor a command/platform path
    // alone owns platform code: such a package only uses what it imports, so
    // it is classified by its imports like any other.
    if (metadata.some(token => token.value === 'native-stub') ||
        physicalDirectories.includes(pkg.path) ||
        (/^src\/(?:platform_native|cmd)(?:\/|$)/u.test(pkg.path) &&
          declaresNativeFunction(readSources(pkg.path)))) {
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

export function readNativeCorePlatformPackages(repository: string, {env = process.env,
  execute = execFileSync}: DiscoveryOptions = {}) {
  repository = realpathSync(repository);
  const git = (args: string[]) => execute('git', args, {cwd: repository, env, encoding: 'utf8',
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
  const compiler: Parameters<typeof normalizeMoonGraph>[0] = JSON.parse(execute('moon', ['tree', '--package', '--json'], {
    cwd: repository, env, encoding: 'utf8', timeout: 60000, maxBuffer: 16 * 1024 ** 2,
  }));
  const graph = normalizeMoonGraph(compiler, tree, repository);
  const result = partitionNativeCorePlatformPackages(graph,
    path => readFileSync(join(repository, path, 'moon.pkg'), 'utf8'),
    path => tree.filter(entry => entry.path.endsWith('.mbt') &&
      entry.path.slice(0, entry.path.lastIndexOf('/')) === path)
      .map(entry => readFileSync(join(repository, entry.path), 'utf8')));
  assert.equal(git(['rev-parse', 'HEAD']).trim(), head, 'Source changed during platform discovery');
  clean();
  return result;
}
