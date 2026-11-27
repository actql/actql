// Optional plugin acceptance on the same normal artifact, never a new producer.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, copyFile, readFile, writeFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {registeredExternalPackageImages} from './initial-control-package-images.mjs';
import {prepareHealthPackages, execute} from './health-monitor-adapters.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './node-benchmark-evidence.mjs';
import {publicConsumerEnvironment, publicInstallCommand, releaseConsumerDestination,
  verifyPublicConsumer} from './release-public-install.mjs';
import {nodeReleaseIncludesProvider, verifyPackageRelease} from './package-release.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';

type ReleaseManifest = Awaited<ReturnType<typeof verifyPackageRelease>>;
type Command = typeof execute;
type ProviderOptions = {repository?: string; retained?: string; release?: string;
  publicRegistry?: boolean; cases?: readonly string[]; command?: Command};
type Observation = Record<string, unknown>;
type ObservationInput = {caseId: string; phase: string; pid: number; originalPid?: number; observation: Observation};
type PhaseRecord = {
  case: string; phase: string; status: 'unexecuted' | 'running' | 'passed' | 'failed'; reason?: string;
  pid?: number; actual?: Observation; consumer?: string; failure?: ReturnType<typeof nodeBenchmarkFailure>;
};
type Prepared = Awaited<ReturnType<typeof prepareHealthPackages>> | Awaited<ReturnType<typeof installRelease>>;
type ExternalPreparation = {archive: string; sha256: string; packageImages: ReturnType<typeof registeredExternalPackageImages>};
type Report = {
  source: string; phases: PhaseRecord[]; complete: boolean;
  preparations: (Omit<Prepared, 'publicPayload'> & {case: string;
    publicPayload?: Awaited<ReturnType<typeof verifyPublicConsumer>>;
    external?: ExternalPreparation})[];
  failures?: ReturnType<typeof nodeBenchmarkFailure>[]; cleanup?: ReturnType<typeof nodeBenchmarkFailure>[];
};

const registeredResponsesCase = 'registered-openai-responses';
const registeredResponsesLimitCase = 'registered-openai-responses-over-limit';
const registeredProviderCases = Object.freeze([
  'registered-project', 'registered-anthropic', 'registered-google', 'registered-mixed', 'registered-mistral',
  registeredResponsesCase,
]);
export const registeredSafetyAcceptanceCases = Object.freeze([
  'registered-openai-filter', 'registered-google-recitation', 'registered-google-blocklist',
]);
const registeredCapabilityCase = 'registered-capabilities';
const registeredCheckpointCase = 'registered-checkpoint';
const registeredCheckpointFailures: Readonly<Record<string, string>> = Object.freeze({
  'registered-checkpoint-raw-denied': 'MoonBitHostFailure',
  'registered-checkpoint-changed-route': 'ClientModelProviderSelectionChanged',
  'registered-checkpoint-missing-binding': 'ClientModelProviderSelectionUnavailable',
  'registered-checkpoint-stale-lease': 'ResumeClaimStale',
});
const registeredCheckpointCases = [registeredCheckpointCase, ...Object.keys(registeredCheckpointFailures)];
const registeredInterruptionCases: readonly string[] = ['registered-response-loss', 'registered-entered-cancel'];
const registeredHttpFailures: Readonly<Record<string, number>> = Object.freeze({
  'registered-http-401': 401, 'rate-limit': 429, 'registered-http-503': 503,
});
// The default ordinary campaign already selects rate-limit and its cold read.
export const registeredAuthorityAcceptanceCases = Object.freeze([
  registeredCapabilityCase, registeredResponsesLimitCase, ...registeredCheckpointCases, ...registeredInterruptionCases,
  ...Object.keys(registeredHttpFailures).filter(id => id !== 'rate-limit'),
]);
const externalCase = 'registered-external';
const externalDuplicateCase = 'registered-external-double';
const externalCases: readonly string[] = [externalCase, externalDuplicateCase];
const externalAdapter = '@actql-acceptance/external-openai-adapter';
const registeredTerminalFailures = Object.freeze({
  'registered-length': 'truncated', 'registered-refusal': 'refusal',
  'registered-openai-filter': 'safety_rejected', 'registered-google-recitation': 'safety_rejected',
  'registered-google-blocklist': 'safety_rejected',
});
const registeredBindingRefusals: Readonly<Record<string, {rejected: string; bindingIssue?: string}>> = Object.freeze({
  'registered-foreign-model': {rejected: 'MoonBitHostFailure', bindingIssue: 'ForeignConfiguration'},
  'registered-missing-routes': {rejected: 'InvalidInstalledModelSdkInstallation'},
});
const registeredRefusalCases = Object.freeze([
  'registered-too-late', 'registered-invalid',
  'registered-credential-reference', 'registered-credential-header',
  ...Object.keys(registeredBindingRefusals),
]);
const directProviderCases = Object.freeze(['direct-project', 'direct-response-loss', 'direct-partial-raw']);
export const registeredProviderAcceptanceCases = Object.freeze([
  ...registeredProviderCases, 'registered-length', 'registered-refusal', ...registeredRefusalCases,
]);

