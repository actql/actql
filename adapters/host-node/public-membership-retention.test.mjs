import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

test('public retained membership preserves duplicate Text matches and NULL',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-membership-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    let advances = 0;
    let completions = 0;
    let outputRepresentations;
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1',
        account_id: 'public-membership',
        entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}],
      }),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
        principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
        type: 'pkcs8', format: 'pem'})},
      faultInjection(step) {
        if (step === 'local_compute_advanced') advances++;
      },
      observe(step, detail) {
        if (step === 'computed') {
          completions++;
          outputRepresentations = detail.outputRepresentations;
        }
      },
    };
    // Both Text operands cross the comparison cursor boundary, without raising
    // the installed construction policy. Duplicate matches must not drop NULL.
    const text = 'g'.repeat(256);
    const program = {version: 'actql/0.1', id: 'public-membership',
      params: {items: {type: 'array', nullable: false,
        items: {type: 'string', nullable: true}}},
      stages: [{id: 'producer', inputs: {}, steps: [{values: {schema: {
        id: {type: 'number', nullable: false},
        tag: {type: 'string', nullable: true},
      }, rows: [{id: 3, tag: null}, {id: 2, tag: text + 'x'},
        {id: 1, tag: text}]}, as: 'seed'},
      {from: 'seed', derive: {included: {in: [{field: 'tag'},
        {$param: 'items'}]}}, as: 'flags'},
      {from: 'flags', select: ['id', 'included'], as: 'selected'},
      {from: 'selected', sort: [{id: 'asc'}], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'included']}},
      }, {id: 'consumer_a',
        inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
        steps: [{select: ['id', 'included'], as: 'out'}],
        results: {r: {from: 'out', fields: ['id', 'included']}},
      }, {id: 'consumer_b',
        inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
        steps: [{select: ['included', 'id'], as: 'out'}],
        results: {r: {from: 'out', fields: ['included', 'id']}},
      }], results: {
        published: {from: {stage: 'producer', result: 'r'}},
        consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
        consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
      }};
    const configuration = {mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}};
    const client = await connectEmbeddedLocal(configuration);
    t.after(() => client.close());
    const source = JSON.stringify(program);
    const options = {format: 'json', requestId: 'public-membership',
      parameters: {items: [text, text]}};
    const execution = await client.aql(source, options).catch(error => {
      assert.fail(inspect(error, {depth: 8}));
    });
    const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const expected = [{id: 1, included: true}, {id: 2, included: false},
      {id: 3, included: null}];
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.deepEqual(await execution.result(name).all(), expected, name);
    }
    assert.ok(outputRepresentations?.some(value =>
      value.representation === 'retained-file'));
    assert.ok(advances > 0, 'the actual bounded execution yielded');
    assert.equal(completions, 1);
    const completedAdvances = advances;
    const repeated = await client.aql(source, options);
    assert.deepEqual(repeated.ref, execution.ref);
    assert.deepEqual(await repeated.result('published').all(), expected);
    assert.equal(advances, completedAdvances,
      'same-request reuse must not execute another comparison');
    assert.equal(completions, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), [],
      'temporary retained input/output files are reclaimed');
  });
