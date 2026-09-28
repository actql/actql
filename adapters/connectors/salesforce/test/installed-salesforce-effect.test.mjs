import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {accountConfiguration, effectHost, effectProgram, installedEffect,
  recordEntry} from './installed-salesforce-effect.fixture.mjs';
import {closeFailingJournal} from './salesforce-effect-site.fixture.mjs';
import {loadInstalledSalesforceSource} from
  '../host/installed-salesforce-source.mjs';
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

test('a rejected row fails, halts its member and is never retried',
  async t => {
    const installation = await installedEffect(t, {writes: [update],
      org: {rejectWrites: [2]}});
    const state = join(installation.root, 'host');
    const host = await effectHost(t, installation, state);
    const run = await host.run(updateProgram(host.installed.mappings,
      [...ids, 'a00000000000003'].map(id => ({id}))), 'partial-set')
      .then(value => value, error => ({error}));
    // The first row applied. Salesforce rejected the second with a 400
    // INVALID_FIELD error before saving it: a definite failure. The third
    // is never sent under halt, so the Run fails.
    assert.equal(run.started?.value?.status, 'failed',
      String(run.error?.code));
    assert.equal(writesOf(installation.org).length, 2);
    const [, rejected] = host.outcomes[0].stage.receipt.members[0].rowOwners;
    const entry = host.outcomes[0].stage.apply.ledger.readClaimedOutcome(
      rejected.claim);
    assert.deepEqual(JSON.parse(entry.outcomeJson).typed_outcome, {state: 'failed',
      error: {code: 'SalesforceWriteRejected',
        message: 'Salesforce rejected the write before saving it',
        details: {http_status: 400,
          errors: [{error_code: 'INVALID_FIELD', fields: ['Name']}]}}});
    await host.close();
    // A restart settles nothing new and sends nothing.
    const second = await effectHost(t, installation, state);
    const resumed = await second.resume('partial-set',
      run.accepted.ref.runDefinitionCid,
      JSON.parse(host.outcomes[0].stage.continuationWire))
      .then(value => value, error => ({error}));
    assert.notEqual(resumed.result?.status, 'succeeded');
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

// A loader that fails after acquiring its Site: the load's own failure stays
// the error, and an incomplete Site release travels with it as the caller's
// retry responsibility (the Host's initialization cleanup contract).
test('a failed Salesforce loader keeps its cause and hands over the Site release',
  async t => {
    const installation = await installedEffect(t, {writes: [update]});
    // Effect load: the published generation no longer matches the writes.
    const effectJournal = closeFailingJournal(1);
    const effectFailure = await installation.load({writes: [{...update,
      fields: ['Name', 'External_Key__c']}]},
    {openCredentialJournal: effectJournal.open}).then(() => undefined,
      error => error);
    assert.equal(effectFailure.code, 'SalesforceEffectPublicationMismatch');
    assert.equal(effectFailure.cleanupPending, true);
    assert.deepEqual(effectFailure.cleanupErrors.map(error => error.code),
      ['InjectedJournalCloseFailure']);
    assert.equal((await effectFailure.cleanupHandle.retry()).pending, false);
    assert.equal(effectJournal.calls.close, 2);
    // Source load: its publication is missing.
    const sourceJournal = closeFailingJournal(1);
    const sourceFailure = await loadInstalledSalesforceSource({
      version: 'actql-installed-salesforce-source/0.1',
      siteProfilePath: installation.profile.siteProfilePath,
      publicationPath: join(installation.root, 'missing-source.json'),
      connectorId: 'salesforce', resources: ['Test_Record__c'],
      accountConfigurationWire: installation.profile.accountConfigurationWire,
    }, {...installation.options, openCredentialJournal: sourceJournal.open})
      .then(() => undefined, error => error);
    assert.equal(sourceFailure.code, 'SalesforcePublicationMissing');
    assert.equal(sourceFailure.cleanupPending, true);
    assert.equal((await sourceFailure.cleanupHandle.retry()).pending, false);
    assert.equal(sourceJournal.calls.close, 2);
    // A publication whose describe cannot run (the Resource is not
    // declared) keeps that failure, not the release failure.
    const failedPublish = closeFailingJournal(1);
    const publishFailure = await installation.publish({writes: [{
      resource: 'Not_Declared__c', kind: 'update', fields: ['Name']}]},
    {openCredentialJournal: failedPublish.open}).then(() => undefined,
      error => error);
    assert.equal(publishFailure.code, 'SalesforceCatalogDescribeNotAuthorized');
    assert.equal(publishFailure.cleanupPending, true);
    assert.equal((await publishFailure.cleanupHandle.retry()).pending, false);
    // A successful publication whose release fails reports that release
    // failure with its retry; the generation it wrote stays published.
    const publishedJournal = closeFailingJournal(1);
    const releaseFailure = await installation.publish({},
      {openCredentialJournal: publishedJournal.open}).then(() => undefined,
      error => error);
    assert.equal(releaseFailure.code, 'InjectedJournalCloseFailure');
    assert.equal(releaseFailure.cleanupPending, true);
    assert.equal(publishedJournal.calls.close, 1);
    assert.equal((await releaseFailure.cleanupHandle.retry()).pending, false);
    assert.equal(publishedJournal.calls.close, 2);
    assert.ok(await installation.load());
  });

// Non-success replies to the first write of a two-row halted member. A
// documented rejection is a definite failure recorded in the Ledger; every
// other reply keeps the row unknown. Either way the Run never resends it,
// even after a restart.
test('non-success Salesforce write replies settle only on documented rejections',
  async t => {
    const error = (errorCode, fields) => [{message: 'provider detail 42',
      errorCode, ...(fields === undefined ? {} : {fields})}];
    const cases = [
      ['403 request limit', {status: 403,
        body: error('REQUEST_LIMIT_EXCEEDED')}, 'failed',
      {code: 'SalesforceWriteRejected', http_status: 403,
        errors: [{error_code: 'REQUEST_LIMIT_EXCEEDED', fields: []}]}],
      ['400 with an undeclared field', {status: 400,
        body: error('INVALID_FIELD', ['Name', 'Secret__c'])}, 'failed',
      {code: 'SalesforceWriteRejected', http_status: 400,
        errors: [{error_code: 'INVALID_FIELD', fields: ['Name']}]}],
      ['404 record not found', {status: 404, body: error('NOT_FOUND')},
        'failed', {code: 'SalesforceWriteRejected', http_status: 404,
          errors: [{error_code: 'NOT_FOUND', fields: []}]}],
      ['500 provider error', {status: 500, body: error('UNKNOWN_EXCEPTION')},
        'needs_reconciliation'],
      ['503 unavailable', {status: 503, body: error('SERVER_UNAVAILABLE')},
        'needs_reconciliation'],
      ['400 proxy page', {status: 400, raw: '<html>Bad Request</html>'},
        'needs_reconciliation'],
      ['400 uncertainty code', {status: 400,
        body: error('SERVER_UNAVAILABLE')}, 'needs_reconciliation'],
    ];
    for (const [label, reply, expected, failure] of cases) {
      const installation = await installedEffect(t, {writes: [update],
        org: {writeReplies: {1: reply}}});
      const state = join(installation.root, 'host');
      const host = await effectHost(t, installation, state);
      const run = await host.run(updateProgram(host.installed.mappings),
        `reply-${label.replaceAll(' ', '-')}`)
        .then(value => value, value => ({error: value}));
      assert.equal(run.started?.value?.status, expected,
        `${label}: ${run.error?.code}`);
      // The first row was sent once; under halt the second never was.
      assert.equal(writesOf(installation.org).length, 1, label);
      const {stage} = host.outcomes[0];
      const outcome = stage.apply.ledger.readClaimedOutcome(
        stage.receipt.members[0].rowOwners[0].claim);
      if (failure === undefined) {
        assert.equal(outcome, undefined, label);
      } else {
        const typed = JSON.parse(outcome.outcomeJson).typed_outcome;
        assert.equal(typed.state, 'failed', label);
        assert.deepEqual({code: typed.error.code, ...typed.error.details},
          failure, label);
        assert.equal(JSON.stringify(typed).includes('provider detail'), false);
      }
      await host.close();
      // A restart sends nothing more for this Set.
      const second = await effectHost(t, installation, state);
      await second.resume(`reply-${label.replaceAll(' ', '-')}`,
        run.accepted.ref.runDefinitionCid,
        JSON.parse(stage.continuationWire)).catch(() => undefined);
      assert.equal(writesOf(installation.org).length, 1, `${label} restart`);
    }
  });

// Salesforce documents an upsert 300 as writing nothing, but the credential
// transport refuses every 3xx as a redirect before reading its body. The
// sent row therefore stays unknown and is never resent: the gap is in the
// transport, not in the classification.
test('an upsert 300 stays unknown: the transport refuses it as a redirect',
  async t => {
    const installation = await installedEffect(t, {writes: [{
      resource: 'Test_Record__c', kind: 'upsert', key: 'External_Key__c',
      fields: ['Name']}], writeOperation: 'upsert',
    org: {writeReplies: {1: {status: 300, body: [
      '/services/data/v62.0/sobjects/Test_Record__c/a01',
      '/services/data/v62.0/sobjects/Test_Record__c/a02']}}}});
    const state = join(installation.root, 'host');
    const host = await effectHost(t, installation, state);
    const [mapping] = host.installed.mappings;
    const program = effectProgram({save: {upsert: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}, key: 'id',
      set: {Name: {field: 'id'}}}}}, ids.map(id => ({id})));
    const run = await host.run(program, 'upsert-300').then(value => value,
      error => ({error}));
    assert.equal(run.error?.code, 'RemoteCredentialRedirectRejected');
    assert.equal(writesOf(installation.org).length, 1);
    const {stage} = host.outcomes[0];
    assert.equal(stage.apply.ledger.readClaimedOutcome(
      stage.receipt.members[0].rowOwners[0].claim), undefined);
    await host.close();
    const second = await effectHost(t, installation, state);
    const resumed = await second.resume('upsert-300',
      run.error.accepted.ref.runDefinitionCid,
      JSON.parse(stage.continuationWire));
    assert.equal(resumed.result.status, 'needs_reconciliation');
    assert.equal(writesOf(installation.org).length, 1);
  });
