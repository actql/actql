import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {accountConfiguration, effectHost, effectProgram, installedEffect,
  recordEntry} from './installed-salesforce-effect.fixture.mjs';
import {checkInstalledSalesforceEffectProfile} from
  '../host/installed-salesforce-effect.mjs';

const writesOf = org => org.seen.filter(item => item.method === 'PATCH' ||
  item.method === 'POST');
const recordReads = org => org.seen.filter(item => item.method === 'GET' &&
  /\/sobjects\/[A-Za-z_]+\/[^/]+$/u.test(item.path) &&
  !item.path.endsWith('/describe'));
const ids = ['a00000000000001', 'a00000000000002'];
const update = {resource: 'Test_Record__c', kind: 'update', fields: ['Name']};

// A Program of one update Effect per installed Mapping, over `rows`.
function updateProgram(mappings, rows = ids.map(id => ({id}))) {
  return effectProgram(Object.fromEntries(mappings.map((mapping, index) =>
    [index === 0 ? 'save' : `save_${index}`, {update: {
      target: mapping.target, mapping: mapping.mappingRef,
      from: {result: 'rows'}, id: 'id', set: {Name: {field: 'id'}}}}])),
  rows);
}

test('an installed update Effect reads its targets, writes each row once and publishes',
  async t => {
    const installation = await installedEffect(t, {writes: [update]});
    const host = await effectHost(t, installation,
      join(installation.root, 'host'));
    installation.org.setTargetName('observed-before');
    const {started} = await host.run(updateProgram(host.installed.mappings),
      'update-once');
    assert.equal(started.kind, 'started');
    assert.equal(started.value.status, 'published');
    const writes = writesOf(installation.org);
    assert.deepEqual(writes.map(item => [item.method,
      item.path.split('/').slice(-2).join('/'), JSON.parse(item.body)]),
    ids.map(id => ['PATCH', `Test_Record__c/${id}`, {Name: id}]));
    // Each target was read under a check-read decision before any write,
    // and again for the whole-set refresh after the commit decision.
    const firstWrite = installation.org.seen.indexOf(writes[0]);
    assert.equal(recordReads(installation.org).filter(item =>
      installation.org.seen.indexOf(item) < firstWrite).length, 4);
    // The Preview carries the observed before-values.
    const preview = JSON.parse(host.outcomes[0].stage.apply.capturedInputs ===
      undefined ? '{}' : host.control.effectComputationPreviewWire(
        host.outcomes[0].stage.preview));
    assert.deepEqual(preview.effects[0].changes.map(change => change.before),
      ids.map(id => ({state: 'present', value: {Name: 'observed-before'}})));
    assert.equal(JSON.stringify(preview).includes(installation.org.orgId),
      false);
  });

