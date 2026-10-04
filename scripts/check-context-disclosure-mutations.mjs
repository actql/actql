// Bounded Host mutations using the existing exact named-assertion guard.
// Import failure, asynchronous exceptions, timeout and unmatched selection
// remain infrastructure failures, never mutation detection evidence.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'adapters/host-node/client-check.mjs';
const acceptance = 'adapters/host-node/client-check.test.mjs';
const tests = {
  private: ['private Source inventories cannot change public context references',
    'private-context', 'deepStrictEqual'],
  public: ['public context references retain policy profiles and visible contracts',
    'public-context', 'notStrictEqual'],
  source: ['failed Source read owners preserve the bound public check',
    'source-owner', 'deepStrictEqual'],
};
const mutations = [
  ['private Environment CID enters the public preimage',
    'checking_context: checkingContext, visible_aliases: visible',
    'environment_cid: environmentCid, checking_context: checkingContext, visible_aliases: visible', 'private'],
  ['public checker selections and policy are omitted',
    'checking_context: checkingContext', 'checking_context: null', 'public'],
  ['authorized Source contracts are omitted',
    'visible_aliases: visible', 'visible_aliases: []', 'public'],
  ['failed Source read owners make the whole check unavailable',
    'return portions.flatMap(value => value ?? []).sort((left, right) =>',
    "if (portions.some(value => value === undefined)) return undefined;\n" +
    '    return portions.flatMap(value => value ?? []).sort((left, right) =>', 'source'],
];
const accepted = target => {
  const [name, id, operator] = tests[target];
  const expected = ['local', 'http'].map(entrance => ({name: `${entrance}: ${name}`,
    assertions: [{id, operator}]}));
  const pattern = `^(?:${expected.map(value => value.name).join('|')})$`;
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test',
    'node', '--timeout-seconds', '120', '--', '--test-name-pattern', pattern, acceptance],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected, acceptance);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to, target] of mutations) {
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(path, original.replace(from, to));
    if (target === 'source') {
      const source = readFileSync(path, 'utf8');
      const anchor = 'const visible = await visibleAliases(signal);';
      if (source.split(anchor).length !== 2) throw new Error('Source failure mutation anchor not unique');
      writeFileSync(path, source.replace(anchor, anchor +
        "\n    if (visible === undefined) return JSON.parse(moon.clientProgramCheckUnavailable('corr:mutant'));"));
    }
    results.push({name, rejected: !accepted(target)});
  }
} finally {
  writeFileSync(path, original);
}
const restoredAccepted = Object.keys(tests).every(accepted);
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