// Assertions over the original child report only; this issues no Run authority
// or substitute provider result. The caller still owns actual process/state
// selection, same-source software verification and independent installations.
export function checkPackedProviderObservation({caseId, phase, pid, originalPid, observation: value}: ObservationInput) {
  assert.equal(value.phase, phase);
  assert(Number.isSafeInteger(pid) && pid > 0);
  if (registeredCheckpointCases.includes(caseId)) {
    assert.equal(value.caseId, caseId);
    assert.equal(value.pid, pid);
    const first = phase === caseId;
    const approved = phase === 'approve';
    const original = value.reference as {runDefinitionCid: string; authorityScopeCid: string};
    const cid = /^sha256:[0-9a-f]{64}$/u;
    const expectedFailure = first ? undefined : registeredCheckpointFailures[caseId];
    const expectedPendingClose = approved && caseId === 'registered-checkpoint-stale-lease';
    const shouldSend = approved && caseId === registeredCheckpointCase;
    const missingBinding = approved && caseId === 'registered-checkpoint-missing-binding';
    assert(first || approved || phase === 'cold' && caseId === registeredCheckpointCase);
    if (!first) assert.notEqual(pid, originalPid);
    assert.match(original.runDefinitionCid, cid);
    assert.match(original.authorityScopeCid, cid);
    assert.match(value.taskCid as string, cid);
    assert.equal(value.terminalCause, expectedFailure);
    assert.equal(value.firstClose, expectedPendingClose ? 'ClientCleanupPending' : 'closed');
    assert.equal(value.scopedStateFd0, expectedPendingClose ? undefined : true);
    for (const field of ['tlsAttempts', 'peerConnections', 'posts']) assert.equal(value[field], shouldSend ? 1 : 0);
    assert.equal(value.credentialReads, approved && caseId !== 'registered-checkpoint-changed-route' &&
      !missingBinding ? 1 : 0);
    if (missingBinding) {
      const evidence = value.missingBindingEvidence as {originalSha256: string; admittedSha256: string} | undefined;
      assert(evidence !== undefined);
      assert.match(evidence.originalSha256, cid);
      assert.match(evidence.admittedSha256, cid);
      assert.notEqual(evidence.originalSha256, evidence.admittedSha256);
    } else assert.equal(value.missingBindingEvidence, undefined);
    const approval = value.approval as {runDefinitionCid: string} | undefined;
    assert.equal(approval?.runDefinitionCid, approved ? original.runDefinitionCid : undefined);
    assert.deepEqual(value.usageCounts, {authorize: Number(shouldSend),
      capture: Number(shouldSend), record: Number(shouldSend)});
    if (shouldSend || phase === 'cold') {
      const settlement = value.settlement as {slotCid: string; attemptCid: string};
      assert.match(settlement.slotCid, /^sha256:[0-9a-f]{64}$/u);
      assert.match(settlement.attemptCid, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(value.attempts, [{attempt_cid: settlement.attemptCid, state: 'SavedSuccess'}]);
      assert.deepEqual(value.typedResult, [{id: 'original-text', outcome: 'ok', value: {answer: true}}]);
      const evidence = value.usageEvidence as {
        usage: {input_tokens: number; output_tokens: number; observation_origin: string;
          model_task_contract_cid: string; model_call_slot_cid: string; raw_response_artifact_cid: string};
        receipt: unknown;
        raw: {manifest_cid: string; holding_cid: string; objects: {cid: string; byte_count: number}[]};
      } | undefined;
      assert(evidence?.usage && evidence.raw);
      const {usage, receipt, raw} = evidence;
      assert.deepEqual([usage.input_tokens, usage.output_tokens, usage.observation_origin], [2, 3, 'reported']);
      assert.equal(usage.model_task_contract_cid, value.taskCid);
      assert.equal(usage.model_call_slot_cid, settlement.slotCid);
      assert.equal(usage.raw_response_artifact_cid, raw.manifest_cid);
      assert.match(raw.manifest_cid, cid);
      assert.match(raw.holding_cid, cid);
      assert.equal(raw.objects.length, 2);
      assert.notEqual(raw.objects[0].cid, raw.objects[1].cid);
      for (const object of raw.objects) {
        assert.match(object.cid, cid);
        assert(Number.isSafeInteger(object.byte_count) && object.byte_count > 0);
      }
      const subject = {runDefinitionCid: original.runDefinitionCid, authorityScopeCid: original.authorityScopeCid};
      assert.deepEqual(receipt, {subject, target: 'inferred', manifest: {
        kind: 'usage', status: 'complete', subject, target: 'inferred',
        items: [{modelCallSlotCid: settlement.slotCid, attemptCid: settlement.attemptCid, status: 'complete'}],
      }});
    } else {
      assert.deepEqual(value.attempts, []);
      assert.equal(value.typedResult, undefined);
      assert.equal(value.settlement, undefined);
      assert.equal(value.usageEvidence, undefined);
    }
    return;
  }
  if (registeredInterruptionCases.includes(caseId)) {
    const cold = phase === 'cold';
    const cancelled = caseId === 'registered-entered-cancel';
    assert(cold || phase === caseId);
    const start = cold ? 0 : 1;
    const cid = /^sha256:[0-9a-f]{64}$/u;
    assert.equal(value.interruption, cancelled ? 'entered-cancel' : 'response-loss');
    assert.equal(value.pid, pid);
    assert.equal(value.firstCloseReturned, true);
    assert.equal(value.aliveScopedFD0, true);
    assert.equal(value.registeredSdk, true);
    assert.equal(value.projectCredential, true);
    for (const field of ['calls', 'projectTlsConnects', 'originalModelStarts', 'interruptionCredentialReads']) {
      assert.equal(value[field], start);
    }
    assert.match(value.originalRunDefinitionCid as string, cid);
    const journal = value.unknownJournal as {
      state: string; settled: boolean; scopeCid: string; slotCid: string; attemptCid: string; providerBindingCid: string;
    };
    assert.equal(journal.state, 'EnteredUnknown');
    assert.equal(journal.settled, false);
    for (const id of [journal.scopeCid, journal.slotCid, journal.attemptCid, journal.providerBindingCid]) assert.match(id, cid);
    const control = value.unknownControl as {revision: number; cancellation_requested: boolean; physical_stop: string};
    assert(Number.isSafeInteger(control.revision) && control.revision >= 0);
    assert.equal(control.cancellation_requested, cancelled);
    assert.equal(control.physical_stop, 'confirmed');
    const cancellation = value.cancellation as {kind: string; revision: number;
      cancelRef: {runDefinitionCid: string; expectedRevision: number}} | undefined;
    if (cancelled) {
      assert.equal(cancellation?.kind, 'accepted');
      assert.equal(cancellation.cancelRef.runDefinitionCid, value.originalRunDefinitionCid);
      assert.equal(cancellation.revision, cancellation.cancelRef.expectedRevision + 1);
      assert.equal(control.revision, cancellation.revision + 1);
    } else assert.equal(cancellation, undefined);
    assert.equal(value.originalSavedFirst, undefined);
    if (cold) {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalUnknown, true);
      assert.equal(value.zeroResend, true);
      assert.equal(value.egressChecks, 0);
      assert.equal(value.responseClosedBeforeFirstClose, undefined);
    } else {
      assert.equal(value.tasks, 1);
      assert.equal(value.requests, 1);
      assert.equal(value.responseClosedBeforeFirstClose, true);
    }
    return;
  }
  if (caseId === registeredResponsesLimitCase) {
    assert.equal(phase, registeredResponsesLimitCase);
    assert.deepEqual(value, {phase, rejected: 'MoonBitHostFailure', credentialReads: 0,
      tlsAttempts: 0, peerConnections: 0, calls: 0, modelStarts: 0, modelScopes: 0, modelAttempts: 0,
      aliveScopedFD0: true, usageCaptures: 0});
    return;
  }
  const bindingRefusal = registeredBindingRefusals[caseId];
  if (bindingRefusal !== undefined) {
    assert.equal(phase, caseId);
    assert.deepEqual(value, {phase, pid, ...bindingRefusal, bindingProjections: 1, credentialReads: 0,
      egressChecks: 0, tlsAttempts: 0, peerConnections: 0, calls: 0, modelStarts: 0, modelScopes: 0,
      modelAttempts: 0, aliveScopedFD0: true, usageAuthorizations: 0, usageCaptures: 0});
    return;
  }
  if (caseId.startsWith('registered-credential-')) {
    assert.deepEqual(value, {phase, rejected: 'RegisteredSdkCredentialMismatch',
      credentialReads: 0, tlsAttempts: 0, calls: 0});
    return;
  }
  if (caseId === 'registered-invalid') {
    assert.deepEqual(value, {phase, startupRefused: true, registrations: 0, calls: 0,
      defaultOpened: true, firstCloseReturned: true, aliveScopedFD0: true});
    return;
  }
  if (caseId === 'registered-too-late') {
    assert.deepEqual(value, {phase, startupRefused: true, registrations: 0, calls: 0});
    return;
  }
  assert.equal(value.firstCloseReturned, true); assert.equal(value.aliveScopedFD0, true);
  if (directProviderCases.includes(caseId)) {
    const cold = phase === 'cold';
    const responseLost = caseId === 'direct-response-loss';
    const incompleteRaw = caseId === 'direct-partial-raw';
    const unknown = responseLost || incompleteRaw;
    assert.equal(value.directHttp, true);
    assert.equal(value.registeredSdk, undefined);
    const dependencyClosure = value.directDependencyClosure as Readonly<{packages: number; sha256: string}>;
    assert(dependencyClosure && Number.isSafeInteger(dependencyClosure.packages) && dependencyClosure.packages > 0);
    assert.match(dependencyClosure.sha256, /^[a-f0-9]{64}$/u);
    assert(typeof value.originalRunDefinitionCid === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value.originalRunDefinitionCid));
    assert(typeof value.originalAuthorityScopeCid === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value.originalAuthorityScopeCid));
    assert.equal(value.originalTerminalStatus, unknown ? 'needs_reconciliation' : 'succeeded');
    const journal = value.directJournal;
    assert(journal !== null && typeof journal === 'object' && !Array.isArray(journal));
    const original = journal as Readonly<{runId: string; scopeCid: string; slotCid: string; attemptCid: string; state: string}>;
    assert.deepEqual(Object.keys(original).sort(), ['attemptCid', 'runId', 'scopeCid', 'slotCid', 'state']);
    assert.match(original.runId, /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/u);
    for (const cid of [original.scopeCid, original.slotCid, original.attemptCid]) assert.match(cid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(original.state, unknown ? 'EnteredUnknown' : 'SavedSuccess');
    assert.equal(value.directResultRefusal, unknown ? 'ResultAccessDenied' : undefined);
    assert.equal(value.directPeerClosedBeforeFirstClose, unknown && !cold ? true : undefined);
    assert.equal(value.directRawAbsent, responseLost ? true : undefined);
    if (responseLost) assert.equal(value.directRaw, undefined);
    else {
      const raw = value.directRaw as Readonly<{holdingCid: string; descriptorCid: string; contentCid: string;
        byteCount: number; httpStatus: number; transportEof: boolean; objectCids: string[]}>;
      assert(raw && Number.isSafeInteger(raw.byteCount) && raw.byteCount > 0);
      assert.equal(raw.httpStatus, incompleteRaw ? 503 : 200);
      assert.equal(raw.transportEof, !incompleteRaw);
      assert.equal(raw.objectCids.length, 2);
      assert.notEqual(raw.objectCids[0], raw.objectCids[1]);
      for (const cid of [raw.holdingCid, raw.descriptorCid, raw.contentCid, ...raw.objectCids]) {
        assert.match(cid, /^sha256:[a-f0-9]{64}$/u);
      }
      if (incompleteRaw) {
        assert.equal(raw.byteCount, 8);
        assert.equal(raw.contentCid, 'sha256:0e94b5b974cd7b4cab7cf2729e6996ad87ac3e3c8c5897b3300297549518a4c1');
      } else if (!cold) assert.equal(raw.descriptorCid, value.originalRawArtifactCid);
    }
    const resolved = !cold && !responseLost ? 1 : 0;
    assert.deepEqual([value.directDnsStarted, value.directDnsCompleted, value.peerServerName],
      [resolved, resolved, resolved === 1 ? 'localhost' : null]);
    for (const field of ['calls', 'peerTcpAccepts', 'peerTlsHandshakes', 'peerSocketCloses',
      'modelCredentialReads', 'originalModelStarts']) assert.equal(value[field], cold ? 0 : 1, field);
    if (cold) {
      assert.notEqual(pid, originalPid);
      assert.equal(value.egressChecks, 0);
      if (unknown) {
        assert.equal(value.originalUnknown, true);
        assert.equal(value.zeroResend, true);
        assert.equal(value.originalSavedFirst, undefined);
      } else assert.equal(value.originalSavedFirst, true);
    } else {
      assert.equal(value.checkedWithoutPhysicalWork, true);
      if (!unknown) {
        assert.equal(value.usageCaptures, 1);
        assert(typeof value.originalRawArtifactCid === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value.originalRawArtifactCid));
      }
    }
    return;
  }
  if (caseId === registeredCapabilityCase) {
    assert.equal(value.projectCredential, true);
    assert.equal(value.registeredSdk, true);
    assert.deepEqual(value.capabilityRoutes, ['fixture-chat', 'fixture-unsupported']);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    const journal = value.capabilityJournal as Readonly<{supported: {providerBindingCid: string; savedAttempts: number;
      attemptCid?: string; entrySha256?: string; settlementSha256?: string};
      refused?: {preDispatchRefusal: boolean; scopes: number}}>;
    assert.match(journal.supported.providerBindingCid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(journal.supported.savedAttempts, 1);
    if (phase === registeredCapabilityCase) {
      assert.equal(value.tasks, 2);
      for (const field of ['calls', 'requests', 'projectTlsConnects', 'originalModelStarts', 'usageCaptures']) {
        assert.equal(value[field], 1);
      }
      assert.equal(value.capabilityIssue, 'InstalledModelStructuredModelUnsupported');
      assert(Number.isSafeInteger(value.capabilityCredentialReads) && (value.capabilityCredentialReads as number) > 0);
    } else {
      assert.notEqual(pid, originalPid);
      for (const field of ['calls', 'projectTlsConnects', 'originalModelStarts', 'capabilityCredentialReads']) {
        assert.equal(value[field], 0);
      }
      if (phase === 'cold') assert.equal(value.egressChecks, 0);
    }
    assert.equal(value.deniedCredentialReads, 0);
    if (phase === 'changed-route' || phase === 'retained-unbound') {
      assert.equal(value.changedIssue, phase === 'retained-unbound' ? 'SubmissionRefused' : 'SubmissionConflict');
      assert.equal(value.changedReason, phase === 'retained-unbound' ?
        'model_provider_selection_unavailable' : 'model_provider_selection');
      assert.equal(value.historicalSavedAfterChange, true);
      if (phase === 'retained-unbound') {
        const cid = /^sha256:[0-9a-f]{64}$/u;
        const evidence = value.missingBindingEvidence as {originalSha256: string; admittedSha256: string} | undefined;
        assert(evidence !== undefined);
        for (const identity of [evidence.originalSha256, evidence.admittedSha256, journal.supported.attemptCid,
          journal.supported.entrySha256, journal.supported.settlementSha256]) assert.match(identity as string, cid);
        assert.notEqual(evidence.originalSha256, evidence.admittedSha256);
        assert.equal(value.savedEgressChecks, 0);
      }
    } else {
      assert.deepEqual(journal.refused, {preDispatchRefusal: true, scopes: 0});
      assert.match(value.deniedRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
      assert.notEqual(value.deniedRunDefinitionCid, value.originalRunDefinitionCid);
      assert.equal(value.deniedModelStarts, 0);
      if (phase === 'cold') assert.equal(value.originalSavedFirst, true);
    }
    return;
  }
  if (caseId === externalDuplicateCase) {
    assert.equal(value.registeredSdk, true);
    assert.equal(value.externalTerminal, 'failed');
    assert.equal(value.externalResultIssue, 'ResultAccessDenied');
    for (const name of ['externalAdapterCid', 'externalLockCid', 'originalRunDefinitionCid']) {
      assert.match(value[name] as string, /^sha256:[a-f0-9]{64}$/u);
    }
    for (const name of ['calls', 'projectTlsConnects', 'externalTcp', 'externalCredentialReads',
      'originalModelStarts', 'usageCaptures', 'usageAuthorizations']) assert.equal(value[name], 0, name);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalFailureObserved, true);
      assert.equal(value.egressChecks, 0);
      assert.equal(value.interceptedFetches, 0);
      assert.equal(value.additionalIssue, undefined);
    } else {
      assert.equal(value.interceptedFetches, 2);
      assert.equal(value.additionalIssue, 'SdkAdditionalRequestRefused');
    }
    return;
  }
  if (caseId === externalCase) {
    assert.equal(value.registeredSdk, true);
    for (const name of ['externalAdapterCid', 'externalLockCid', 'originalRunDefinitionCid']) {
      assert.match(value[name] as string, /^sha256:[0-9a-f]{64}$/u);
    }
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalSavedFirst, true);
      for (const name of ['calls', 'projectTlsConnects', 'egressChecks', 'originalModelStarts']) assert.equal(value[name], 0);
    } else {
      for (const name of ['tasks', 'requests', 'calls', 'projectTlsConnects', 'originalModelStarts', 'usageCaptures']) {
        assert.equal(value[name], 1);
      }
      assert.equal(value.usageMode, 'reported');
    }
    return;
  }
  if (Object.hasOwn(registeredHttpFailures, caseId)) {
    const cold = phase === 'cold';
    const status = registeredHttpFailures[caseId];
    assert(cold || phase === caseId);
    assert.equal(value.pid, pid);
    assert.equal(value.httpStatus, status);
    assert.equal(value.terminalFailure, status === 429 ? 'rate_limit' : 'provider_error');
    assert.equal(value.registeredSdk, true);
    assert.equal(value.projectCredential, true);
    const start = cold ? 0 : 1;
    for (const field of ['calls', 'projectTlsConnects', 'originalModelStarts', 'completedHttpFailures',
      'failureCredentialReads']) assert.equal(value[field], start);
    const cid = /^sha256:[0-9a-f]{64}$/u;
    assert.match(value.originalRunDefinitionCid as string, cid);
    const journal = value.failureJournal as {
      state: string; settled: boolean; settledAt: string; scopeCid: string; slotCid: string;
      attemptCid: string; providerBindingCid: string;
      evidence: Record<string, {cid: string; holdingCid: string}>;
    };
    assert.equal(journal.state, 'SavedFailure');
    assert.equal(journal.settled, true);
    assert(Number.isFinite(Date.parse(journal.settledAt)));
    for (const id of [journal.scopeCid, journal.slotCid, journal.attemptCid, journal.providerBindingCid]) assert.match(id, cid);
    assert.deepEqual(Object.keys(journal.evidence).sort(), ['model_attempt_accounting', 'model_attempt_outcome',
      'model_call_attempt', 'model_capture_bundle', 'model_dispatch_authority', 'model_slot_capture']);
    for (const evidence of Object.values(journal.evidence)) {
      assert.match(evidence.cid, cid);
      assert.match(evidence.holdingCid, cid);
    }
    assert.equal(value.originalUnknown, undefined);
    if (cold) {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalSavedFirst, true);
      assert.equal(value.egressChecks, 0);
    } else {
      assert.equal(value.tasks, 1);
      assert.equal(value.requests, 1);
    }
    return;
  }
  if (Object.hasOwn(registeredTerminalFailures, caseId)) {
    assert.equal(value.terminalFailure, registeredTerminalFailures[caseId as keyof typeof registeredTerminalFailures]);
    assert.equal(value.registeredSdk, true);
    assert.equal(value.projectCredential, true);
    assert.equal(value.maxCalls, 1);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalSavedFirst, true);
      for (const field of ['calls', 'egressChecks', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 0);
    } else {
      for (const field of ['tasks', 'requests', 'calls', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 1);
    }
    return;
  }
  if (caseId === 'registered-mixed') {
    assert.equal(value.registeredSdk, true); assert.equal(value.projectCredential, true);
    assert.deepEqual(value.mixedProviders, ['models/http', 'models/messages']);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      for (const field of ['calls', 'egressChecks', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 0);
      assert.equal(value.originalSavedFirst, true); assert.deepEqual(value.dispatchedProviders, []);
    } else {
      for (const field of ['calls', 'tasks', 'requests', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 2);
      assert.deepEqual(value.dispatchedProviders, value.mixedProviders);
    }
    return;
  }
  const singleReported = caseId === 'project-key' || registeredProviderCases.includes(caseId);
  if (caseId === 'usage-reported' || singleReported) {
    assert.equal(value.maxCalls, 1);
  }
  assert.equal(value.registeredSdk, true);
  assert.equal(value.projectCredential, true);
  assert.equal(value.projectTlsConnects, phase === 'cold' || phase === 'missing-key' ? 0 : phase === 'warm' ? 2 : 1);
  if (caseId === 'registered-mistral' || caseId === registeredResponsesCase) {
    assert.equal(value.originalModelStarts, phase === 'cold' ? 0 : 1);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
  }
  if (phase === 'warm') {
    assert.equal(value.tasks, 2); assert.equal(value.requests, 2); assert.equal(value.calls, 2);
  } else if (phase === 'cold') {
    assert.notEqual(pid, originalPid, 'Cold observation requires a distinct original process');
    assert.equal(value.calls, 0); assert.equal(value.egressChecks, 0);
    if (caseId.startsWith('timeout-')) {
      assert.equal(value.timeoutMode, caseId.slice('timeout-'.length));
      assert.equal(value.preserveOriginalState, true);
      assert.equal(value.originalUnknown, true); assert.equal(value.zeroResend, true);
      assert.equal(value.originalSavedFirst, undefined);
    } else assert.equal(value.originalSavedFirst, true);
  } else if (phase.startsWith('timeout-')) {
    assert.equal(value.timeoutMode, phase.slice('timeout-'.length));
    assert.equal(value.preserveOriginalState, true);
    for (const field of ['tasks', 'requests', 'calls']) assert.equal(value[field], 1);
    if (phase === 'timeout-call') {
      assert(typeof value.continuousWrites === 'number' && Number.isSafeInteger(value.continuousWrites) && value.continuousWrites >= 2 && value.continuousWrites < 128);
      assert.equal(value.responseClosedBeforeFirstClose, true);
    }
  } else if (phase === 'missing-key') {
    assert.equal(value.requests, 1); assert.equal(value.calls, 0); assert.equal(value.credentialRefused, true);
  } else {
    assert.equal(value.usageMode, singleReported ? 'reported' : phase.slice('usage-'.length));
    for (const field of ['tasks', 'requests', 'calls', 'usageCaptures']) assert.equal(value[field], 1);
  }
}

