// Test assembly of the installed Salesforce Effect over the local HTTPS org:
// an installed Site profile, the Host's Effect profile and its published
// generation, and the common Effect Run owners that call the factory. The
// Run-start and publication-plan facts stand in for the standard Host's
// installed Effect path; the factory under test receives only them.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {installNodeClientEffectRun, openClientRequestJournal} from
  '../../../host-node/client-effect-run.mjs';
import {installNodeClientEffectProgramPreparation} from
  '../../../host-node/client-program-preparation.mjs';
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  recoverAdmittedEffectRun, runCapturedEffectComputation} from
  '../../../host-node/entry.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeEffectPublicationPlan} from
  '../../../host-node/local-values-plan.mjs';
import {openLocalPublicationStore} from
  '../../../store-local/publication-store.mjs';
import {releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation} from
  '../../../host-common/completed-run-publication.mjs';
import {ExecutionAuthorizationError} from
  '../../../host-common/authorization-gate.mjs';
import {INSTALLED_SALESFORCE_EFFECT_VERSION, loadInstalledSalesforceEffect,
  publishInstalledSalesforceEffect, salesforceEffectUnit} from
  '../host/installed-salesforce-effect.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION} from
  '../host/installed-salesforce-site.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';

export {moon, salesforceMoon};
const cid = digit => `sha256:${digit.repeat(64)}`;
const repository = new URL('../../../../', import.meta.url);
const limits = localContractLimits;

// Entries are in the configuration's canonical order (by entry id).
export const accountConfiguration = entries => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'salesforce-effect-account', entries: [...entries].sort(
    (a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0)});

export const recordEntry = (orgId, operation, outcome = 'allow',
  resource = 'Test_Record__c') => ({
  entry_id: `records-${resource.toLowerCase().replaceAll('_', '-')}-${
    operation}`,
  outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [`salesforce:${orgId}`]},
  resource: {any_of: [resource]}, operation: {any_of: [operation]}});

// The local org, the installed Site profile, and a published Effect profile
// for `writes`. `load` installs the Effect as a Host start would; `publish`
// republishes the generation explicitly.
// `principalId` and `accountConfigurationWire` default to a standalone
// installation; a standard Host's installation uses the Host's own.
export async function installedEffect(t, {writes, writeOperation = 'update',
  entries, siteProfile = {}, org: orgOptions = {},
  principalId = 'principal-a', accountConfigurationWire} = {}) {
  const org = await openSalesforceEffectSiteFixture(t, {commonMoon: moon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2'),
    writeOperation, connectorId: 'salesforce', ...orgOptions});
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-effect-'));
  const loaded = [];
  // Hosts over this installation end before its directories are removed.
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    for (const effect of loaded) effect.close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), org.credential.ca);
  const siteDocument = {
    version: INSTALLED_SALESFORCE_SITE_VERSION,
    apiVersion: 'v62.0', cliAlias: 'actql-test',
    cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: org.origin,
    journalRoot: join(root, 'credential-journal'), orgId: org.orgId,
    siteGeneration: 1, siteKey: 'salesforce-site', namespaceId: 'namespace-a',
    caPath: join(root, 'org-ca.crt'), ...siteProfile,
  };
  const sitePath = join(root, 'salesforce-site.json');
  const writeSite = document => writeFile(sitePath, JSON.stringify(document));
  await writeSite(siteDocument);
  const baseEnvironmentWire = (await readFile(new URL(
    'spec/local-check-environment.json', repository), 'utf8')).trimEnd();
  const profile = {
    version: INSTALLED_SALESFORCE_EFFECT_VERSION,
    siteProfilePath: sitePath,
    accountConfigurationWire: accountConfigurationWire ??
      accountConfiguration(entries ?? [recordEntry(org.orgId, 'read'),
        recordEntry(org.orgId, 'effect')]),
    connectorId: 'salesforce',
    publicationPath: join(root, 'effect-publication.json'),
    writes,
  };
  const options = {root, principalId, moon, salesforceMoon,
    runtimeBundleCid: cid('b'),
    resolveSecret: async () => 'test-only-secret', baseEnvironmentWire};
  const ledgerRoot = join(root, 'effect-ledger');
  await mkdir(ledgerRoot, {recursive: true});
  const publish = (overrides = {}, publishOptions = {}) =>
    publishInstalledSalesforceEffect({...profile, ...overrides},
      {...options, ...publishOptions});
  const load = async (overrides = {}, loadOptions = {}) => {
    const effect = await loadInstalledSalesforceEffect(
      {...profile, ...overrides}, {...options, ledgerRoot, ...loadOptions});
    loaded.push(effect);
    return effect;
  };
  const published = await publish();
  return {org, root, profile, siteDocument, writeSite, published, publish,
    load, baseEnvironmentWire, options, ledgerRoot,
    onClose: close => closers.push(close)};
}

