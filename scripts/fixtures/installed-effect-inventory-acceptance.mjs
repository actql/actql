// Shared source/packed acceptance. The only supplied production ports are
// the public Client, installed HTTP Host, and Effect publication APIs. The
// fixtures below answer HTTPS as GitHub; they replace no execution owner.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fixtureCertificates, openHttpsExchangeFixture} from
  '../../adapters/site-node/https-exchange-fixture.mjs';
import {commentSends, graphqlRoute} from
  '../../adapters/connectors/github/test/github-graphql.fixture.mjs';

const terminal = ['succeeded', 'failed', 'needs_reconciliation', 'cancelled'];
const canonical = value => JSON.stringify(value, function (_key, member) {
  return member !== null && typeof member === 'object' && !Array.isArray(member)
    ? Object.fromEntries(Object.keys(member).sort().map(key => [key, member[key]]))
    : member;
});
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki',
  format: 'pem'});

async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('InstalledEffectInventoryAcceptanceTimeout');
}

// Waiting is visible before its producer retires temporary resources. The
// original stop receipt can legitimately advance the control revision. Read
// acceptance compares revisions only after that existing Owner confirms stop.
export async function waitForInstalledCheckpointPhysicalStop(execution) {
  return waitFor(async () => {
    const state = await execution.status();
    assert.equal(state.status, 'waiting_checkpoint');
    return state.control?.physical_stop === 'confirmed' ? state : undefined;
  });
}

// These provider tables, input rows, and expected output rows/transcripts
// are authored independently. No expected data comes from product output.
const providers = [
  {name: 'alpha', repositoryId: 'R_ALPHA', databaseId: 4101,
    subjectId: 'I_ALPHA', number: 7},
  {name: 'beta', repositoryId: 'R_BETA', databaseId: 4202,
    subjectId: 'I_BETA', number: 9},
];
const successes = [
  {nonce: 'forward-alpha', selected: 0, order: [0, 1],
    rows: [{node_id: 'I_ALPHA', comment: 'alpha forward'}],
    result: [{node_id: 'I_ALPHA', comment: 'alpha forward'}],
    variables: {subjectId: 'I_ALPHA', body: 'alpha forward'},
    comment: {subjectId: 'I_ALPHA', body: 'alpha forward', databaseId: 1000}},
  {nonce: 'forward-beta', selected: 1, order: [0, 1],
    rows: [{node_id: 'I_BETA', comment: 'beta forward'}],
    result: [{node_id: 'I_BETA', comment: 'beta forward'}],
    variables: {subjectId: 'I_BETA', body: 'beta forward'},
    comment: {subjectId: 'I_BETA', body: 'beta forward', databaseId: 1000}},
  {nonce: 'reverse-alpha', selected: 0, order: [1, 0],
    rows: [{node_id: 'I_ALPHA', comment: 'alpha reverse'}],
    result: [{node_id: 'I_ALPHA', comment: 'alpha reverse'}],
    variables: {subjectId: 'I_ALPHA', body: 'alpha reverse'},
    comment: {subjectId: 'I_ALPHA', body: 'alpha reverse', databaseId: 1001}},
  {nonce: 'reverse-beta', selected: 1, order: [1, 0],
    rows: [{node_id: 'I_BETA', comment: 'beta reverse'}],
    result: [{node_id: 'I_BETA', comment: 'beta reverse'}],
    variables: {subjectId: 'I_BETA', body: 'beta reverse'},
    comment: {subjectId: 'I_BETA', body: 'beta reverse', databaseId: 1001}},
];

function providerState(provider) {
  return {repositories: new Map([[provider.repositoryId, {
    databaseId: provider.databaseId, nameWithOwner: `fixture/${provider.name}`,
    issues: []}]]), names: new Map([[`fixture/${provider.name}`,
    provider.repositoryId]]), subjects: new Map([[provider.subjectId, {
    type: 'Issue', repository: provider.repositoryId, number: provider.number}]]),
  comments: []};
}

function accountConfiguration(connections) {
  connections = [...connections].sort();
  const entry = (entry_id, outcome, operation, resource) => ({entry_id, outcome,
    exclusions: [], principal: {all: true}, connection: {any_of: connections},
    resource: {any_of: resource}, operation: {any_of: [operation]}});
  return canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'effect-inventory-fixture', entries: [
      entry('comment-commit', 'delegate', 'effect', ['issue_comments']),
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}},
      // Observing the original Run and its named Result is separate from
      // submission and provider access. Grant only this fixture's owner.
      {entry_id: 'host-run-result-read', outcome: 'allow', exclusions: [],
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}},
      entry('target-read', 'allow', 'read', ['issue_comments', 'issues']),
    ]});
}

