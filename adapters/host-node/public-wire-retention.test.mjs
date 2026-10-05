import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

test('public retained wire preserves long column and Object keys across consumers',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-wire-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    let advances = 0;
    let completions = 0;
    let outputRepresentations;
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1',
        account_id: 'public-wire', entries: [{entry_id: 'write', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
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
    // Stay inside the installed 1,000-byte construction policy, while crossing
    // the 64-unit cursor boundary for column names, Object keys and Text.
    const column = 'c'.repeat(80);
    const key = 'k'.repeat(80);
    const text = 'g'.repeat(512);
    const program = {version: 'actql/0.1', id: 'public-wire', stages: [{
      id: 'producer', inputs: {}, steps: [{values: {schema: {
        id: {type: 'number', nullable: false},
        [column]: {type: 'object', nullable: false,
          fields: {[key]: {type: 'string', nullable: true}}},
      }, rows: [{id: 2, [column]: {[key]: null}},
        {id: 1, [column]: {[key]: text}}]}, as: 'seed'},
      {from: 'seed', sort: [{id: 'asc'}], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', column]}},
    }, {
      id: 'consumer_a', inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
      steps: [{select: ['id', column], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', column]}},
    }, {
      id: 'consumer_b', inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
      steps: [{select: [column, 'id'], as: 'out'}],
      results: {r: {from: 'out', fields: [column, 'id']}},
    }], results: {
      published: {from: {stage: 'producer', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    }};
    const configuration = {mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}};
    let client = await connectEmbeddedLocal(configuration);
    t.after(() => client.close());
    const source = JSON.stringify(program);
    const options = {format: 'json', requestId: 'public-wire'};
    const execution = await client.aql(source, options).catch(error => {
      assert.fail(inspect(error, {depth: 8}));
    });
    const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const expected = [{id: 1, [column]: {[key]: text}},
      {id: 2, [column]: {[key]: null}}];
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.deepEqual(await execution.result(name).all(), expected, name);
    }
    assert.ok(outputRepresentations?.some(value =>
      value.representation === 'retained-file'));
    assert.ok(advances > 0, 'the actual bounded execution yielded');
    const completedAdvances = advances;
    assert.equal(completions, 1);
    const ref = execution.ref;
    await client.close();
    client = await connectEmbeddedLocal(configuration);
    const restored = await client.attach(ref);
    const repeated = await client.aql(source, options);
    assert.deepEqual(repeated.ref, ref);
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.deepEqual(await restored.result(name).all(), expected, name);
    }
    assert.equal(advances, completedAdvances,
      'reopening and resending must not reach another positive-progress yield');
    assert.equal(completions, 1, 'the saved Run is not recomputed');
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), [],
      'temporary retained input/output files are reclaimed');
  });
