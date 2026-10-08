// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const unit = 'packages/sdk/check-protocol-failures.test.mjs';
const publicTests = 'adapters/host-node/client-check.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const publicTargets = ['local', 'http'].map(entrance => target(
  `${entrance}: check protocol failures retain original input without verdict or retry authority`,
  'protocol-failure-public-rejection'));
const mutations = [
  {name: 'a durable submission identity silently rebinds a changed Program',
    path: 'adapters/host-node/client-request-journal.mjs',
    file: 'adapters/host-node/client-submission-intent-immutability.test.mjs',
    from: '        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);\n' +
      "        if (requestId === undefined) fail('InvalidClientSubmittedIntent');\n" +
      '        const existing = intentSelect.get(requestId);',
    to: '        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);\n' +
      "        if (requestId === undefined) fail('InvalidClientSubmittedIntent');\n" +
      '        let existing = intentSelect.get(requestId);\n' +
      '        if (existing !== undefined && existing.intent_cid !== original.identity) {\n' +
      "          const ready = existing.phase === 'ready';\n" +
      '          const outcome = ready ? {...JSON.parse(existing.outcome_wire), intentCid: original.identity} : null;\n' +
      "          database.prepare('UPDATE client_submitted_intents SET intent_cid = ?, intent_wire = ?, phase = ?, outcome_wire = ? WHERE submission_id = ?')\n" +
      "            .run(original.identity, original.wire, ready ? 'ready' : 'preparing',\n" +
      '              outcome === null ? null : canonicalValueJson(outcome, {dataKeys: true}), requestId);\n' +
      '          existing = intentSelect.get(requestId);\n' +
      '        }',
    additionalEdits: [{path: 'adapters/host-node/client-submission.mjs',
      from: "      if (result.kind === 'ready') return await replayReady(value, retained, fields, result);",
      to: "      if (result.kind === 'ready') return result;"}],
    targets: ['local', 'https'].flatMap(entrance => ['ready', 'not_accepted'].map(phase => target(
      `${entrance}: changed Program cannot rebind a ${phase} submission identity`,
      'submission-intent-immutable', 'deepStrictEqual')))},
  {name: 'unknown outcome classified as a known failure', path, file: unit,
    from: "kind: problem === 'unknown_outcome' ? 'uninterpretable' : 'protocol_failure',",
    to: "kind: 'protocol_failure',",
    targets: [target('check protocol failures distinguish unknown outcomes from malformed known facts and pins', 'protocol-failure-kind', 'deepStrictEqual')]},
  {name: 'submitted parameter snapshot lost', path, file: unit,
    from: "...(Object.hasOwn(body, 'parameters') ? {parameters: body.parameters} : {})",
    to: "...(Object.hasOwn(body, 'parameters') ? {parameters: null} : {})",
    targets: [target('check protocol failures retain each original submitted snapshot only under its real error', 'protocol-failure-input', 'deepStrictEqual')]},
  {name: 'submitted input serialized in the error', path, file: unit,
    from: "const error = new ClientError('InvalidHostCheckOutcome');",
    to: "const error = new ClientError('InvalidHostCheckOutcome', {input: body});",
    targets: [target('check protocol failures retain each original submitted snapshot only under its real error', 'protocol-failure-disclosure')]},
  {name: 'caller presentation edits change the observation', path, file: unit,
    from: 'kind: failure.kind, problem: failure.problem, summary, hint',
    to: 'kind: error.kind ?? failure.kind, problem: failure.problem, summary, hint',
    targets: [target('check protocol failure presentation is immutable across hostile display options and error edits', 'protocol-failure-presentation', 'deepStrictEqual')]},
  {name: 'unknown outcome admission bypass', path, file: publicTests, occurrences: 2,
    from: 'if (!validCheckOutcome(outcome)) reject();', to: '', targets: publicTargets},
  {name: 'malformed known completed outcome admission bypass', path, file: publicTests, occurrences: 2,
    from: 'if (!validCheckOutcome(outcome)) reject();',
    to: "if (outcome.outcome !== 'completed' && !validCheckOutcome(outcome)) reject();", targets: publicTargets},
  {name: 'legacy diagnostics payload changes under the retained schema identity',
    path: 'spec/contracts/actql-protocol-schemas.json', file: 'scripts/diagnostic-migration-contract.test.mjs',
    from: '"ok": {\n                  "const": false\n                }',
    to: '"ok": {\n                  "const": true\n                }',
    targets: [target('legacy diagnostic payload retains the frozen schema and identity',
      'legacy-diagnostic-body', 'deepStrictEqual')]},
  {name: 'public check accepts legacy diagnostics relabeling', path, file: publicTests, occurrences: 2,
    from: 'if (!validCheckOutcome(outcome)) reject();', to: '',
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: check migration rejects legacy diagnostics and planning labels`,
      'legacy-diagnostic-public-rejection'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-protocol-failure-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No check protocol failure mutations selected');
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
  const edits = [item, ...(item.additionalEdits ?? [])];
  const originals = new Map(edits.map(edit => [edit.path, readFileSync(edit.path, 'utf8')]));
  for (const edit of edits) {
    if (originals.get(edit.path).split(edit.from).length !== (edit.occurrences ?? 1) + 1) {
      throw new Error(`Mutation anchor not unique: ${item.name}`);
    }
  }
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    for (const edit of edits) writeFileSync(edit.path,
      originals.get(edit.path).replaceAll(edit.from, edit.to));
    rejected = !run(item);
  } finally {
    for (const [path, original] of originals) writeFileSync(path, original);
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
