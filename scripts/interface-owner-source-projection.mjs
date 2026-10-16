// Read immutable Git objects with the same syntax reader used by I6. Product
// modules are never imported, and no active owner's checkout is changed.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {javascriptInterface} from './interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {moonApiInterface, moonOperations} from './moon-interface-inventory.mjs';
import {pythonSourceBlobInterfaces} from './python-interface-sources.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';

export function projectOwnerSources(root, {source, base, paths: selection = ['adapters', 'packages'],
  all = false, commands = []}) {
  for (const revision of [source, base]) assert.match(revision, /^[0-9a-f]{40}$/u);
  const git = args => execFileSync('git', args, {cwd: root, maxBuffer: 16 * 1024 * 1024});
  const command = all ? ['ls-tree', '-r', '--name-only', '-z', source, '--', ...selection]
    : ['diff', '--name-only', '-z', '--diff-filter=ACMR', base, source, '--', ...selection];
  const paths = git(command).toString('utf8').split('\0').filter(path =>
    (/\.(?:[cm]?[jt]sx?|mbti?|pyi?)$/u.test(path) || commands.includes(path)) && !isConnectorTestFixture(path) &&
    !/(?:\.test|_test|_wbtest)\./u.test(path));
  assert(paths.length, 'No owner product sources');
  const python = [];
  const modules = paths.sort().flatMap(module => {
    const bytes = git(['show', `${source}:${module}`]);
    const text = bytes.toString('utf8');
    const command = commands.includes(module) && !/\.(?:[cm]?[jt]sx?|mbti?|pyi?)$/u.test(module);
    const pythonCommand = command && /^#!(?:\/usr\/bin\/env[ \t]+python3?|\/usr\/bin\/python3?)(?:[ \t\r\n]|$)/u.test(text);
    if (command) assert(pythonCommand || /^#!(?:\/usr\/bin\/env[ \t]+node|\/usr\/bin\/node)(?:[ \t\r\n]|$)/u.test(text),
      `Unregistered original executable interface: ${module}`);
    if (/\.pyi?$/u.test(module) || pythonCommand) {
      python.push({module, source: text});
      return [];
    }
    return [{module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...(module.endsWith('.mbti') ? moonApiInterface(text)
        : module.endsWith('.mbt') ? {exports: [], operations: moonOperations(text)}
          : /\.[cm]?tsx?$/u.test(module) ? typescriptInterface(text, module) : javascriptInterface(text))}];
  });
  if (python.length) modules.push(...pythonSourceBlobInterfaces(python));
  return {qualification: 'owner-selected-source-syntax-only', source, base,
    modules: modules.sort((a, b) => a.module.localeCompare(b.module))};
}