export async function runPackedProviderAI(root: string, {repository = fileURLToPath(new URL('../', import.meta.url)),
  retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES,
  release = process.env.ACTQL_PACKED_PROVIDER_RELEASE, publicRegistry = false, cases, command = execute}: ProviderOptions = {}) {
  const software = release ?? retained;
  assert(isAbsolute(root) && typeof software === 'string' && isAbsolute(software) &&
    (release === undefined || retained === undefined),
  'Require fresh external output and one original, matching package cohort');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Normal plugin acceptance refuses runtime overlays');
  const source = checkoutState(repository);
  assert(source.clean, 'Normal plugin acceptance requires clean fixed source');
  if (process.env.GITHUB_SHA) assert.equal(source.revision, process.env.GITHUB_SHA);
  const releaseSelected = release === undefined ? undefined : await readSelectedRelease(release);
  assert(!publicRegistry || releaseSelected !== undefined, 'Public Provider install requires an original release');
  if (releaseSelected !== undefined) {
    const {manifest} = releaseSelected;
    assert.equal(manifest.sourceSha, source.revision);
    assert(nodeReleaseIncludesProvider(manifest.cohort.packages), 'Provider acceptance requires the explicit five-package cohort');
  }
  root = await releaseConsumerDestination(root, [repository, software]);
  await mkdir(root);
  const raw = join(root, 'raw'), casesRoot = join(root, 'cases');
  await mkdir(raw); await mkdir(casesRoot);
  // Each timeout cold read observes its own entered original, never a Saved
  // success or a replacement request. Its state and profile stay in that case.
  const available = [['warm', 'cold'], ['missing-key'], ['project-key', 'cold'], ['rate-limit', 'cold'],
    ['usage-reported', 'cold'], ['usage-zero'], ['usage-absent'],
    ['timeout-headers', 'cold'], ['timeout-body', 'cold'], ['timeout-call', 'cold']];
  const selections = cases === undefined ? available : [...available,
    ...[...registeredProviderCases, ...externalCases, ...registeredInterruptionCases].map(id => [id, 'cold']),
    ...Object.keys(registeredHttpFailures).filter(id => id !== 'rate-limit').map(id => [id, 'cold']),
    [registeredResponsesLimitCase],
    [registeredCapabilityCase, 'cold', 'changed-route', 'retained-unbound'],
    [registeredCheckpointCase, 'approve', 'cold'],
    ...Object.keys(registeredCheckpointFailures).map(id => [id, 'approve']),
    ...directProviderCases.map(id => [id, 'cold']),
    ...Object.keys(registeredTerminalFailures).map(id => [id, 'cold']),
    ...registeredRefusalCases.map(id => [id])].filter(([id]) => cases.includes(id));
  if (cases !== undefined) assert(cases.length > 0 && selections.length === cases.length,
    'Every selected provider case must match once');
  const hasDirect = selections.some(([id]) => directProviderCases.includes(id));
  assert(!hasDirect || releaseSelected === undefined,
    'Direct HTTP acceptance requires the standard retained Client cohort');
  const report: Report = {source: source.revision, preparations: [],
    phases: selections.flatMap(phases => phases.map(phase => ({case: phases[0], phase, status: 'unexecuted',
      reason: phase === 'cold' ? 'Requires the same original case and its confirmed first close' : 'Requires a fresh verified installation'}))),
    complete: false};
  const preparedCases: Prepared[] = [], failures: unknown[] = [], cleanup: unknown[] = [];
  const env = Object.fromEntries(['PATH', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'TMPDIR']
    .filter(key => typeof process.env[key] === 'string').map(key => [key, process.env[key]]));
  for (const phases of selections) {
    const id = phases[0], caseRoot = join(casesRoot, id), caseRaw = join(raw, id);
    const direct = directProviderCases.includes(id);
    await mkdir(caseRoot); await mkdir(caseRaw);
    // Every preparation retains its own exclusive install-node.* diagnostics.
    let externalArchive: string | undefined;
    const run: Command = (cmd, args, options) => command(cmd,
      externalArchive !== undefined && options?.name === 'install-node' ? [...args, externalArchive] : args,
      {...options, raw: caseRaw});
    try {
      const fixture = join(repository, 'scripts/fixtures/external-model-adapter');
      if (externalCases.includes(id)) {
        assert(releaseSelected === undefined, 'The fixture package uses the exact retained ordinary cohort');
        await run('npm', ['pack', '--pack-destination', caseRoot, '--ignore-scripts', '--json'],
          {cwd: fixture, name: 'pack-external-adapter', timeout: 60_000});
        externalArchive = join(caseRoot, 'actql-acceptance-external-openai-adapter-1.0.0.tgz');
      }
      const prepared: Prepared = releaseSelected === undefined ? await prepareHealthPackages({repository, root: caseRoot,
        source: {sha: source.revision, dirty: false}, retained: software,
        ...(direct ? {} : {optionalProvider: join(software, 'optional-provider')}),
        command: run, normalLifecycle: true})
        : await installRelease(caseRoot, software, releaseSelected.manifest, releaseSelected.manifestPath, run, publicRegistry);
      preparedCases.push(prepared);
      const external: ExternalPreparation | undefined = externalArchive === undefined ? undefined : {
        archive: externalArchive,
        sha256: createHash('sha256').update(await readFile(externalArchive)).digest('hex'),
        packageImages: registeredExternalPackageImages(prepared.consumer, externalAdapter),
      };
      if (external !== undefined) {
        assert.equal(external.packageImages[0].name, externalAdapter);
        for (const file of ['package.json', 'index.mjs', 'second-fetch.mjs', 'npm-shrinkwrap.json']) {
          const held: {sha256: string; bytes: number} | undefined =
            external.packageImages[0].images.find(image => image.path === file);
          const bytes = await readFile(join(fixture, file));
          assert.equal(held?.sha256, createHash('sha256').update(bytes).digest('hex'));
          assert.equal(held?.bytes, bytes.length);
        }
        await writeFile(join(prepared.consumer, 'external-package-images.fixture.json'),
          JSON.stringify(external.packageImages) + '\n', {flag: 'wx'});
      }
      report.preparations.push({case: id, consumer: prepared.consumer,
        manifestPath: prepared.manifestPath, manifest: prepared.manifest,
        ...(external === undefined ? {} : {external}),
        ...(publicRegistry && 'publicPayload' in prepared ? {publicPayload: prepared.publicPayload} : {})});
      const checkpoint = registeredCheckpointCases.includes(id);
      const fixtureName = checkpoint ? 'registered-model-checkpoint.fixture.mjs'
        : 'normal-openai-installed.fixture.mjs';
      await copyFile(join(repository, 'scripts/fixtures', fixtureName), join(prepared.consumer, 'fixture.mjs'));
      await copyFile(join(repository, 'scripts/fixtures/external-rest/conformance.mjs'),
        join(prepared.consumer, 'conformance.mjs'));
      await copyFile(join(repository, 'scripts/fixtures/normal-provider-diagnostics.fixture.mjs'),
        join(prepared.consumer, 'normal-provider-diagnostics.fixture.mjs'));
      await copyFile(join(repository, 'adapters/host-node/fixtures/work-observation.fixture.mjs'),
        join(prepared.consumer, 'work-observation.fixture.mjs'));
      let originalPid: number | undefined, originalRunDefinitionCid: unknown, deniedRunDefinitionCid: unknown;
      let originalAuthorityScopeCid: unknown, originalDirectJournal: unknown, originalDirectDependencyClosure: unknown;
      let originalDirectRaw: unknown;
      let interruptionOriginal: Observation | undefined;
      let httpFailureOriginal: Observation | undefined;
      let checkpointOriginal: Observation | undefined;
      let checkpointApproval: {pid: number; settlement: unknown; usageEvidence: unknown} | undefined;
      for (const phase of phases) {
        const record = report.phases.find(value => value.case === id && value.phase === phase);
        assert(record, 'Missing original phase');
        record.status = 'running'; delete record.reason;
        try {
          const args = checkpoint ? ['fixture.mjs', phase, id] : ['fixture.mjs', phase];
          const actual = await run(process.execPath, args,
            {cwd: prepared.consumer, env, name: phase, timeout: 120_000});
          const value = JSON.parse(actual.stdout.trim()) as Observation;
          Object.assign(record, {pid: actual.pid, actual: value, consumer: prepared.consumer});
          checkPackedProviderObservation({caseId: id, phase, pid: actual.pid, originalPid, observation: value});
          if (checkpoint) {
            if (phase === id) checkpointOriginal = value;
            else {
              assert(checkpointOriginal);
              for (const field of ['reference', 'adapter', 'lock', 'sdk', 'taskCid']) {
                assert.deepEqual(value[field], checkpointOriginal[field]);
              }
              if (phase === 'approve') checkpointApproval = {pid: actual.pid,
                settlement: value.settlement, usageEvidence: value.usageEvidence};
              if (phase === 'cold') {
                assert(checkpointApproval);
                assert.notEqual(actual.pid, checkpointApproval.pid);
                assert.deepEqual(value.settlement, checkpointApproval.settlement);
                assert.deepEqual(value.usageEvidence, checkpointApproval.usageEvidence);
              }
            }
          }
          if (registeredInterruptionCases.includes(id)) {
            if (phase === id) interruptionOriginal = value;
            else {
              assert(interruptionOriginal);
              for (const field of ['originalRunDefinitionCid', 'unknownJournal', 'unknownControl', 'cancellation']) {
                assert.deepEqual(value[field], interruptionOriginal[field]);
              }
            }
          }
          if (Object.hasOwn(registeredHttpFailures, id)) {
            if (phase === id) httpFailureOriginal = value;
            else {
              assert(httpFailureOriginal);
              for (const field of ['originalRunDefinitionCid', 'failureJournal']) {
                assert.deepEqual(value[field], httpFailureOriginal[field]);
              }
            }
          }
          if (externalCases.includes(id)) {
            const adapterPath = id === externalDuplicateCase ? 'second-fetch.mjs' : 'index.mjs';
            for (const [field, path] of [['externalAdapterCid', adapterPath], ['externalLockCid', 'npm-shrinkwrap.json']]) {
              assert.equal(value[field], 'sha256:' + external!.packageImages[0].images.find(image => image.path === path)?.sha256);
            }
          }
          if ((id === externalCase || id === registeredResponsesCase) && phase !== 'cold') {
            const usage = JSON.parse(await readFile(join(prepared.consumer, 'usage-original.json'), 'utf8'));
            assert.match(usage.raw_response_artifact_cid, /^sha256:[0-9a-f]{64}$/u);
            assert.equal(usage.input_tokens, 2); assert.equal(usage.output_tokens, 3);
          }
          if (direct) {
            if (phase === id) {
              originalAuthorityScopeCid = value.originalAuthorityScopeCid;
              originalDirectJournal = value.directJournal;
              originalDirectDependencyClosure = value.directDependencyClosure;
              originalDirectRaw = value.directRaw;
            } else {
              assert.equal(value.originalAuthorityScopeCid, originalAuthorityScopeCid);
              assert.deepEqual(value.directJournal, originalDirectJournal);
              assert.deepEqual(value.directDependencyClosure, originalDirectDependencyClosure);
              assert.deepEqual(value.directRaw, originalDirectRaw);
            }
          }
          if (direct || id === 'registered-mixed' || id === 'registered-mistral' || id === registeredResponsesCase ||
              externalCases.includes(id) ||
              id === registeredCapabilityCase || Object.hasOwn(registeredTerminalFailures, id)) {
            if (phase === id) originalRunDefinitionCid = value.originalRunDefinitionCid;
            else assert.equal(value.originalRunDefinitionCid, originalRunDefinitionCid);
          }
          if (id === registeredCapabilityCase) {
            if (phase === id) deniedRunDefinitionCid = value.deniedRunDefinitionCid;
            if (phase === 'cold') assert.equal(value.deniedRunDefinitionCid, deniedRunDefinitionCid);
          }
          if (phase === id) originalPid = actual.pid;
          record.status = 'passed';
        } catch (failure) {
          record.status = 'failed'; record.failure = nodeBenchmarkFailure(failure); throw failure;
        }
      }
      if (external !== undefined) {
        assert.deepEqual(registeredExternalPackageImages(prepared.consumer, externalAdapter), external.packageImages);
        assert.equal(createHash('sha256').update(await readFile(external.archive)).digest('hex'), external.sha256);
      }
    } catch (failure) {failures.push(failure);}
  }
  for (const prepared of preparedCases) {
    try {
      if (publicRegistry) {
        assert('publicPayload' in prepared);
        assert.deepEqual(await verifyPublicConsumer(prepared.consumer, prepared.manifest, 'provider-ai-sdk'),
          prepared.publicPayload, 'Public Provider installation changed during acceptance');
      } else await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    }
    catch (failure) {cleanup.push(failure);}
  }
  try {assert.deepEqual(checkoutState(repository), source);}
  catch (failure) {cleanup.push(failure);}
  if (releaseSelected !== undefined) {
    try {
      assert.deepEqual(await readFile(releaseSelected.manifestPath), releaseSelected.manifestBytes);
      assert.deepEqual(await verifyPackageRelease(software), releaseSelected.manifest);
    } catch (failure) {cleanup.push(failure);}
  }
  report.complete = failures.length === 0 && cleanup.length === 0 && report.phases.every(value => value.status === 'passed');
  report.failures = failures.map(nodeBenchmarkFailure); report.cleanup = cleanup.map(nodeBenchmarkFailure);
  await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  if (failures.length === 1 && cleanup.length === 0) throw failures[0];
  if (failures.length) throw new AggregateError([...failures, ...cleanup],
    'OptionalProviderAcceptanceFailed', {cause: failures[0]});
  if (cleanup.length) throw new AggregateError(cleanup, 'OptionalProviderSoftwareChanged');
  assert(report.complete, 'Every original phase must complete before normal acceptance');
  return report;
}

