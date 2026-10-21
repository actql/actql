import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {verifyCommonLocalNormalizationCatalog} from './local-common-normalization-catalog.mjs';

const read = name => JSON.parse(readFileSync(name, 'utf8'));
const stem = 'spec/contracts/actql-effect-free-local-common-normalization-';
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

test('all complete legacy catalogue schema and journal bodies retain their accepted identities', () => {
  const fixed = read('scripts/fixtures/local-common-normalization/legacy-members.json');
  assert.equal(fixed.source, '2fba680bacefa9a8474401c407c904ade9a3b2db');
  assert(fixed.members.length > 30);
  for (const item of fixed.members) {
    const bytes = readFileSync(item.path);
    assert.equal(bytes.length, item.bytes, item.path);
    assert.equal(sha(bytes), item.sha256, item.path);
    assert(item.gitEntry.startsWith('100644 blob '));
  }
});

test('the fresh catalogue has one closed original-occurrence scope and only actual existing rules', () => {
  const body = read(stem + 'catalog.json');
  const prior = read('spec/contracts/actql-effect-free-local-bounded-relation-completion-free-catalog.json');
  assert.deepEqual(body.rules, prior.rules);
  assert.equal(body.version, prior.version);
  assert.equal(body.profile, prior.profile);
  assert.equal(body.applicability.audit_work_limit, 10000);
  assert.deepEqual(body.applicability.parameter_origins, ['supplied', 'default']);
  assert.deepEqual(body.applicability.normalization_journal_limits, prior.applicability.normalization_journal_limits);
  assert(!Object.keys(body.applicability).some(name => ['checked_operations', 'expression_nodes', 'aggregate_functions'].includes(name)));
  const fixed = read(stem + 'fixture.json');
  assert.equal(canonical(body), fixed.catalog_preimage);
  assert.equal('sha256:' + sha(fixed.catalog_preimage), fixed.catalog_cid);
  assert.equal(verifyCommonLocalNormalizationCatalog().catalogCid, fixed.catalog_cid);
});

test('independent actual Sort entry keeps its rule path and nonempty journal identity', () => {
  const fixed = read('scripts/fixtures/local-common-normalization/sort-identity.json');
  const value = JSON.parse(fixed.preimage);
  assert.equal(value.entries.length, 1);
  assert.equal(value.entries[0].rule, 'sort.candidate_key_completion');
  assert.equal(value.entries[0].path, '$.stages[0].steps[2].sort');
  assert.equal(canonical(value), fixed.preimage);
  assert.equal('sha256:' + sha(fixed.preimage), fixed.journal_cid);
  assert.equal(canonical({...value, journal_cid: fixed.journal_cid}), fixed.wire);
  const empty = read(stem + 'fixture.json');
  assert.equal(value.rule_catalog_cid, empty.catalog_cid);
  assert.notEqual(fixed.journal_cid, empty.journal_cid);
  assert.notEqual('sha256:' + sha(canonical({...value, entries: []})), fixed.journal_cid);
});
