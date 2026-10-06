// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const sdk = 'packages/sdk/index.mjs', sdkTests = 'packages/sdk/check-fixes.test.mjs';
const wire = 'packages/client-wire/index.mjs', wireTests = 'packages/client-wire/check-fixes.test.mjs';
const host = 'src/connectors_builtin_node/client_check.mbt', hostTests = 'adapters/host-node/client-check.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const mutations = [
  {name: 'fix review bypass', path: sdk, file: sdkTests,
    from: "      if (reviewed !== true) fail('CheckFixReviewRequired');", to: '',
    targets: [target('fix application rejects copied stale unreviewed and conflicting edits without I/O', 'fix-review')]},
  {name: 'fix revision bypass', path: sdk, file: sdkTests,
    from: "        if (currentRecord(observation) !== record) fail('CheckFixStale');", to: '',
    targets: [2, 3, 4].map(phase => target(`fix application cannot overwrite a concurrent edit during check ${phase}`, 'fix-stale'))},
  {name: 'fix final context bypass', path: sdk, file: sdkTests,
    from: 'assertCurrent(); assertContext(after);', to: 'assertCurrent();',
    targets: [target('fix application rejects observed permission context changes at check 4', 'fix-context')]},
  {name: 'fix conflicting insertion bypass', path: sdk, file: sdkTests,
    from: 'previous.start_byte === edit.start_byte', to: 'false',
    targets: [target('fix application rejects copied stale unreviewed and conflicting edits without I/O', 'fix-conflict')]},
  {name: 'fix current buffer not committed', path: sdk, file: sdkTests,
    from: '      current = {text, version};\n      const ticket = ++issued;',
    to: '      current = {text: record.input.text, version};\n      const ticket = ++issued;',
    targets: [target('fix application preserves exact input and rechecks before one atomic commit', 'fix-committed-buffer')]},
  {name: 'fix EOF boundary bypass', path: wire, file: wireTests,
    from: '      if (fix.edits.some(edit => edit.start_byte !== input.byte_length ||\n          edit.end_byte !== input.byte_length)) return false;', to: '',
    targets: [target('comment fix wire admits only known exact revision-bound EOF insertions', 'fix-wire')]},
  {name: 'fix public producer omitted', path: host, file: hostTests,
    from: '              write_check_comment_fix(writer, documents)', to: '              ()',
    targets: ['local', 'http'].map(entrance => target(`${entrance}: lexical fixes retain original EOF edits and require review`, 'lexical-fix-original', 'deepStrictEqual'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-lexical-fix-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No lexical fix mutations selected');
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  return mutationAcceptance(spawnSync(process.execPath,
    ['scripts/local-checks.mjs', 'test', 'node', '--timeout-seconds', '120', '--',
      '--test-name-pattern', `^(?:${item.targets.map(value => escape(value.name)).join('|')})$`, item.file],
    {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024}), item.targets, item.file);
};
const rebuild = () => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'build', 'moon',
    '--timeout-seconds', '120', '--', '--target', 'js', '--release', 'src/connectors_builtin_node'],
    {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`Mutation runtime preparation failed: ${result.stdout}\n${result.stderr}`);
  }
};
const results = [];
for (const item of selected) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== 2) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replace(item.from, item.to));
    if (item.path === host) rebuild();
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
    if (item.path === host) rebuild();
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