test('an installed create and upsert Effect write through their own Mappings',
  async t => {
    for (const [write, method] of [
      [{resource: 'Test_Record__c', kind: 'createFromResult', sources: [
        {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
        {target: 'Name', field: 'id', nullBehavior: 'reject'}]}, 'POST'],
      [{resource: 'Test_Record__c', kind: 'upsert', key: 'External_Key__c',
        fields: ['Name']}, 'PATCH'],
    ]) {
      const installation = await installedEffect(t, {writes: [write],
        writeOperation: write.kind === 'upsert' ? 'upsert' : 'create'});
      const host = await effectHost(t, installation,
        join(installation.root, 'host'));
      const [mapping] = host.installed.mappings;
      // A Result-backed create writes what its Mapping names from the Result.
      const program = write.kind === 'createFromResult'
        ? effectProgram({save: {create: {target: mapping.target,
          mapping: mapping.mappingRef, from: {result: 'rows'}}}},
        ids.map(id => ({id})))
        : effectProgram({save: {upsert: {target: mapping.target,
          mapping: mapping.mappingRef, from: {result: 'rows'}, key: 'id',
          set: {Name: {field: 'id'}}}}}, ids.map(id => ({id})));
      const {started} = await host.run(program, `${write.kind}-once`);
      assert.equal(started.value.status, 'published', write.kind);
      assert.deepEqual(writesOf(installation.org).map(item => item.method),
        [method, method]);
      if (write.kind === 'upsert') {
        assert.deepEqual(writesOf(installation.org).map(item =>
          item.path.split('/').slice(-3).join('/')).sort(),
        ids.map(id => `Test_Record__c/External_Key__c/${id}`));
      }
    }
  });

test('a denied commit or check read writes nothing',
  async t => {
    const cases = [
      ['commit', org => [recordEntry(org, 'read'),
        recordEntry(org, 'effect', 'deny')], 'ExecutionAuthorizationDenied'],
      ['check read', org => [recordEntry(org, 'effect')],
        'SalesforceEffectTargetReadNotAuthorized'],
    ];
    for (const [label, entries, code] of cases) {
      const installation = await installedEffect(t, {writes: [update]});
      // The Host restarts under the changed account configuration.
      const host = await effectHost(t, installation,
        join(installation.root, 'host'), {effect: await installation.load({
          accountConfigurationWire: accountConfiguration(
            entries(installation.org.orgId))})});
      const failure = await host.run(updateProgram(host.installed.mappings),
        `denied-${label}`).then(() => undefined, error => error);
      assert.ok(failure, label);
      assert.equal(failure.code ?? failure.authorization?.code ?? code, code,
        `${label}: ${failure.code}`);
      assert.equal(writesOf(installation.org).length, 0, label);
      if (label === 'check read') {
        assert.equal(recordReads(installation.org).length, 0);
      }
    }
  });

test('a published generation is restored only as it was published',
  async t => {
    const installation = await installedEffect(t, {writes: [update]});
    // Another write set is another generation.
    await assert.rejects(installation.load({writes: [{...update,
      fields: ['Name', 'External_Key__c']}]}),
    {code: 'SalesforceEffectPublicationMismatch'});
    // A tampered Mapping list is not this generation.
    const path = installation.profile.publicationPath;
    const text = await readFile(path, 'utf8');
    const record = JSON.parse(text);
    record.mappings[0].mapping_cid = `sha256:${'9'.repeat(64)}`;
    await writeFile(path, JSON.stringify(record));
    await assert.rejects(installation.load(),
      {code: 'SalesforceEffectPublicationMismatch'});
    await writeFile(path, text);
    // Another Site generation must publish again first.
    await installation.writeSite({...installation.siteDocument,
      siteGeneration: 2});
    await assert.rejects(installation.load(),
      {code: 'ForeignSalesforceDeclaration'});
    // Nothing was read to restore any of them.
    assert.equal(writesOf(installation.org).length, 0);
    // An unknown profile is refused before anything is installed; a checked
    // profile keeps its shape and checks again.
    await assert.rejects(installation.load({version: 'unknown/0.1'}),
      {code: 'InvalidInstalledEffectProfile'});
    const checkedProfile = checkInstalledSalesforceEffectProfile(
      installation.profile);
    assert.deepEqual(checkInstalledSalesforceEffectProfile(checkedProfile),
      checkedProfile);
    for (const write of [{resource: 'Test_Record__c', kind: 'create',
      fields: ['Name']}, {...update, extra: true},
    {resource: 'Test_Record__c', kind: 'upsert', fields: ['Name']}]) {
      assert.throws(() => checkInstalledSalesforceEffectProfile({
        ...installation.profile, writes: [write]}),
      {code: 'InvalidInstalledEffectProfile'});
    }
  });

const other = {resource: 'Other_Record__c', kind: 'update', fields: ['Name']};
const twoTargets = org => [
  recordEntry(org, 'read'), recordEntry(org, 'effect'),
  recordEntry(org, 'read', 'allow', 'Other_Record__c'),
  recordEntry(org, 'effect', 'allow', 'Other_Record__c')];

// Capture a two-member Set in one Host process, stop before its commit, and
// return what a restarted Host continues from.
async function capturedSet(t, {writes = [update, other],
  org: orgOptions} = {}) {
  const installation = await installedEffect(t, {writes,
    org: {writableObjects: ['Other_Record__c'], ...orgOptions},
    entries: twoTargets('00D000000000001EAA')});
  const state = join(installation.root, 'host');
  const first = await effectHost(t, installation, state,
    {stopBeforeApply: true});
  const {accepted, started} = await first.run(
    updateProgram(first.installed.mappings), 'restart-set');
  assert.equal(started.value.status, 'captured');
  await first.close();
  assert.equal(writesOf(installation.org).length, 0);
  return {installation, state, accepted,
    continuation: started.value.continuation};
}

test('a captured Set continues after a restart and never writes twice',
  async t => {
    const {installation, state, accepted, continuation} =
      await capturedSet(t);
    const second = await effectHost(t, installation, state);
    const resumed = await second.resume('restart-set',
      accepted.ref.runDefinitionCid, continuation);
    assert.equal(resumed.result.status, 'published');
    assert.deepEqual(writesOf(installation.org).map(item =>
      item.path.split('/').slice(-2).join('/')).sort(),
    ['Other_Record__c', 'Test_Record__c'].flatMap(resource =>
      ids.map(id => `${resource}/${id}`)));
    await second.close();
    // Another restart finds every row settled: nothing more is sent.
    const third = await effectHost(t, installation, state);
    const again = await third.resume('restart-set',
      accepted.ref.runDefinitionCid, continuation).then(value => value,
      error => ({error}));
    assert.equal(again.result?.status, 'published',
      String(again.error?.code));
    assert.equal(writesOf(installation.org).length, 4);
  });

test('a restarted Set is refused before any write when one target changed',
  async t => {
    const changes = [
      ['permission', async installation => ({
        accountConfigurationWire: accountConfiguration([
          ...twoTargets(installation.org.orgId).slice(0, 3),
          recordEntry(installation.org.orgId, 'effect', 'deny',
            'Other_Record__c')])}), 'ExecutionAuthorizationDenied'],
      ['Mapping', async installation => {
        const writes = [update, {...other, fields: ['Name',
          'External_Key__c']}];
        await installation.publish({writes});
        return {writes};
      }, 'SalesforceEffectMappingNotInstalled'],
      ['Site generation', async installation => {
        await installation.writeSite({...installation.siteDocument,
          siteGeneration: 2});
        await installation.publish();
        return {};
      }, 'SalesforceEffectInstallationChanged'],
      ['target', async installation => {
        installation.org.setTargetName('changed-after-preview');
        return {};
      }, 'MoonBitHostFailure'],
      // The Host now runs another standard runtime: the Site attests it,
      // so the Preview's capability no longer matches.
      ['runtime', async () => ({options: {
        runtimeBundleCid: `sha256:${'c'.repeat(64)}`}}),
      'SalesforceEffectInstallationChanged'],
    ];
    for (const [label, change, code] of changes) {
      const {installation, state, accepted, continuation} =
        await capturedSet(t);
      const {options, ...overrides} = await change(installation);
      const second = await effectHost(t, installation, state,
        {effect: await installation.load(overrides, options)});
      const failure = await second.resume('restart-set',
        accepted.ref.runDefinitionCid, continuation).then(
        () => undefined, error => error);
      assert.ok(failure, label);
      assert.equal(failure.authorization?.code === undefined
        ? failure.code : 'ExecutionAuthorizationDenied', code,
      `${label}: ${failure.code}`);
      assert.equal(writesOf(installation.org).length, 0, label);
    }
  });

test('a rejected row is kept unknown, halts its member and is never retried',
  async t => {
    const installation = await installedEffect(t, {writes: [update],
      org: {rejectWrites: [2]}});
    const state = join(installation.root, 'host');
    const host = await effectHost(t, installation, state);
    const run = await host.run(updateProgram(host.installed.mappings,
      [...ids, 'a00000000000003'].map(id => ({id}))), 'partial-set')
      .then(value => value, error => ({error}));
    // The first row applied. The provider's reply to the second is not a
    // typed single-record outcome, so it stays unknown rather than failed;
    // the third is never sent under halt.
    assert.equal(run.started?.value?.status, 'needs_reconciliation',
      String(run.error?.code));
    assert.equal(writesOf(installation.org).length, 2);
    await host.close();
    const second = await effectHost(t, installation, state);
    const resumed = await second.resume('partial-set',
      run.accepted.ref.runDefinitionCid,
      JSON.parse(host.outcomes[0].stage.continuationWire));
    assert.equal(resumed.result.status, 'needs_reconciliation');
    assert.equal(writesOf(installation.org).length, 2);
  });

test('a lost write reply is kept unknown and never resent after restart',
  async t => {
    const installation = await installedEffect(t, {writes: [update],
      org: {loseWriteReplyOnce: true}});
    const state = join(installation.root, 'host');
    const host = await effectHost(t, installation, state);
    const run = await host.run(updateProgram(host.installed.mappings),
      'lost-reply').then(value => value, error => ({error}));
    const sent = writesOf(installation.org).length;
    // The send was claimed and its reply lost: this process reports the
    // transport failure, never success or a retryable failure.
    assert.equal(run.error?.code, 'ECONNRESET');
    assert.equal(sent, 1);
    await host.close();
    const second = await effectHost(t, installation, state);
    const continuation = JSON.parse(
      host.outcomes[0].stage.continuationWire);
    const accepted = run.accepted ?? run.error.accepted;
    const resumed = await second.resume('lost-reply',
      accepted.ref.runDefinitionCid, continuation).then(value => value,
      error => ({error}));
    assert.equal(resumed.result?.status, 'needs_reconciliation',
      String(resumed.error?.code));
    assert.equal(writesOf(installation.org).length, sent);
  });

test('each member writes only under its own tuple\'s commit decision for the Set',
  async t => {
    const cases = [
      ['missing tuple', decisions => decisions.slice(0, 1)],
      ['another tuple reused', decisions => [decisions[0], decisions[0]]],
      // Genuine dispatch decisions of the same gate, for another sealed Set.
      ['another Set', (decisions, foreign) => foreign],
      ['copied decision', decisions => decisions.map(decision =>
        ({...decision}))],
    ];
    for (const [label, alter] of cases) {
      const installation = await installedEffect(t, {writes: [update, other],
        org: {writableObjects: ['Other_Record__c']},
        entries: twoTargets('00D000000000001EAA')});
      let foreign;
      const host = await effectHost(t, installation,
        join(installation.root, 'host'), {wrapStage: stage => ({...stage,
          apply: {...stage.apply,
            async refreshPreflight(facts) {
              const {gate, scopes} = stage.apply.authorization;
              foreign = [];
              for (const scope of scopes) {
                foreign.push(await gate.authorize('effect_commit',
                  {...scope, operation: 'effect'},
                  {subjectCid: `sha256:${'9'.repeat(64)}`}));
              }
              return stage.apply.refreshPreflight(facts);
            },
            bindDispatch: facts => stage.apply.bindDispatch({...facts,
              decisions: alter(facts.decisions, foreign)})}})});
      const failure = await host.run(updateProgram(host.installed.mappings),
        `commit-${label.replaceAll(' ', '-')}`).then(() => undefined,
        error => error);
      assert.ok(['SalesforceEffectCommitNotAuthorized',
        'SalesforceCredentialGrantNotAuthorized'].includes(failure?.code),
      `${label}: ${failure?.code}`);
      assert.equal(writesOf(installation.org).length, 0, label);
    }
  });