// A Values Program whose one Unit writes `rows` through each named Effect.
export function effectProgram(effects, rows, schema = {id: {type: 'string',
  nullable: false}}, fields = Object.keys(schema)) {
  return {version: 'actql/0.1', id: 'client-values', stages: [{
    id: 'source', inputs: {},
    steps: [{values: {schema, rows}, as: 'selected'}],
    results: {rows: {from: 'selected', fields}},
    effects}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}};
}

const storeConfiguration = directory => ({directory,
  storeAuthorityCid: cid('7'), capacityBytes: 64 * 1024 * 1024,
  maxObjectBytes: localOutputLimits.maxWireBytes, maxObjects: 1000,
  maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
  privateEvidenceKey: Buffer.alloc(32, 4)});

// One Host process over `state`: a request journal, the publication Store
// and the installed Effect. `run` accepts and starts one Program request; the
// installed factory captures and the common owner completes it.
// `stopBeforeApply` ends the process's part after the capture, as a Host
// stopped while the Set waits for approval would.
export async function effectHost(t, installation, state, {effect,
  wrapStage, stopBeforeApply = false} = {}) {
  const installed = effect ?? await installation.load();
  const environmentWire = installed.environmentWire;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const prepareProgram = installNodeClientEffectProgramPreparation({moon,
    environment});
  await mkdir(state, {recursive: true});
  const journal = openClientRequestJournal(join(state, 'requests'));
  const control = runtimeCore(moon).publicationControl;
  const store = await openLocalPublicationStore(storeConfiguration(
    join(state, 'store')), control);
  const [registry, contract] = await Promise.all([
    readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',
      repository), 'utf8'),
    readFile(new URL('spec/contracts/actql-aoa.json', repository), 'utf8'),
  ]);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  const now = () => new Date().toISOString();
  const outcomes = [];
  const executions = [];
  const runs = installNodeClientEffectRun({moon, publicationControl: control,
    journal, now,
    authorizeRequest: async () => ({executionContextCid: cid('a'),
      hostPolicyCid: cid('b'), createdAt: now(),
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()}),
    authorizeRunStart: async () => true,
    async execute(facts) {
      const plan = sourceFreeEffectPublicationPlan({moon, control,
        prepared: facts.prepared,
        compilation: facts.compilation, allowed: facts.allowed,
        definition: facts.definition, authorityScopeCid: cid('e'),
        namespaceId: 'namespace-a', storeAuthorityCid: store.storeAuthorityCid,
        now});
      const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        facts.owner, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(owned);
      const execution = await runCapturedEffectComputation(owned);
      executions.push(execution);
      const compiledPlan = checked(moon.strategyPublicationAdmit(
        'compiled_plan', moon.clientProgramEffectCompilationCompiledPlanWire(
          facts.compilation), limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const stage = await installed.prepareCaptured({moon, control, store,
        execution, checkedHost: owned, prepared: facts.prepared,
        identity: facts.identity, plan,
        previewContext: {runDefinition: facts.definition,
          runInvocation: plan.invocationOwner, compiledPlan},
        unit: salesforceEffectUnit(moon, facts.compilation)});
      const owned2 = wrapStage === undefined ? stage : wrapStage(stage);
      if (stopBeforeApply) {
        // As the installed Host does before the Set waits: the durable
        // intents let a later process rebuild the exact claims.
        stage.apply.ledger.prepareCapturedSetIntents(
          stage.apply.capturedInputs, stage.apply.members,
          stage.apply.maxFrontierWork);
        await suspendCompletedEffectfulComputation({execution, store,
          storedResults: stage.storedResults, control,
          computation: stage.computation, preview: stage.preview});
        outcomes.push({stage, result: {status: 'suspended'}});
        return Object.freeze({status: 'captured',
          continuation: JSON.parse(stage.continuationWire)});
      }
      try {
        const result = await completeCapturedEffectRun({apply: owned2.apply,
          receipt: owned2.receipt, publication: owned2.publication});
        outcomes.push({stage, result});
        return result;
      } catch (error) {
        outcomes.push({stage, error});
        // As the installed Host does: a commit refused before any send
        // releases the unpublished Results.
        if (error instanceof ExecutionAuthorizationError &&
            error.authorization?.action === 'deny') {
          await releaseCompletedRunPreparedPayloads(stage.storedResults,
            control);
        }
        throw error;
      }
    }});
  // What this process still holds when it ends: a failed Set's unpublished
  // Results are released; otherwise the process stops and only its local
  // payload custody ends, while the durable capture stays for a restart.
  const endCustody = async (stage, result) => {
    if (result?.status === 'suspended') return;
    if (result?.status === 'failed') {
      await releaseCompletedRunPreparedPayloads(stage.storedResults, control);
      return;
    }
    for (const item of stage.storedResults.results) {
      if (item.prepared.status().pending) await item.prepared.release();
    }
  };
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    for (const {stage, result} of outcomes) {
      stage.dispose();
      await endCustody(stage, result);
    }
    for (const execution of executions) {
      await execution.close();
    }
    await store.close();
    journal.close();
    if (effect === undefined) installed.close();
  };
  installation.onClose(close);
  return {installed, journal, store, control, outcomes, close,
    async run(document, requestId) {
      const prepared = prepareProgram({kind: 'program', input: document,
        parameters: null});
      const accepted = await runs.accept({prepared,
        authorityScopeCid: cid('e'), requestId, namespaceId: 'namespace-a',
        principalId: 'principal-a',
        connection: {mode: 'local', owner: 'local'},
        lookupExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000)
          .toISOString()});
      try {
        return {accepted, started: await runs.start(accepted)};
      } catch (error) {
        // The accepted request stays the Run's handle for a restart.
        if (error !== null && typeof error === 'object') {
          error.accepted = accepted;
        }
        throw error;
      }
    },
    // Recover the admitted Run of `requestId` in this process and continue
    // it through the installed factory's recovery projection.
    async resume(requestId, runDefinitionCid, continuation) {
      const recovery = await recoverAdmittedEffectRun({requests: journal,
        store, key: {namespaceId: 'namespace-a', authorityScopeCid: cid('e'),
          requestId, runDefinitionCid},
        principalId: 'principal-a', contractLimits: limits,
        authorizeEvidenceRead: async () => true});
      let stage;
      try {
        stage = installed.prepareRecovered({moon, control, store,
          recovered: {requestIdentity: recovery.requestIdentity,
            requestScope: recovery.requestScope,
            computation: recovery.computation},
          continuation, contractLimits: limits});
      } catch (error) {
        outcomes.push({stage: {dispose() {},
          storedResults: recovery.computation.storedResults}});
        throw error;
      }
      try {
        const result = await completeRecoveredEffectRun({
          apply: stage.apply, receipt: stage.receipt,
          publication: stage.publication});
        outcomes.push({stage, result});
        return {stage, result};
      } catch (error) {
        outcomes.push({stage});
        throw error;
      }
    }};
}
