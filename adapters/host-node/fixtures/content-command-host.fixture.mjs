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
import {installedRowEffectConstructionLimits} from '../installed-row-effect.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../installed-effect-plan.mjs';
import {selectInstalledHostEnvironment} from '../installed-host-policy.mjs';
import {contentCommandFixture} from './content-command.fixture.mjs';
import {canonical, cid, resource, token} from './file-listing-source.fixture.mjs';

export async function openContentCommandHost({scratch, generated, keys, entrance,
  allowSourceRead = true, fault, modelInstallation, registerModelProviders, hostCapacityPolicy,
  faultInjection, modelApprovalRequired = false, generatedCommand = false,
  onPrepareContent, prepareContentChild, originalContentValue, installEffects = true}) {
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
    {entry_id: 'host-control-result-read', outcome: 'allow',
      principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/r', 'run']},
      operation: {any_of: ['read']}, exclusions: []},
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
  let generatedHoldingCid;
  const requestOriginals = new WeakMap(), physicalChildren = new Set();
  const requestLimits = installedRowEffectConstructionLimits();
  const ioLimits = Object.freeze({maxRequestBytes: requestLimits.body.maxBytes,
    maxRecoveryBytes: requestLimits.preview.maxWireBytes, maxResponseBytes: 2,
    maxOutcomeBytes: canonical({state: 'applied', result: {}}).length,
    maxTransferBytes: expectedBytes.length});
  // This writer retains at most one copied chunk per byte, its concatenation,
  // the response Buffer, three file handles, and their original path strings.
  // The same finite constructor metadata reaches the Common native fold;
  // no writer, physical occurrence or Resource is produced by these DATA.
  const receiptPath = join(scratch.path, 'receiver-receipt.json');
  const pathUnits = targetPath.length + receiptPath.length + scratch.path.length;
  const receiptBytes = Buffer.byteLength(canonical({request_cid: token('c'), content_cid: expectedContentCid}));
  const writeConstruction = Object.freeze({
    retained: Object.freeze({nodes: BigInt(ioLimits.maxTransferBytes) + 12n,
      text: 2n * BigInt(pathUnits + receiptBytes),
      wire: 2n * BigInt(ioLimits.maxTransferBytes) + BigInt(ioLimits.maxResponseBytes + receiptBytes)}),
    workspace: Object.freeze({nodes: 4n, text: 2n * BigInt(ioLimits.maxResponseBytes),
      wire: BigInt(ioLimits.maxResponseBytes + receiptBytes) + 4n * BigInt(pathUnits)}),
  });
  const requestOf = (value, target) => ({value, target});
  const retainCommandContent = (request, content, contentOwner) => {
    if (!generatedCommand) return;
    const borrow = content('content');
    assert.equal(borrow.current(), true);
    assert.equal(borrow.wire(), canonical(request.value.content));
    const storage = contentOwner.storageForContent(borrow.binding);
    assert.ok(storage);
    requestOriginals.set(request, {borrow, contentOwner, storage});
  };
  const checkReference = async request => {
    assert.deepEqual(request.target, destination);
    if (generatedCommand) {
      assert.equal(request.value.name, 'approved.csv');
      const ref = request.value.content;
      assert.equal(ref.media_type, 'text/csv');
      assert.equal(ref.metadata.content_cid, expectedContentCid);
      assert.equal(ref.metadata.size_bytes, expectedBytes.length);
      const original = requestOriginals.get(request);
      assert.ok(original, 'same original Command Content request');
      assert.equal(original.borrow.current(), true);
      assert.equal(original.contentOwner.storageCurrentForContent(original.storage, original.borrow.binding), true);
      assert.equal(ref.metadata.issuer_evidence.content_store_cid, original.storage.storeAuthorityCid);
      const holding = original.storage.holding;
      assert.equal(holding.holding_cid, generatedHoldingCid);
      assert.equal(holding.namespace, 'content');
      assert.equal(holding.manifest_cid, ref.content_ref_cid);
      assert.deepEqual(holding.objects, [{cid: expectedContentCid, byte_count: expectedBytes.length}]);
      return;
    }
    assert.deepEqual(request.value, {content, name: 'approved.csv'});
    await generated.issue(); // existing custody/current authority, not shape alone
    assert.equal(generated.store.status().storedBytes, 3);
  };
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
        const construction = options.construction;
        assert.equal(typeof construction?.prepareAuthoredCommands, 'function');
        const prepared = construction.prepareAuthoredCommands(fixture.declarationViewsWire, Object.freeze({
          operation: 'files.write', commands: Object.freeze([Object.freeze({resource: 'transfers',
            body: canonical(fixture.command)})]), contracts: fixture.commandContracts,
        }));
        const managedPlanRecipe = prepareInstalledPhysicalWritePlanRecipe({moon,
          operation: 'files.write', inputLimits: requestLimits, limits: ioLimits,
          construction: writeConstruction});
        await construction.openSpecializedSite({accountConfiguration: account,
          authorizationConstructor: options => installRowSourceAuthorization({...options,
            connectorRegistration: 'fixture'}),
          siteConstructor: (_argument, {authorization}) => Object.freeze({
            issueReadGrant: () => ({}),
            issueEffectGrant({decision}) {
              assert.equal(decision.action, 'dispatch');
              assert.equal(decision.boundary, 'effect_commit');
              assert.equal(decision.basis, 'resumed');
              writeGrants++;
              return {};
            },
            async close() {
              for (const child of physicalChildren) await child.close();
              assert.ok([...physicalChildren].every(child => child.status().pending === false));
              await authorization.close();
            },
          }),
        });
        return construction.createRowEffect({connection: 'fixture:files',
          runtimeBundleCid: options.runtimeBundleCid, bindingCid: token('c'), ledgerRoot: options.ledgerRoot,
          limits: requestLimits, managedPlanRecipe, managedPlanDefinition: prepared.commandDefinition,
          driver: {kinds: ['command'], writeOperation: () => 'files.write',
            prepareRequest({value, selector, content: originalContent, contentOwner}) {
              onPrepareContent?.({value, selector, originalContent});
              const request = requestOf(value, selector);
              retainCommandContent(request, originalContent, contentOwner);
              return {request, requestCid: cid(request)};
            }, ...(prepareContentChild === undefined ? {} : {
              prepareRequestChild(context) {
                const request = requestOf(context.value, context.selector);
                retainCommandContent(request, context.content, context.contentOwner);
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
            }, ...(generatedCommand ? {
              prepareRecoveredContentChild({recovered, members, entries, memberIndexes,
                control, store, contentRun, principalId, assertCurrent, signal, limits}) {
                const retained = [];
                let attempted = false, stopping = false, released = false, flight;
                const child = Object.freeze({
                  prepare() {
                    assert.equal(attempted || stopping, false);
                    attempted = true;
                    const work = (async () => {
                      const compiled = control.adoptCheckedClientEffectSerializationRun(
                        recovered.allowed, recovered.runDefinition);
                      for (const index of memberIndexes) {
                        const sources = recovered.computation.effectSources.filter(source =>
                          source.memberIndex === members[index].memberIndex);
                        assert.equal(sources.length, 1);
                        for (const [row, entry] of entries[index].entries()) {
                          assertCurrent(); signal?.throwIfAborted(); assert.equal(stopping, false);
                          const original = contentRun.prepareRecoveredCommandContent({
                            prepared: recovered.prepared, compiled, definition: recovered.runDefinition,
                            captured: recovered.computation.computation.capturedRun,
                            preview: recovered.computation.preview, invocation: recovered.computation.invocation,
                            source: sources[0].source, store, principalId,
                            memberIndex: members[index].memberIndex, row, inputName: 'content',
                            referenceWire: canonical(entry.request.value.content), signal,
                            limits: {maxFields: limits.maxFields, maxWork: limits.maxWork,
                              maxWireBytes: limits.body.maxBytes, maxNodes: limits.body.maxNodes,
                              maxDepth: limits.body.maxDepth},
                            assertCurrent() {assert.equal(stopping, false); assertCurrent();},
                          });
                          retained.push(original);
                          const restored = await original.prepare();
                          assertCurrent(); signal?.throwIfAborted(); assert.equal(stopping, false);
                          requestOriginals.set(entry.request, {...restored,
                            storage: restored.contentOwner.storageForContent(restored.borrow.binding)});
                        }
                      }
                    })();
                    flight = work;
                    return work.finally(() => {if (flight === work) flight = undefined;});
                  },
                  async release() {
                    stopping = true;
                    if (flight !== undefined) return false;
                    for (const original of retained) await original.release();
                    if (retained.some(original => original.status().pending)) return false;
                    released = true;
                    return true;
                  },
                  status: () => Object.freeze({pending: !released || flight !== undefined}),
                });
                return child;
              },
            } : {}), async send({request, physicalOperation}) {
              await checkReference(request);
              let active = true, transferred = 0;
              const handles = new Set();
              const child = Object.freeze({status: () => Object.freeze({pending: active || handles.size !== 0}),
                async close() {
                  if (active) return child.status();
                  for (const handle of handles) {await handle.close(); handles.delete(handle);}
                  return child.status();
                }});
              physicalChildren.add(child);
              physicalOperation.retainPhysicalChild(child);
              const acquire = async (...args) => {const handle = await open(...args); handles.add(handle); return handle;};
              const close = async handle => {await handle.close(); handles.delete(handle);};
              const chunks = [];
              try {
                const accept = chunk => {
                  assert.ok(chunk.length <= ioLimits.maxTransferBytes - transferred);
                  physicalOperation.chargeBytes(BigInt(chunk.length));
                  transferred += chunk.length;
                  chunks.push(Buffer.from(chunk));
                };
                if (generatedCommand) {
                  const original = requestOriginals.get(request);
                  await original.contentOwner.consumeContent(original.borrow.binding, accept);
                } else await generated.store.consumePhysicalHolding(generated.holding.holding_cid, 0, accept);
                const bytes = Buffer.concat(chunks);
                assert.deepEqual(bytes, expectedBytes);
                const output = await acquire(targetPath, 'wx');
                try { await output.writeFile(bytes); await output.sync(); }
                finally { await close(output); }
                // The fixture receiver retains its own operation fact. Sender
                // response/unknown responsibility remains in the existing Ledger.
                const receipt = await acquire(receiptPath, 'wx');
                try {
                  await receipt.writeFile(canonical({request_cid: cid(request),
                    content_cid: request.value.content.metadata.content_cid}));
                  await receipt.sync();
                } finally { await close(receipt); }
                const directory = await acquire(scratch.path, 'r');
                try { await directory.sync(); } finally { await close(directory); }
                sends++;
                if (fault === 'lost_reply') throw new Error('FixtureCommandReplyLost');
                return {observation: {useCid: cid({write: sends}), statusCode: 201,
                  body: Buffer.from('{}')}};
              } finally {active = false;}
            }, project: ({observation}) => {
              projections.push({useCid: observation.useCid, statusCode: observation.statusCode,
                body: Buffer.from(observation.body).toString('utf8')});
              if (fault === 'stop_projection') throw new Error('FixtureCommandProjectionStopped');
              return {kind: 'typed-success-response', outcome: {state: 'applied', result: {}}};
            },
            footprint: () => ({providerNamespace: 'file-fixture', resourceKind: 'file', boundaryCid: token('c')}),
          }});
      }}),
    }}]);
  const sourceProfilePath = join(scratch.path, 'source.json');
  const effectProfilePath = join(scratch.path, 'effect.json');
  const queryAliases = fixture.declared.views.map(view => ({name: 'files.transfers',
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
    schemaContractCid: view.carrier_schema_cid}));
  await writeFile(sourceProfilePath, canonical({version: sourceVersion, connectorId: 'content-fixture',
    sourceOrigin: managedSource.origin, queryAliases}));
  await writeFile(effectProfilePath, canonical({version: effectVersion, connectorId: 'content-fixture'}));
  const installation = {directory: join(scratch.path, 'host'), connectorTable, sourceProfilePath,
      ...(installEffects ? {effectProfilePath} : {}),
      modelInstallation, registerModelProviders, hostCapacityPolicy,
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
          sourceLocations: typeof error.stack === 'string'
            ? (error.stack.match(/(?:adapters|packages)\/[A-Za-z0-9_./-]+\.mjs:\d+:\d+/gu) ?? []).slice(0, 4) : [],
          ...(error.code === 'ERR_MODULE_NOT_FOUND' && error.url?.startsWith('file:')
            ? {module: error.url} : {})});
        visit(error.primaryFailure); visit(error.cause);
      };
      visit(error);
      console.error(JSON.stringify({fixture: 'independent-source-command', failures}));
      // This endpoint is a fixture child, not the rejected Host's cleanup ACK.
      await managedSource.close();
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
