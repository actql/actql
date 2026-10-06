import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

test('public retained sequence orders long identities and compound Text keys',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-sequence-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    let advances = 0;
    let completions = 0;
    let outputRepresentations;
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'public-sequence',
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
    // Cross the Text cursor boundary within the installed construction policy.
    const id = suffix => 'g'.repeat(80) + suffix;
    const group = suffix => 'p'.repeat(80) + suffix;
    const aux = 'q'.repeat(80) + '😀';
    const fields = ['aux', 'end_id', 'end_time_ms', 'key', 'match_end_ms',
      'match_start_ms', 'start_id', 'start_time_ms'];
    const program = {version: 'actql/0.1', id: 'public-sequence', stages: [{
      id: 'producer', inputs: {}, steps: [{values: {schema: {
        id: {type: 'string', nullable: false},
        key: {type: 'string', nullable: false},
        aux: {type: 'string', nullable: true},
        clock: {type: 'number', nullable: false},
        value: {type: 'number', nullable: false},
      }, rows: [
        {id: id(3), key: group(1), aux, clock: 3, value: 2},
        {id: id(1), key: group(1), aux, clock: 1, value: 1},
        {id: id(4), key: group(2), aux: null, clock: 4, value: 2},
        {id: id(2), key: group(1), aux, clock: 2, value: 2},
        {id: id(5), key: group(2), aux: null, clock: 3, value: 1},
      ]}, as: 'seed'}, {from: 'seed', sequence: {
        by: ['key', 'aux'], id: 'id', time: 'clock',
        pattern: [{as: 'start', where: 'value = 1'},
          {as: 'end', where: 'value = 2'}],
        within: 10, overlap: 'allow', contiguity: 'subsequence',
      }, as: 'matched'}, {from: 'matched', sort: [{key: 'asc'},
        {match_start_ms: 'asc'}, {match_end_ms: 'asc'}, {start_id: 'asc'},
        {end_id: 'asc'}], as: 'ordered'},
      {from: 'ordered', select: fields, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, ...['consumer_a', 'consumer_b'].map(name => ({
      id: name, inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
      steps: [{select: name === 'consumer_a' ? fields : [...fields].reverse(),
        as: 'out'}], results: {r: {from: 'out', fields}},
    }))], results: {
      published: {from: {stage: 'producer', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    }};
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    t.after(() => client.close());
    for (const empty of [false, true]) {
      const submitted = structuredClone(program);
      if (empty) submitted.stages[0].steps[0].values.rows = [];
      submitted.id = empty ? 'public-sequence-empty' : 'public-sequence';
      const source = JSON.stringify(submitted);
      const options = {format: 'json', requestId: submitted.id};
      const execution = await client.aql(source, options).catch(error => {
        assert.fail(inspect(error, {depth: 8}));
      });
      const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
      assert.equal(state.status, 'succeeded', JSON.stringify(state));
      const expected = empty ? [] : [
        {aux, end_id: id(2), end_time_ms: 2, key: group(1), match_end_ms: 2,
          match_start_ms: 1, start_id: id(1), start_time_ms: 1},
        {aux, end_id: id(3), end_time_ms: 3, key: group(1), match_end_ms: 3,
          match_start_ms: 1, start_id: id(1), start_time_ms: 1},
        {aux: null, end_id: id(4), end_time_ms: 4, key: group(2), match_end_ms: 4,
          match_start_ms: 3, start_id: id(5), start_time_ms: 3},
      ];
      for (const name of ['published', 'consumed_a', 'consumed_b']) {
        assert.deepEqual(await execution.result(name).all(), expected, name);
      }
      assert.ok(outputRepresentations?.some(value =>
        value.representation === 'retained-file'));
      assert.ok(advances > 0);
      assert.equal(completions, empty ? 2 : 1);
      const savedAdvances = advances;
      const repeated = await client.aql(source, options);
      assert.deepEqual(repeated.ref, execution.ref);
      assert.deepEqual(await repeated.result('published').all(), expected);
      assert.equal(advances, savedAdvances);
      assert.equal(completions, empty ? 2 : 1);
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    }
  });
