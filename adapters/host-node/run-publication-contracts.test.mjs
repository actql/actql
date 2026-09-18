import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalCid, canonicalJson, admitPublicationContract,
  publicationContractNames, publicationContractSchema,
  publicationIdentityField, sealPublicationContract} from
  './run-publication-contracts.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

test('runtime contract registry covers every fixed publication schema', () => {
  assert.deepEqual(publicationContractNames(), [
    'result_definition', 'run_invocation', 'result_retention_policy',
    'durable_result_binding', 'publication_request',
    'publication_attempt', 'publication_record', 'manifest_read_grant',
    'result_read_grant', 'delivery_attempt', 'delivery_record',
    'public_index_entry',
  ]);
  for (const name of publicationContractNames()) {
    const schema = publicationContractSchema(name);
    assert(schema.required.includes(publicationIdentityField(name)));
    assert.equal(schema.additionalProperties, false);
    assert(Object.isFrozen(schema));
  }
});

test('canonical identity normalizes text and excludes only the self field', () => {
  assert.equal(canonicalJson({b: 'e\u0301\r\n', a: 2}),
    '{"a":2,"b":"é\\n"}');
  const body = sealPublicationContract('result_definition', {
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('1'),
    result_name: 'r',
  });
  assert.equal(body.result_definition_cid, canonicalCid({
    version: body.version,
    program_definition_cid: body.program_definition_cid,
    result_name: body.result_name,
  }));
  assert.deepEqual(admitPublicationContract('result_definition', body), body);
  assert.throws(() => admitPublicationContract('result_definition', {
    ...body, result_definition_cid: cid('2'),
  }), {code: 'PublicationIdentityMismatch'});
});

test('closed admission rejects missing, additional, and malformed members', () => {
  const base = {
    version: 'actql-result-definition/0.1',
    program_definition_cid: cid('1'),
    result_name: 'r',
  };
  assert.throws(() => sealPublicationContract('result_definition', {
    ...base, extra: true,
  }), {code: 'PublicationContractClosed'});
  assert.throws(() => sealPublicationContract('result_definition', {
    version: base.version,
    result_name: base.result_name,
  }), {code: 'PublicationContractRequired'});
  assert.throws(() => sealPublicationContract('result_definition', {
    ...base, program_definition_cid: 'not-a-cid',
  }), {code: 'PublicationContractPattern'});
});

test('attempt and terminal record remain different identities', () => {
  const attempt = sealPublicationContract('publication_attempt', {
    version: 'actql-publication-attempt/0.1',
    publication_request_cid: cid('1'),
    run_definition_cid: cid('2'),
    attempt_id: 'attempt-1',
    fence_cid: cid('3'),
    started_at: '2026-09-18T00:00:00.000Z',
  });
  assert.equal(Object.hasOwn(attempt, 'state'), false);
  const record = sealPublicationContract('publication_record', {
    version: 'actql-publication-record/0.1',
    publication_attempt_cid: attempt.publication_attempt_cid,
    sequence: 0,
    state: 'succeeded',
    observed_at: '2026-09-18T00:00:01.000Z',
    public_index_entry_cid: cid('4'),
    cleanup_owner_cids: [],
  });
  assert.notEqual(record.publication_record_cid,
    attempt.publication_attempt_cid);
  assert.throws(() => sealPublicationContract('publication_record', {
    version: 'actql-publication-record/0.1',
    publication_attempt_cid: attempt.publication_attempt_cid,
    sequence: 0,
    state: 'succeeded',
    observed_at: '2026-09-18T00:00:01.000Z',
    cleanup_owner_cids: [],
  }), {code: 'PublicationContractRequired'});
});

test('canonical values reject ambiguous or non-JSON input', () => {
  assert.throws(() => canonicalJson(-0), {code: 'InvalidCanonicalNumber'});
  assert.throws(() => canonicalJson(Number.POSITIVE_INFINITY),
    {code: 'InvalidCanonicalNumber'});
  assert.throws(() => canonicalJson(new Date()),
    {code: 'InvalidCanonicalValue'});
  assert.throws(() => canonicalJson({'é': 1, 'e\u0301': 2}),
    {code: 'CanonicalKeyCollision'});
});
