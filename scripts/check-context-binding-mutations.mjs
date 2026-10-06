// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'adapters/host-node/client-check.mjs';
const acceptance = 'adapters/host-node/client-check.test.mjs';
const targets = [
  ...['local', 'http'].map(entrance => ({
    name: `${entrance}: context references bind both schemas through ordinary and fallback input`,
    assertions: [{id: 'context-schema-public', operator: 'strictEqual'}],
  })),
];
const mutations = [
  {name: 'outcome schema omitted', path, file: acceptance, targets,
    from: '      outcome_schema_cid: checkOutcomeSchemaCid,', to: ''},
  {name: 'fallback outcome schema omitted', path, file: acceptance, targets,
    from: '      preimage = canonicalJson({...bound,\n        received:',
    to: '      const {outcome_schema_cid, ...fallbackBound} = bound;\n' +
      '      preimage = canonicalJson({...fallbackBound,\n        received:'},
  {name: 'exact context strings normalized', path, file: acceptance, targets,
    from: '.update(preimage).digest(\'hex\')',
    to: '.update(preimage.normalize(\'NFC\')).digest(\'hex\')'},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-context-binding-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No context binding mutations selected');
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath,
    ['scripts/local-checks.mjs', 'test', 'node', '--timeout-seconds', '120', '--',
      '--test-name-pattern', `^(?:${item.targets.map(value => escape(value.name)).join('|')})$`, item.file],
    {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, item.file);
};
const results = [];
for (const item of selected) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== 2) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replace(item.from, item.to));
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