function program(mappings, rows) {
  return JSON.stringify({version: 'actql/0.1', id: 'effect-inventory',
    stages: [{id: 'source', inputs: {}, steps: [{values: {schema: {
      node_id: {type: 'string', nullable: false},
      comment: {type: 'string', nullable: false}}, rows}, as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['node_id', 'comment']}},
    effects: Object.fromEntries(mappings.map((mapping, index) => [
      index === 0 ? 'comment' : `comment_${index}`, {create: {
        target: mapping.target, mapping: mapping.mappingRef,
        from: {result: 'rows'}}}]))}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}});
}

export async function runInstalledEffectInventoryAcceptance({connect,
  openInstalledRemoteHttpHost, publishEffect, profile = 'inventory',
  observeWaitingCheckpoint}) {
  assert.ok(['inventory', 'observability', 'checkpoint-review'].includes(profile));
  if (profile === 'checkpoint-review') {
    assert.equal(typeof observeWaitingCheckpoint, 'function');
  } else assert.equal(observeWaitingCheckpoint, undefined);
  // Telemetry acceptance reuses the real lifecycle without repeating the
  // independent provider-position matrix or legacy installation control.
  const selectedSuccesses = profile === 'inventory' ? successes : [successes[0]];
  for (const port of [connect, openInstalledRemoteHttpHost, publishEffect]) {
    assert.equal(typeof port, 'function');
  }
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-inventory-'));
  const owned = [];
  const own = close => {
    let closed = false;
    const once = async () => {
      if (closed) return;
      await close();
      closed = true;
    };
    owned.push(once);
    return once;
  };
  const originalCAs = getCACertificates('default');
  let failure;
  try {
    const tlsRoot = join(root, 'host-tls');
    await mkdir(tlsRoot);
    const tls = await fixtureCertificates(tlsRoot);
    setDefaultCACertificates([...originalCAs, tls.ca.toString('utf8')]);
    const reviewerKeys = generateKeyPairSync('ed25519');
    const hostKeys = generateKeyPairSync('ed25519');
    const tokens = new Map([['synthetic-owner-token', userInfo().username],
      ['synthetic-reviewer-token', 'inventory-reviewer-principal']]);
    const signer = {keyId: 'inventory-reviewer-key', reviewerId: 'inventory-reviewer',
      sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
    const installations = [];
    const counts = {dispatch: 0, secrets: [0, 0]};
    for (const provider of providers) {
      const state = providerState(provider);
      const api = await openHttpsExchangeFixture(undefined, {
        routes: [graphqlRoute(() => state)],
        faults: provider.name === 'beta' ? [{kind: 'apply-then-lose-reply',
          method: 'POST', pathname: '/graphql', bodyIncludes: 'beta lost reply'}] : [],
      });
      own(api.close);
      const directory = join(root, provider.name);
      await mkdir(directory);
      const authority = generateKeyPairSync('ed25519');
      const keyPath = join(directory, 'credential.key');
      await writeFile(keyPath, pem(authority.privateKey), {mode: 0o600});
      const sitePath = join(directory, 'site.json');
      const journalRoot = join(directory, 'credential-journal');
      await writeFile(sitePath, JSON.stringify({
        version: 'actql-installed-github-site/0.1', apiOrigin: api.origin,
        owner: 'fixture', repo: provider.name, namespaceId: `namespace-${provider.name}`,
        environment: 'test', siteKey: `site-${provider.name}`, siteGeneration: 1,
        credentialAuthorityId: `authority-${provider.name}`,
        credentialKeyId: `key-${provider.name}`, credentialPrivateKeyPath: keyPath,
        journalRoot, tokenEnvironment: `ACTQL_SYNTHETIC_${provider.name.toUpperCase()}_TOKEN`,
        caPath: api.caPath}));
      installations.push({...provider, api, state, sitePath, journalRoot,
        effectProfilePath: join(directory, 'effect.json'),
        publicationPath: join(directory, 'publication.json'),
        connection: `github:${new URL(api.origin).host}/fixture/${provider.name}`});
    }
    const configuration = accountConfiguration(installations.map(item => item.connection));
    const resolveEffectSecret = async scope => {
      const index = installations.findIndex(item => scope.siteKey === `site-${item.name}`);
      assert.ok(index >= 0, 'secret callback must name an installed Site');
      const selected = installations[index];
      assert.equal(scope.resourceOrigin, selected.api.origin);
      assert.equal(scope.namespaceId, `namespace-${selected.name}`);
      assert.equal(scope.connectorRegistration, 'github');
      counts.secrets[index]++;
      return `synthetic-ephemeral-${selected.name}-token`;
    };
    const hostRoot = join(root, 'state');
    for (const item of installations) {
      await writeFile(item.effectProfilePath, JSON.stringify({
        version: 'actql-installed-github-effect/0.1', siteProfilePath: item.sitePath,
        publicationPath: item.publicationPath, connectorId: `gh-${item.name}`,
        accountConfigurationWire: configuration,
        writes: [{resource: 'issue_comments', sources: [
          {target: 'subject_id', field: 'node_id', null_behavior: 'reject'},
          {target: 'body', field: 'comment', null_behavior: 'reject'}]}]}));
      const published = await publishEffect({directory: hostRoot,
        effectProfilePath: item.effectProfilePath, resolveEffectSecret});
      assert.equal(published.mappings.length, 1);
      item.mapping = published.mappings[0];
    }
    assert.notEqual(installations[0].mapping.mappingRef, installations[1].mapping.mappingRef);
    assert.notEqual(installations[0].mapping.mappingCid, installations[1].mapping.mappingCid);
    const journals = await Promise.all(installations.map(item => stat(
      join(item.journalRoot, 'credential-journal.sqlite3'))));
    assert.notEqual(`${journals[0].dev}:${journals[0].ino}`,
      `${journals[1].dev}:${journals[1].ino}`, 'Sites must not share a credential journal');
    const observation = index => ({requests: installations[index].api.seen().length,
      secrets: counts.secrets[index], sends: commentSends(installations[index].api).length});
    assert.deepEqual([observation(0), observation(1)], [
      {requests: 1, secrets: 1, sends: 0}, {requests: 1, secrets: 1, sends: 0},
    ], 'publication performs exactly its own repository lookup');

    const authorization = {accountConfiguration: configuration,
      reviewers: [{keyId: 'inventory-reviewer-key', reviewerId: 'inventory-reviewer',
        principalId: 'inventory-reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}],
      reviewReaders: ['inventory-reviewer-principal'],
      hostKey: {keyId: 'inventory-host-key', privateKey: pem(hostKeys.privateKey)},
      leaseMs: 10_000, resumeAfterAnswer: false};
    async function openHost(order, {singular = false, directory = hostRoot} = {}) {
      const host = await openInstalledRemoteHttpHost({directory,
        authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
        ...(singular ? {effectProfilePath: installations[order[0]].effectProfilePath}
          : {effectProfilePaths: order.map(index => installations[index].effectProfilePath)}),
        resolveEffectSecret, authorization, beforeDispatch: () => {counts.dispatch++;}});
      const closeHost = own(() => host.close());
      const server = createServer({key: tls.key, cert: tls.cert}, host.handler);
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
      });
      const closeServer = own(async () => {
        server.closeAllConnections?.();
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      });
      const clients = [];
      return {async as(token = 'synthetic-owner-token') {
        const client = await connect({mode: 'remote', durability: 'durable', token,
          endpoint: `https://127.0.0.1:${server.address().port}/`});
        clients.push(own(() => client.close()));
        return client;
      }, async close() {
        const results = await Promise.allSettled(clients.map(close => close()));
        await closeServer();
        await closeHost();
        const errors = results.filter(result => result.status === 'rejected').map(result => result.reason);
        if (errors.length) throw new AggregateError(errors, 'ClientCleanupFailed');
      }};
    }

    async function original(client, saved) {
      const lookup = await client.lookupSubmission(saved.submissionRef);
      assert.equal(lookup.kind, 'ready', JSON.stringify(lookup));
      assert.deepEqual(lookup.submissionRef, saved.submissionRef);
      assert.deepEqual(lookup.admission.ref, saved.runRef);
      return client.attach(lookup.admission.ref);
    }
    async function submit(host, nonce, wire) {
      const client = await host.as();
      const submissionRef = client.newSubmission({nonce});
      // Persist before sending; every reconnect below reads the original
      // reference instead of allocating a nonce under the new Host epoch.
      const savedPath = join(root, `${nonce}.json`);
      await writeFile(savedPath, JSON.stringify({submissionRef}));
      const execution = await client.startSource(wire, {format: 'json', submissionRef});
      await writeFile(savedPath, JSON.stringify({submissionRef, runRef: execution.ref}));
      const state = await waitFor(async () => {
        const current = await execution.status();
        return current.status === 'waiting_checkpoint' || terminal.includes(current.status)
          ? current : undefined;
      });
      assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(state));
      await original(client, JSON.parse(await readFile(savedPath, 'utf8')));
      return savedPath;
    }
    async function approve(host, saved) {
      const reviewer = await host.as('synthetic-reviewer-token');
      const checkpoints = (await reviewer.checkpoints()).items;
      assert.equal(checkpoints.length, 1, 'one existing Set approval owner');
      assert.equal(checkpoints[0].kind, 'effect_set');
      const answer = await reviewer.resolveCheckpoints([
        {checkpoint: checkpoints[0], decision: 'approved'}],
      {signer: {...signer, authorityScopeCid: saved.runRef.authorityScopeCid}});
      assert.deepEqual(answer.results.map(item => item.status), ['committed']);
    }
    async function finishAfterRestart(savedPath, order, expectedStatus, hostOptions) {
      const saved = JSON.parse(await readFile(savedPath, 'utf8'));
      const host = await openHost(order, hostOptions);
      const execution = await original(await host.as(), saved);
      const state = await waitFor(async () => {
        const current = await execution.status();
        return terminal.includes(current.status) ? current : undefined;
      });
      assert.equal(state.status, expectedStatus, JSON.stringify(state));
      return {host, execution, state, saved};
    }

    // Both owners occupy both positions, each through a separate public Run.
    // Reversing order while approval is durable must select the original owner.
    for (const expected of selectedSuccesses) {
      const selected = installations[expected.selected];
      const unselected = 1 - expected.selected;
      const untouched = observation(unselected);
      const sentBefore = commentSends(selected.api).length;
      const dispatchBefore = counts.dispatch;
      const first = await openHost(expected.order);
      assert.deepEqual(observation(unselected), untouched);
      const path = await submit(first, expected.nonce, program([selected.mapping], expected.rows));
      assert.ok(counts.dispatch > dispatchBefore, 'the successful control reaches dispatch');
      assert.equal(commentSends(selected.api).length, sentBefore);
      if (profile === 'checkpoint-review') {
        // Observe a real waiting Set through the public Client and installed
        // Explorer. No answer or resume is needed to read its original review.
        const saved = JSON.parse(await readFile(path, 'utf8'));
        const before = installations.map((_, index) => observation(index));
        const observations = [];
        const observe = async (host, phase) => {
          const execution = await original(await host.as(), saved);
          const state = await waitForInstalledCheckpointPhysicalStop(execution);
          assert.equal(state.status, 'waiting_checkpoint');
          const dispatchBeforeReview = counts.dispatch;
          const result = await observeWaitingCheckpoint({
            client: await host.as('synthetic-reviewer-token'),
            phase, original: saved, expectedRows: expected.rows,
            expectedRunId: state.run_id,
          });
          assert.equal(counts.dispatch, dispatchBeforeReview,
            'review reads cannot start another Run or redispatch the original');
          const after = await execution.status();
          assert.equal(after.status, 'waiting_checkpoint');
          assert.equal(after.run_id, state.run_id);
          assert.equal(after.control.revision, state.control.revision);
          assert.deepEqual(installations.map((_, index) => observation(index)), before,
            'review reads cannot reacquire a provider, issue a credential or send an Effect');
          observations.push(result);
        };
        await observe(first, 'original');
        await first.close();
        const reopened = await openHost([...expected.order].reverse());
        await observe(reopened, 'restarted');
        await reopened.close();
        // Keep the original pending Set, captures and test installation for
        // audit. Physical Hosts close; no cancel, resolution, replay or reset.
        return {profile, retainedRoot: root, original: saved, observations,
          waitingRuns: 1, answers: 0, resumes: 0,
          callbackCounts: {dispatch: counts.dispatch, secrets: [...counts.secrets]},
          providerSends: installations.map(item => commentSends(item.api).length)};
      }
      await first.close();
      const reversed = [...expected.order].reverse();
      const review = await openHost(reversed);
      await approve(review, JSON.parse(await readFile(path, 'utf8')));
      await review.close();
      assert.equal(commentSends(selected.api).length, sentBefore, 'approval alone sends nothing');
      const resumed = await finishAfterRestart(path, expected.order, 'succeeded');
      assert.deepEqual(await resumed.execution.result('answer').all(), expected.result);
      assert.deepEqual(commentSends(selected.api).slice(sentBefore).map(request => request.variables),
        [expected.variables]);
      assert.deepEqual(selected.state.comments.slice(sentBefore), [expected.comment]);
      await resumed.host.close();
      const settled = observation(expected.selected);
      const repeated = await finishAfterRestart(path, reversed, 'succeeded');
      assert.deepEqual(await repeated.execution.result('answer').all(), expected.result);
      await repeated.host.close();
      assert.deepEqual(observation(expected.selected), settled, 'restart never resends a completed comment');
      assert.deepEqual(observation(unselected), untouched, 'unselected provider and secret callback stay idle');
    }

    // The initial mixed-owner profile is one VALUES Unit. A mixed Set with
    // an additional Unit is still refused by installation preparation. An absent
    // Mapping may be refused earlier by ordinary checking. Neither branch
    // admits a Run, reaches dispatch, reads a credential, or calls a provider.
    for (const [nonce, mappings] of [
      ['unsupported-mixed-multistage-set', installations.map(item => item.mapping)],
      ['absent-mapping', [{...installations[0].mapping,
        mappingRef: 'mapping:gh-absent/issue_comments/create-0000000000000000.v1'}]],
    ]) {
      const before = {dispatch: counts.dispatch, providers: [observation(0), observation(1)]};
      const host = await openHost([1, 0]);
      const client = await host.as();
      const submissionRef = client.newSubmission({nonce});
      const authored = JSON.parse(program(mappings,
        [{node_id: 'I_ALPHA', comment: 'must never be sent'}]));
      if (nonce === 'unsupported-mixed-multistage-set') {
        const {effects: _effects, ...values} = authored.stages[0];
        authored.stages.unshift({...values, id: 'prelude'});
      }
      await assert.rejects(client.startSource(JSON.stringify(authored), {format: 'json', submissionRef}));
      const refused = await client.lookupSubmission(submissionRef);
      assert.deepEqual(refused.submissionRef, submissionRef);
      if (nonce === 'unsupported-mixed-multistage-set') {
        assert.equal(refused.kind, 'preparation_failed');
        assert.equal(refused.problem.code, 'ClientProgramUnsupported');
      } else assert.ok(['not_accepted', 'preparation_failed'].includes(refused.kind), JSON.stringify(refused));
      assert.equal(refused.admission, undefined, 'preparation refusal has no Run');
      assert.deepEqual((await (await host.as('synthetic-reviewer-token')).checkpoints()).items, []);
      await host.close();
      assert.deepEqual({dispatch: counts.dispatch, providers: [observation(0), observation(1)]}, before);
    }

    // Cancelling a held Set keeps its original Run identity
    // and retires the capture without sending or activating the other Site.
    const betaBeforeCancel = observation(1);
    const alphaSendsBeforeCancel = commentSends(installations[0].api).length;
    const cancelFirst = await openHost([1, 0]);
    const cancelPath = await submit(cancelFirst, 'cancelled-alpha',
      program([installations[0].mapping],
        [{node_id: 'I_ALPHA', comment: 'must be cancelled'}]));
    const cancelled = await original(await cancelFirst.as(),
      JSON.parse(await readFile(cancelPath, 'utf8')));
    // The Checkpoint can be visible before its producer finishes cleanup.
    // Observe that owner's persisted stop receipt before admitting the one
    // cancellation, so its revision cannot race the remaining cleanup step.
    const cancelState = await waitFor(async () => {
      const current = await cancelled.status();
      assert.equal(terminal.includes(current.status), false, JSON.stringify(current));
      return current.status === 'waiting_checkpoint' &&
        current.control?.physical_stop === 'confirmed' ? current : undefined;
    });
    assert.equal(cancelState.control.cancellation_requested, false);
    await cancelled.cancel();
    await waitFor(async () => (await cancelled.status()).status === 'cancelled');
    await cancelFirst.close();
    const afterCancel = observation(0);
    const cancelledAgain = await finishAfterRestart(cancelPath, [0, 1], 'cancelled');
    await cancelledAgain.host.close();
    assert.equal(commentSends(installations[0].api).length, alphaSendsBeforeCancel);
    assert.deepEqual(observation(0), afterCancel, 'cancelled recovery starts no provider work');
    assert.deepEqual(observation(1), betaBeforeCancel);

    const alphaBeforeLost = observation(0);
    const betaSends = commentSends(installations[1].api).length;
    const lostFirst = await openHost([1, 0]);
    const lostPath = await submit(lostFirst, 'lost-beta-response', program([installations[1].mapping],
      [{node_id: 'I_BETA', comment: 'beta lost reply'}]));
    await lostFirst.close();
    const lostReview = await openHost([0, 1]);
    await approve(lostReview, JSON.parse(await readFile(lostPath, 'utf8')));
    await lostReview.close();
    assert.equal(commentSends(installations[1].api).length, betaSends);
    const lost = await finishAfterRestart(lostPath, [1, 0], 'needs_reconciliation');
    assert.deepEqual(lost.state.next_action, {effects: ['comment'], kind: 'reconcile'});
    assert.deepEqual(commentSends(installations[1].api).slice(betaSends).map(request => request.variables),
      [{subjectId: 'I_BETA', body: 'beta lost reply'}]);
    assert.deepEqual(installations[1].state.comments.slice(betaSends),
      [{subjectId: 'I_BETA', body: 'beta lost reply',
        databaseId: profile === 'observability' ? 1000 : 1002}]);
    assert.equal(installations[1].api.remainingFaults(), 0);
    await lost.host.close();
    const betaAfterLost = observation(1);
    const lostAgain = await finishAfterRestart(lostPath, [0, 1], 'needs_reconciliation');
    assert.deepEqual(lostAgain.state.next_action, {effects: ['comment'], kind: 'reconcile'});
    await lostAgain.host.close();
    assert.deepEqual(observation(1), betaAfterLost, 'unknown outcomes never trigger another provider attempt');
    assert.deepEqual(observation(0), alphaBeforeLost);

    if (profile === 'inventory') {
      // Legacy singular options use the same published profile and real owner.
      const singularOptions = {singular: true, directory: join(root, 'singular-state')};
      const betaBeforeSingular = observation(1);
      const singularSends = commentSends(installations[0].api).length;
      const singularFirst = await openHost([0], singularOptions);
      const singularPath = await submit(singularFirst, 'singular-alpha-control',
        program([installations[0].mapping], [{node_id: 'I_ALPHA', comment: 'alpha singular'}]));
      await singularFirst.close();
      const singularReview = await openHost([0], singularOptions);
      await approve(singularReview, JSON.parse(await readFile(singularPath, 'utf8')));
      await singularReview.close();
      const singular = await finishAfterRestart(singularPath, [0], 'succeeded', singularOptions);
      assert.deepEqual(await singular.execution.result('answer').all(),
        [{node_id: 'I_ALPHA', comment: 'alpha singular'}]);
      assert.deepEqual(commentSends(installations[0].api).slice(singularSends).map(request => request.variables),
        [{subjectId: 'I_ALPHA', body: 'alpha singular'}]);
      assert.deepEqual(installations[0].state.comments.slice(singularSends),
        [{subjectId: 'I_ALPHA', body: 'alpha singular', databaseId: 1002}]);
      await singular.host.close();
      assert.deepEqual(observation(1), betaBeforeSingular);
    }
    return {successfulPluralRuns: selectedSuccesses.length,
      preparationRefusals: 2, cancelledWithoutSend: 1,
      unknownAfterRestart: 1, singularControl: profile === 'inventory' ? 1 : 0,
      distinctCredentialJournals: 2,
      callbackCounts: {dispatch: counts.dispatch, secrets: [...counts.secrets]},
      providerSends: installations.map(item => commentSends(item.api).length)};
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const errors = [];
    for (const close of owned.reverse()) {
      try { await close(); } catch (error) { errors.push(error); }
    }
    setDefaultCACertificates(originalCAs);
    if (failure === undefined && errors.length === 0 && profile !== 'checkpoint-review'
      && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
      try { await rm(root, {recursive: true, force: true}); }
      catch (error) { errors.push(error); }
    } else {
      console.error(`Effect inventory fixture state retained at ${root}`);
    }
    if (errors.length) throw new AggregateError(failure === undefined ? errors : [failure, ...errors],
      'InstalledEffectInventoryAcceptanceCleanupFailed');
  }
}
