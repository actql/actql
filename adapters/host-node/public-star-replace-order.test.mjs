import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp} from 'node:fs/promises';
import {userInfo} from 'node:os';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const number = {type: 'number', nullable: false};
const input = {
  parameterDeclarations: {items: {type: 'array', nullable: false, max_items: 2, items: number}},
  parameters: {items: [1, 2]},
};
const source = 'WITH t AS (SELECT x, 30 - x * 10 AS y FROM UNNEST(@items) AS x) ';

async function fixture(t) {
  const parent = new URL('../../_build/star-replace-order/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const directory = await mkdtemp(new URL('local-', parent));
  t.diagnostic(`Star replacement ORDER Host evidence: ${directory}`);
  const keys = generateKeyPairSync('ed25519');
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {
    directory,
    authorization: {
      accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
        account_id: 'star-replace-order', entries: [{entry_id: 'allow', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {all: true}, exclusions: []}]}),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    },
  }});
  t.after(async () => {
    await client.close();
    // Retain the signed Host artifacts for failed and final source review.
  });
  return client;
}

for (const item of [
  {
    name: 'same-name aggregate',
    projections: ['* REPLACE (SUM(x) AS x)', 'SUM(x) AS x, y', 'SUM(x) AS `x`, y'],
    // Independently derived from rows {x:1,y:20}, {x:2,y:10}.
    expected: [{x: 1, y: 20}, {x: 2, y: 10}],
  },
  {
    name: 'simultaneous replacement input',
    projections: ['* REPLACE (SUM(y) AS x, y + 1 AS y)',
      'SUM(y) AS x, y + 1 AS y', 'SUM(y) AS `x`, y + 1 AS y'],
    expected: [{x: 10, y: 11}, {x: 20, y: 21}],
  },
]) {
  test(`local SQL star REPLACE ORDER preserves ${item.name}`, {timeout: 90_000}, async t => {
    const client = await fixture(t);
    const cases = [[item.projections[0], 'x'], [item.projections[0], '`x`'],
      [item.projections[1], '`x`'], [item.projections[2], '`x`']];
    for (const [index, [projection, order]] of cases.entries()) {
      const text = `${source}SELECT ${projection} FROM t GROUP BY y ORDER BY ${order}`;
      const run = await client.aql(text, {format: 'sql', requestId: `case-${index}`, ...input});
      const state = await run.wait({signal: AbortSignal.timeout(15_000)});
      assert.equal(state.status, 'succeeded', text + ': ' + JSON.stringify(state));
      const result = run.result('answer');
      assert.deepEqual(await result.all(), item.expected, text);
      // SUM retains its declared nullable result contract; the key stays non-null.
      assert.deepEqual((await result.describe()).columns,
        [{name: 'x', contract: {type: 'number', nullable: true}},
          {name: 'y', contract: number}], text);
    }
  });
}
