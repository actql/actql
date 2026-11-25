import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {verifyCommonLocalNormalizationCatalog, verifySourceLocalNormalizationCatalog} from './local-common-normalization-catalog.mjs';

type Catalog = {rules: unknown[]; version: string; profile: string; applicability: {
  audit_work_limit: number; parameter_origins: string[]; normalization_journal_limits: unknown;
}};
type Fixture = {catalog_preimage: string; catalog_cid: string; journal_cid: string};
type SortFixture = {preimage: string; journal_cid: string; wire: string};
type Journal = {rule_catalog_cid: string; entries: {rule: string; path: string}[]};
type LegacyMembers = {source: string; members: {path: string; gitEntry: string; bytes: number; sha256: string}[]};
const read = <Value,>(name: string): Value => JSON.parse(readFileSync(name, 'utf8'));
const stem = 'spec/contracts/actql-effect-free-local-common-normalization-';
const canonical = (value: unknown): string => value === null || typeof value !== 'object' ? JSON.stringify(value)!
  : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical((value as Record<string, unknown>)[key])).join(',') + '}';
const sha = (bytes: string | Buffer) => createHash('sha256').update(bytes).digest('hex');

test('Source successor retains old rules and independently pinned nonempty original journals', () => {
  const prior = read<Fixture>(stem + 'fixture.json');
  const result = verifySourceLocalNormalizationCatalog();
  assert.notEqual(result.catalogCid, prior.catalog_cid);
  assert.notEqual(result.journalCid, prior.journal_cid);
});

test('all complete legacy catalogue schema and journal bodies retain their accepted identities', () => {
  const fixed = read<LegacyMembers>('scripts/fixtures/local-common-normalization/legacy-members.json');
  assert.equal(fixed.source, '2fba680bacefa9a8474401c407c904ade9a3b2db');
  assert(fixed.members.length > 30);
  for (const item of fixed.members) {
    // Historical identities bind their original source, while the separate
    // current catalogue tests below validate this checkout's selected bodies.
    const bytes: Buffer = execFileSync('git', ['show', `${fixed.source}:${item.path}`],
      {timeout: 10000, maxBuffer: 16 * 1024 * 1024});
    const entry: string = execFileSync('git', ['ls-tree', fixed.source, '--', item.path],
      {encoding: 'utf8', timeout: 10000}).trim().split('\t')[0];
    assert.equal(entry, item.gitEntry, item.path);
    assert.equal(bytes.length, item.bytes, item.path);
    assert.equal(sha(bytes), item.sha256, item.path);
    assert(item.gitEntry.startsWith('100644 blob '));
  }
});

test('the fresh catalogue has one closed original-occurrence scope and only actual existing rules', () => {
  const body = read<Catalog>(stem + 'catalog.json');
  const prior = read<Catalog>('spec/contracts/actql-effect-free-local-bounded-relation-completion-free-catalog.json');
  assert.deepEqual(body.rules, prior.rules);
  assert.equal(body.version, prior.version);
  assert.equal(body.profile, prior.profile);
  assert.equal(body.applicability.audit_work_limit, 10000);
  assert.deepEqual(body.applicability.parameter_origins, ['supplied', 'default']);
  assert.deepEqual(body.applicability.normalization_journal_limits, prior.applicability.normalization_journal_limits);
  assert(!Object.keys(body.applicability).some(name => ['checked_operations', 'expression_nodes', 'aggregate_functions'].includes(name)));
  const fixed = read<Fixture>(stem + 'fixture.json');
  assert.equal(canonical(body), fixed.catalog_preimage);
  assert.equal('sha256:' + sha(fixed.catalog_preimage), fixed.catalog_cid);
  assert.equal(verifyCommonLocalNormalizationCatalog().catalogCid, fixed.catalog_cid);
});

test('independent actual Sort entry keeps its rule path and nonempty journal identity', () => {
  const fixed = read<SortFixture>('scripts/fixtures/local-common-normalization/sort-identity.json');
  const value: Journal = JSON.parse(fixed.preimage);
  assert.equal(value.entries.length, 1);
  assert.equal(value.entries[0].rule, 'sort.candidate_key_completion');
  assert.equal(value.entries[0].path, '$.stages[0].steps[2].sort');
  assert.equal(canonical(value), fixed.preimage);
  assert.equal('sha256:' + sha(fixed.preimage), fixed.journal_cid);
  assert.equal(canonical({...value, journal_cid: fixed.journal_cid}), fixed.wire);
  const empty = read<Fixture>(stem + 'fixture.json');
  assert.equal(value.rule_catalog_cid, empty.catalog_cid);
  assert.notEqual(fixed.journal_cid, empty.journal_cid);
  assert.notEqual('sha256:' + sha(canonical({...value, entries: []})), fixed.journal_cid);
});
