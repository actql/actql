// Source-side entrance discovery. Installed artifact coverage is a separate
// result: a source entrance is not evidence that a generated binary exists.
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {basename, dirname, relative, resolve} from 'node:path';
import {packageEntrances} from './interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

export function repositoryFiles(root) {
  return [...new Set(execFileSync('git', ['ls-files', '-z', '--cached', '--others',
    '--exclude-standard'], {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})
    .split('\0').filter(Boolean))].sort();
}

export function npmInterfaceRoots(root, files = repositoryFiles(root)) {
  return files.filter(path => basename(path) === 'package.json' && !isConnectorTestFixture(path))
    .flatMap(path => {
      const manifest = JSON.parse(readFileSync(resolve(root, path), 'utf8'));
      const entrances = packageEntrances(manifest, resolve(root, dirname(path)));
      if (!entrances.length) return [];
      return [{kind: manifest.bin ? 'npm-cli' : 'npm-package', name: manifest.name,
        manifest: path, entrances: entrances.map(entry => relative(root, entry)),
        dependencies: Object.keys({...manifest.dependencies, ...manifest.peerDependencies,
          ...manifest.optionalDependencies}).sort()}];
    }).sort((a, b) => a.manifest.localeCompare(b.manifest));
}
