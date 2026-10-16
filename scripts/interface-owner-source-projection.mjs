// Read immutable Git objects with the same syntax reader used by I6. Product
// modules are never imported, and no active owner's checkout is changed.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {javascriptInterface} from './interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {moonApiInterface} from './moon-interface-inventory.mjs';

export function projectOwnerSources(root, {source, base, paths: selection = ['adapters', 'packages'], all = false}) {
  for (const revision of [source, base]) assert.match(revision, /^[0-9a-f]{40}$/u);
  const git = args => execFileSync('git', args, {cwd: root, maxBuffer: 16 * 1024 * 1024});
  const command = all ? ['ls-tree', '-r', '--name-only', '-z', source, '--', ...selection]
    : ['diff', '--name-only', '-z', '--diff-filter=ACMR', base, source, '--', ...selection];
  const paths = git(command).toString('utf8').split('\0').filter(path =>
    /\.(?:[cm]?js|mbti)$/u.test(path) && !isConnectorTestFixture(path) &&
    !/(?:\.test|_test|_wbtest)\./u.test(path));
  assert(paths.length, 'No owner JavaScript product sources');
  const modules = paths.sort().map(module => {
    const bytes = git(['show', `${source}:${module}`]);
    return {module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...(module.endsWith('.mbti') ? moonApiInterface(bytes.toString('utf8'))
        : javascriptInterface(bytes.toString('utf8')))};
  });
  return {qualification: 'owner-selected-source-syntax-only', source, base, modules};
}
