// Public Program -> installed Source -> captured Command Preview -> approval
// -> physical storage. The Source supplies refs issued over actual Store bytes;
// Programs do not author opaque envelopes. This fixture is not GCS acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {open, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {openManagedContentSourceFixture} from './managed-content-source.fixture.mjs';
import {setTimeout as delay} from 'node:timers/promises';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {inspect} from 'node:util';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../embedded-local.mjs';
import {connect as connectRemote} from '../../../packages/sdk/index.mjs';
import {fixtureCertificates} from '../../site-node/https-exchange-fixture.mjs';
import {createInstalledConnectorTable} from '../installed-connectors.mjs';
import {installRowSourceAuthorization} from '../installed-row-source.mjs';
import {createInstalledRowEffect} from '../installed-row-effect.mjs';
import {selectInstalledHostEnvironment} from '../installed-host-policy.mjs';
import {contentCommandFixture} from './content-command.fixture.mjs';
import {canonical, cid, resource, token} from './file-listing-source.fixture.mjs';

export async function openContentCommandHost({scratch, generated, keys, entrance,
  allowSourceRead = true, fault, modelInstallation, registerModelProviders, hostCapacityPolicy,
  faultInjection, modelApprovalRequired = false, generatedCommand = false,
  onPrepareContent, prepareContentChild, originalContentValue}) {
  const content = JSON.parse(generated.description.wire);
  const destination = resource('d');
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv',
    classification: modelInstallation === undefined ? 'unknown' : 'internal',
    ...(hostCapacityPolicy === undefined ? {} : {baseEnvironmentWire:
      selectInstalledHostEnvironment(moon, (await readFile(new URL(
        '../../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd(),
      hostCapacityPolicy)})});
  const {evidence_bundle_cid: _, ...hostBody} = JSON.parse(fixture.environmentWire);
  hostBody.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...hostBody.host_policy_profile.capacity};
  const numeric = JSON.parse(await readFile(new URL('../../../spec/contracts/actql-numeric-reduction.json', import.meta.url)));
  const law = JSON.parse(await readFile(new URL('../../../spec/dependencies/actql-graph-laws.json', import.meta.url)));
  const hostEnv = moon.clientProgramCheckEnvironmentWithGraphProfile(
    canonical({...hostBody, evidence_bundle_cid: cid(hostBody)}), cid(hostBody),
    false, true, true, true, true, false, false, cid(numeric), cid(law));
  assert.ok(hostEnv);
  const hostPreparation = moon.clientProgramPrepareEffectComputationWithParameters(
    canonical(fixture.program), 'json', hostEnv, undefined, []);
  assert.ok(moon.clientProgramEffectPreparationReady(hostPreparation),
    inspect(moon.clientProgramEffectPreparationIssue(hostPreparation), {depth: 16}));
  const owner = userInfo().username;
  const account = canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'public-command', entries: [{entry_id: 'fixture-only', outcome: 'allow',
      principal: {all: true}, connection: {any_of: ['fixture:files']}, resource: {all: true},
      operation: {any_of: ['read', 'write']}, exclusions: []},
    {entry_id: 'fixture-effect-approval', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['fixture:files']}, resource: {any_of: ['transfers']},
      operation: {any_of: ['effect']}, exclusions: []},
    {entry_id: 'host-run-acceptance', outcome: 'allow', principal: {all: true},
      connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['row-source-acquired']},
      operation: {any_of: ['write']}, exclusions: []},
    ...(modelInstallation === undefined ? [] : [{entry_id: 'fixture-model-infer',
      outcome: modelApprovalRequired ? 'delegate' : 'allow', principal: {all: true}, connection: {any_of: ['models/fixture']},
      resource: {all: true}, operation: {any_of: ['infer']}, exclusions: []}])]
      .sort((left, right) => left.entry_id < right.entry_id ? -1 : 1)});
  const events = [];
  let reads = 0, sends = 0, writeGrants = 0;
  const projections = [];
  const targetPath = join(scratch.path, 'approved.csv');
  // The common CSV law always quotes Text cells; the plain header needs none.
  const expectedBytes = Buffer.from(generatedCommand ? 'name\n"approved.csv"\n' : 'id\n');
  const expectedContentCid = `sha256:${createHash('sha256').update(expectedBytes).digest('hex')}`;
  let commandStore, generatedHoldingCid;
  const bindStore = async pendingEffect => {
    const effect = await pendingEffect;
    return Object.freeze({...effect,
      prepareCaptured(facts) { commandStore = facts.store; return effect.prepareCaptured(facts); },
      prepareRecovered(facts) { commandStore = facts.store; return effect.prepareRecovered(facts); },
    });
  };
  const checkReference = async request => {
    assert.deepEqual(request.target, destination);
    if (generatedCommand) {
      assert.equal(request.value.name, 'approved.csv');
      const ref = request.value.content;
      assert.equal(ref.media_type, 'text/csv');
      assert.equal(ref.metadata.content_cid, expectedContentCid);
      assert.equal(ref.metadata.size_bytes, expectedBytes.length);
      assert.equal(ref.metadata.issuer_evidence.content_store_cid, commandStore.storeAuthorityCid);
      const holding = await commandStore.inspectPhysicalHolding(generatedHoldingCid);
      assert.equal(holding.namespace, 'content');
      assert.equal(holding.manifest_cid, ref.content_ref_cid);
      assert.deepEqual(holding.objects, [{cid: expectedContentCid, byte_count: expectedBytes.length}]);
      return;
    }
    assert.deepEqual(request.value, {content, name: 'approved.csv'});
    await generated.issue(); // existing custody/current authority, not shape alone
    assert.equal(generated.store.status().storedBytes, 3);
  };
  const requestOf = (value, target) => ({value, target});
  const managedSource = await openManagedContentSourceFixture({scratch, keys, account,
    generated, destination, content, fixture, allowSourceRead, onRead: () => reads++});
  const sourceVersion = 'actql-installed-command-fixture-source/0.1';
  const effectVersion = 'actql-installed-command-fixture-effect/0.1';
  const connectorTable = createInstalledConnectorTable([{name: 'fixture',
    registration: 'fixture', revision: 'fixture/0.1', source: {profileVersion: sourceVersion,
      load: async () => ({check: p => p, identityParts: p => [p],
        async load(_profile, options) {
          const baseIssuer = moon.clientProgramRowReferenceIssuer((kind, wire) =>
            kind === 'file' && wire === canonical(destination),
          (media, wire) => generated.admitsContent === undefined
            ? media === 'text/csv' && wire === generated.description.wire
            : generated.admitsContent(media, wire),
          wire => wire === canonical(destination) ||
            (generated.authorizesReference === undefined
              ? wire === generated.description.wire : generated.authorizesReference(wire)));
          // Reuse an already issued original through the same existing
          // reissuer as installed keyed capture; never recreate it from DATA.
          const issuer = originalContentValue === undefined ? baseIssuer :
            moon.clientProgramRowContentReferenceIssuer(baseIssuer,
              moon.clientProgramCapturedContentReissuer((media, wire) =>
                (media === undefined || media === generated.description.mediaType) &&
                wire === generated.description.wire ? originalContentValue : undefined));
          return managedSource.load(_profile, options, issuer);
        }}),
    }, effect: {profileVersion: effectVersion, load: async () => ({
      check: p => p, identityParts: p => [p], async load(_profile, options) {
        const authorization = await installRowSourceAuthorization({accountConfiguration: account,
          principalId: owner, root: options.root, connectorRegistration: 'fixture'});
        return bindStore(createInstalledRowEffect({moon, environmentWire: fixture.environmentWire,
          connectorId: 'content-fixture', connectorRegistration: 'fixture',
          connectorRevision: 'fixture/0.1', connection: 'fixture:files',
          installation: options.installation, runtimeBundleCid: options.runtimeBundleCid,
          bindingCid: token('c'), ledgerRoot: options.ledgerRoot,
          commands: [{resource: 'transfers', commandRef: fixture.command.command_id,
            commandCid: fixture.command.contract_cid, body: canonical(fixture.command)}],
          authorization, site: {issueReadGrant: () => ({}),
            issueEffectGrant({decision}) {
              assert.equal(decision.action, 'dispatch');
              assert.equal(decision.boundary, 'effect_commit');
              assert.equal(decision.basis, 'resumed');
              writeGrants++;
              return {};
            }, close: () => authorization.close()},
          driver: {kinds: ['command'], writeOperation: () => 'files.write',
            prepareRequest({value, selector, content: originalContent}) {
              onPrepareContent?.({value, selector, originalContent});
              const request = requestOf(value, selector);
              return {request, requestCid: cid(request)};
            }, ...(prepareContentChild === undefined ? {} : {
              prepareRequestChild(context) {
                const request = requestOf(context.value, context.selector);
                return prepareContentChild({...context, originalContent: context.content,
                  preparedRequest: {request, requestCid: cid(request)}});
              }}), requestFacts: request => request, requestCid: cid,
            async recheckRequests({entries}) {
              for (const entry of entries) {
                try { await checkReference(entry.request); }
                catch (error) {
                  events.push({event: 'fixture_reference_rejected', detail: {message: error.message}});
                  throw error;
                }
              }
            }, recoveryEntry: () => {
              const wire = canonical({holding_cid: generatedCommand ? generatedHoldingCid : generated.holding.holding_cid,
                ...(generatedCommand ? {} : {content_ref: content})});
              return {kind: 'fixture-content-store',
                observationCid: cid(JSON.parse(wire)), wire};
            },
            recoverRequests({body, durable}) {
              if (generatedCommand) {
                const entry = durable.connectorRecovery.find(value =>
                  value.memberIndex === 0 && value.kind === 'fixture-content-store');
                assert.ok(entry, 'recover the original saved Content custody, not another generation');
                const saved = JSON.parse(entry.wire);
                assert.equal(entry.observationCid, cid(saved));
                assert.deepEqual(Object.keys(saved), ['holding_cid']);
                assert.match(saved.holding_cid, /^sha256:[0-9a-f]{64}$/u);
                generatedHoldingCid = saved.holding_cid;
              }
              return {currents: [undefined], requests: [body.effects[0].changes.map(change =>
                requestOf(change.intended_changes.value, change.target_row_identity))]};
            }, async send({request}) {
              await checkReference(request);
              const chunks = [];
              await (generatedCommand ? commandStore : generated.store).consumePhysicalHolding(
                generatedCommand ? generatedHoldingCid : generated.holding.holding_cid, 0,
                chunk => chunks.push(Buffer.from(chunk)));
              const bytes = Buffer.concat(chunks);
              assert.deepEqual(bytes, expectedBytes);
              const output = await open(targetPath, 'wx');
              try { await output.writeFile(bytes); await output.sync(); }
              finally { await output.close(); }
              // The fixture receiver retains its own operation fact. Sender
              // response/unknown responsibility remains in the existing Ledger.
              const receipt = await open(join(scratch.path, 'receiver-receipt.json'), 'wx');
              try {
                await receipt.writeFile(canonical({request_cid: cid(request),
                  content_cid: request.value.content.metadata.content_cid}));
                await receipt.sync();
              } finally { await receipt.close(); }
              const directory = await open(scratch.path, 'r');
              try { await directory.sync(); } finally { await directory.close(); }
              sends++;
              if (fault === 'lost_reply') throw new Error('FixtureCommandReplyLost');
              return {observation: {useCid: cid({write: sends}), statusCode: 201,
                body: Buffer.from('{}')}};
            }, project: ({observation}) => {
              projections.push({useCid: observation.useCid, statusCode: observation.statusCode,
                body: Buffer.from(observation.body).toString('utf8')});
              if (fault === 'stop_projection') throw new Error('FixtureCommandProjectionStopped');
              return {kind: 'typed-success-response', outcome: {state: 'applied', result: {}}};
            },
            footprint: () => ({providerNamespace: 'file-fixture', resourceKind: 'file', boundaryCid: token('c')}),
          }}));
      }}),
    }}]);
  const sourceProfilePath = join(scratch.path, 'source.json');
  const effectProfilePath = join(scratch.path, 'effect.json');
  const queryAliases = fixture.declared.views.map(view => ({name: 'files.transfers',
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
    schemaContractCid: view.carrier_schema_cid}));
  await writeFile(sourceProfilePath, canonical({version: sourceVersion, connectorId: 'content-fixture',
    sourceOrigin: managedSource.origin, queryAliases}));
  await writeFile(effectProfilePath, canonical({version: effectVersion}));
  const installation = {directory: join(scratch.path, 'host'), connectorTable, sourceProfilePath,
      effectProfilePath, modelInstallation, registerModelProviders, hostCapacityPolicy,
      resolveSourceSecret: managedSource.resolveSecret,
      authorization: {accountConfiguration: account,
        faultInjection: Object.assign(async (event, facts) => {
          if (event === 'effect_content_generation_retained' ||
              event === 'effect_content_generation_recovered') generatedHoldingCid = facts.holdingCid;
          await faultInjection?.(event, facts);
        }, faultInjection),
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: owner,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        observe: (event, detail) => events.push({event, detail})}};
  let client, server, host, previousCertificates;
  let closed = false;
  const close = async () => {
    if (closed) return;
    await client?.close();
    if (server !== undefined) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
    await managedSource.close();
    if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
    closed = true;
  };
  if (entrance === 'Local') {
    try {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
    } catch (error) {
      // Report closed diagnostic tags only, never configuration, keys or rows.
      const failures = [], seen = new Set();
      const visit = error => {
        if (!error || seen.has(error) || failures.length >= 8) return;
        seen.add(error);
        const tag = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(value)
          ? value : undefined;
        failures.push({code: tag(error.code), name: tag(error.name), tag: tag(error.message),
          ...(error.code === 'ERR_MODULE_NOT_FOUND' && error.url?.startsWith('file:')
            ? {module: error.url} : {})});
        visit(error.primaryFailure); visit(error.cause);
      };
      visit(error);
      console.error(JSON.stringify({fixture: 'independent-source-command', failures}));
      throw error;
    }
  } else {
    const {key, cert, ca} = await fixtureCertificates(scratch.path);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer content-command-fixture' ? owner : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'content-command-fixture', durability: 'durable'});
  }
  return {client, close, fixture, events, targetPath, keys, generated,
    reads: () => reads, sends: () => sends, writeGrants: () => writeGrants, projections};
}