async function readSelectedRelease(directory: string) {
  const manifest = await verifyPackageRelease(directory);
  const manifestPath = join(directory, 'release.json');
  return {manifest, manifestPath, manifestBytes: await readFile(manifestPath)};
}

async function installRelease(root: string, release: string, manifest: ReleaseManifest, manifestPath: string,
  run: Command, publicRegistry: boolean) {
  const consumer = join(root, 'consumer');
  const env = publicConsumerEnvironment(process.env, root);
  await Promise.all([consumer, env.HOME, env.TMPDIR].map(path => mkdir(path)));
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  if (publicRegistry) {
    await writeFile(env.npm_config_userconfig, '');
    await writeFile(env.npm_config_globalconfig, '');
    await run('npm', publicInstallCommand(manifest, 'provider-ai-sdk'), {cwd: consumer, env, name: 'install-release'});
    const publicPayload = await verifyPublicConsumer(consumer, manifest, 'provider-ai-sdk');
    return {manifest, manifestPath, consumer, publicPayload};
  }
  await run('npm', ['install', '--ignore-scripts=false', '--no-audit', '--no-fund', '--no-save', '--omit=optional',
    ...manifest.packages.map(row => join(release, row.file))], {cwd: consumer, env, name: 'install-release'});
  await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  return {manifest, manifestPath, consumer};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [root, selection, ...extra] = process.argv.slice(2);
  assert(root !== undefined && [undefined, '--registered-only', '--registered-safety-only', '--registered-external-only',
    '--registered-capabilities-only', '--registered-responses-only', '--registered-checkpoints-only',
    '--registered-interruptions-only', '--registered-http-failures-only', '--registered-authority-only', '--direct-only'].includes(selection)
    && extra.length === 0,
  'usage: test-packed-provider-ai-sdk.mjs ABSOLUTE_FRESH_OUTPUT [--registered-only | --registered-safety-only | --registered-external-only | --registered-capabilities-only | --registered-responses-only | --registered-checkpoints-only | --registered-interruptions-only | --registered-http-failures-only | --registered-authority-only | --direct-only]');
  const cases = selection === '--direct-only' ? directProviderCases
    : selection === '--registered-only' ? registeredProviderAcceptanceCases
    : selection === '--registered-safety-only' ? registeredSafetyAcceptanceCases
    : selection === '--registered-external-only' ? externalCases
    : selection === '--registered-responses-only' ? [registeredResponsesCase, registeredResponsesLimitCase]
    : selection === '--registered-capabilities-only' ? [registeredCapabilityCase]
    : selection === '--registered-checkpoints-only' ? registeredCheckpointCases
    : selection === '--registered-interruptions-only' ? registeredInterruptionCases
    : selection === '--registered-authority-only' ? registeredAuthorityAcceptanceCases
    : selection === '--registered-http-failures-only' ? Object.keys(registeredHttpFailures) : undefined;
  process.exitCode = await runLocalCheck({root: fileURLToPath(new URL('../', import.meta.url)),
    heavy: false, timeoutSeconds: 300, graceSeconds: 5,
    steps: [{name: 'Original normal provider, usage and timeout consumers', command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runPackedProviderAI} from './scripts/test-packed-provider-ai-sdk.mjs'; await runPackedProviderAI(process.argv[1], JSON.parse(process.argv[2]));",
        root, JSON.stringify({cases})]}]});
}
