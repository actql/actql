// Read immutable Git objects with the same syntax reader used by I6. Product
// modules are never imported, and no active owner's checkout is changed.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {javascriptInterface} from './interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {moonApiInterface, moonOperations} from './moon-interface-inventory.mjs';
import {pythonSourceBlobInterfaces} from './python-interface-sources.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';

function ownerSourcePath(path, commands) {
  return (/\.(?:[cm]?[jt]sx?|mbti?|pyi?)$/u.test(path) || commands.includes(path)) &&
    !isConnectorTestFixture(path) && !/(?:\.test|_test|_wbtest)\./u.test(path);
}

export function projectOwnerSources(root, {source, base, paths: selection = ['adapters', 'packages'],
  all = false, commands = [], allowEmpty = false}) {
  for (const revision of [source, base]) assert.match(revision, /^[0-9a-f]{40}$/u);
  const git = args => execFileSync('git', args, {cwd: root, maxBuffer: 16 * 1024 * 1024});
  const command = all ? ['ls-tree', '-r', '--name-only', '-z', source, '--', ...selection]
    : ['diff', '--name-only', '-z', '--diff-filter=ACMR', base, source, '--', ...selection];
  const paths = git(command).toString('utf8').split('\0').filter(path => path && ownerSourcePath(path, commands));
  assert(paths.length || allowEmpty, 'No owner product sources');
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

function syntaxDifference(before, after) {
  const differences = {};
  for (const field of ['exports', 'operations']) {
    const name = value => typeof value === 'string' ? value : value.name;
    const previous = new Map((before?.[field] ?? []).map(value => [name(value), value]));
    const current = new Map((after?.[field] ?? []).map(value => [name(value), value]));
    differences[field] = {
      added: [...current.keys()].filter(key => !previous.has(key)),
      removed: [...previous.keys()].filter(key => !current.has(key)),
      changed: [...current.keys()].filter(key => previous.has(key) &&
        !isDeepStrictEqual(previous.get(key), current.get(key))),
    };
  }
  return differences;
}

// Draft candidates only: never assign an operation to a contract group, choose
// a responsibility facet, approve a reference, or issue generation evidence.
export function projectOwnerSourceUpdates(root, options, declarations) {
  const previous = new Map();
  for (const declaration of declarations) {
    assert(!previous.has(declaration.module), `Duplicate owner update declaration: ${declaration.module}`);
    previous.set(declaration.module, declaration);
  }
  const projection = projectOwnerSources(root, {...options, allowEmpty: true});
  const {source, base, paths = ['adapters', 'packages'], commands = []} = options;
  const removed = execFileSync('git', ['diff', '--no-renames', '--name-only', '-z',
    '--diff-filter=D', base, source, '--', ...paths], {cwd: root, maxBuffer: 16 * 1024 * 1024})
    .toString('utf8').split('\0').filter(path => path && ownerSourcePath(path, commands));
  const updates = projection.modules.flatMap(actual => {
    const old = previous.get(actual.module);
    const fields = ['sha256', 'exports', 'operations', 'imports', 'compilerFields', 'unresolvedSyntax'];
    const mechanicalFields = fields.filter(key => key in actual && !isDeepStrictEqual(old?.[key], actual[key]));
    if (old && !mechanicalFields.length) return [];
    const candidate = structuredClone(old ?? {module: actual.module});
    for (const key of fields) if (key in actual) candidate[key] = structuredClone(actual[key]);
    return [{module: actual.module, status: old ? 'changed' : 'unregistered',
      mechanicalFields, difference: syntaxDifference(old, actual), candidate,
      reviewRequired: ['responsibility classification', 'all ten semantic references',
        'operation/export contract membership', 'independent boundary evidence']}];
  });
  for (const module of removed) updates.push({module, status: 'removed',
    difference: syntaxDifference(previous.get(module), undefined), candidate: null,
    reviewRequired: ['original responsibility relocation or retirement', 'remaining references and consumers']});
  return {qualification: 'mechanical-owner-update-candidates-only; not-review-generation-or-admission',
    source, base, updates: updates.sort((a, b) => a.module.localeCompare(b.module))};
}
