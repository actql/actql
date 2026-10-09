import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
const {loadInstalledSource, installedSourceIdentity, installedSourcePublicationFacts} = await import(
  process.env.ACTQL_TEST_NAMESPACE_INSTALLED_SOURCE_MODULE ?? new URL('./installed-source.mjs', import.meta.url));
const {observeSourceAliasNamespace, sourceAliasNamespaceObservationFacts,
  sourceAliasPublication} = await import(process.env.ACTQL_TEST_NAMESPACE_PUBLICATION_MODULE ??
    new URL('./source-alias-publication.mjs', import.meta.url));

const moon = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
const wire = JSON.parse(await readFile(new URL('./fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
const environment = moon.clientProgramCheckEnvironment(canonicalText(wire),
  wire.evidence_bundle_cid, false, false, true, true, false, false, false);
const alias = name => ({name, sourceRef: 'connector://crm/main/r#v',
  sourceViewContractCid: wire.source_views[0].contract_cid,
  schemaContractCid: wire.source_views[0].output.schema.cid});
const binding = (digit = '1', principalId = 'reader') => Object.freeze({principalId,
  contextCid: `sha256:${digit.repeat(64)}`,
  inputs: Object.freeze([Object.freeze({document_id: 'source', kind: 'text',
    revision: `rev:${digit.repeat(64)}`, byte_length: 3})])});

async function authorization(t, {name = 'queries', operation = 'inspect_absence',
  outcome = 'allow', principal = 'reader', decide, deferral} = {}) {
  const gate = await createNodeAuthorizationGate({
    configuration: canonicalText({version: 'actql-execution-account-config/0.1',
      account_id: 'source-namespace', entries: [{entry_id: 'namespace-disclosure',
        outcome, principal: {any_of: [principal]},
        connection: {any_of: ['actql-source-namespace']}, resource: {any_of: [name]},
        operation: {any_of: [operation]}, exclusions: []}]}),
    context: {principal, contextCid: `sha256:${'a'.repeat(64)}`},
    ...(decide === undefined ? {} : {decide, answeringAuthorities: ['reviewer']}),
    ...(deferral === undefined ? {} : {deferral})});
  t.after(() => gate.close());
  return gate;
}

async function installed(t, {names = ['records'], generation = 1, changeDuringLoad, changeAliasesDuringLoad,
  identityFailure = false} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-namespace-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'source.json');
  const profile = {version: 'actql-installed-namespace-fixture/0.1', generation,
    queryAliases: names.map(alias)};
  await writeFile(path, JSON.stringify(profile));
  const counts = {loads: 0, source: 0, model: 0, effect: 0, credential: 0};
  const connectorTable = createInstalledConnectorTable([{
    name: 'namespace_fixture', registration: 'namespace_fixture', revision: 'namespace_fixture/0.1',
    source: {profileVersion: profile.version, load: async () => ({
      check: value => value,
      identityParts: value => {
        if (identityFailure) throw new Error('MetadataUnavailable');
        return [value];
      },
      async load() {
        counts.loads++;
        if (changeDuringLoad) await writeFile(path, JSON.stringify({...profile, generation: generation + 1}));
        if (changeAliasesDuringLoad) await writeFile(path,
          JSON.stringify({...profile, queryAliases: changeAliasesDuringLoad.map(alias)}));
        return Object.freeze({connectorRegistration: 'namespace_fixture', connectorRevision: 'namespace_fixture/0.1',
          open() { counts.source++; assert.fail('Checking must not acquire a Source'); },
          close() {}});
      },
    })},
  }]);
  const source = await loadInstalledSource(path, {root: directory, principalId: 'reader', moon,
    connectorTable, resolveSecret() { counts.credential++; assert.fail('Checking must not resolve credentials'); }});
  t.after(() => source.close());
  return {source, path, counts, connectorTable};
}

function publication(sources, paths, {name = 'queries', aliases = sources.flatMap(source => source.queryAliases)} = {}) {
  return sourceAliasPublication(moon, environment, aliases, [], {
    namespace: {name, profilePaths: paths}, installedSources: sources});
}

test('complete empty namespace requires explicit closure and its own disclosure grant', async t => {
  const gate = await authorization(t);
  const original = binding();
  const empty = publication([], []);
  const observation = await observeSourceAliasNamespace(empty, gate, original);
  assert.equal(observation.state, 'complete');
  const facts = sourceAliasNamespaceObservationFacts(empty, observation, original);
  assert.equal(facts.namespace, 'queries');
  assert.deepEqual(facts.aliases, []);
  assert.equal(facts.authority.principal, 'reader');
  assert.equal(facts.authority.configurationCid, gate.configurationCid);
  assert.equal(gate.resourceUsage().retainedDecisions, 0);
  // An empty positive publication is not an empty-namespace certificate.
  const open = sourceAliasPublication(moon, environment);
  assert.deepEqual(await observeSourceAliasNamespace(open, gate, original), {state: 'unresolved'});
  assert.equal(JSON.stringify(empty), JSON.stringify(open), 'Private completeness evidence must not be serialized');
});

test('namespace evidence uses every original unfiltered installed registration', async t => {
  const {source, path, counts} = await installed(t, {names: ['hidden']});
  assert.ok(installedSourcePublicationFacts(source));
  assert.equal(installedSourcePublicationFacts({...source}), undefined);
  const gate = await authorization(t), original = binding();
  const complete = publication([source], [path]);
  const observation = await observeSourceAliasNamespace(complete, gate, original);
  assert.equal(observation.state, 'complete');
  assert.deepEqual(sourceAliasNamespaceObservationFacts(complete, observation, original).aliases, [alias('hidden')]);
  // The caller's filtered aliases cannot replace the pre-authorization range.
  for (const incomplete of [publication([source], [path], {aliases: []}),
    publication([], [path]), publication([{...source}], [path]), publication([source], []),
    publication([source], [path, join(path, 'missing')])]) {
    const result = await observeSourceAliasNamespace(incomplete, gate, original);
    assert.deepEqual(result, {state: 'unresolved'}, '[check-mutation:namespace-completeness]');
    assert.equal(sourceAliasNamespaceObservationFacts(incomplete, result, original), undefined);
  }
  assert.deepEqual(counts, {loads: 1, source: 0, model: 0, effect: 0, credential: 0});
});

test('registration failure or revision change cannot issue a namespace certificate', async t => {
  const gate = await authorization(t), original = binding();
  for (const options of [{changeDuringLoad: true}, {identityFailure: true}]) {
    const {source, path} = await installed(t, options);
    assert.equal(installedSourcePublicationFacts(source), undefined);
    const selected = publication([source], [path]);
    assert.deepEqual(await observeSourceAliasNamespace(selected, gate, original), {state: 'unresolved'});
  }
});

test('exact Unicode alias changes during installation cannot close a namespace', async t => {
  const {source, path} = await installed(t,
    {names: ['`cafe\u0301`'], changeAliasesDuringLoad: ['`caf\u00e9`']});
  assert.equal(installedSourcePublicationFacts(source), undefined,
    '[check-mutation:namespace-exact-generation]');
  const gate = await authorization(t), original = binding();
  const selected = publication([source], [path]);
  assert.deepEqual(await observeSourceAliasNamespace(selected, gate, original), {state: 'unresolved'});
});

test('installed Source identity preserves exact query alias metadata', async t => {
  const {path, connectorTable} = await installed(t, {names: ['`cafe\u0301`']});
  const original = await installedSourceIdentity(path, {connectorTable});
  const profile = JSON.parse(await readFile(path, 'utf8'));
  await writeFile(path, JSON.stringify({...profile, queryAliases: [alias('`caf\u00e9`')]}));
  assert.notEqual(await installedSourceIdentity(path, {connectorTable}), original,
    '[check-mutation:namespace-exact-identity]');
});

test('installed Source generations match independent fixed preimages', async t => {
  // Independently hashed UTF-8 length-framed canonical metadata, followed by
  // the exact ordered alias row domain for a nonempty publication.
  const vectors = [
    [undefined, 'sha256:6e87cb5138d32798aace9e139de1dbe03acca54be20fd852f1c5fbfb1d18bfdd'],
    ['records', 'sha256:350499593d9325deb802c7df9a0194e0c11d84aef7d361fcd999fd49fa5bcbf1'],
    ['`caf\u00e9`', 'sha256:bf609554608439509cf60b8c1ad69bf4d8becbd784b37c86eed043a824090dc6'],
    ['`cafe\u0301`', 'sha256:f21c531d230b22f67bb6029a46d7eaf5028482ef99c7d40f787e94507de5952a'],
  ];
  for (const [name, expected] of vectors) {
    const {path, connectorTable} = await installed(t, {names: name === undefined ? [] : [name]});
    assert.equal(await installedSourceIdentity(path, {connectorTable}), expected);
    const profile = JSON.parse(await readFile(path, 'utf8'));
    if (name === undefined) delete profile.queryAliases;
    else {
      const entry = alias(name);
      profile.queryAliases = [{schemaContractCid: entry.schemaContractCid,
        sourceViewContractCid: entry.sourceViewContractCid, sourceRef: entry.sourceRef, name: entry.name}];
    }
    await writeFile(path, JSON.stringify(profile, null, 2));
    assert.equal(await installedSourceIdentity(path, {connectorTable}), expected,
      'Object property order, whitespace and an omitted empty publication preserve the generation');
  }
});

test('ordinary read and check grants do not disclose namespace absence', async t => {
  const selected = publication([], []), original = binding();
  for (const options of [{operation: 'read'}, {operation: 'check'}, {outcome: 'deny'},
    {name: 'other'}, {principal: 'another'}]) {
    const gate = await authorization(t, options);
    const observation = await observeSourceAliasNamespace(selected, gate, original);
    assert.deepEqual(observation, {state: 'unresolved'}, '[check-mutation:namespace-disclosure]');
    assert.equal(sourceAliasNamespaceObservationFacts(selected, observation, original), undefined);
    assert.equal(gate.resourceUsage().retainedDecisions, 0);
  }
  const fabricated = {withContext: () => ({configurationCid: `sha256:${'a'.repeat(64)}`,
    authorize: () => ({action: 'dispatch'}), close() {}})};
  assert.deepEqual(await observeSourceAliasNamespace(selected, fabricated, original), {state: 'unresolved'});
});

test('observation custody rejects copies and a different input or namespace', async t => {
  const gate = await authorization(t), original = binding(), selected = publication([], []);
  const observation = await observeSourceAliasNamespace(selected, gate, original);
  assert.ok(sourceAliasNamespaceObservationFacts(selected, observation, original));
  for (const [owner, result, input] of [[{...selected}, observation, original],
    [selected, {...observation}, original], [selected, observation, {...original}],
    [selected, observation, binding('2')], [publication([], [], {name: 'other'}), observation, original],
    [publication([], []), observation, original]]) {
    assert.equal(sourceAliasNamespaceObservationFacts(owner, result, input), undefined,
      '[check-mutation:namespace-custody]');
  }
});

test('each observation rechecks disclosure and releases its authorization scope', async t => {
  let permit = true, calls = 0;
  const gate = await authorization(t, {outcome: 'delegate', decide(view) {
    calls++;
    return {decision: permit ? 'permit' : 'reject', subject: view.subject, authority: 'reviewer', claims: []};
  }});
  const selected = publication([], []), original = binding();
  const first = await observeSourceAliasNamespace(selected, gate, original);
  assert.equal(first.state, 'complete');
  permit = false;
  const next = binding();
  const denied = await observeSourceAliasNamespace(selected, gate, next);
  assert.deepEqual(denied, {state: 'unresolved'});
  assert.equal(sourceAliasNamespaceObservationFacts(selected, first, next), undefined);
  assert.equal(calls, 2, 'A later check must not reuse a prior disclosure decision');
  assert.equal(gate.resourceUsage().retainedDecisions, 0);
});

test('namespace revision includes exact alias spelling and admitted configuration', async t => {
  const gate = await authorization(t);
  const revisions = [];
  for (const options of [{names: ['`caf\u00e9`']}, {names: ['`cafe\u0301`']},
    {names: ['`caf\u00e9`'], generation: 2}]) {
    const {source, path} = await installed(t, options);
    const selected = publication([source], [path]), original = binding();
    const observation = await observeSourceAliasNamespace(selected, gate, original);
    const facts = sourceAliasNamespaceObservationFacts(selected, observation, original);
    assert.ok(facts);
    assert.deepEqual(facts.aliases, source.queryAliases);
    revisions.push(facts.revision);
  }
  assert.equal(new Set(revisions).size, 3);
});

test('namespace declarations remain bounded and cannot accept a completeness boolean', () => {
  for (const namespace of [{name: 'queries', profilePaths: [], complete: true},
    {name: 'queries', profilePaths: Array(129).fill('/source')},
    {name: 'queries', profilePaths: ['/source', '/source']},
    {name: 'queries', profilePaths: ['relative']},
    {name: 'x'.repeat(257), profilePaths: []}]) {
    assert.throws(() => sourceAliasPublication(moon, environment, [], [], {namespace}),
      {message: 'InvalidSourceNamespaceDeclaration'});
  }
});

test('namespace inspection cannot create a deferred approval or execute a Source', async t => {
  let described = 0, persisted = 0;
  const gate = await authorization(t, {outcome: 'delegate',
    decide: view => ({decision: 'defer', subject: view.subject}),
    deferral: {describe() { described++; throw new Error('UnexpectedApproval'); },
      journal: {persistCheckpoint() { persisted++; throw new Error('UnexpectedCheckpoint'); },
        submitResolution() { assert.fail('No approval is submitted by checking'); }},
      authorities: [{reviewerId: 'reviewer'}], binding: {}},
  });
  const selected = publication([], []), original = binding();
  assert.deepEqual(await observeSourceAliasNamespace(selected, gate, original), {state: 'unresolved'});
  assert.equal(described, 0, '[check-mutation:namespace-no-approval] Namespace inspection must not prepare a review');
  assert.equal(persisted, 0, 'Namespace inspection must not persist a Checkpoint');
  assert.equal(gate.resourceUsage().retainedDecisions, 0);
});

test('namespace observations require immutable original document revision bindings', async t => {
  const gate = await authorization(t), selected = publication([], []), original = binding();
  const invalid = [Object.freeze({principalId: 'reader', contextCid: original.contextCid}),
    Object.freeze({...original, inputs: [...original.inputs]}),
    Object.freeze({...original, inputs: Object.freeze([{...original.inputs[0]}])}),
    Object.freeze({...original, inputs: Object.freeze([null])}),
    Object.freeze({...original, inputs: Object.freeze([Object.freeze({...original.inputs[0], revision: 'old'})])}),
    Object.freeze({...original, inputs: Object.freeze([...original.inputs, ...original.inputs])})];
  const evaluations = gate.counters().evaluations;
  for (const input of invalid) {
    assert.deepEqual(await observeSourceAliasNamespace(selected, gate, input), {state: 'unresolved'});
  }
  assert.equal(gate.counters().evaluations, evaluations);
});

// Independently computed with Python hashlib over the declared compact JSON
// preimages and the committed environment fixture CID, never product output.
const emptyNamespaceRevisions = [
  ['queries', 'sha256:847e95c5dea85193b7cff769bd868a74b8263a6ac8920338c9321c4d643c53a1'],
  ['other', 'sha256:afe08a6651bbc069aac537e03971b8835e321b46a94258558f683dd1e47ed19d'],
  ['queries:v2', 'sha256:d52f2751f250e2117c80a3a6d1e6043377ef70b39af1b14d7abde3061f6f023b'],
  ['queries/nested', 'sha256:4e96a829b13a607c0c67b30ae279deda07b1c68e91302ceebca9cc67531b06c1'],
];
test('empty namespace revisions match independent fixed preimages', async t => {
  assert.equal(wire.evidence_bundle_cid,
    'sha256:535c4c9bbefc918c4e1c67afcc8a7fae402d37b9113d039b3a03c758ae59a58e');
  for (const [name, expected] of emptyNamespaceRevisions) {
    const gate = await authorization(t, {name}), selected = publication([], [], {name}), original = binding();
    const observation = await observeSourceAliasNamespace(selected, gate, original);
    assert.equal(sourceAliasNamespaceObservationFacts(selected, observation, original)?.revision, expected);
  }
});
