// Bounded SDK mutations reuse the exact named-assertion guard. Infrastructure
// failures are never accepted as proof that an invalid location was detected.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-check.test.mjs';
const expected = ['local', 'http'].map(entrance => ({
  name: `${entrance}: structured check locations name only submitted JSON nodes`,
  assertions: [{id: 'structured-refusal', operator: 'strictEqual'},
    {id: 'structured-valid', operator: 'notStrictEqual'},
    {id: 'structured-resolved', operator: 'strictEqual'}],
}));
const arrayGuard = "    if (Array.isArray(value)) {\n" +
  "      if (!/^(?:0|[1-9][0-9]*)$/u.test(key)) return false;\n" +
  "      const index = Number(key);\n" +
  "      if (!Number.isSafeInteger(index) || index >= value.length) return false;\n" +
  "    }\n";
const mutations = [
  ['a missing submitted node is accepted',
    '    if (!structuredNodeExists(original.value, location.pointer)) return undefined;', ''],
  ['an inherited object property is accepted',
    'if (!Object.hasOwn(value, key)) return false;', 'if (!(key in value)) return false;'],
  ['an escaped literal tilde-slash name is decoded in the wrong order',
    "token.replaceAll('~1', '/').replaceAll('~0', '~')",
    "token.replaceAll('~0', '~').replaceAll('~1', '/')"],
  ['an array length property is accepted as a submitted element', arrayGuard, ''],
];
const accepted = () => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${expected.map(value => value.name).join('|')})$`, acceptance],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected, acceptance);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to] of mutations) {
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(path, original.replace(from, to));
    results.push({name, rejected: !accepted()});
  }
} finally {
  writeFileSync(path, original);
}
const restoredAccepted = accepted();
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
