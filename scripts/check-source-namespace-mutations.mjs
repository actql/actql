// Focused private-Owner faults. Reuse strict named-assertion admission so import
// failures, unhandled exceptions, timeout and unselected tests never count.
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {readFileSync, unlinkSync, writeFileSync} from 'node:fs';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const modulePath = fileURLToPath(new URL('../adapters/host-node/source-alias-publication.mjs', import.meta.url));
const file = 'adapters/host-node/source-alias-publication.test.mjs';
const original = readFileSync(modulePath, 'utf8');
const faults = [
  {name: 'filtered publication falsely closes the namespace',
    from: 'if (JSON.stringify(rows(allAliases)) !== JSON.stringify(rows(aliases))) return undefined;',
    to: 'void aliases;',
    target: 'namespace evidence uses every original unfiltered installed registration',
    assertion: {id: 'namespace-completeness', operator: 'deepStrictEqual'}},
  {name: 'a read grant discloses negative namespace membership',
    from: "operation: 'inspect_absence',", to: "operation: 'read',",
    // Match the admitted decision too: test the policy defect, not malformed facts.
    second: ["decision.tuple?.operation !== 'inspect_absence'", "decision.tuple?.operation !== 'read'"],
    target: 'ordinary read and check grants do not disclose namespace absence',
    assertion: {id: 'namespace-disclosure', operator: 'deepStrictEqual'}},
  {name: 'a different call acquires original observation custody',
    from: 'retained !== undefined && retained.publication === publication && retained.binding === binding',
    to: 'retained !== undefined',
    target: 'observation custody rejects copies and a different input or namespace',
    assertion: {id: 'namespace-custody', operator: 'strictEqual'}},
  {name: 'namespace checking prepares an approval',
    from: 'allowDeferral: false', to: 'allowDeferral: true',
    target: 'namespace inspection cannot create a deferred approval or execute a Source',
    assertion: {id: 'namespace-no-approval', operator: 'strictEqual'}},
];
const expected = fault => [{name: fault.target, assertions: [fault.assertion]}];
const escaped = value => value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
function selected(fault, url) {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern', `^${escaped(fault.target)}$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024,
    env: {...process.env, ACTQL_TEST_NAMESPACE_PUBLICATION_MODULE: url}});
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  return mutationAcceptance(result, expected(fault), file);
}
const results = [];
for (const fault of faults) {
  if (!selected(fault, pathToFileURL(modulePath).href)) throw new Error(`Baseline failed: ${fault.name}`);
  const path = fileURLToPath(new URL(`../adapters/host-node/.source-namespace-mutant-${randomUUID()}.mjs`, import.meta.url));
  let mutated = original;
  for (const [from, to] of [[fault.from, fault.to], ...(fault.second ? [fault.second] : [])]) {
    if (mutated.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${fault.name}`);
    mutated = mutated.replace(from, to);
  }
  writeFileSync(path, mutated, {flag: 'wx'});
  // Keep an unexpected failure's module alongside its bounded command evidence.
  if (selected(fault, pathToFileURL(path).href)) throw new Error(`Fault accepted: ${fault.name}`);
  if (!selected(fault, pathToFileURL(modulePath).href)) throw new Error(`Restored selection failed: ${fault.name}`);
  unlinkSync(path);
  results.push({name: fault.name, namedAssertionRejected: true, restoredAccepted: true});
}
console.log(JSON.stringify({mutations: results}, null, 2));
