// Reuse the existing strict named-assertion verifier and bounded test wrappers.
// Import failures, exceptions, timeouts and unselected cases are infrastructure
// failures, never evidence that an intended authoring assertion detected a fault.
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const file = 'adapters/host-node/client-check-text-boundary.test.mjs';
const cases = (name, assertions) => ['local', 'http'].map(entrance =>
  ({name: `${entrance}: ${name}`, assertions}));
const mutations = [
  {name: 'Program location replaces its original node', path: 'packages/sdk/index.mjs',
    from: 'return Object.freeze({...location, input: original});',
    to: "return Object.freeze({...location, pointer: '', input: original});",
    targets: cases('scoped Program locations distinguish missing nodes, null and original Unicode keys',
      [{id: 'scoped-program-parent', operator: 'strictEqual'}])},
  {name: 'report omissions retain template verification', path: 'src/connectors_builtin_node/client_check.mbt',
    from: 'let reported_verdict = if template_report_limited {\n    "undetermined"\n  } else {\n    verdict\n  }',
    to: 'let reported_verdict = verdict',
    targets: cases('scoped reporting truncation cannot publish template verification',
      [{id: 'scoped-report-truncation', operator: 'strictEqual'}])},
  {name: 'denied Source aliases become visible', path: 'adapters/host-node/client-check.mjs',
    from: "if (decision?.action !== 'dispatch') return [];",
    to: "if (decision?.action !== 'dispatch') return aliases;",
    targets: cases('scoped protected Sources preserve equivalent public reasons, pointers and Requirements',
      [{id: 'scoped-source-verdict', operator: 'strictEqual'},
        {id: 'scoped-source-disclosure', operator: 'deepStrictEqual'}])},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-scoped-authoring-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No scoped authoring mutations selected');
const build = () => execFileSync(process.execPath, ['scripts/local-checks.mjs',
  'build', 'moon', '--timeout-seconds', '120', '--', '--target', 'js', '--release',
  'src/connectors_builtin_node'], {stdio: 'inherit', timeout: 130000});
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs',
    'test', 'node', '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${item.targets.map(value => escape(value.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, file);
};
const results = [];
for (const item of selected) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== 2) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replace(item.from, item.to));
    if (item.path.endsWith('.mbt')) build();
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
    if (item.path.endsWith('.mbt')) build();
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
