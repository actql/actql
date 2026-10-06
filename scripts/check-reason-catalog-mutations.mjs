// Two targeted SDK faults reuse the existing strict named-assertion verifier.
// Generated output and source are always restored; infrastructure is not detection.
import {readFileSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
const file = 'adapters/host-node/client-check.test.mjs';
const targets = id => ['local', 'http'].map(entrance => ({
  name: `${entrance}: generated catalog advice keeps authoritative outcomes and original locations`,
  assertions: [{id, operator: 'strictEqual'}]}));
const mutations = [
  {name: 'presentation prose changes an undetermined verdict', path: 'packages/sdk/index.mjs',
    from: 'const observation = explainCheckOutcome(snapshot, {locale: presentation.locale});',
    to: 'const baseObservation = explainCheckOutcome(snapshot, {locale: presentation.locale});\n' +
      '  const blameFromProse = snapshot.report?.coverage.limits.some(reason => selectCheckReasonPresentation(reason)?.english[0].includes("cannot"));\n' +
      '  const observation = blameFromProse && baseObservation.report ? {...baseObservation, report: {...baseObservation.report, verdict: "invalid"}} : baseObservation;',
    targets: targets('catalog-render-verdict')},
  {name: 'catalog reports a different public facts identity', path: 'packages/sdk/check-reason-catalog.generated.js',
    from: '"reasonSchemaCid": "sha256:d9639a46b9b524e0655a11a04fde8043241487b1375286f7383bee700c654e9c"',
    to: '"reasonSchemaCid": "sha256:' + '0'.repeat(64) + '"', targets: targets('catalog-schema-pin')},
];
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${item.targets.map(target => escape(target.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, file);
};
const results = [];
for (const item of mutations) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== 2) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try { writeFileSync(item.path, original.replace(item.from, item.to)); rejected = !run(item); }
  finally { writeFileSync(item.path, original); }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
