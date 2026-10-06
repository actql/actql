import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

test('public retained interval join compares long Text keys and excludes NULL',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-interval-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    let advances = 0;
    let completions = 0;
    let outputRepresentations;
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1',
        account_id: 'public-interval',
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
    const key = suffix => 'g'.repeat(80) + suffix;
    const schema = names => ({key: {type: 'string', nullable: true},
      ...Object.fromEntries(names.map(name =>
        [name, {type: 'number', nullable: false}]))});
    const fields = ['left_value', 'right_value'];
    const program = {version: 'actql/0.1', id: 'public-interval', stages: [
      {id: 'left', inputs: {}, steps: [{values: {
        schema: schema(['time', 'value']), rows: [
          {key: key('a'), time: 2, value: 10},
          {key: key('b'), time: 7, value: 11},
          {key: null, time: 1, value: 12},
        ]}, as: 'out'}], results: {r: {from: 'out',
        fields: ['key', 'time', 'value']}}},
      {id: 'right', inputs: {}, steps: [{values: {
        schema: schema(['start', 'end', 'value']), rows: [
          {key: key('a'), start: 0, end: 3, value: 20},
          {key: key('a'), start: 2, end: 4, value: 21},
          {key: key('b'), start: 8, end: 9, value: 22},
          {key: null, start: 0, end: 3, value: 23},
        ]}, as: 'out'}], results: {r: {from: 'out',
        fields: ['key', 'start', 'end', 'value']}}},
      {id: 'producer', inputs: {
        l: {result: {stage: 'left', result: 'r'}},
        r: {result: {stage: 'right', result: 'r'}},
      }, steps: [{from: 'l', interval_join: {
        with: 'r', kind: 'left', mode: 'point_in_interval',
        on: [{left: 'key', right: 'key'}], left: {time: 'time'},
        right: {start: 'start', end: 'end'},
        select: {left_value: 'left.value', right_value: 'right.value'},
        max_output_rows: 12,
      }, as: 'joined'}, {from: 'joined', sort: [
        {left_value: 'asc'}, {right_value: 'asc'},
      ], as: 'out'}], results: {r: {from: 'out', fields}}},
      ...['consumer_a', 'consumer_b'].map(name => ({id: name,
        inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
        steps: [{select: name === 'consumer_a' ? fields : [...fields].reverse(),
          as: 'out'}], results: {r: {from: 'out', fields}},
      })),
    ], results: {
      published: {from: {stage: 'producer', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    }};
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    t.after(() => client.close());
    const source = JSON.stringify(program);
    const options = {format: 'json', requestId: 'public-interval'};
    const execution = await client.aql(source, options).catch(error => {
      assert.fail(inspect(error, {depth: 8}));
    });
    const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const expected = [
      {left_value: 10, right_value: 20}, {left_value: 10, right_value: 21},
      {left_value: 11, right_value: null}, {left_value: 12, right_value: null},
    ];
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.deepEqual(await execution.result(name).all(), expected, name);
    }
    assert.ok(outputRepresentations?.some(value =>
      value.representation === 'retained-file'));
    assert.ok(advances > 0);
    assert.equal(completions, 1);
    const savedAdvances = advances;
    const repeated = await client.aql(source, options);
    assert.deepEqual(repeated.ref, execution.ref);
    assert.deepEqual(await repeated.result('published').all(), expected);
    assert.equal(advances, savedAdvances);
    assert.equal(completions, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
  });
