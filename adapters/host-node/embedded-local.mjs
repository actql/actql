import {composeInstalledSourceEnvironment} from './installed-funded-environment.mjs';
import {localProjectFilesystem} from './local-files-native.mjs';
import {createInstalledHostServices, installedSourceConfigurationReader,
  completeInstalledSourceInitialization, borrowInstalledSourceInitialization,
  retireInstalledSourceInitialization} from './installed-host-services.mjs';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../local-node/request-preparation-adapter.mjs';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
import {runtimeField, runtimeIsError, runtimeIsOk, runtimeIsOkRequired, runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
// Private selected-namespace DATA reader. Exporting this pure operation does
// not expose the startup issuer or authenticate a caller-created packet.
export {snapshotInitialControlHostInput} from './initial-control-host-input.mjs';
export {readSourceManagedOriginalInput} from './source-managed-original-input.mjs';
export {snapshotInitialControlHostInput as readInitialControlHostInput}
  from './initial-control-host-input.mjs';
import {installClientRunPlan} from './client-run-plan.mjs';
import {configureInferEvidence} from './infer-evaluation-evidence.mjs';
// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {snapshotHostCapacityPolicy, snapshotHostLookupExecutionPolicy,
  selectInstalledHostEnvironment, selectInstalledLocalMaterializationEnvironment, localFilesLookupExecutionPolicy, localResourceLookupExecutionPolicy} from './installed-host-policy.mjs';
import {createHash, createPublicKey, randomBytes, randomUUID} from 'node:crypto';
import {mkdir, readFile, stat} from 'node:fs/promises';
import {homedir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {existsSync} from 'node:fs';
import {validClientConnection} from '../../packages/client-wire/index.mjs';
import {createEmbeddedHostRegistry, installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {installHttpRequestPreparation} from './http-request-preparation.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent}
  from './client-request-journal.mjs';
// The selected startup captures these exact existing Owner operations from
// this namespace. An export alone supplies neither admission nor authority.
export {openClientRequestJournal as openOriginalHostRequestJournal,
  observeOriginalClientRequestJournalCustody as observeOriginalHostRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent as assertOriginalHostRequestJournalFacilityCurrent};
import {installNodeClientSubmission, issueNodeClientSubmissionEpoch} from './client-submission.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
export {admitHostRootFormat as admitOriginalHostRootFormat};
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientEffectRun} from './client-effect-run.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {selectAcquiredEffectSources} from './acquired-effect-sources.mjs';
import {withLocalExecutionPauseHandler} from '../local-node/retained-store.mjs';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {BOUND_SOURCE_INVENTORY, BOUND_SOURCE_SUBMISSION,
  ordinarySourceDescriptors} from './ordinary-source-binding.mjs';
import {capturedDuckDBConfiguration} from './captured-duckdb-source.mjs';
import {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import {prepareEffectCaptureResources} from './effect-capture-resources.mjs';

// Keep this retirement callback outside the construction/current closure.
// Its binding retains only the existing Host bag and fixed frame; it must
// not prolong captured Request/Definition or restored material aliases across
// a consuming resource return after the current callback has been severed.
function retireEffectCaptureResourceFrame(record, liveRuns, entry, view) {
  if (record.computeLiveRuns !== liveRuns || !liveRuns.has(entry) ||
      entry.resources !== view || entry.closed) {
    throw clientOperationError('ForeignEffectCaptureResources');
  }
  entry.resources = undefined; entry.closed = true;
  liveRuns.delete(entry);
}
import {retireCompletedEffectfulCapture, suspendCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {sourceAliasPublication, sourceAliasPublicationOriginal,
  retireSourceAliasPublicationOriginal} from './source-alias-publication.mjs';
import {installedModelEnvironment, readInstalledModelExecution, consumeInstalledModelPreparationRefusal,
  readInstalledModelDependencies, installModelProviders,
  admitInstalledModelProvider, admitInstalledModelProviderBinding} from
  './installed-model.mjs';
import {loadInstalledProjectConfiguration, installedProjectOriginalsForRuntime,
  retireInstalledProjectConfiguration}
  from './installed-project-configuration.mjs';
import {beginInitialControlInstallation, assertInitialControlInstallationCurrent,
  readInitialControlInstallationAsset, readInitialControlInstallationInput}
  from './node-initial-control-installation.mjs';
import {loadInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {loadInstalledProjectMockAnswers} from '../local-node/installed-project-mock-answers.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {prepareInstalledProjectMock, installPreparedProjectMockSources, installedMockRequestRealization}
  from '../local-node/installed-project-mock.mjs';
import {createDeclaredFileInstallationInventory} from '../local-node/declared-file-installation.mjs';
import {prepareInstalledProjectLocalFiles, installPreparedProjectLocalFiles, LOCAL_FILES_DEFAULT_LIMITS}
  from '../connectors/local/host/installed-project-files.mjs';
import {installPreparedProjectLocalFileEffects}
  from '../connectors/local/host/installed-project-file-effects.mjs';
import {installPreparedProjectMockEffects, observeInstalledMockEffectResources}
  from '../local-node/installed-mock-row-effect.mjs';
import {installedRuntimeBundleCid} from './source-profile-json.mjs';
import {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import {ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun, finishInstalledEffectModelScope,
  installedEffectModelPreparation}
  from './installed-effect-managed-run.mjs';
import {prepareSourceManagedInstallation, assertSourceManagedInstallationCurrent,
  assertSourceManagedPreparationCurrent, prepareManagedComputeInstallation,
  assertManagedComputeInstallationCurrent, assertManagedComputePreparationCurrent,
  prepareProjectSourceManagedInstallation}
  from './node-source-managed-installation.mjs';
import {installNodeInferRun} from './installed-infer-run.mjs';
import {openNodeComposedInferProvider, finishNodeInferOriginalReadScopes} from './infer-operation.mjs';
import {bindInferOriginalReadRecipe} from './infer-original-installation.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {snapshotInstalledCalendar, installedCalendarIdentityCid,
  installedCalendarSelection, admitInstalledCalendar} from './installed-calendar.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installedRunWaitDecision, issueInstalledRunObservationKey,
  issueInstalledUnpublishedRunState} from
  '../host-common/run-state-observation.mjs';
import {installedEffectIdentity, installedEffectPaths, loadInstalledEffects,
  publishInstalledEffectProfile} from
  './installed-effect.mjs';
import {composeInstalledEffects, installedEffectFor, installedUpdateTargets} from './installed-effect-inventory.mjs';
import {installedRowEffectDescriptors, validateInstalledUpdateOwnerSelections}
  from './installed-row-effect.mjs';
import {installUpdateTargetOriginals} from './installed-update-originals.mjs';
import {runUpdateSelectionCid, createUpdateTargetOriginalShapeControl}
  from './update-target-original-shape.mjs';
import {assertInstalledConnectorTable} from './installed-connectors.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey} from
  './local-continuation-evidence.mjs';
import {installedSourceIdentity, installedSourcePaths, loadInstalledSources,
  installedSourceFor, installedSourceReadAccesses, installedSourceReadBindings,
  publishInstalledSourceProfile} from
  './installed-source.mjs';
import {createDiagnosticObserver} from
  '../host-common/diagnostic-observer.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installHostObservation, observationTraceParent,
  captureManagedRunObservation} from '../host-common/observation.mjs';
import {ledgerLimitsFields, ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {installNodeClientDispatchOwner, confirmNodeRunCancellation, cancelNodeRunContinuation,
  observeNodeRestoredModelStop, observeNodeRestoredLocalStop, recordNodeRunPhysicalStop} from './client-dispatch-owner.mjs';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {originalInitialControlClose, retainInstalledHostInitializationFailure, retainInstalledHostRuntimeFailure} from
  './installed-host-cleanup.mjs';
import {issueInferTrustedRuntimeView, checkInferTrustedRuntimeView,
  forgetInferTrustedRuntimeView, associateInferTrustedStartupView,
  requireInferTrustedStartupView, borrowInferTrustedStartupView,
  forgetInferTrustedStartupView, bindInferTrustedStore,
  checkInferTrustedStore, selectedInferTrustedStoreDimensions, bindInferTrustedSdkStaticModules,
  checkInferTrustedSdkStaticModules, checkInferTrustedSdkEagerModules} from './infer-trusted-runtime-view.mjs';
import {verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState, observeAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
export {
  openLocalPublicationStore as openOriginalHostPublicationStore,
  assertOriginalLocalPublicationStoreFacilityCurrent as assertOriginalHostPublicationStoreFacilityCurrent,
  prepareLocalPublicationStoreOwnership as prepareOriginalHostPublicationOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership as assertOriginalHostPublicationOwnershipCurrent,
  closePreparedLocalPublicationStoreOwnership as closeOriginalHostPublicationOwnership,
} from '../store-local/publication-store.mjs';
import {prepareHostJournalInstallation} from './node-host-journal-installation.mjs';
import {prepareHostResultPublicationInstallation} from './node-host-result-installation.mjs';
import {enableNodeCompileCache} from './compile-cache.mjs';
import * as publicationStoreModule from '../store-local/publication-store.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {installLocalRetainedStore, installLocalSnapshotStore} from
  '../local-node/retained-store.mjs';
import {installHostRunAcceptance} from './client-checkpoints.mjs';
import {createLocalCheckpointAnswer} from './local-checkpoint-answer.mjs';
import {installClientOwnerObservations} from './client-owner-observations.mjs';
import {installClientStaticPlan} from './client-interactive-plan.mjs';
import {installClientRunInspect} from './client-run-inspect.mjs';
import {createClientOwnerCursorCodec} from './client-owner-cursor.mjs';
import {installClientEffectObservations} from './client-effect-observations.mjs';
import {assertEffectTargetReadBinding, effectTargetReadContinuation} from
  './effect-target-read-continuation.mjs';
import {EFFECT_TARGET_CONTINUATION} from './effect-target-read-inventory.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate,
  observeInstalledAccount} from './local-account-config.mjs';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan, sourceFreeValuesAdmissionEvidence, sourceFreePlanOriginal, sourceFreeTaskPlan, prepareTimedClientInvocation,
  sourceFreeEffectPublicationPlan, acquiredEffectPublicationAdmission,
  openSourceFreeEffectComputation,
  acquiredTaskRunAdmission, inferTaskRunAdmission, restoreInferTaskRunAdmission, selectRestoredInferOccurrence, serializationTaskRunAdmission,
  selectInstalledSerializationGraph} from
  './local-values-plan.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';

const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(import.meta.url);

const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const now = () => new Date().toISOString();
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const plus = (date, milliseconds) => new Date(Date.parse(date) +
  milliseconds).toISOString();
const clientOperationError = (code, cause) => Object.assign(
  new Error(code, cause === undefined ? undefined : {cause}), {code});
const profiles = createEmbeddedHostRegistry(sameEmbeddedInstallation);

// Only the actual selected startup may retain this original module operation.
// It checks the existing registry's original candidate/Host, not a caller
// callback, DATA/CID, eight-reference view or capacity/authority declaration.
export function assertInitialControlHostPreparation(originals) {
  if (originals?.supplier !== openPreparedInstalledHost ||
      originals?.moduleLifetime !== import.meta) {
    throw clientOperationError('InstalledHostPreparationChanged');
  }
  profiles.assertPreparation(originals.host, originals.installation, originals.generation);
}

// Retained Run Resource currentness is distinct from new preparation. The
// manager must establish its exact adopted Run before using this identity
// projection; closing ingress does not retire that original Host generation.
export function assertRetainedSourceManagedHost(originals) {
  if (originals?.supplier !== openPreparedInstalledHost ||
      originals?.moduleLifetime !== import.meta) {
    throw clientOperationError('InstalledHostPreparationChanged');
  }
  profiles.assertRetainedPreparation(originals.host, originals.installation, originals.generation);
}

// The actual selected startup captures this fixed operation, not a caller
// predicate. Its installation phase may check the original Host before a
// request exists. A request phase additionally requires that SAME pending
// in-process request; neither check issues Source capacity or authority.
export function assertSourceManagedHostPreparation(originals, originalOwnedRequest) {
  assertInitialControlHostPreparation(originals);
  if (originalOwnedRequest !== undefined) {
    profiles.assertSourceRequest(originals.host, originals.installation,
      originals.generation, originalOwnedRequest);
  }
}

// Fixed namespace projection for the actual selected Host/Journal supplier.
// The same registry entry retained these originals before root-format I/O;
// copied paths, matching CIDs or this record alone cannot issue a facility.
export function readHostJournalPreparation(originals) {
  assertInitialControlHostPreparation(originals);
  return profiles.hostJournalPreparation(originals.host, originals.installation,
    originals.generation);
}

// Original Common/control and authority correspondence, not a factory for a
// resource service. The actual Root must already hold its separate purpose.
export function readHostResultPublicationPreparation(originals) {
  const journal = readHostJournalPreparation(originals);
  const runtime = originals.installation.projectRuntime;
  const control = runtimeCore(runtime).publicationControl;
  return Object.freeze({runtime, control, root: journal.root, principalId: journal.principalId,
    privateEvidenceKey: originals.installation.effectInstallation?.privateEvidenceKey ??
      originals.installation.mockAccount?.evidenceKey.key,
    storeAuthorityCid: localPublicationStoreAuthorityCid(journal.root, journal.principalId)});
}

// Only the fixed startup calls this after the same pending SDK request has
// produced its opaque checked Program. Bounds DATA cannot issue its service.
export function readHostResultPublicationRunRequirements(originals, prepared) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  const moon = originals.installation.projectRuntime;
  const resultCount = moon.clientProgramResultCount(prepared);
  const maxRows = moon.clientProgramValuesMaxRows(prepared);
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  return Object.freeze({resultCount, maxRows, maxContractBytes: localContractLimits.maxWireBytes});
}

export function readHostEffectResultPublicationRunRequirements(originals, prepared) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  const moon = originals.installation.projectRuntime;
  const resultCount = moon.clientProgramEffectResultCount(prepared);
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  return Object.freeze({resultCount, maxRows: localOutputLimits.maxRows,
    maxContractBytes: localContractLimits.maxWireBytes});
}

// Same live ingress lineage only. Copies, CIDs and retained cold DATA cannot
// recreate a pending request or issue its Source installation/child.
export function originalSourceManagedHostRequest(originals, derivedRequest) {
  assertSourceManagedHostPreparation(originals);
  return profiles.originalSourceRequest(originals.host, originals.installation,
    originals.generation, derivedRequest);
}

// The selected Source Root captures this fixed original projection. A copied
// packet, equal configuration or public view cannot reconstruct the private
// registry's same Host/installation/generation association.
export function readInstalledMockPreparation(originals) {
  assertSourceManagedHostPreparation(originals);
  const retained = profiles.mockPreparation(originals.host, originals.installation,
    originals.generation);
  if (retained.view === undefined) throw clientOperationError('InstalledMockPreparationUnavailable');
  return retained.view.originalsForRuntime(retained.runtime);
}

// This exact Connector factory result is retained by the existing Host before
// preparing its service. Equal connection text or a caller's view cannot
// replace the same issued Project/runtime association.
export function readInstalledProjectSourcePreparation(originals) {
  assertSourceManagedHostPreparation(originals);
  const {projectSourcePreparation, projectRuntime, project} = originals.installation;
  if (projectSourcePreparation === undefined || project === undefined) {
    throw clientOperationError('InstalledProjectSourcePreparationUnavailable');
  }
  const bundle = projectSourcePreparation.originalsForRuntime(projectRuntime);
  if (bundle.project !== installedProjectOriginalsForRuntime(project, projectRuntime)) {
    throw clientOperationError('ForeignInstalledProjectSourcePreparation');
  }
  return bundle;
}

// Static contract strings belong to the same installed Host, not each Run.
// The private installation bag is cut only after successful final retirement.
function installedManagedRunContracts(originals) {
  const installation = originals.installation;
  const retained = installation.managedRunContracts;
  if (retained !== undefined) {
    if (retained.initialControl !== installation.initialControl) {
      throw clientOperationError('ForeignInstalledManagedRunContracts');
    }
    return retained;
  }
  const aoa = JSON.parse(readInitialControlInstallationAsset(
    installation.initialControl, originals, 'spec/contracts/actql-aoa.json'));
  const contracts = Object.freeze({initialControl: installation.initialControl,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    expression: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])});
  installation.managedRunContracts = contracts;
  return contracts;
}

// Installed Root owns the exact interpreted sequence contracts. The funded
// preparation route requires this retained nominal admission, not a mutable
// process cache hit or re-interpretation under a per-request borrowed quote.
export function prepareInstalledSequenceContractOriginal(originals) {
  assertSourceManagedHostPreparation(originals);
  const installation = originals.installation;
  const moon = installation.projectRuntime;
  const old = installation.sequenceContractOriginal;
  if (old !== undefined) {
    if (old.moon !== moon || old.control !== installation.initialControl) {
      throw clientOperationError('ForeignInstalledManagedRunContracts');
    }
    return old;
  }
  if (typeof moon?.clientPrepareInstalledSequenceContracts !== 'function' ||
      typeof moon?.clientPrepareInstalledCompilationManifests !== 'function') {
    throw clientOperationError('NodeManagedRunRuntimeUnavailable');
  }
  // Shared compiler manifests are admitted during fixed installation, not
  // lazily constructed under a later request's preparation reservation.
  checked(moon.clientPrepareInstalledCompilationManifests());
  const registry = readInitialControlInstallationAsset(installation.initialControl,
    originals, 'spec/dependencies/aoa-pipeline-registry.json');
  const contracts = installedManagedRunContracts(originals);
  const admission = checked(moon.clientPrepareInstalledSequenceContracts(registry,
    contracts.values, contracts.expression, contracts.ordered));
  const original = Object.freeze({moon, control: installation.initialControl,
    registry, contracts, admission});
  installation.sequenceContractOriginal = original;
  return original;
}

// The real Root already retained the separate managed-Compute premise before
// the packet snapshot. This exact checked original supplies only the existing
// Core inventory for its bounds check, never a replacement issuer or Ledger.
export function readSourceManagedRunRequirements(originals, checkedPrepared) {
  return readSourceManagedRunRequirementsOwned(originals, checkedPrepared);
}

// Project the SAME plan retained before the Node supplier acquires its parent.
// A six-number match cannot upgrade the former Compute-only Effect route.
export function readSourceManagedEffectRunRequirements(originals, checkedPrepared, operationPlan) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  const installation = originals.installation, moon = installation.projectRuntime;
  const run = installation.computeRuns?.get(checkedPrepared);
  if (run === undefined || run.runtime !== moon || run.prepared !== checkedPrepared || run.closed ||
      run.preparationKind !== 'effect-plan' || run.operationPlan !== operationPlan ||
      typeof moon?.clientProgramInstalledEffectManagedPlanRequirements !== 'function') {
    throw clientOperationError('NodeManagedRunAdmissionUnavailable');
  }
  const limits = moon.clientProgramInstalledEffectManagedPlanRequirements(operationPlan);
  if (!Array.isArray(limits) || limits.length !== 6 ||
      limits.some(value => typeof value !== 'bigint' || value < 0n) ||
      limits.slice(0, 3).some(value => value > 2147483647n)) throw clientOperationError('InvalidHostRuntimeResult');
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  if (installation.computeRuns?.get(checkedPrepared) !== run || run.closed || run.operationPlan !== operationPlan) {
    throw clientOperationError('ForeignInstalledEffectManagedRun');
  }
  return Object.freeze({planningWork: Number(limits[0]), attempts: Number(limits[1]),
    holdings: Number(limits[2]), transferBytes: limits[3], retainedBytes: limits[4], executionBytes: limits[5]});
}

function readSourceManagedRunRequirementsOwned(originals, checkedPrepared) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  const {initialControl, projectRuntime: moon} = originals.installation;
  if (moon.clientProgramAcquisitionCount(checkedPrepared) === 0) {
    // A Source installation also owns its joint Compute purpose. The exact
    // checked zero-capture graph, not the configured Source count, selects
    // empty acquisition inputs on that same original parent.
    return readManagedComputeRunRequirements(originals, checkedPrepared);
  }
  const projectSources = originals.installation.projectSourcePreparation === undefined ? undefined :
    readInstalledProjectSourcePreparation(originals);
  const retained = projectSources === undefined ? profiles.mockPreparation(originals.host,
    originals.installation, originals.generation) : undefined;
  const requirements = moon.clientProgramInstalledManagedRunRequirements;
  if ((projectSources === undefined && retained.runtime !== moon) || initialControl === undefined ||
      typeof requirements !== 'function') {
    throw clientOperationError('NodeManagedRunAdmissionUnavailable');
  }
  const bundle = projectSources ?? retained.view.originalsForRuntime(moon);
  const asset = path => readInitialControlInstallationAsset(initialControl, originals, path);
  const contracts = installedManagedRunContracts(originals);
  // Each selected physical child reads its original complete bounded file
  // once. Its original raw bytes remain charged alongside decoded/captured
  // rows; this is not a byte total sampled from the successful template.
  const documentBytes = 1048576n;
  const declarations = [], transferBytes = [], executionBytes = [];
  const count = moon.clientProgramAcquisitionCount(checkedPrepared);
  if (!Number.isSafeInteger(count) || count < 1 || count > 32) {
    throw clientOperationError('InstalledSourcePreparationMismatch');
  }
  const prepareRequirement = moon.clientProgramPrepareLocalQueryRequirement;
  const registry = prepareInstalledSequenceContractOriginal(originals).admission;
  for (let stage = 0; stage < count; stage++) {
    // Both Mock and configured Sources follow the checked capture inventory,
    // not installation order. Repeated views retain separate occurrence slots.
    const requirement = checked(Reflect.apply(prepareRequirement, moon,
      [checkedPrepared, stage, 0, registry, contracts.values, contracts.expression, contracts.ordered]));
    const sourceRef = moon.clientProgramQueryRequirementSourceRef(requirement);
    const matches = bundle.sources.filter(source =>
      JSON.parse(source.wire).views.some(view => view.source_ref === sourceRef));
    if (matches.length !== 1) throw clientOperationError('InstalledSourcePreparationMismatch');
    const source = matches[0];
    declarations.push(source.declaration);
    transferBytes.push(projectSources === undefined ? documentBytes
      : BigInt(source.limits.maxPages) * BigInt(source.limits.maxPageBytes));
    executionBytes.push(projectSources === undefined ? documentBytes
      : BigInt(source.limits.maxPageBytes));
  }
  const limits = checked(Reflect.apply(requirements, moon, [
    checkedPrepared, declarations,
    asset('spec/contracts/actql-query-acquisition.json'),
    asset('spec/contracts/actql-query-process-evidence.json'),
    transferBytes, executionBytes,
    prepareInstalledSequenceContractOriginal(originals).admission,
    contracts.values, contracts.expression, contracts.ordered]));
  if (!Array.isArray(limits) || limits.length !== 6 ||
      limits.some(value => typeof value !== 'bigint' || value < 0n) ||
      limits.slice(0, 3).some(value => value > 2147483647n)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  if (projectSources === undefined) retained.view.originalsForRuntime(moon);
  else if (readInstalledProjectSourcePreparation(originals) !== projectSources) {
    throw clientOperationError('ForeignInstalledProjectSourcePreparation');
  }
  return Object.freeze({planningWork: Number(limits[0]), attempts: Number(limits[1]),
    holdings: Number(limits[2]), transferBytes: limits[3],
    retainedBytes: limits[4], executionBytes: limits[5]});
}

// Original immutable installed context for the funded ordinary preparation
// driver. Shared catalog/contracts remain this installation's dependencies.
export function retireSourceManagedInitialPreparation(originals, prepared) {
  assertSourceManagedHostPreparation(originals);
  const retire = originals.installation.retireInitialPreparation;
  if (typeof retire !== 'function') throw clientOperationError('InstalledSourcePreparationCleanupPending');
  retire(prepared);
}

export function readLocalPreparationContext(originals) {
  assertSourceManagedHostPreparation(originals);
  const installation = originals.installation;
  const context = installation.closedValuesPreparationContext;
  if (context === undefined || context.runtime !== installation.projectRuntime ||
      context.control !== installation.initialControl ||
      installation.sequenceContractOriginal === undefined) return undefined;
  const rows = Object.getOwnPropertyDescriptor(context, 'valuesMaxRows');
  if ((rows !== undefined && !Object.hasOwn(rows, 'value')) ||
      rows?.value !== installation.valuesMaxRows) {
    throw clientOperationError('NodeLocalPreparationAdmissionUnavailable');
  }
  const mode = Object.getOwnPropertyDescriptor(context, 'retainedRelationOutput');
  if (mode === undefined || !Object.hasOwn(mode, 'value') || typeof mode.value !== 'boolean' ||
      mode.value !== installation.retainedRelationOutput) {
    throw clientOperationError('NodeLocalPreparationAdmissionUnavailable');
  }
  return context;
}

// Same original Source inventory serves its retained Plan and legacy purpose
// quote. A Source capacity is immutable DATA; it grants neither a read nor a
// second Resource Run. Actual source readers retain their existing authority.
function retainedManagedCaptureInventory(originals, run, contracts) {
  const moon = originals.installation.projectRuntime, checkedPrepared = run.prepared;
  if (run.runtime !== moon || run.closed || Object.hasOwn(run, 'failure') ||
      originals.installation.computeRuns?.get(checkedPrepared) !== run ||
      run.sourceProfile !== originals.installation.managedSourceProfile) {
    throw clientOperationError('ForeignInstalledComputeRun');
  }
  if (run.sourceCapacities === undefined) {
    const count = moon.clientProgramAcquisitionCount(checkedPrepared);
    if (!Number.isSafeInteger(count) || count < 1) {
      throw clientOperationError('InstalledSourcePreparationMismatch');
    }
    const inventory = [];
    const installed = prepareInstalledSequenceContractOriginal(originals);
    for (let stage = 0; stage < count; stage++) {
      if (typeof moon.clientProgramSelectInstalledSourceInput !== 'function' ||
          typeof moon.clientProgramSelectedSourceInputKind !== 'function' ||
          typeof moon.clientProgramSelectedSourceInputRef !== 'function') {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      const selection = checked(moon.clientProgramSelectInstalledSourceInput(
        checkedPrepared, run.request, stage, 0));
      const kind = moon.clientProgramSelectedSourceInputKind(selection);
      if (kind !== 'query' && kind !== 'whole-input' || kind === 'whole-input' && count !== 1) {
        throw clientOperationError('InstalledSourcePreparationMismatch');
      }
      const adapter = installedSourceFor(run.sourceProfile,
        moon.clientProgramSelectedSourceInputRef(selection));
      let requirement, selected;
      if (kind === 'whole-input') {
        if (typeof adapter.managedWholeSourceCapacity !== 'function') {
          throw clientOperationError('InstalledSourceCapacityUnavailable');
        }
        selected = adapter.managedWholeSourceCapacity({preparedProgram: checkedPrepared,
          sourceSelection: selection, installedContracts: installed.admission});
        if (selected?.wholeInput !== true) throw clientOperationError('InstalledSourceCapacityUnavailable');
      } else {
        requirement = checked(run.queryTimePreparation === undefined
          ? moon.clientProgramPrepareLocalQueryRequirement(
            checkedPrepared, stage, 0, installed.admission,
            contracts.values, contracts.expression, contracts.ordered)
          : moon.clientProgramPrepareLocalQueryRequirementAtQueryTime(
            checkedPrepared, stage, 0, run.queryTimePreparation, run.request,
            installed.admission, contracts.values, contracts.expression, contracts.ordered));
        selected = adapter.managedCaptureCapacity(requirement);
      }
      if (selected?.capacity === undefined || typeof selected.transferBytes !== 'bigint' ||
          typeof selected.executionBytes !== 'bigint' ||
          selected.transferBytes < 0n || selected.executionBytes < 0n) {
        throw clientOperationError('InstalledSourceCapacityUnavailable');
      }
      inventory.push(Object.freeze({kind, selection, adapter, requirement, capacity: selected.capacity,
        transferBytes: selected.transferBytes, executionBytes: selected.executionBytes}));
    }
    run.sourceCapacities = Object.freeze(inventory);
  }
  if (run.closed || Object.hasOwn(run, 'failure') ||
      originals.installation.computeRuns?.get(checkedPrepared) !== run ||
      run.sourceProfile !== originals.installation.managedSourceProfile) {
    throw clientOperationError('ForeignInstalledComputeRun');
  }
  return run.sourceCapacities;
}

// The Request manager invokes this only while its original constructor input
// remains borrowed. Complete/adopt retains this exact Plan; no Run quote or
// sequence preparation is substituted after an original refusal.
function prepareManagedComputeCapturePlan(originals, run, invocationOriginal) {
  const {projectRuntime: moon, retainedRelationOutput} = originals.installation;
  if (typeof retainedRelationOutput !== 'boolean') {
    throw clientOperationError('NodeManagedRunRuntimeUnavailable');
  }
  const contracts = installedManagedRunContracts(originals);
  const inventory = retainedManagedCaptureInventory(originals, run, contracts);
  const installed = prepareInstalledSequenceContractOriginal(originals);
  let plan;
  if (inventory[0].kind === 'whole-input') {
    const timed = run.queryTimePreparation !== undefined;
    const construct = timed ? moon.clientProgramPrepareInstalledManagedWholeSourcePlanAtQueryTime
      : moon.clientProgramPrepareInstalledManagedWholeSourcePlan;
    if (inventory.length !== 1 || typeof construct !== 'function') {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    const original = inventory[0];
    const args = [
      run.prepared, run.request, original.capacity, original.transferBytes, original.executionBytes,
      installed.admission, contracts.values, contracts.expression, contracts.ordered, retainedRelationOutput];
    // Same temporary Core Option as ModuleBody. The typed constructor checks
    // it; no additional projection, retained carrier or legacy timed fallback.
    plan = checked(Reflect.apply(construct, moon, timed ? [...args, invocationOriginal] : args));
  } else {
    if (inventory.some(value => value.kind !== 'query') ||
        typeof moon.clientProgramInstalledManagedCapturePlanPrepare !== 'function') {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    plan = checked(moon.clientProgramInstalledManagedCapturePlanPrepare(
      run.prepared, run.request, inventory.map(value => value.capacity),
      inventory.map(value => value.transferBytes), inventory.map(value => value.executionBytes),
      installed.admission, contracts.values, contracts.expression, contracts.ordered,
      retainedRelationOutput, run.queryTimePreparation));
  }
  if (run.closed || Object.hasOwn(run, 'failure') ||
      originals.installation.computeRuns?.get(run.prepared) !== run) {
    throw clientOperationError('ForeignInstalledComputeRun');
  }
  return plan;
}

// The same Request invokes this while its Model construction input is live.
// Complete physical backing belongs before this call; the retained Bounds,
// capacities and module below are originals, not an allocation permission.
function prepareRequestMockModelPlan(originals, run, model, compilation, parent, input) {
  const {projectRuntime: moon, initialControl, retainedRelationOutput} = originals.installation;
  const current = () => {
    assertSourceManagedHostPreparation(originals);
    if (parent === undefined || input === undefined || run.runtime !== moon || run.closed ||
        Object.hasOwn(run, 'failure') || run.model !== model ||
        originals.installation.computeRuns?.get(run.prepared) !== run) {
      throw clientOperationError('ForeignInstalledModelPreparation');
    }
    originalSourceManagedHostRequest(originals, run.prepared);
  };
  current();
  const installed = prepareInstalledSequenceContractOriginal(originals), contracts = installed.contracts;
  if (installed.moon !== moon || installed.control !== initialControl ||
      typeof retainedRelationOutput !== 'boolean' || model.control !== runtimeCore(moon).publicationControl ||
      typeof moon.clientProgramPreparedComposedInferBounds !== 'function' ||
      typeof moon.clientProgramComposedInferRetainedLimits !== 'function') {
    throw clientOperationError('NodeManagedRunRuntimeUnavailable');
  }
  const count = moon.clientProgramAcquisitionCount(run.prepared);
  if (count !== 0 && count !== 1 && count !== 2) throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
  function retainBoundsAndBudget(model) {
    // Retain the actual selected opaque Limits before the module/Plan frame.
    // The nine fixed DATA fields are the existing consumer suffix, not the
    // Model Ledger totals and not a repeat of the old fifteen-number quote.
    model.selectedBounds = model.selection?.selectedBounds ??
      checked(moon.clientProgramPreparedComposedInferBounds(model.occurrence, model.graph));
    const limits = moon.clientProgramComposedInferRetainedLimits(model.selectedBounds);
    if (!Array.isArray(limits) || limits.length !== 9 ||
        limits.some(value => typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) ||
        limits.slice(6).some(value => value > 2147483647n)) throw clientOperationError('InvalidHostRuntimeResult');
    const physical = model.originalReadInstallation;
    if (physical !== undefined && (count === 2 ||
        typeof model.control[count === 1 ? 'prepareCheckedClientRequestNodeModelCapturePlan'
          : 'prepareCheckedClientRequestNodeModelSourceFreePlan'] !== 'function')) {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    // The installed Node read's declared complete envelope stays beside its
    // actual Graph/Request originals. Native Plan validation preserves the
    // checked non-byte dimensions and refuses insufficient physical extents.
    model.budget = Object.freeze({bootstrapRetainedBytes: limits[0], bootstrapExecutionBytes: limits[1],
      readRetainedBytes: physical === undefined ? limits[2] : physical.nodeInstallation.layout.retained_bytes,
      readExecutionBytes: physical === undefined ? limits[3] : physical.nodeInstallation.layout.execution_bytes,
      modelRetainedBytes: physical === undefined ? limits[4] : physical.modelRetainedBytes,
      modelExecutionBytes: physical === undefined ? limits[5] : physical.modelExecutionBytes,
      maxReservations: physical === undefined ? Number(limits[6]) : Math.max(Number(limits[6]), physical.bootstrap.maxReservations),
      maxHoldings: physical === undefined ? Number(limits[7]) : Math.max(Number(limits[7]), physical.bootstrap.maxHoldings),
      maxDelegations: physical === undefined ? Number(limits[8]) : Math.max(Number(limits[8]), physical.bootstrap.maxDelegations)});
  }
  if (model.components !== undefined) {
    const members = model.components, selected = model.selection?.components;
    let moduleName = count === 0 ? 'prepareCheckedClientRequestModelsSourceFreeComponentModule'
      : 'prepareCheckedClientRequestModelsProviderComponentCaptureModule';
    const planName = count === 0 ? 'prepareCheckedClientRequestModelsSourceFreePlan'
      : 'prepareCheckedClientRequestModelsCapturePlan';
    if (!Array.isArray(members) || !Object.isFrozen(members) || members.length < 2 ||
        !Array.isArray(selected) || selected.length !== members.length || !Array.isArray(model.graph) ||
        model.graph.length !== members.length || members.some((member, index) =>
          member.group !== model || member.selection !== selected[index] || member.graph !== model.graph[index] ||
          member.occurrence !== selected[index].occurrence || member.serializationGraph !== undefined ||
          member.originalReadInstallation !== undefined || member.component !== undefined) ||
        count === 0 && typeof model.control[moduleName] !== 'function' ||
        typeof model.control[planName] !== 'function') {
      throw clientOperationError('InstalledModelGroupPreparationUnavailable');
    }
    for (const member of members) retainBoundsAndBudget(member);
    current();
    let sourceArguments = [];
    if (count > 0) {
      if (run.sourceProfile !== originals.installation.managedSourceProfile ||
          typeof moon.clientProgramRequestModelDirectSourceCoordinates !== 'function') {
        throw clientOperationError('InstalledModelSourcePreparationUnavailable');
      }
      const coordinates = checked(moon.clientProgramRequestModelDirectSourceCoordinates(parent, input));
      if (!Array.isArray(coordinates) || coordinates.length !== count) throw clientOperationError('InstalledSourcePreparationMismatch');
      const sources = [];
      for (const coordinate of coordinates) {
        const selected = checked(moon.clientProgramSelectInstalledSourceInput(run.prepared, run.request, coordinate[0], coordinate[1]));
        if (moon.clientProgramSelectedSourceInputKind(selected) !== 'query') throw clientOperationError('InstalledModelSourcePreparationUnavailable');
        const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
        const adapter = installedSourceFor(run.sourceProfile, sourceRef);
        if (typeof adapter?.managedEffectPlanSelection !== 'function') throw clientOperationError('InstalledModelSourcePreparationUnavailable');
        const source = adapter.managedEffectPlanSelection(); current();
        const native = source?.nativeSource;
        if ((source?.declaration === undefined) === (native === undefined) ||
            native === undefined && source.provider === undefined ||
            typeof source.transferBytes !== 'bigint' || source.transferBytes < 0n ||
            typeof source.executionBytes !== 'bigint' || source.executionBytes < 0n ||
            native !== undefined && (count !== 1 || native === null || !Object.isFrozen(native) ||
              native.sourceRef !== sourceRef || source.provider !== undefined ||
              ![native.sourceRef, native.schema, native.table].every(value => typeof value === 'string' && value.length > 0) ||
              !Array.isArray(native.contracts) || !Object.isFrozen(native.contracts) || native.contracts.length !== 3 ||
              native.contracts.some(value => typeof value !== 'string' || value.length === 0))) {
          throw clientOperationError('InstalledModelSourcePreparationUnavailable');
        }
        sources.push(source);
      }
      const native = sources[0].nativeSource;
      if (native !== undefined) {
        moduleName = 'prepareCheckedClientRequestModelsDuckDBComponentCaptureModule';
        if (typeof moon.clientProgramPrepareRequestModelsDuckDBComponentCaptureModule !== 'function' ||
            typeof model.control[moduleName] !== 'function') {
          throw clientOperationError('InstalledModelSourcePreparationUnavailable');
        }
        sourceArguments = [native.sourceRef, native.schema, native.table, ...native.contracts,
          sources[0].transferBytes, sources[0].executionBytes];
      } else {
        if (typeof model.control[moduleName] !== 'function') {
          throw clientOperationError('InstalledModelGroupPreparationUnavailable');
        }
        sourceArguments = [sources.map(source => source.declaration), sources.map(source => source.provider),
          readInitialControlInstallationAsset(initialControl, originals, 'spec/contracts/actql-query-acquisition.json'),
          readInitialControlInstallationAsset(initialControl, originals, 'spec/contracts/actql-query-process-evidence.json'),
          sources.map(source => source.transferBytes), sources.map(source => source.executionBytes)];
      }
      run.modelSourceSelections = Object.freeze(sources);
    }
    run.preparedSequences = Reflect.apply(model.control[moduleName], model.control, [
      parent, input, run.request, model.compiled, model.runDefinition, compilation,
      ...sourceArguments, installed.admission, true, run.queryTimePreparation, (index, _capacity, prefix, bindSuffix) => {
        current();
        const member = members[index];
        if (member === undefined || member.component !== undefined || typeof bindSuffix !== 'function') {
          throw clientOperationError('ForeignInstalledModelPreparation');
        }
        const component = openNodeComposedInferProvider({moon, selected: member.selection,
          inputPrefix: prefix, bindComputeSuffix: bindSuffix, deferred: true});
        if (run.closed || Object.hasOwn(run, 'failure') || run.model !== model ||
            originals.installation.computeRuns?.get(run.prepared) !== run) {
          throw clientOperationError('ForeignInstalledModelPreparation');
        }
        member.component = component;
        current();
        return component.provider;
      }]);
    current();
    run.modelPlan = Reflect.apply(model.control[planName], model.control, [parent, input,
      run.preparedSequences, run.request, model.compiled, model.runDefinition,
      Object.freeze(members.map(member => member.occurrence)), model.graph,
      Object.freeze(members.map(member => member.selectedBounds))]);
    current();
    return run.modelPlan;
  }
  retainBoundsAndBudget(model);
  const physical = model.originalReadInstallation;
  current();
  if (count === 1) {
    const plain = model.serializationGraph === undefined;
    const construct = plain ? moon.clientProgramPrepareRequestModelProviderComponentCaptureModule
      : moon.clientProgramPrepareRequestModelProviderCaptureModule;
    if (physical === undefined && (!plain ||
          typeof model.control.prepareCheckedClientRequestModelCapturePlan !== 'function') ||
        plain && (model.selection?.graph !== model.graph || model.selection?.occurrence !== model.occurrence ||
          Object.getOwnPropertyDescriptor(model, 'component')?.value !== undefined ||
          Object.getOwnPropertyDescriptor(model, 'component')?.writable !== true) ||
        run.sourceProfile !== originals.installation.managedSourceProfile || typeof construct !== 'function' ||
        typeof model.control[plain ? 'prepareCheckedClientRequestModelProviderComponentCaptureModule'
          : 'prepareCheckedClientRequestModelProviderCaptureModule'] !== 'function') {
      throw clientOperationError('InstalledModelSourcePreparationUnavailable');
    }
    if (typeof moon.clientProgramSelectInstalledSourceInput !== 'function' ||
        typeof moon.clientProgramSelectedSourceInputKind !== 'function' ||
        typeof moon.clientProgramSelectedSourceInputRef !== 'function') {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    const selected = checked(moon.clientProgramSelectInstalledSourceInput(run.prepared, run.request, 0, 0));
    if (moon.clientProgramSelectedSourceInputKind(selected) !== 'query') {
      throw clientOperationError('InstalledModelSourcePreparationUnavailable');
    }
    const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
    if (typeof sourceRef !== 'string' || sourceRef.length === 0) {
      throw clientOperationError('InstalledModelSourcePreparationUnavailable');
    }
    const adapter = installedSourceFor(run.sourceProfile, sourceRef);
    if (typeof adapter?.managedEffectPlanSelection !== 'function') {
      throw clientOperationError('InstalledModelSourcePreparationUnavailable');
    }
    // A pure selection has no child to recover. Do not attach returned DATA
    // to a bag retired by its current callback; retain only the live original.
    const original = adapter.managedEffectPlanSelection();
    current();
    const native = original?.nativeSource;
    if ((original?.declaration === undefined) === (native === undefined) ||
        native === undefined && original.provider === undefined ||
        typeof original.transferBytes !== 'bigint' || original.transferBytes < 0n ||
        typeof original.executionBytes !== 'bigint' || original.executionBytes < 0n ||
        native !== undefined && (!plain || native === null || !Object.isFrozen(native) ||
          native.sourceRef !== sourceRef || original.provider !== undefined ||
          ![native.sourceRef, native.schema, native.table].every(value => typeof value === 'string' && value.length > 0) ||
          !Array.isArray(native.contracts) || !Object.isFrozen(native.contracts) || native.contracts.length !== 3 ||
          native.contracts.some(value => typeof value !== 'string' || value.length === 0) ||
          typeof moon.clientProgramPrepareRequestModelDuckDBComponentCaptureModule !== 'function' ||
          typeof model.control.prepareCheckedClientRequestModelDuckDBComponentCaptureModule !== 'function')) {
      throw clientOperationError('InstalledModelSourcePreparationUnavailable');
    }
    run.modelSourceSelection = original;
  }
  if (count === 0 && (typeof moon.clientProgramPrepareRequestModelSourceFreeModule !== 'function' ||
      typeof model.control.prepareCheckedClientRequestModelSourceFreeModule !== 'function')) {
    throw clientOperationError('NodeManagedRunRuntimeUnavailable');
  }
  if (model.serializationGraph !== undefined) {
    const content = run.contentPreparation;
    if (content === undefined || content.prepared !== run.prepared || content.managed !== run ||
        content.plan.compiled !== model.compiled || content.plan.runDefinition !== model.runDefinition ||
        content.plan.serializationGraph !== model.serializationGraph ||
        typeof content.contentControl?.prepareModelRequestPrefix !== 'function') {
      throw clientOperationError('InstalledContentRunPreparationUnavailable');
    }
    // Retain the prefix before module/Scope/adoption or another current
    // callback. This is the same Request compiler and original workspace.
    run.serialization = content.contentControl.prepareModelRequestPrefix(parent, input,
      run.request, model.compiled, model.runDefinition, content.prefixLimits,
      content.workspace, run.queryTimePreparation);
    current();
  }
  if (count === 0) {
    // This configured source-free consumer opens the existing retained-output
    // Host. Quote that same choice before module/Model Scope construction,
    // rather than the installation's unrelated optional output hint.
    const configuredSourceFree = physical === undefined && model.selection?.localMock !== true &&
      model.serializationGraph === undefined;
    const retainedModelOutput = configuredSourceFree ? true : retainedRelationOutput;
    if (configuredSourceFree) {
      if (typeof moon.clientProgramPrepareRequestModelSourceFreeComponentModule !== 'function' ||
          typeof model.control.prepareCheckedClientRequestModelSourceFreeComponentModule !== 'function') {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      run.preparedSequences = model.control.prepareCheckedClientRequestModelSourceFreeComponentModule(
        parent, input, run.request, model.compiled, model.runDefinition, compilation,
        installed.admission, retainedModelOutput, run.queryTimePreparation, (_capacity, prefix, bindSuffix) => {
          current();
          if (model.component !== undefined || typeof bindSuffix !== 'function') {
            throw clientOperationError('ForeignInstalledModelPreparation');
          }
          const component = openNodeComposedInferProvider({moon, selected: model.selection,
            inputPrefix: prefix, bindComputeSuffix: bindSuffix, deferred: true});
          if (run.closed || Object.hasOwn(run, 'failure') || run.model !== model ||
              originals.installation.computeRuns?.get(run.prepared) !== run) {
            throw clientOperationError('ForeignInstalledModelPreparation');
          }
          model.component = component;
          current();
          return component.provider;
        });
    } else {
      run.preparedSequences = model.control.prepareCheckedClientRequestModelSourceFreeModule(
        parent, input, run.request, model.compiled, model.runDefinition, compilation,
        installed.admission, retainedModelOutput, run.queryTimePreparation);
    }
    current();
    run.modelPlan = physical === undefined
      ? model.control.prepareCheckedClientRequestModelSourceFreePlan(parent, input,
        run.preparedSequences, run.request, model.compiled, model.runDefinition,
        model.occurrence, model.graph, model.selectedBounds)
      : model.control.prepareCheckedClientRequestNodeModelSourceFreePlan(parent, input,
        run.preparedSequences, run.request, model.compiled, model.runDefinition,
        model.occurrence, model.graph, model.selectedBounds, physical);
  } else if (count === 1) {
    const original = run.modelSourceSelection;
    const native = original.nativeSource;
    const query = native === undefined ? readInitialControlInstallationAsset(initialControl, originals,
      'spec/contracts/actql-query-acquisition.json') : native.contracts[0];
    const evidence = native === undefined ? readInitialControlInstallationAsset(initialControl, originals,
      'spec/contracts/actql-query-process-evidence.json') : native.contracts[1];
    const plain = model.serializationGraph === undefined;
    const construct = native !== undefined ? model.control.prepareCheckedClientRequestModelDuckDBComponentCaptureModule
      : plain ? model.control.prepareCheckedClientRequestModelProviderComponentCaptureModule
        : model.control.prepareCheckedClientRequestModelProviderCaptureModule;
    const args = [parent, input, run.request, model.compiled, model.runDefinition, compilation,
      ...(native === undefined ? [original.declaration, original.provider, query, evidence]
        : [native.sourceRef, native.schema, native.table, query, evidence, native.contracts[2]]),
      original.transferBytes, original.executionBytes, installed.admission,
      retainedRelationOutput, run.queryTimePreparation];
    if (plain) args.push((_capacity, prefix, bindSuffix) => {
      current();
      if (model.component !== undefined || typeof bindSuffix !== 'function') {
        throw clientOperationError('ForeignInstalledModelPreparation');
      }
      const component = openNodeComposedInferProvider({moon, selected: model.selection,
        inputPrefix: prefix, bindComputeSuffix: bindSuffix, deferred: true});
      // The deferred constructor has entered no physical read. Fence the
      // original bag without a callback before retaining this same output;
      // then keep it through any fallible current observation or Plan step.
      if (run.closed || Object.hasOwn(run, 'failure') || run.model !== model ||
          originals.installation.computeRuns?.get(run.prepared) !== run) {
        throw clientOperationError('ForeignInstalledModelPreparation');
      }
      model.component = component;
      current();
      return component.provider;
    });
    run.preparedSequences = Reflect.apply(construct, model.control, args);
    current();
    run.modelPlan = physical === undefined
      ? model.control.prepareCheckedClientRequestModelCapturePlan(parent, input,
        run.preparedSequences, run.request, model.compiled, model.runDefinition,
        model.occurrence, model.graph, model.selectedBounds)
      : model.control.prepareCheckedClientRequestNodeModelCapturePlan(parent, input,
        run.preparedSequences, run.request, model.compiled, model.runDefinition,
        model.occurrence, model.graph, model.selectedBounds, physical);
  } else {
    const sources = readInstalledMockPreparation(originals).sources;
    if (sources.length !== 2 || model.selection?.graph !== model.graph || model.component !== undefined ||
        typeof moon.clientProgramPrepareRequestModelComponentCaptureModule !== 'function' ||
        typeof model.control.prepareCheckedClientRequestModelComponentCaptureModule !== 'function') {
      throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
    }
    const query = readInitialControlInstallationAsset(initialControl, originals,
      'spec/contracts/actql-query-acquisition.json');
    const evidence = readInitialControlInstallationAsset(initialControl, originals,
      'spec/contracts/actql-query-process-evidence.json');
    // Same fixed Mock document limits as its real original reader. These
    // supply demand to Core; no row, Source observation or ACK is fabricated.
    const documentBytes = Object.freeze([1048576n, 1048576n]);
    run.preparedSequences = model.control.prepareCheckedClientRequestModelComponentCaptureModule(
      parent, input, run.request, model.compiled, model.runDefinition, compilation,
      sources.map(value => value.declaration), query, evidence,
      documentBytes, documentBytes, installed.admission, retainedRelationOutput, run.queryTimePreparation,
      (_capacity, prefix, bindSuffix) => {
        current();
        if (model.component !== undefined || typeof bindSuffix !== 'function') {
          throw clientOperationError('ForeignInstalledModelPreparation');
        }
        const component = openNodeComposedInferProvider({moon, selected: model.selection,
          inputPrefix: prefix, bindComputeSuffix: bindSuffix, deferred: true});
        if (run.closed || Object.hasOwn(run, 'failure') || run.model !== model ||
            originals.installation.computeRuns?.get(run.prepared) !== run) {
          throw clientOperationError('ForeignInstalledModelPreparation');
        }
        model.component = component;
        current();
        return component.provider;
      });
    current();
    run.modelPlan = model.control.bindCheckedClientMockModelCapturePlan(run.preparedSequences,
      model.compiled, model.runDefinition, model.occurrence, model.graph, model.selectedBounds);
  }
  current();
  return run.modelPlan;
}

// The separate selected Compute original covers this projection. An empty
// declaration inventory is not a Source installation or a scalar admission:
// Common still checks the same nominal preparation and its complete graph.
export function readManagedComputeRunRequirements(originals, checkedPrepared) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  const {initialControl, projectRuntime: moon} = originals.installation;
  if (initialControl === undefined || moon === undefined ||
      typeof moon.clientProgramInstalledManagedRunRequirements !== 'function') {
    throw clientOperationError('NodeManagedRunAdmissionUnavailable');
  }
  const asset = path => readInitialControlInstallationAsset(initialControl, originals, path);
  const contracts = installedManagedRunContracts(originals);
  const run = originals.installation.computeRuns?.get(checkedPrepared);
  let limits;
  if (run?.sourceProfile !== undefined) {
    if (run.runtime !== moon || run.prepared !== checkedPrepared || run.closed ||
        run.sourceProfile !== originals.installation.managedSourceProfile ||
        typeof moon.clientProgramInstalledManagedCaptureRunRequirements !== 'function') {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    retainedManagedCaptureInventory(originals, run, contracts);
    if (run.sourceCapacities.some(value => value.kind !== 'query')) {
      // Whole input must complete the original Request Plan constructor. The
      // legacy independent quote cannot cast its capacity into Query arrays.
      throw clientOperationError('InstalledWholeSourceRequestPreparationRequired');
    }
    limits = checked(moon.clientProgramInstalledManagedCaptureRunRequirements(
      checkedPrepared, run.sourceCapacities.map(value => value.capacity),
      run.sourceCapacities.map(value => value.transferBytes),
      run.sourceCapacities.map(value => value.executionBytes),
      prepareInstalledSequenceContractOriginal(originals).admission,
      contracts.values, contracts.expression, contracts.ordered));
  } else if (run !== undefined) {
    const retainedRelationOutput = originals.installation.retainedRelationOutput;
    if (typeof retainedRelationOutput !== 'boolean' ||
        run.runtime !== moon || run.prepared !== checkedPrepared || run.closed ||
        typeof moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts !== 'function' ||
        typeof moon.clientProgramInstalledManagedRunIssueIsUnsupported !== 'function' ||
        typeof moon.clientProgramPreparedInstalledManagedSourceFreeRequirements !== 'function') {
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    }
    // The existing per-Host Run record retains this same immutable preparation
    // before limits projection or actual Resource admission can fail.
    if (run.preparedSequences === undefined) {
      const originalContracts = prepareInstalledSequenceContractOriginal(originals);
      if (originalContracts.moon !== moon || originalContracts.control !== initialControl ||
          originalContracts.contracts !== contracts) {
        throw clientOperationError('ForeignInstalledManagedRunContracts');
      }
      const result = moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts(
        checkedPrepared, originalContracts.admission,
        contracts.values, contracts.expression, contracts.ordered, retainedRelationOutput);
      // This exact pure Core preparation precedes Resource and business Run
      // admission. Only its typed Unsupported variant proves a refusal; no
      // arbitrary Host exception or missing journal record does so.
      if (runtimeIsError(result) && moon.clientProgramInstalledManagedRunIssueIsUnsupported(
        runtimeField(result, 0)) && run.request !== undefined && run.failure === undefined &&
          run.original === undefined &&
          run.admission === undefined && run.value === undefined) {
        const error = clientOperationError('ClientProgramUnsupported', runtimeField(result, 0));
        run.preAdmissionRefusal = Object.freeze({error, prepared: checkedPrepared,
          request: run.request, control: initialControl});
        throw error;
      }
      run.preparedSequences = checked(result);
    }
    limits = moon.clientProgramPreparedInstalledManagedSourceFreeRequirements(run.preparedSequences);
  } else {
  limits = checked(moon.clientProgramInstalledManagedRunRequirements(
    checkedPrepared, [],
    asset('spec/contracts/actql-query-acquisition.json'),
    asset('spec/contracts/actql-query-process-evidence.json'), [], [],
    prepareInstalledSequenceContractOriginal(originals).admission,
    contracts.values, contracts.expression, contracts.ordered));
  }
  if (!Array.isArray(limits) || limits.length !== 6 ||
      limits.some(value => typeof value !== 'bigint' || value < 0n) ||
      limits.slice(0, 3).some(value => value > 2147483647n)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, checkedPrepared);
  return Object.freeze({planningWork: Number(limits[0]), attempts: Number(limits[1]),
    holdings: Number(limits[2]), transferBytes: limits[3],
    retainedBytes: limits[4], executionBytes: limits[5]});
}

// Only the same Host's nominal checked Content preparation can project these
// managed limits. This DATA does not issue its separate Resource original.
export function readLocalContentRunRequirements(originals, prepared, selected) {
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  const moon = originals.installation.projectRuntime;
  if (originals.installation.projectSourcePreparation === undefined ||
      typeof moon?.clientProgramInstalledManagedKeyedContentCheckPreparation !== 'function' ||
      typeof moon?.clientProgramInstalledManagedKeyedContentRequirements !== 'function') {
    throw clientOperationError('InstalledContentRunPreparationUnavailable');
  }
  checked(moon.clientProgramInstalledManagedKeyedContentCheckPreparation(selected, prepared));
  const limits = moon.clientProgramInstalledManagedKeyedContentRequirements(selected);
  if (!Array.isArray(limits) || limits.length !== 6 ||
      limits.some(value => typeof value !== 'bigint' || value < 0n) ||
      limits.slice(0, 3).some(value => value > 2147483647n)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  return Object.freeze({planningWork: Number(limits[0]), attempts: Number(limits[1]),
    holdings: Number(limits[2]), transferBytes: limits[3], retainedBytes: limits[4], executionBytes: limits[5]});
}

// Mock preparation remains a distinct operational purpose on the same Host.
export function readLocalMockModelRunRequirements(originals, prepared, model) {
  if (model?.compilation !== undefined) throw clientOperationError('InstalledEffectPlanUnavailable');
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  const {initialControl, projectRuntime: moon} = originals.installation;
  const asset = path => readInitialControlInstallationAsset(initialControl, originals, path);
  const contracts = installedManagedRunContracts(originals);
  const declarations = moon.clientProgramAcquisitionCount(prepared) === 0 ? []
    : readInstalledMockPreparation(originals).sources.map(source => source.declaration);
  const documentBytes = declarations.map(() => 1048576n);
  const control = runtimeCore(moon).publicationControl;
  // Preserve the original extracted method's undefined receiver.
  const limits = (0, control.checkedClientMockModelRunRequirements)(
    prepared, model.compiled,
    model.runDefinition, model.occurrence, model.graph,
    declarations, asset('spec/contracts/actql-query-acquisition.json'),
    asset('spec/contracts/actql-query-process-evidence.json'), documentBytes, documentBytes,
    prepareInstalledSequenceContractOriginal(originals).admission,
    contracts.values, contracts.expression, contracts.ordered);
  if (!Array.isArray(limits) || limits.length !== 15 ||
      limits.some(value => typeof value !== 'bigint' || value < 0n) ||
      [...limits.slice(0, 3), ...limits.slice(12)].some(value => value > 2147483647n)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  assertSourceManagedHostPreparation(originals);
  originalSourceManagedHostRequest(originals, prepared);
  // The same retained record is populated before the Resource original is
  // issued; a second quote cannot substitute another compiled preparation.
  model.budget = Object.freeze({bootstrapRetainedBytes: limits[6], bootstrapExecutionBytes: limits[7],
    readRetainedBytes: limits[8], readExecutionBytes: limits[9],
    modelRetainedBytes: limits[10], modelExecutionBytes: limits[11],
    maxReservations: Number(limits[12]), maxHoldings: Number(limits[13]), maxDelegations: Number(limits[14])});
  return Object.freeze({planningWork: Number(limits[0]), attempts: Number(limits[1]),
    holdings: Number(limits[2]), transferBytes: limits[3], retainedBytes: limits[4], executionBytes: limits[5]});
}

// Called only by the selected Source Root's captured namespace operation,
// after its original managed preparation holding exists, but before that Root
// acquires the fixture FD and completes the same Source installation. The
// opaque original is checked by the fixed Root receiver, never by its shape.
export function prepareInstalledMockSourcePreparation(originals, originalSourceInstallation) {
  assertSourceManagedHostPreparation(originals);
  assertSourceManagedPreparationCurrent(originalSourceInstallation, originals);
  const previous = profiles.mockPreparation(originals.host, originals.installation,
    originals.generation, true);
  if (previous !== undefined) {
    if (previous.sourceInstallation !== originalSourceInstallation) {
      throw clientOperationError('ForeignInstalledMockPreparation');
    }
    return previous.flight;
  }
  const {project, projectProfile, projectRuntime, declaredFileInstallationInventory: installationInventory} = originals.installation;
  if (installationInventory === undefined) throw clientOperationError('DeclaredFileInstallationUnavailable');
  const retained = {runtime: projectRuntime, sourceInstallation: originalSourceInstallation,
    view: undefined, flight: undefined};
  profiles.retainMockPreparation(originals.host, originals.installation,
    originals.generation, retained);
  const assertCurrent = () => {
    assertSourceManagedHostPreparation(originals);
    assertSourceManagedPreparationCurrent(originalSourceInstallation, originals);
  };
  retained.flight = (async () => {
    const view = await prepareInstalledProjectMock(projectRuntime, project, projectProfile,
      {assertCurrent, installationInventory});
    // Retain the acquired original before the fallible final current check.
    // Failure keeps this same view and flight; it never prepares another pair.
    retained.view = view;
    assertCurrent();
    view.originalsForRuntime(projectRuntime);
  })().catch(async cause => {
    await installationInventory.fail(cause);
    throw cause;
  });
  return retained.flight;
}

// Same existing Common intent admission/identity as the receiving Host. This
// selected Source path avoids creating a separate native WebCrypto operation;
// its Root checks the original receipt and registered frozen body first.
export function sourceManagedSubmittedIntentCid(originals, originalSourceInstallation, body) {
  assertSourceManagedHostPreparation(originals);
  assertSourceManagedPreparationCurrent(originalSourceInstallation, originals);
  const moon = originals.installation.projectRuntime;
  const wire = canonicalValueJson({kind: body.kind, input: body.input,
    parameters: body.parameters,
    ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
    ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {})}, {dataKeys: true});
  const intent = moon.clientSubmittedIntent(wire, 1048576, 65536, 64);
  if (intent === undefined) throw clientOperationError('NodeSourceManagedIntentUnavailable');
  const cid = moon.clientSubmittedIntentCid(intent);
  assertSourceManagedHostPreparation(originals);
  assertSourceManagedPreparationCurrent(originalSourceInstallation, originals);
  if (typeof cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(cid)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  return cid;
}

// Same existing submitted-intent Owner, under the distinct actual Compute
// installation. No Source original, copied packet or equal CID can replace it.
export function managedComputeSubmittedIntentCid(originals, originalComputeInstallation, body) {
  assertSourceManagedHostPreparation(originals);
  assertManagedComputePreparationCurrent(originalComputeInstallation, originals);
  const moon = originals.installation.projectRuntime;
  const wire = canonicalValueJson({kind: body.kind, input: body.input,
    parameters: body.parameters,
    ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
    ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {})}, {dataKeys: true});
  const intent = moon.clientSubmittedIntent(wire, 1048576, 65536, 64);
  if (intent === undefined) throw clientOperationError('NodeManagedComputeIntentUnavailable');
  const cid = moon.clientSubmittedIntentCid(intent);
  assertSourceManagedHostPreparation(originals);
  assertManagedComputePreparationCurrent(originalComputeInstallation, originals);
  if (typeof cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(cid)) {
    throw clientOperationError('InvalidHostRuntimeResult');
  }
  return cid;
}

const bytesCid = bytes => `sha256:${createHash('sha256')
  .update(bytes).digest('hex')}`;
const publicKeyCid = value => bytesCid(createPublicKey(value).export({
  type: 'spki', format: 'der'}));

async function embeddedInstallationIdentity(root, installation, project, moon, projectSources, configurationReader) {
  validateSourceNamespace(installation?.sourceNamespace);
  validateSourceNamespace(installation?.sourceSelectorNamespace);
  const connectorTable = installation?.connectorTable;
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  const sourcePaths = installedSourcePaths(installation);
  const effectPaths = installedEffectPaths(installation);
  const identities = await Promise.all(sourcePaths.map(path =>
    installedSourceIdentity(path, {connectorTable, configurationReader, moon})));
  const source = identities.length === 0 ? null : identities.length === 1
    ? identities[0] : {version: 'actql-installed-source-inventory/0.1', identities};
  const effectIdentities = [];
  for (const path of effectPaths) {
    effectIdentities.push(await installedEffectIdentity(path, {connectorTable}));
  }
  const effect = effectIdentities.length === 0 ? null : effectIdentities.length === 1
    ? effectIdentities[0] : {version: 'actql-installed-effect-inventory/0.1',
      identities: effectIdentities};
  const authorization = installation?.authorization;
  const accountIdentity = authorization?.accountConfiguration !== undefined
    ? bytesCid(canonicalJson(JSON.parse(
      authorization.accountConfiguration)))
    : authorization?.accountConfig === undefined ? null :
      bytesCid(canonicalJson(JSON.parse(await readFile(
        authorization.accountConfig, 'utf8'))));
  const ordinary = Object.fromEntries(Object.entries(authorization ?? {})
    .filter(([key, value]) => !['accountConfiguration', 'accountConfig',
      'hostKey', 'reviewers'].includes(key) &&
      typeof value !== 'function'));
  const identity = bytesCid(canonicalJson({
    version: 'actql-embedded-installation/0.1', root,
    ...(project === undefined ? {} : {project: {
      directory: project.directory,
      configuration: bytesCid(Buffer.from(installedProjectOriginalsForRuntime(project, moon).configurationWire, 'utf8')),
      registry: installedProjectOriginalsForRuntime(project, moon).modelRegistryWire === undefined ? null :
        bytesCid(Buffer.from(installedProjectOriginalsForRuntime(project, moon).modelRegistryWire, 'utf8')),
      ...(projectSources === undefined ? {} : {connections:
        bytesCid(Buffer.from(projectSources.originalsForRuntime(moon).connections.wire, 'utf8'))}),
    }}),
    source, effect, accountIdentity, ordinary,
    ...(installation?.sourceSelectorNamespace === undefined ? {} : {
      sourceSelectorNamespace: installation.sourceSelectorNamespace}),
    ...(installation?.sourceNamespace === undefined ? {} : {
      sourceNamespace: bytesCid(Buffer.from(installation.sourceNamespace, 'utf8'))}),
    ...(installation?.hostCapacityPolicy === undefined ? {} : {
      hostCapacityPolicy: installation.hostCapacityPolicy}),
    ...(installation?.hostLookupExecutionPolicy === undefined ? {} : {
      hostLookupExecutionPolicy: installation.hostLookupExecutionPolicy}),
    ...(installation?.modelInstallation === undefined ? {} : {
      modelEnvironment: installation.modelInstallation}),
    ...(installation?.calendarArtifact === undefined ? {} : {
      calendarArtifact: installedCalendarIdentityCid(installation.calendarArtifact)}),
    ...(installation?.resultDataPolicy === undefined ? {} : {
      resultDataPolicy: installation.resultDataPolicy}),
    ...(installation?.retainedRelationOutput === true ? {
      retainedRelationOutput: true} : {}),
    ...(installation?.valuesMaxRows === undefined ? {} : {
      valuesMaxRows: installation.valuesMaxRows}),
    hostKey: authorization?.hostKey === undefined ? null : {
      keyId: authorization.hostKey.keyId,
      publicKeyCid: publicKeyCid(authorization.hostKey.privateKey)},
    reviewers: authorization?.reviewers?.map(reviewer => ({
      keyId: reviewer.keyId, reviewerId: reviewer.reviewerId,
      principalId: reviewer.principalId,
      publicKeyCid: publicKeyCid(reviewer.publicKey)})) ?? null}));
  return Object.freeze({identity, connectorTable, callbacks: Object.freeze({
    resolveSourceSecret: installation?.resolveSourceSecret,
    resolveEffectSecret: installation?.resolveEffectSecret,
    registerModelProviders: installation?.registerModelProviders,
    verifyRequestValuePolicy: installation?.verifyRequestValuePolicy,
    inferEvidence: installation?.inferEvidence,
    observation: installation?.observation,
    decide: authorization?.decide, observe: authorization?.observe,
    faultInjection: authorization?.faultInjection})});
}

function sameEmbeddedInstallation(left, right) {
  return left.identity === right.identity && left.connectorTable === right.connectorTable &&
    Object.keys(left.callbacks).every(key =>
      left.callbacks[key] === right.callbacks[key]);
}

function localStateRoot() {
  const supplied = process.env.ACTQL_LOCAL_STATE_DIR;
  if (supplied !== undefined && !supplied) {
    throw new TypeError('InvalidLocalStateDirectory');
  }
  return resolve(supplied ?? join(homedir(), '.local', 'share', 'actql'));
}

// The realization this installed Host runs: source-free values Programs on
// its in-process Site. With Run-acceptance protection installed, the account
// decides the tuple (Site key, this realization, write) for each request.
const REALIZATION_KEY = 'source-free-values';

function validateValuesMaxRows(value) {
  if (value !== undefined && (!Number.isSafeInteger(value) || value < 1 || value > 2147483647)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
}

function validateSourceNamespace(value) {
  if (value !== undefined && (typeof value !== 'string' || !value || !value.isWellFormed() || Buffer.byteLength(value) > 256)) {
    throw new TypeError('InvalidSourceNamespaceDeclaration');
  }
}

// Separate lexical scope: a returned cleanup continuation cannot keep the
// retiring method's Prepared parameter or SDK request body alive.
function managedPreparationRetirementContinuation(run, record) {
  let retired = false, finalAccounting;
  return () => {
    if (!retired) {
      let observed;
      // The original input/control children have returned before this final
      // cut. Core drops its Ledger on success; late Result observation keeps
      // only these exact immutable scalars, never a live/current witness.
      if (typeof run.usage === 'function') {
        try {
          const values = checked(Reflect.apply(run.usage, run.runtime, [run.value]));
          const length = ledgerLimitsFields.length + ledgerUsageFields.length;
          if (Array.isArray(values) && values.length === length &&
              Reflect.ownKeys(values).length === length + 1) {
            let numeric = true;
            for (let index = 0; index < length; index++) {
              const field = Object.getOwnPropertyDescriptor(values, String(index));
              if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'bigint') {
                numeric = false; break;
              }
            }
            if (numeric) observed = Object.freeze(values);
          }
        } catch { /* Optional metadata cannot replace original cleanup. */ }
      }
      checked(Reflect.apply(run.retire,run.runtime,[run.value]));
      finalAccounting = observed;
      retired = true;
    }
    run.manager.retireSeveredPreparation(run.original);
    record.computeLiveRuns.delete(run);
    for(const key of Object.keys(run)) run[key]=undefined;
    run.closed=true;
    if (finalAccounting !== undefined) run.finalAccounting = finalAccounting;
  };
}

// Capture implementation methods and their original receivers once. Both
// admission and dispatch use this same ordinary route; Model and Content keep
// their existing typed constructors, never the ordinary Pure fallback.
function captureInstalledManagedRunRoute({sourceProfile, preparation, moon, prepareInvocation}) {
  const profilePrepare = sourceProfile?.prepareManagedRun;
  const sourcePrepare = preparation?.prepareManagedSourceRun;
  const computePrepare = preparation?.prepareManagedComputeRun;
  if (profilePrepare !== undefined && typeof profilePrepare !== 'function') {
    throw clientOperationError('InstalledManagedSourceUnavailable');
  }
  return ({preparedProgram, requestIdentity, acquisitionCount, model, serializationCount}) => {
    if (model !== undefined || serializationCount !== 0) {
      throw clientOperationError('InstalledManagedDomainPreparationRequired');
    }
    if (acquisitionCount > 0) {
      if (profilePrepare !== undefined) {
        const value = Reflect.apply(profilePrepare, sourceProfile,
          [Object.freeze({preparedProgram, requestIdentity, prepareInvocation})]);
        if (value === undefined) throw clientOperationError('NodeManagedRunAdmissionUnavailable');
        return value;
      }
      if (typeof sourcePrepare === 'function') return Reflect.apply(sourcePrepare, preparation,
        [moon, preparedProgram, requestIdentity, sourceProfile, prepareInvocation]);
    } else if (typeof computePrepare === 'function') {
      return Reflect.apply(computePrepare, preparation,
        [moon, preparedProgram, requestIdentity, undefined, prepareInvocation]);
    }
    if (preparation !== undefined) throw clientOperationError('NodeManagedRunAdmissionUnavailable');
    return undefined;
  };
}

async function openInstalledHost(originalInstallation, preparation) {
  // Both installed Local and HTTP entrances supply this same fixed owner.
  // Standalone compiler callers use their separate adapter, never this Host.
  if (preparation === undefined || typeof preparation.fundedPreparation !== 'function' ||
      typeof preparation.requestPreparation !== 'function') {
    throw new TypeError('InstalledRequestPreparationUnavailable');
  }
  let {root, mode = 'local', beforeDispatch, workspaceId,
  authorization, connectorTable, sourceProfilePath, sourceProfilePaths, sourceNamespace, sourceSelectorNamespace, resolveSourceSecret,
  effectProfilePath, effectProfilePaths, resolveEffectSecret, effectInstallation,
  modelInstallation, registerModelProviders, project, projectProfile, projectRuntime,
  calendarArtifact, resultDataPolicy, inferEvidence, hostCapacityPolicy,
  hostLookupExecutionPolicy, verifyRequestValuePolicy,
  retainedRelationOutput = false, valuesMaxRows, observation: observationConnection} = originalInstallation;
  // This is the actual returned Host generation, not a CID/configuration
  // stand-in or another resource Owner. The installer covers native/process
  // domains as trusted implementation responsibility, NOT zero bytes or RSS.
  const host = preparation?.host ?? {};
  let modelRuntimeClosing = false;
  let preparedSourceEnvironment;
  let clientProgramPreparationReferences;
  let modelRuntimeView;
  let modelRuntimeStartupView;
  let modelSdkStaticOriginals;
  let modelProviders;
  let projectTasks;
  let mockModels;
  let mockAccount;
  let standardAccountPreparation;
  let localCheckpointAnswer, localSigningMetadata;
  const localSigningRecoveries = new Set();
  let store;
  let mockEffectObservation;
  let mockEffectObservationMethods;
  let localFileEffectInstallation;
  const mockEffectRuns = new Map();
  let mockEffectOriginals = new WeakMap();
  const localFileEffectRuns = new Map();
  let localFileEffectOriginals = new WeakMap();
  // Nominal association in this SAME Host, not a capacity pool or Run Owner.
  // A key is an actual Common-issued Scope; its value is retired only after
  // that Scope's original Common cleanup succeeds.
  const modelRuntimeScopes = new WeakMap();
  const runtimeTarget = () => `${process.version}/${process.platform}/${process.arch}` +
    `/openssl:${process.versions.openssl}/v8:${process.versions.v8}`;
  const runtimeOriginals = () => ({host, supplier: openInstalledHost,
    installation: originalInstallation, generation: host, runtime: process,
    moduleLifetime: import.meta, transport: registerModelProviders, target: runtimeTarget()});
  function assertModelRuntime() {
    checkInferTrustedRuntimeView(modelRuntimeView, runtimeOriginals());
    if (modelRuntimeStartupView !== undefined) {
      requireInferTrustedStartupView(modelRuntimeStartupView, runtimeOriginals());
    }
    if (store !== undefined) {
      checkInferTrustedStore(modelRuntimeView, runtimeOriginals(), store, publicationStoreModule);
      // This is the SAME Store's existing lifetime fact, not a caller flag or
      // native release ACK. Pending close still retains the original duties.
      if (store.status().closed) throw clientOperationError('InferTrustedStoreClosed');
    }
  }
  function assertNewModelRuntime() {
    if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
    assertModelRuntime();
  }
  function bindModelSdkStaticOriginals(originals) {
    // Existing borrow/current rechecks remain legal while cleanup is pending;
    // this check is not new-allocation or send admission during Host closing.
    assertModelRuntime();
    // The ordinary trusted Host borrows the loaded SDK originals through the
    // installed Provider's retained closure. It does not need an early/eager
    // import history and must not manufacture that distinct recipe's proof.
    // Its same-Host/current Provider checks and actual I/O admission remain.
    if (modelRuntimeStartupView === undefined) return undefined;
    bindInferTrustedSdkStaticModules(modelRuntimeView, runtimeOriginals(), originals);
    checkInferTrustedSdkStaticModules(modelRuntimeView, runtimeOriginals(), originals);
    modelSdkStaticOriginals ??= originals;
    // One private same-Host function, not a new closure at every current check.
    // Old static-only selections remain legal until a supplier explicitly
    // requires the distinct exact eager startup responsibility.
    return requireModelSdkEagerStartup;
  }
  function requireModelSdkEagerStartup() {
    assertModelRuntime();
    checkInferTrustedSdkEagerModules(modelRuntimeView, runtimeOriginals(),
      modelSdkStaticOriginals);
  }
  function retireModelPreparationReferences() {
    const consumer = clientProgramPreparationReferences;
    if (consumer !== undefined) {
      Reflect.apply(consumer.retire, consumer.owner, []);
      clientProgramPreparationReferences = undefined;
    }
    const original = preparedSourceEnvironment;
    if (original !== undefined) {
      // Cut this Host's association only after its existing shutdown duties.
      // Other holders may retain the pure immutable Environment; no physical
      // ACK or global invalidation is implied by releasing these aliases.
      retireSourceAliasPublicationOriginal(original.moon, original.environment, original.publication);
      preparedSourceEnvironment = undefined;
    }
    modelSdkStaticOriginals = undefined;
    // Drop the installer's borrowed configuration/callback and table links
    // only at the same final cleanup boundary. This is NOT process/native ACK.
    originalInstallation = undefined;
    registerModelProviders = undefined;
    modelProviders?.clear();
    // This drops DATA/backreferences only after the same Host shutdown duties
    // retire. It is not physical read/Provider/Store or numerical release ACK.
    projectTasks = undefined;
    projectProfile?.retire(projectRuntime);
    if (project !== undefined) retireInstalledProjectConfiguration(project, projectRuntime);
    projectProfile = undefined;
    projectRuntime = undefined;
    project = undefined;
    // Actual FileTarget children close through installedEffect before this
    // final Host boundary. These remaining Run/limit links are copied managed
    // references, not another physical ACK or a Source/Model capacity credit.
    mockEffectRuns.clear();
    mockEffectOriginals = new WeakMap();
    // The installed Effect has already closed its actual read/write children.
    // These remaining original Run associations are managed references only.
    localFileEffectRuns.clear();
    localFileEffectOriginals = new WeakMap();
    localFileEffectInstallation = undefined;
    mockEffectObservation = mockEffectObservationMethods = undefined;
    localSigningMetadata?.retireMetadataView();
    localSigningMetadata = localCheckpointAnswer = undefined;
    mockAccount = undefined;
    standardAccountPreparation = undefined;
  }
  function retireModelRuntime() {
    if (modelRuntimeView !== undefined) {
      if (modelRuntimeStartupView !== undefined) {
        forgetInferTrustedStartupView(modelRuntimeStartupView, host, host);
        modelRuntimeStartupView = undefined;
      }
      forgetInferTrustedRuntimeView(modelRuntimeView, host, host);
      modelRuntimeView = undefined;
    }
    retireModelPreparationReferences();
  }
  preparation?.retainReferenceRetirement(retireModelPreparationReferences);
  try {
  hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
  hostLookupExecutionPolicy = snapshotHostLookupExecutionPolicy(hostLookupExecutionPolicy);
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  validateValuesMaxRows(valuesMaxRows);
  validateSourceNamespace(sourceNamespace);
  validateSourceNamespace(sourceSelectorNamespace);
  if (workspaceId !== undefined && !validClientConnection({mode, owner: mode,
    consentRefs: [], runners: [], workspaceId})) {
    throw new TypeError('InvalidInstalledWorkspaceBinding');
  }
  if (typeof retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidLocalRetainedOutputConfiguration');
  }
  const selectedSourcePaths = installedSourcePaths({sourceProfilePath, sourceProfilePaths});
  const selectedEffectPaths = installedEffectPaths({effectProfilePath, effectProfilePaths});
  if (valuesMaxRows !== undefined &&
      (effectInstallation !== undefined || selectedEffectPaths.length > 0)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  if (effectInstallation !== undefined && selectedEffectPaths.length > 0) {
    throw new TypeError('InvalidInstalledEffectSite');
  }
  const principalId = userInfo().username;
  const journalDirectory = join(root, 'requests');
  // Root-format admission can create and fsync the first marker. Retain the
  // actual Host subject before that operation, not only before SQLite open.
  preparation?.retainHostJournalPreparation(root, principalId, journalDirectory);
  // The actual Journal facility precedes even root-format creation/fsync.
  // Initial control and Source/Compute admissions cannot cover this write.
  if (preparation !== undefined) await preparation.prepareHostJournal();
  const rootCreation = preparation === undefined ? await admitHostRootFormat(root)
    : await preparation.admitRootFormat(root);
  const originalSourcePreparation = preparation?.sourcePreparation();
  const mockSourceInstallation = originalSourcePreparation !== undefined &&
    projectProfile?.originalsForRuntime(projectRuntime).selected === 'mock';
  if (!mockSourceInstallation && mode === 'local' && preparation !== undefined) {
    // Save the actual first initialization before later Source/Model/Store
    // setup can fail. A current marker with no reference is not permission
    // to recreate a missing Account; only this same intent can resume it.
    standardAccountPreparation = await preparation.prepareStandardAccount(
      principalId, authorization, rootCreation);
  }
  if (!mockSourceInstallation && registerModelProviders !== undefined) {
    // The normal Host trusts its supported platform and embedding application.
    // Retain the actual installation/currentness identity, not an exact patch,
    // preload ancestry, process-once lifetime or whole-runtime allocation proof.
    // This reference view supplies no Run limit, Model I/O or send authority.
    modelRuntimeView = issueInferTrustedRuntimeView(runtimeOriginals());
    // Preserve the optional explicit diagnostic recipe when actually present;
    // an ordinary Host does not reconstruct or require its missing history.
    modelRuntimeStartupView = associateInferTrustedStartupView(modelRuntimeView, runtimeOriginals());
    assertNewModelRuntime();
  }
  const moon = await import(runtimeUrl.href);
  const projectOriginal = project === undefined ? undefined :
    installedProjectOriginalsForRuntime(project, moon);
  if (projectProfile !== undefined && (projectRuntime !== moon ||
      projectProfile.originalsForRuntime(moon).configuration !== projectOriginal?.configuration)) {
    throw clientOperationError('ForeignInstalledProjectProfile');
  }
  function assertProjectRuntime() {
    if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
    if (project !== undefined &&
        installedProjectOriginalsForRuntime(project, moon) !== projectOriginal) {
      throw clientOperationError('ForeignInstalledProjectOriginal');
    }
    if (modelRuntimeView !== undefined) assertNewModelRuntime();
  }
  if (modelRuntimeView !== undefined) assertModelRuntime();
  // Open the original initial Resource before any configured Source load.
  // This owner survives Requests; Environment/sequence views are constructed
  // later and cannot stand in for this actual original carrier.
  const installationServices = preparation === undefined
    ? createInstalledHostServices({root, principalId, moon, assertCurrent: assertProjectRuntime})
    : preparation.sourceInitializationServices(moon, root, principalId, assertProjectRuntime);
  const control = runtimeCore(moon).publicationControl;
  async function releaseLocalSigningRecovery(recovered) {
    // Recovery acquired real prepared-schema owners. Signing only borrows the
    // authenticated metadata, so relinquish those temporary owners without
    // retiring the original durable capture or requiring current authority.
    const recoveryResources = recovered.recoveryResources;
    await suspendCompletedEffectfulComputation({store, control, ...recovered.computation});
    localSigningRecoveries.delete(recovered);
    recovered = undefined;
    if (recoveryResources !== undefined && await recoveryResources.close() !== true) {
      throw clientOperationError('EffectCaptureResourceCleanupPending');
    }
  }
  const installedResultDataPolicy = resultDataPolicy === undefined ? undefined :
    control.admitSourceFreeResultPolicy(resultDataPolicy, localContractLimits);
  const evidenceConfiguration = configureInferEvidence(inferEvidence);
  // The explicit Mock profile never registers a configured physical Provider.
  // Its portable Model owner retains the original fixture Task and answers;
  // neither that DATA installation nor this empty physical table grants send.
  modelProviders = !mockSourceInstallation
    ? installModelProviders(moon, registerModelProviders,
      modelRuntimeView === undefined ? undefined : assertModelRuntime,
      modelRuntimeView === undefined ? undefined : assertNewModelRuntime,
      modelRuntimeView === undefined ? undefined : bindModelSdkStaticOriginals)
    : new Map();
  const inferSelections = new WeakMap();
  const earlyMockInferPlans = new WeakMap();
  const earlyContentPlans = new WeakMap();
  function releaseRequestModelAliases(prepared) {
    // The existing registry/Run retirement calls this fixed Host alias cut.
    // A retained Prepared key must not retain its Model graph/provider/Plan.
    // Physical Model and Effect selections keep their separate owners.
    if (inferSelections.get(prepared)?.localMock !== true &&
        earlyMockInferPlans.get(prepared)?.model === undefined) return;
    inferSelections.delete(prepared);
    earlyMockInferPlans.delete(prepared);
  }
  function releaseRequestDomainAliases(prepared) {
    releaseRequestModelAliases(prepared);
    // Content calls this only from its same-record alias retirement, after
    // checked Run retirement or the original Request's abort/holder fence.
    earlyContentPlans.delete(prepared);
  }
  const effectSubmissions = new WeakMap();
  const effectSelections = new WeakMap();
  // Both installed entrances borrow the same startup's original fixed image.
  // The required preparation owner leaves no unprepared pathname fallback.
  const environmentSource = preparation.readEnvironmentSource();
  const selectedLookupPolicy = hostLookupExecutionPolicy ??
    preparation?.localFilesLookupExecutionPolicy?.(moon);
  // An independently supplied Remote Effect and a profile-loaded Effect carry
  // their published generic policy identity. Loading that publication must
  // not replace its policy with the ordinary Local row profile.
  // Ordinary Local materialization, including Remote Values/Source callers,
  // continues to consume the same installed Local Resource row selector.
  const baseEnvironmentWire = originalInstallation.declaredFileBaseEnvironmentWire ??
    ((mode === 'remote' && effectInstallation !== undefined) ||
      selectedEffectPaths.length !== 0
    ? selectInstalledHostEnvironment : selectInstalledLocalMaterializationEnvironment)(
    moon, environmentSource.trimEnd(), hostCapacityPolicy, selectedLookupPolicy);
  // Both adapters restore published declarations without provider I/O. The
  // combined environment is admitted before either can dispatch work.
  let sourceProfile;
  let sourcePublicationSources;
  let installedEffect;
  let environmentWire, effectiveHostCapacityPolicyCid;
  let environmentBody, environmentEvidenceCid;
  let updateTargetOriginals;
  function assertMockEffectRunOriginal(original) {
    assertProjectRuntime();
    preparation.assertResultPublicationCurrent();
    const retained = mockEffectOriginals.get(original);
    if (retained === undefined || retained.original !== original ||
        mockEffectRuns.get(retained.prepared) !== retained) {
      throw clientOperationError('ForeignInstalledMockEffectRun');
    }
    if (retained.failure !== undefined) throw retained.failure;
    // A retired Source/Compute Scope does not retire this business Run's file
    // requests. Its authorization/claims remain the existing Effect owners'.
    return retained;
  }
  function retainMockEffectRunOriginal(facts) {
    assertProjectRuntime();
    if (mockEffectObservationMethods === undefined || facts.prepared === undefined ||
        facts.compilation === undefined || facts.allowed === undefined ||
        facts.definition === undefined || facts.identity === undefined) {
      throw clientOperationError('InstalledMockEffectResourcesUnavailable');
    }
    let retained = mockEffectRuns.get(facts.prepared);
    if (retained !== undefined) {
      assertMockEffectRunOriginal(retained.original);
      if (retained.compilation !== facts.compilation || retained.allowed !== facts.allowed ||
          retained.definition !== facts.definition || retained.identity !== facts.identity) {
        throw clientOperationError('ForeignInstalledMockEffectRun');
      }
      return retained.original;
    }
    if (mockEffectRuns.size === 4096) throw clientOperationError('InstalledMockEffectRunLimit');
    retained = {prepared: facts.prepared, compilation: facts.compilation, allowed: facts.allowed,
      definition: facts.definition, identity: facts.identity, original: Object.freeze({}),
      checkedRun: undefined, limits: undefined, failure: undefined,
      readmittedAllowed: undefined, readmittedDefinition: undefined};
    mockEffectRuns.set(facts.prepared, retained);
    mockEffectOriginals.set(retained.original, retained);
    try {
      // Validate the same actual Common prepared/allowed/definition original.
      // This creates no Run, Ledger, Allow, physical reservation or replacement.
      retained.checkedRun = checked(moon.clientProgramBindCompiledEffectRun(
        facts.prepared, facts.allowed, facts.definition));
      retained.limits = Reflect.apply(mockEffectObservationMethods.limits,
        mockEffectObservation, [retained.original]);
      assertMockEffectRunOriginal(retained.original);
      return retained.original;
    } catch (cause) {retained.failure = cause; throw cause;}
  }
  const mockEffectResources = Object.freeze({
    bindRunOriginal(facts) {
      const recovered = facts.recovered;
      if (recovered !== undefined) {
        // Recovery supplies newly validated local handles for the saved Run,
        // not an old process pointer or a fresh Source/Compute admission.
        const retained = journal.lookupOwnedDefinition({namespaceId, authorityScopeCid,
          requestId: moon.clientRequestCallerId(recovered.requestIdentity),
          runDefinitionCid: recovered.runDefinition?.identity}, moon, control);
        if (retained === undefined || retained.runDefinition.identity !== recovered.runDefinition?.identity) {
          throw clientOperationError('ForeignInstalledMockEffectRun');
        }
        return retainMockEffectRunOriginal({...recovered, identity: recovered.requestIdentity});
      }
      const retained = mockEffectRuns.get(facts.prepared);
      if (retained === undefined || retained.compilation !== facts.compilation ||
          retained.identity !== facts.identity) {
        throw clientOperationError('ForeignInstalledMockEffectRun');
      }
      assertMockEffectRunOriginal(retained.original);
      const initial = retained.definition === facts.definition &&
        (facts.allowed === undefined || retained.allowed === facts.allowed);
      const readmitted = retained.readmittedDefinition !== undefined &&
        retained.readmittedDefinition === facts.definition &&
        retained.readmittedAllowed === facts.allowed;
      if (!initial && !readmitted) {
        // start() reconstructs validated local handles from the winning
        // Journal even in this process. Equal CIDs or copied DATA are not that
        // original: authenticate the same request/record, its exact saved
        // evidence and the new typed Common binding, without reissuing any
        // physical Run/Scope or replacing its retained file-owner original.
        const saved = journal.resolveDefinition(retained.identity,
          {namespaceId}, moon, control);
        const evidence = saved?.runAdmissionEvidence;
        if (facts.allowed === undefined || saved?.runDefinition?.wire === undefined ||
            saved.runDefinition.wire !== moon.strategyPublicationContractJson(retained.definition) ||
            saved.runDefinition.wire !== moon.strategyPublicationContractJson(facts.definition) ||
            evidence?.prepared !== moon.strategyRunEvidenceJson(
              moon.clientProgramAllowedEffectRunPrepared(facts.allowed)) ||
            evidence?.authorization !== moon.strategyRunEvidenceJson(
              moon.clientProgramAllowedEffectRunAuthorization(facts.allowed))) {
          throw clientOperationError('ForeignInstalledMockEffectRun');
        }
        const checkedRun = checked(moon.clientProgramBindCompiledEffectRun(
          facts.prepared, facts.allowed, facts.definition));
        assertMockEffectRunOriginal(retained.original);
        retained.checkedRun = checkedRun;
        retained.readmittedAllowed = facts.allowed;
        retained.readmittedDefinition = facts.definition;
      }
      return retained.original;
    },
    assertCurrent(original) {assertMockEffectRunOriginal(original);},
    limits(original) {
      const retained = assertMockEffectRunOriginal(original);
      if (retained.limits === undefined) throw clientOperationError('InstalledMockEffectResourcesUnavailable');
      return retained.limits;
    },
  });
  function assertLocalFileEffectRunOriginal(original) {
    assertProjectRuntime();
    preparation.assertResultPublicationCurrent();
    const retained = localFileEffectOriginals.get(original);
    if (retained === undefined || localFileEffectRuns.get(retained.prepared) !== retained) {
      throw clientOperationError('ForeignInstalledLocalFileEffectRun');
    }
    return retained;
  }
  const localFileEffectResources = Object.freeze({
    bindRunOriginal(facts) {
      assertProjectRuntime();
      preparation.assertResultPublicationCurrent();
      const actual = facts.recovered ?? facts;
      const prepared = actual.prepared, allowed = actual.allowed, definition = actual.definition;
      const identity = actual.requestIdentity ?? actual.identity;
      if (prepared === undefined || allowed === undefined || definition === undefined || identity === undefined) {
        throw clientOperationError('InstalledLocalFileEffectResourcesUnavailable');
      }
      const requestId = moon.clientRequestCallerId(identity);
      const definitionCid = moon.strategyPublicationContractIdentity(definition);
      const definitionWire = moon.strategyPublicationContractJson(definition);
      const saved = journal.lookupOwnedDefinition({namespaceId, authorityScopeCid,
        requestId, runDefinitionCid: definitionCid}, moon, control);
      const evidence = saved?.runAdmissionEvidence;
      if (moon.clientRequestAuthorityScopeCid(identity) !== authorityScopeCid ||
          saved?.runDefinition?.identity !== definitionCid ||
          saved.runDefinition.wire !== definitionWire ||
          evidence?.prepared !== moon.strategyRunEvidenceJson(
            moon.clientProgramAllowedEffectRunPrepared(allowed)) ||
          evidence?.authorization !== moon.strategyRunEvidenceJson(
            moon.clientProgramAllowedEffectRunAuthorization(allowed))) {
        throw clientOperationError('ForeignInstalledLocalFileEffectRun');
      }
      // A validated saved Run may have new local handles after reopen. Common
      // checks their nominal prepared/allowed/definition relationship; matching
      // strings alone cannot bind a copied handle or issue another Run/Ledger.
      const checkedRun = checked(moon.clientProgramBindCompiledEffectRun(prepared, allowed, definition));
      let retained = localFileEffectRuns.get(prepared);
      if (retained === undefined) {
        if (localFileEffectRuns.size === 4096) throw clientOperationError('InstalledLocalFileEffectRunLimit');
        retained = {prepared, checkedRun, requestId, definitionWire,
          original: Object.freeze({}), limits: preparation.localFilesEffectLimits(moon)};
        localFileEffectRuns.set(prepared, retained);
        localFileEffectOriginals.set(retained.original, retained);
      } else if (retained.requestId !== requestId || retained.definitionWire !== definitionWire) {
        throw clientOperationError('ForeignInstalledLocalFileEffectRun');
      } else retained.checkedRun = checkedRun;
      assertLocalFileEffectRunOriginal(retained.original);
      return retained.original;
    },
    assertCurrent(original) {assertLocalFileEffectRunOriginal(original);},
    limits(original) {return assertLocalFileEffectRunOriginal(original).limits;},
  });
  function selectedInstalledEffect({prepared, compilation, updateTargetSelections}) {
    const selections = updateTargetSelections ?? updateTargetOriginals?.selectionsOf(prepared);
    const implementation = installedEffect ?? effectInstallation;
    if (implementation?.effects === undefined) {
      validateInstalledUpdateOwnerSelections(implementation, selections, prepared);
      return implementation;
    }
    let selected = effectSelections.get(prepared);
    if (selected === undefined) {
      selected = installedEffectFor(installedEffect,
        installedRowEffectDescriptors(moon, prepared, compilation));
      selected.assertPrepared?.({moon, prepared, compilation});
      effectSelections.set(prepared, selected);
    }
    validateInstalledUpdateOwnerSelections(selected, selections, prepared);
    return selected;
  }
  function recoveredInstalledEffect(facts) {
    const selections = facts.recovered.updateTargetSelections;
    facts.recovered.assertUpdateSelectionCurrent?.();
    const provider = facts.continuation?.provider ?? facts.continuation;
    if (selections !== undefined || Object.hasOwn(provider ?? {}, 'stage_index')) {
      const preview = JSON.parse(facts.control.effectComputationPreviewWire(
        facts.recovered.computation.preview));
      try {
        updateTargetOriginals.validateRecoveredSelectionMembers({
          selections, prepared: facts.recovered.prepared,
          compilation: facts.recovered.compilation, preview, stageIndex: provider?.stage_index});
      } catch {
        throw refusedEffectPreparation(clientOperationError('InstalledEffectOriginalSelectionChanged'));
      }
    }
    if (installedEffect?.effects === undefined) {
      validateInstalledUpdateOwnerSelections(installedEffect, selections);
      return installedEffect;
    }
    // The capture owner has already authenticated and admitted this Preview.
    // Select its original contract inventory; never infer a new Program or Run.
    const preview = facts.recovered.computation.preview;
    const body = JSON.parse(facts.control.effectComputationPreviewWire(preview));
    const descriptors = body.effects.map(member => member.effect_kind === 'command'
      ? {effectId: member.effect_id, kind: 'command', target: member.target,
        commandRef: member.contract, commandCid: member.resolved_command_contract_cid}
      : ({effectId: member.effect_id,
      kind: member.effect_kind, target: member.target, mappingRef: member.mapping,
      mappingCid: member.resolved_mapping_contract_cid,
      ...(member.source_table_input === undefined ? {} : {capabilityCid: member.capability_evidence_cid})}));
    try {
      const selected = installedEffectFor(installedEffect, descriptors);
      validateInstalledUpdateOwnerSelections(selected, selections);
      return selected;
    }
    catch (cause) {
      // This observes only installation metadata before any new provider work.
      // The existing resume owner still preserves attempted unknown outcomes.
      throw refusedEffectPreparation(clientOperationError('InstalledEffectInstallationChanged', cause));
    }
  }
  try {
    const installationSourcePreparation = preparation?.sourcePreparation();
    if (mockSourceInstallation) {
      // Consume the SAME selected physical Source preparation. An explicit
      // Mock installation must not load configured live Source profiles, and
      // its actual Account gate still defaults to Missing, never to Allow.
      mockModels = await preparation.installMockModels(moon);
      mockAccount = await preparation.initializeMockAccount(moon, principalId, authorization, mockModels);
      if (mockAccount !== undefined) authorization = mockAccount.authorization;
      sourceProfile = await preparation.installMockSources(moon, baseEnvironmentWire,
        () => createLocalAuthorizationGate({...authorization, principal: principalId}), installationServices);
      if (preparation.sourcePreparation() !== installationSourcePreparation) {
        throw clientOperationError('InstalledSourcePreparationChanged');
      }
      projectTasks = mockModels;
    } else if (installationSourcePreparation !== undefined) {
      if (selectedSourcePaths.length !== 0) {
        throw clientOperationError('InstalledProjectSourceCompositionUnavailable');
      }
      sourceProfile = await preparation.installProjectSources(moon, baseEnvironmentWire,
        () => createLocalAuthorizationGate({...authorization, principal: principalId}));
      if (preparation.sourcePreparation() !== installationSourcePreparation) {
        throw clientOperationError('InstalledSourcePreparationChanged');
      }
    } else {
      sourceProfile = await loadInstalledSources(selectedSourcePaths,
        {root, principalId, moon, runtimeUrl, baseEnvironmentWire,
          resolveSecret: resolveSourceSecret, connectorTable, installationServices});
      // Namespace closure belongs to these loader originals. Managed views
      // retain execution custody but do not carry the loader's metadata proof.
      sourcePublicationSources = sourceProfile?.sources ??
        (sourceProfile === undefined ? [] : [sourceProfile]);
      if (preparation !== undefined) sourceProfile = preparation.bindManagedSources(moon, sourceProfile);
    }
    if (!mockSourceInstallation) {
      installedEffect = await loadInstalledEffects(selectedEffectPaths, {root, principalId, moon,
        runtimeUrl, baseEnvironmentWire, resolveSecret: resolveEffectSecret, connectorTable, installationServices});
      if (installationSourcePreparation !== undefined) {
        const projectEffects = await preparation.installProjectEffects(moon, baseEnvironmentWire,
          () => createLocalAuthorizationGate({...authorization, principal: principalId}),
          principalId, localFileEffectResources, sourceProfile.connectorBindings, installationServices);
        localFileEffectInstallation = projectEffects;
        if (installedEffect === undefined) installedEffect = projectEffects;
        else {
          // Both returned inventories own their original installations. Reuse
          // the existing composition/cleanup path without loading profiles or
          // reconstructing another Site from matching selector DATA.
          const inventories = [installedEffect, projectEffects];
          const combined = await composeInstalledEffects(
            inventories.flatMap(effect => effect.effects ?? [effect]),
            {moon, baseEnvironmentWire, installationServices}, async (effect, _options, retain) => {
              retain(effect); return effect;
            });
          installedEffect = Object.freeze({...combined, queryStoreTargets: Object.freeze(
            inventories.flatMap(effect => effect.queryStoreTargets ?? []))});
        }
      }
    } else {
      if (selectedEffectPaths.length !== 0 || effectInstallation !== undefined) {
        throw clientOperationError('InstalledMockEffectProfileConflict');
      }
      installedEffect = await preparation.installMockEffects(moon, baseEnvironmentWire,
        () => createLocalAuthorizationGate({...authorization, principal: principalId}),
        principalId, mockEffectResources, sourceProfile.mockWritableSource?.connectorBindings[0]);
      // Retain the actual factory result before a fallible observation/current
      // read, so the existing initialization carrier still owns its file child.
      mockEffectObservation = observeInstalledMockEffectResources(installedEffect);
      mockEffectObservationMethods = Object.freeze({limits: mockEffectObservation.limits,
        statusFor: mockEffectObservation.statusFor, closeFor: mockEffectObservation.closeFor});
      if (!Object.values(mockEffectObservationMethods).every(value => typeof value === 'function')) {
        throw clientOperationError('InstalledMockEffectResourcesUnavailable');
      }
      assertProjectRuntime();
    }
    if (installedEffect !== undefined) {
      if (authorization === undefined && standardAccountPreparation === undefined) {
        throw new TypeError('InstalledEffectAuthorizationRequired');
      }
      // This constructs inert installed metadata only. Standard bootstrap is
      // still pending; no protected dispatch precedes its actual adoption.
      effectInstallation = createInstalledEffectSite({
        ...(installedEffect.effects === undefined ? installedEffect : {}),
        environmentWire: installedEffect.environmentWire,
        prepareCaptured: facts => selectedInstalledEffect(facts).prepareCaptured(facts),
        validateRecoveredInstallation: facts => recoveredInstalledEffect(facts),
        prepareRecovered: facts => recoveredInstalledEffect(facts).prepareRecovered({...facts,
          updateTargetSelections: facts.recovered.updateTargetSelections,
          assertUpdateSelectionCurrent: facts.recovered.assertUpdateSelectionCurrent}),
      });
    }
    if (effectInstallation !== undefined &&
        (typeof effectInstallation.environmentWire !== 'string' ||
          typeof effectInstallation.execute !== 'function' ||
          typeof effectInstallation.resume !== 'function' ||
          effectInstallation.privateEvidenceKey !== undefined &&
            (!(effectInstallation.privateEvidenceKey instanceof Uint8Array) ||
              effectInstallation.privateEvidenceKey.byteLength !== 32))) {
      throw new TypeError('InvalidInstalledEffectSite');
    }
    const composedEnvironment = composeInstalledSourceEnvironment(installationServices, moon,
      baseEnvironmentWire, sourceProfile?.environmentOriginal ?? sourceProfile?.environmentWire,
      installedEffect?.environmentOriginal ?? effectInstallation?.environmentWire);
    environmentWire = composedEnvironment.wire;
    if (mockModels === undefined) {
      environmentWire = installedModelEnvironment(moon, baseEnvironmentWire,
        environmentWire, modelInstallation);
    }
    if (mockModels === undefined && project !== undefined &&
        installedProjectOriginalsForRuntime(project, moon).modelRegistry !== undefined) {
      // These are installation-time reader ceilings, not Model fuel, memory
      // reservations or a numerical execution profile. The ordinary complete
      // Environment checker below still enforces its existing aggregate bounds.
      projectTasks = await loadInstalledProjectModelTasks(moon, project, modelProviders, {
        limits: {maxTasks: 128, maxBytes: 65536, maxNodes: 4096, maxDepth: 64,
          maxMembers: 256, contractNodes: 4096, contractDepth: 64,
          contractTextBytes: 65536, maxWork: 2097152},
        assertCurrent: assertProjectRuntime,
      });
    }
    let body;
    if (environmentWire === composedEnvironment.wire) {
      body = {...composedEnvironment.body};
    } else {
      // A changed Model input is a new document, not the composer's original.
      const {evidence_bundle_cid: ignored, ...selectedBody} = JSON.parse(environmentWire);
      void ignored;
      body = selectedBody;
    }
    const capacity = body.host_policy_profile.capacity;
    const policyChanged = calendarArtifact !== undefined ||
      !Object.hasOwn(capacity, 'max_graph_construction_edges') ||
      !Object.hasOwn(capacity, 'max_graph_construction_input_rows') ||
      !Object.hasOwn(capacity, 'max_graph_construction_nodes');
    if (policyChanged) {
      body.host_policy_profile = {...body.host_policy_profile,
        capacity: {max_graph_construction_edges: 1000,
          max_graph_construction_input_rows: 1000,
          max_graph_construction_nodes: 1000, ...capacity}};
      if (calendarArtifact !== undefined) {
        body.host_policy_profile.calendar = installedCalendarSelection(calendarArtifact);
      }
    }
    if (hostCapacityPolicy !== undefined) {
      effectiveHostCapacityPolicyCid = contentCid(body.host_policy_profile.capacity);
    }
    // Semantic artifact metadata is exact value data, not NFC configuration
    // text. Keep the original serialization path when no Calendar is selected.
    if (!policyChanged && environmentWire === composedEnvironment.wire) {
      environmentEvidenceCid = composedEnvironment.evidenceCid;
    } else {
      environmentEvidenceCid = calendarArtifact === undefined ? contentCid(body)
        : bytesCid(Buffer.from(canonicalValueJson(body), 'utf8'));
      environmentWire = calendarArtifact === undefined
        ? canonicalJson({...body, evidence_bundle_cid: environmentEvidenceCid})
        : canonicalValueJson({...body, evidence_bundle_cid: environmentEvidenceCid});
    }
    environmentBody = body;
    if (projectTasks !== undefined) {
      // Extend AFTER Host-local policy encoding. Do not NFC-normalize the
      // original public Task identifier or rebuild its preimage in JS.
      if (mockModels === undefined) {
        environmentWire = projectTasks.projectEnvironmentForRuntime(moon, environmentWire,
          environmentEvidenceCid).environmentWire;
      } else {
        // All Task/prompt/execution/retry/backoff bodies came from this same
        // Common profile/normalization. Do not rewrite the original model or
        // choose a different Task/provider from current registry defaults.
        modelInstallation = mockModels.modelInstallationForRuntime(moon, environmentWire,
          environmentEvidenceCid);
        environmentWire = modelInstallation.environmentWire;
      }
      // Read a newly issued Task document at the existing final-check phase,
      // after connector binding validation, without retaining the old body.
      environmentBody = environmentEvidenceCid = undefined;
    }
    verifyInstalledConnectorBindings(sourceProfile,
      installedEffect ?? effectInstallation);
  } catch (cause) {
    // An adapter that failed before returning its owner must clean up its
    // own partial acquisition. Preserve its original public failure when the
    // Host has acquired nothing else.
    if (sourceProfile === undefined && installedEffect === undefined) {
      throw cause;
    }
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile, installedEffect});
  }
  let environment;
  let evidenceCid;
  let sourcePublication;
  try {
    if (environmentBody === undefined) {
      const {evidence_bundle_cid: selectedEvidenceCid, ...selectedBody} = JSON.parse(environmentWire);
      environmentEvidenceCid = selectedEvidenceCid;
      environmentBody = selectedBody;
    }
    evidenceCid = environmentEvidenceCid;
    const numericProfile = JSON.parse(preparation === undefined
      ? await readFile(join(packageRoot,
        'spec/contracts/actql-numeric-reduction.json'), 'utf8')
      : preparation.readAsset('spec/contracts/actql-numeric-reduction.json'));
    const numericProfileCid = `sha256:${createHash('sha256')
      .update(canonicalJson(numericProfile)).digest('hex')}`;
    const graphLaw = JSON.parse(preparation === undefined
      ? await readFile(join(packageRoot,
        'spec/dependencies/actql-graph-laws.json'), 'utf8')
      : preparation.readAsset('spec/dependencies/actql-graph-laws.json'));
    // These declarations admit checking for the installed family providers.
    // The exact task offer and execution obligations still select capability.
    const textTimeEnabled = environmentBody.host_policy_profile?.text_time_evaluation !== undefined;
    environmentBody = undefined;
    environment = moon.clientProgramCheckEnvironmentWithGraphProfile(
      environmentWire, evidenceCid,
      textTimeEnabled,
      true, true, true, true,
      calendarArtifact !== undefined, false, numericProfileCid, contentCid(graphLaw));
    if (environment !== undefined) {
      environment = admitInstalledCalendar(moon, environment, calendarArtifact);
    }
    if (environment !== undefined) {
      sourcePublication = sourceAliasPublication(moon, environment,
        sourceProfile?.queryAliases ?? [],
        installedEffect?.queryTableBindings ?? effectInstallation?.queryTableBindings ?? [],
        {updateTargets: installedEffect === undefined ? [] :
          installedUpdateTargets(installedEffect, installedEffect.queryUpdateTargets ?? [], environmentWire),
          storeTargets: installedEffect?.queryStoreTargets ?? [],
          namespace: sourceNamespace === undefined ? undefined : {
          name: sourceNamespace, profilePaths: selectedSourcePaths},
          selectorNamespace: sourceSelectorNamespace === undefined ? undefined : {
            name: sourceSelectorNamespace, profilePaths: selectedSourcePaths},
          installedSources: sourcePublicationSources ?? sourceProfile?.sources ??
            (sourceProfile === undefined ? [] : [sourceProfile])});
      const sourceEnvironmentOriginal = sourceAliasPublicationOriginal(moon, environment, sourcePublication);
      if (sourceEnvironmentOriginal !== undefined) {
        completeInstalledSourceInitialization(installationServices, originalInstallation,
          sourceEnvironmentOriginal.preparedEnvironment, environmentWire);
        preparedSourceEnvironment = Object.freeze({host, moon, environment, publication:sourcePublication,
          preparedEnvironment:sourceEnvironmentOriginal.preparedEnvironment});
        if (preparation !== undefined) {
          originalInstallation.closedValuesPreparationContext = Object.freeze({runtime: moon,
            control: originalInstallation.initialControl, environment,
            preparedEnvironment: sourceEnvironmentOriginal.preparedEnvironment, retainedRelationOutput,
            valuesMaxRows: originalInstallation.valuesMaxRows});
        }
      }
    }
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile, installedEffect});
  }
  if (environment === undefined) {
    throw await retainInstalledHostInitializationFailure(
      new Error('InvalidInstalledLocalEnvironment'),
      {sourceProfile, installedEffect});
  }
  let registry;
  let values;
  let fragment;
  let ordered;
  const namespaceId = 'local';
  const authorityScopeCid = cid({version: 'actql-local-owner-scope/0.1',
    root, principalId, ...(hostCapacityPolicy === undefined ? {} :
      {hostCapacityPolicyCid: effectiveHostCapacityPolicyCid}),
    ...(hostLookupExecutionPolicy === undefined ? {} :
      {hostLookupExecutionPolicyCid: contentCid(hostLookupExecutionPolicy)})});
  const storeAuthorityCid = localPublicationStoreAuthorityCid(root, principalId);
  let journal;
  let originalJournalClose, publicationOwnership;
  let unselectedJournalAttempted = false, unselectedJournalFailure;
  const publicationDirectory = join(root, 'publication');
  function hostJournalExclusion() {
    if (journal !== undefined) {
      const current = observeOriginalClientRequestJournalCustody(journal);
      return Object.freeze({pending: current.databaseClosed !== true ||
        current.observationDatabaseClosed !== true});
    }
    if (!unselectedJournalAttempted) return Object.freeze({pending: false});
    if (unselectedJournalFailure === undefined) return Object.freeze({pending: true});
    const failure = unselectedJournalFailure;
    try {
      if (!failure.observed) {
        failure.cleanup = failure.cause?.cleanupHandle;
        failure.pending = failure.cause?.cleanupPending === true;
        failure.observed = true;
      }
      if (failure.cleanup === undefined) return Object.freeze({pending: failure.pending});
      if (!failure.statusObserved) {
        failure.status = failure.cleanup.status;
        failure.statusObserved = true;
      }
      if (typeof failure.status !== 'function') return Object.freeze({pending: true});
      const current = Reflect.apply(failure.status, failure.cleanup, []);
      const pending = current !== null && typeof current === 'object'
        ? Object.getOwnPropertyDescriptor(current, 'pending') : undefined;
      return Object.freeze({pending: pending === undefined || !Object.hasOwn(pending, 'value') ||
        pending.value !== false});
    } catch {
      // This same constructor still owns the unobserved cleanup. Never
      // release its exclusion from an unavailable getter or public flag.
      return Object.freeze({pending: true});
    }
  }
  function closeHostRequestJournal() {
    if (journal === undefined) return;
    originalJournalClose ??= journal.close;
    if (typeof originalJournalClose !== 'function') {
      throw clientOperationError('InstalledHostJournalCleanupPending');
    }
    Reflect.apply(originalJournalClose, journal, []);
    // Public Journal.close may acknowledge the primary while its optional
    // observation close is still pending. Keep this Host phase retryable
    // until both SAME native originals have actually closed.
    if (hostJournalExclusion().pending) {
      throw clientOperationError('InstalledHostJournalCleanupPending');
    }
  }
  async function closeHostPublicationOwnership() {
    if (publicationOwnership === undefined) return;
    const current = await closePreparedLocalPublicationStoreOwnership(publicationOwnership);
    const pending = current !== null && typeof current === 'object'
      ? Object.getOwnPropertyDescriptor(current, 'pending') : undefined;
    if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
      throw clientOperationError('InstalledHostPublicationOwnershipCleanupPending');
    }
    publicationOwnership = undefined;
    unselectedJournalFailure = undefined;
  }
  async function openHostRequestJournal(journalOptions) {
    if (preparation === undefined) {
      // Every same-root writable Host route acquires the existing Store
      // exclusion before touching the Journal, not merely when Store opens.
      // This moves ordinary custody; it supplies no selected resource credit.
      const original = await prepareLocalPublicationStoreOwnership(publicationDirectory,
        undefined, Object.freeze({status: hostJournalExclusion}));
      publicationOwnership = original;
      assertOriginalPreparedLocalPublicationStoreOwnership(original, publicationDirectory);
      unselectedJournalAttempted = true;
    }
    try {
      journal = preparation === undefined
        ? openClientRequestJournal(journalDirectory, journalOptions, publicationOwnership)
        : await preparation.openRequestJournal(journalDirectory, journalOptions);
      // Retain the acquired Journal before this fallible callback capture.
      originalJournalClose = journal.close;
      return journal;
    } catch (cause) {
      if (preparation === undefined && journal === undefined) {
        unselectedJournalFailure = {cause, observed: false, statusObserved: false};
        hostJournalExclusion();
      }
      throw cause;
    }
  }
  let effectEvidenceKey = mockAccount?.evidenceKey;
  let checkpoints;
  let runAcceptance;
  let modelController;
  let dispatchOwner;
  let diagnostic;
  let observation;
  let localSnapshotConfiguration;
  let ownerViews;
  let activationFlight, activationFailure, publicationOpeningFailure;
  try {
    const delivery = createDiagnosticObserver(authorization?.observe);
    diagnostic = Object.assign((event, detail) => {
      observation?.diagnostic(event, detail);
      delivery(event, detail);
    }, {close: delivery.close, status: delivery.status});
    const sequenceContracts = preparation.readSequenceContracts();
    values = sequenceContracts.contracts.values;
    fragment = sequenceContracts.contracts.expression;
    ordered = sequenceContracts.contracts.ordered;
    registry = sequenceContracts.admission;
    await mkdir(journalDirectory, {recursive: true, mode: 0o700});
    const snapshotDirectory = join(root, 'carrier-snapshots');
    // Installed physical wiring, never Program settings. Allocation occurs
    // only after the common driver has reserved work/capacity and captured
    // the snapshot cleanup owner. Graph row Relations use the same Store for
    // verified export/reload before their ordinary guaranteed projection.
    const installStore = retainedRelationOutput
      ? installLocalRetainedStore : installLocalSnapshotStore;
    // Private fixture wiring, never a Program or transport setting. Select
    // the physical factory before allocation; a rejected factory still owns
    // anything it created until a lease is transferred to the existing driver.
    const snapshotFactory = authorization?.faultInjection?.localSnapshotStoreFactory;
    if (snapshotFactory !== undefined &&
        (typeof authorization.faultInjection !== 'function' ||
          typeof snapshotFactory !== 'function')) {
      throw new TypeError('InvalidLocalSnapshotStoreFactory');
    }
    localSnapshotConfiguration = installStore(async (key, bytes, frame, signal) => {
      // The existing driver invokes this physical factory only after its
      // original attempt reserves the snapshot. Merely connecting/checking
      // needs no snapshot directory or lease. Keep the same parent and factory.
      signal?.throwIfAborted();
      await mkdir(snapshotDirectory, {recursive: true, mode: 0o700});
      signal?.throwIfAborted();
      return snapshotFactory === undefined
        ? createLocalRetainedStore({parentDirectory:snapshotDirectory,
          capacityBytes:bytes,maxFrameBytes:frame,maxEntries:1})
        : snapshotFactory(Object.freeze({key,bytes,frame,
          parentDirectory:snapshotDirectory,signal}));
    },
    authorization?.faultInjection);
    const journalOptions = {
      updateOriginalControl: createUpdateTargetOriginalShapeControl(moon),
      // Private fault hooks exercise the real installed admission clock;
      // Programs and public transport requests cannot select these values.
      submissionEpochTtlMs: authorization?.faultInjection?.submissionEpochTtlMs,
      submissionEpochNow: authorization?.faultInjection?.submissionEpochNow,
    };
    // Only the same selected writable facility may instantiate its Journal.
    // Unselected Hosts retain the existing constructor. A directory or option
    // object cannot select a native constructor or issue resource admission.
    journal = await openHostRequestJournal(journalOptions);
    // The distinct selected Compute purpose needs this SAME opened Journal
    // before it covers SDK request/attempt control. It is not Source credit.
    // Legacy unprepared Hosts keep their original path without a new await.
    if (preparation !== undefined) {
      // query.all() captures its caller input before awaiting submission.
      // Bind the separate Result control original before exposing the client;
      // The same initialization selects its private-evidence key here;
      // Store/payload construction itself remains lazy below.
      await preparation.prepareResultPublication();
      if (originalSourcePreparation === undefined) await preparation.prepareManagedCompute();
    }
    const originalRequestPreparation = preparation.requestPreparation();
    observation = installHostObservation(observationConnection, {journal,
      runId: ref => {
        const retained = journal.lookupRunDefinition(ref, moon, control);
        return retained === undefined ? undefined :
          control.runDefinitionRunId(retained.runDefinition);
      }});
    if (observation !== undefined) journal.installObservationProjection(observation);
    const hostConnection = ({principalId: actual, connection, ref}) =>
      actual === principalId &&
      connection.mode === mode && connection.owner === mode &&
      (ref === undefined || ref.namespaceId === namespaceId &&
        ref.authorityScopeCid === authorityScopeCid);
    const authorizedScope = ({principalId: actual}) =>
      actual === principalId ? {namespaceId, authorityScopeCid} : undefined;
    const negotiate = async value => ({version: 'actql-client-host/0.1',
      mode, owner: mode, durability: 'durable',
      ...(value.connection.workspaceId === undefined ? {} : {workspaceId}),
      scopeRef: authorityScopeCid,
      ...(hostConnection(value) ? {submissionEpoch: await issueNodeClientSubmissionEpoch({
        journal,moon,authorizedScope: request => hostConnection(request)
          ? authorizedScope(request) : undefined},value)} : {}),
      capabilities: ['result-jsonl'], limits: {
        maxReadWireBytes: 10 * 1024 * 1024,
        maxRowWireBytes: 1024 * 1024,
        maxRowRetainedValueBytes: 1024 * 1024,
        maxRetainedValueBytes: 10 * 1024 * 1024,
        maxRows: 10000, maxBatchRows: 1000,
        maxBatchRetainedValueBytes: 10 * 1024 * 1024,
      }});
    const initializePublicationServices = async () => {
    try {
    if (preparation !== undefined) {
      // This separate original precedes Store/key/payload work; neither the
      // Journal nor a source-free Compute quote can supply this purpose.
      await preparation.prepareResultPublication();
    }
    // Generated Content also retains encrypted private proofs. This is Store
    // custody, not an Effect permission or an implicit external write grant.
    if (preparation === undefined && effectInstallation?.privateEvidenceKey === undefined) {
      const keyDirectory = join(root, 'checkpoints');
      try {
        effectEvidenceKey = await loadPrivateEvidenceKey(keyDirectory);
      } catch (error) {
        if (error?.code !== 'PrivateEvidenceKeyUnavailable') throw error;
        let existing = false;
        try { existing = (await stat(keyDirectory)).isDirectory(); }
        catch (missing) { if (missing?.code !== 'ENOENT') throw missing; }
        if (existing) throw error;
        await createPrivateEvidenceKey(keyDirectory);
        effectEvidenceKey = await loadPrivateEvidenceKey(keyDirectory);
      }
    }
    if (modelRuntimeView !== undefined) assertNewModelRuntime();
    try {
    const storeOptions = localPublicationStoreOptions(root, storeAuthorityCid,
      effectInstallation?.privateEvidenceKey ?? effectEvidenceKey?.key);
    store = preparation === undefined
      ? await openLocalPublicationStore(storeOptions, control, undefined, undefined, publicationOwnership)
      : await preparation.openResultPublicationStore(storeOptions, control);
    if (mockAccount !== undefined) await mockAccount.adoptStore(store);
    if (standardAccountPreparation !== undefined) {
      const configuredConnections = [...new Set((sourceProfile?.sources ??
        (sourceProfile === undefined ? [] : [sourceProfile]))
        .flatMap(source => installedSourceReadAccesses(source).map(access => access.connection)))].sort();
      const modelTasks = (projectTasks?.originalsForRuntime(moon) ?? [])
        .map(entry => [entry.providerId, entry.taskCid])
        .sort((left, right) => left[0] < right[0] ? -1 : left[0] > right[0] ? 1
          : left[1] < right[1] ? -1 : left[1] > right[1] ? 1 : 0);
      const controlConnection = authorization?.siteKey ?? 'actql-remote-host';
      authorization = await standardAccountPreparation.adopt(moon, {
        controlConnection, configuredConnections, modelTasks,
        requestTarget: [controlConnection, sourceProfile?.realizationKey ?? REALIZATION_KEY],
      }, store);
    }
    } catch (cause) {
      // This same Store opener may retain a child whose release depends on
      // the already acquired Journal. Its initializer has not started any
      // dispatch/checkpoint service; preserve that original provenance so
      // cleanup can drain Journal independently, without releasing the token.
      publicationOpeningFailure = {cause};
      throw cause;
    }
    if (modelRuntimeView !== undefined) {
      // The real factory's result, not a lookup/configuration reconstruction.
      // Keep the static module and this Store through failed/pending cleanup.
      // Managed Host controls and original Run Promise/Buffer duties still need
      // their own coverage; this is not a normal numeric profile or byte grant.
      bindInferTrustedStore(modelRuntimeView, runtimeOriginals(), store, publicationStoreModule);
      assertModelRuntime();
    }
    effectEvidenceKey?.key.fill(0);
  const lookupRequest = installNodeClientRequestLookup({journal,
    control: moon, authorizedScope});
  const startRun = installNodeClientRunStart({journal,
    requestControl: moon, publicationControl: control,
    authorizeRunStart: ({principalId: actual, connection, ref}) =>
      hostConnection({principalId: actual, connection, ref})});
  const {result: authorizeLocalResult, run: authorizeLocalRun} = createLocalReadAuthorizations({
    moon, authorization, principalId, namespaceId, authorityScopeCid, observation});
  const resultAuthority = installResultAccessAuthority({
    authorizeResultReadRequest: authorizeLocalResult,
    admitResultRead: async (facts, operation) => {
      if (await authorizeLocalResult(facts, operation) !== true) {
        throw Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied'});
      }
      const {attemptId} = facts;
      return {
      authorizationContextCid: cid({version: 'actql-local-read/0.1',
        attemptId}),
      dataCeilingCid: cid({version: 'actql-local-read-ceiling/0.1'}),
      egressAdmissionCid: cid({version: 'actql-local-egress/0.1'}),
      expiresAt: plus(now(), 60 * 60 * 1000),
      maxBytes: localOutputLimits.maxWireBytes, maxUses: 1,
      };
    },
    authorizeResultRead: authorizeLocalResult,
    authorizeDeliveryAttemptLookup: authorizeLocalResult,
    authorizeResultDescription: authorizeLocalResult,
    admitResultDescription: async (facts, operation) => {
      if (await authorizeLocalResult(facts, operation) !== true) {
        throw Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied'});
      }
      const {attemptId} = facts;
      return {
      authorizationContextCid: cid({version: 'actql-local-read/0.1',
        attemptId}),
      dataCeilingCid: cid({version: 'actql-local-read-ceiling/0.1'}),
      egressAdmissionCid: cid({version: 'actql-local-egress/0.1'}),
      expiresAt: plus(now(), 60 * 60 * 1000),
      maxBytes: localOutputLimits.maxWireBytes, maxUses: 1,
      };
    },
  });
  const resultService = installNodeResultAccessService({store, control,
    authority: resultAuthority, now, limits: localContractLimits,
    frameLimits: {maxRowBytes: 1024 * 1024, maxDepth: 64,
      maxFrameBytes: 1024 * 1024}});
  const stateService = installRunStateService({store, control,
    authority: installRunStateAuthority({
      authorizeRunState: ({principalId: actual}) => actual === principalId,
      resultPolicyAvailable: () => true,
    }), now, limits: localContractLimits});
  const attach = installNodeClientRunAttach({journal,
    requestControl: moon, publicationControl: control, authorizedScope,
    authorizeRun: ({ref, principalId: actual}) =>
      actual === principalId && ref.namespaceId === namespaceId &&
      ref.authorityScopeCid === authorityScopeCid});
  const checkSource = installNodeClientCheck({moon, environment,
    publication: sourcePublication,
    ...(sourceNamespace === undefined && sourceSelectorNamespace === undefined ? {} : {
      // Re-read current account configuration for every metadata inspection.
      // This gate cannot defer or persist diagnostic approval.
      namespaceAuthorizationFor: ({principalId: actual}) => createLocalAuthorizationGate({
        ...authorization, principal: actual, deferral: undefined,
      }),
    }),
    tableWriteAccesses: installedEffect?.queryTableWriteAccesses ??
      effectInstallation?.queryTableWriteAccesses ?? [],
    sourceAccesses: (sourceProfile?.sources ??
      (sourceProfile === undefined ? [] : [sourceProfile]))
      .flatMap(installedSourceReadAccesses)});
  // Checking dispatches nothing and reads no source rows; the audience is
  // the authenticated caller this connection admits.
  const check = async ({principalId: actual, connection, ...request}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw clientOperationError('ClientConnectionDenied');
    }
    // Preserve the selected scope and the absence of template bindings across
    // this installed-Host authorization boundary.
    const result = await checkSource({principalId: actual, ...request});
    // The verdict belongs to the common checker. No diagnostic text, source
    // location, authored name, source bytes or hypothetical Run is projected.
    observation?.emit('check', 'check_completed', {checkVerdict: result.report?.verdict,
      outcome: result.report?.verdict === 'invalid' || result.outcome === 'failed'
        ? 'failed' : result.report?.verdict === 'verified' ? 'succeeded' : 'unknown'});
    return result;
  };
  Object.defineProperty(check, 'unavailable', {value: checkSource.unavailable});
  updateTargetOriginals = installUpdateTargetOriginals({moon, control, installedEffect,
    limits: localContractLimits});
  const prepareSubmit = installNodeClientProgramPreparation({moon,
    environment, valuesMaxRows,
    getFundedPreparation: (request, selectedEnvironment, originalVerifier, signal) =>
      preparation.fundedPreparation(request, selectedEnvironment, originalVerifier, signal),
    verifyRequestValuePolicy, restoreEffectOriginal: updateTargetOriginals.restorePrepared,
    restoreInferOriginal: (original, definition, request, evidence, restorationRequest) =>
      preparation.restoreManagedModelOriginal(moon, restorationRequest, original, definition, request,
        () => control.admitStoredClientInferRunOriginal(original, definition, request, evidence,
          [false, true, true, true, true, calendarArtifact !== undefined, false], localContractLimits)),
    allowEffects: effectInstallation !== undefined});
  // The same complete dispatch retirement predicate covers installed ordinary
  // Sources using this Host's managed parent. Other purposes keep their owner.
  const localPreparationCustody = installLocalPreparationRegistry(prepared => {
    if (preparation?.canRetireManagedPreparation?.() !== true) return false;
    if (prepareSubmit.kindOf(prepared) !== 'effect_free') return false;
    const serializations = moon.clientProgramSerializationOccurrences(prepared);
    const inventory = moon.clientProgramComposedInferOccurrences(prepared);
    if (!runtimeIsOk(inventory)) return false;
    const count = runtimeField(inventory, 0).length;
    if (serializations.length !== 0) return serializations.length === 1 && count === 0 &&
      (moon.clientProgramAcquisitionCount(prepared) === 0 ||
        moon.clientProgramAcquisitionCount(prepared) === 2 && preparation.managesInstalledSources?.() === true) &&
      typeof moon.clientProgramPreparationBorrowSibling === 'function';
    // This selects custody only. The registry still requires the SAME
    // Request's actual Core borrower, not an INFER shape or a permission.
    if (count !== 0) return typeof moon.clientProgramPreparationBorrowSibling === 'function';
    return moon.clientProgramAcquisitionCount(prepared) === 0 ||
      preparation.managesInstalledSources?.() === true;
  }, prepared => {
    const finish = preparation?.retireManagedComputeRun(prepared);
    releaseRequestModelAliases(prepared);
    prepareSubmit.retireOriginal(prepared);
    return finish;
  }, typeof moon.clientProgramPreparationBorrowSibling !== 'function' ? undefined : {
    runtime: moon, borrow: (prepared, request) => preparation?.borrowManagedPreparation?.(prepared, request),
  }, releaseRequestDomainAliases);
  preparation?.retainUndispatchedRetirement(localPreparationCustody.retireQuiescentUndispatched,
    localPreparationCustody.retireRetiringOriginal, releaseRequestDomainAliases);
  clientProgramPreparationReferences = Object.freeze({owner: prepareSubmit,
    retire: prepareSubmit.retireReferences});
  const prepareCapturedSubmission = async (submission, ref) => {
    const retained = ref === undefined ? undefined : journal.lookupRunDefinition(ref, moon, control);
    if (retained !== undefined &&
        runUpdateSelectionCid(retained.runDefinition, moon) !== undefined &&
        submission.updateTargetPreparedOriginal === undefined) {
      throw clientOperationError('InstalledEffectOriginalSelectionChanged');
    }
    return submission.updateTargetPreparedOriginal === undefined ? prepareSubmit(submission)
      : prepareSubmit.restoreOriginal(submission.updateTargetPreparedOriginal);
  };
  const capturedUpdateOriginal = submission => {
    if (prepareSubmit.kindOf(submission.preparedProgram) !== 'effectful') return {};
    const original = effectRun.capturePreparedOriginal(submission.preparedProgram);
    return original === undefined ? {} : {updateTargetPreparedOriginal: original};
  };
  const plan = installClientStaticPlan({moon, control, prepare: prepareSubmit,
    authorize: hostConnection});
  Object.freeze(check);
    if (modelInstallation !== undefined && authorization !== undefined) {
      modelController = await installNodeModelContinuation({moon, control,
        store, storeAuthorityCid, authorityScopeCid, namespaceId, now, observe: diagnostic,
        observation, inferEvidence: evidenceConfiguration,
        getCheckpoints: () => checkpoints});
    }
    ({checkpoints, runAcceptance} = await installHostRunAcceptance({root, namespaceId,
      authorityScopeCid, ownerPrincipal: principalId,
      siteKey: authorization?.siteKey ?? 'actql-remote-host',
      realizationKey: sourceProfile?.realizationKey ?? REALIZATION_KEY,
      environmentCid: evidenceCid,
      contractControl: control,
      modelResumeVerifier: modelController?.verifier,
      ...(installedEffect?.effects === undefined
        ? {effectTarget: effectInstallation?.targetReadAuthorization}
        : {effectTargets: installedEffect.effects.filter(effect =>
          effect.targetReadAuthorization !== undefined).map(effect => ({
          selectors: effect.effectSelectors, authorization: effect.targetReadAuthorization}))}),
      authorization: authorization == null ? authorization :
        {...authorization, observe: diagnostic},
      ...(sourceProfile?.sources === undefined &&
          (sourceProfile === undefined ||
            installedSourceReadAccesses(sourceProfile).length === 1)
        ? {source: sourceProfile === undefined ? undefined : {
          ...sourceProfile.readAuthorization,
          sourceRef: installedSourceReadAccesses(sourceProfile)[0].sourceRef}}
        : {sources: (sourceProfile?.sources ?? [sourceProfile]).flatMap(source =>
          installedSourceReadAccesses(source).map(access => ({
            sourceRef: access.sourceRef, ...source.readAuthorization})))})}));
  const projectRunObservation = (ref, state, retained) => {
    if (observation === undefined) return;
    try {
      // MoonBit fixes the projection equivalence. SQLite only retains this
      // bounded key; it cannot authorize a transition or reinterpret a Run.
      const ownerFactKey = issueInstalledRunObservationKey(moon, {
        outcome: state.status, revision: retained.revision,
        cleanupPending: state.cleanupPending,
        physicalCloseConfirmed: retained.physicalCloseConfirmed,
      });
      if (ownerFactKey === undefined) { observation.noteLoss(); return; }
      observation.emit('run', 'owner_observed', {ref, outcome: state.status,
        revision: retained.revision,
        physicalStop: retained.physicalCloseConfirmed === true ? 'confirmed' : undefined,
        cleanupPending: state.cleanupPending}, {ownerFactKey});
    } catch { observation.noteLoss(); }
  };
  const observeRun = async ({ref, principalId: actual}) => {
    if (actual !== principalId || ref.namespaceId !== namespaceId ||
        ref.authorityScopeCid !== authorityScopeCid) {
      throw clientOperationError('RunStateAccessDenied');
    }
    // Recheck the journal revision after asynchronous Store observation so
    // control facts never combine observations from two journal revisions.
    for (let attempt = 0; attempt < 8; attempt++) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined) {
        throw clientOperationError('RunStateAccessDenied');
      }
      const observeControl = journal.observeRunCancellation(ref, moon, control,
        retained);
      const runId = control.runDefinitionRunId(retained.runDefinition);
      let state;
      let continuation;
      const committedState = await observeAuthorizedRunState(stateService, {
        indexKey: ref, principalId: actual, purpose: 'inspect',
      });
      if (committedState !== undefined) {
        state = committedState;
      } else {
        if (!Array.isArray(retained.resultNames)) {
          throw new Error('RunStateInventoryUnknown');
        }
        continuation = checkpoints?.effectRunState(runId,
          ref.runDefinitionCid);
        if (continuation?.status === 'succeeded') {
          // A second journal cannot establish Publication Store success.
          // Reobserve the committed index instead of issuing success from
          // the Checkpoint lifecycle alone.
          continue;
        }
        if (!dispatchOwner.live(ref) && !modelResumeFlights.has(ref.runDefinitionCid) &&
            (checkpoints?.journal.hasUnresolvedModelCalls(runId) === true ||
            continuation?.status === 'resuming' &&
            (checkpoints.hasUnresolvedSourceStart(runId, ref.runDefinitionCid) ||
             checkpoints.hasUnresolvedEffectTargetStart(runId, ref.runDefinitionCid) ||
             checkpoints.hasUnresolvedModelStart(runId, ref.runDefinitionCid)))) {
          state = issueInstalledUnpublishedRunState(moon, {runId,
            observedAt: now(), resultNames: retained.resultNames,
            dispatchReserved: true, preDispatchFailureConfirmed: false,
            cancelledBeforeStart: false, observedTerminalOutcome: 'none',
            executionUnknown: true});
        } else if (continuation !== undefined &&
            continuation.status !== 'running') {
          state = continuation.runState;
        } else {
          const liveExecution = dispatchOwner.live(ref);
          const executionUnknown = retained.dispatchReserved &&
            !retained.preDispatchFailureConfirmed &&
            retained.physicalStartReserved !== false &&
            retained.observedTerminalOutcome === null && !liveExecution;
          state = issueInstalledUnpublishedRunState(moon, {
            runId, observedAt: now(), resultNames: retained.resultNames,
            dispatchReserved: retained.dispatchReserved,
            preDispatchFailureConfirmed:
              retained.preDispatchFailureConfirmed,
            cancelledBeforeStart: retained.cancellationRequested &&
              retained.physicalStartReserved === false,
            observedTerminalOutcome:
              retained.observedTerminalOutcome ?? 'none',
            executionUnknown,
          });
        }
      }
      const after = observeControl();
      if (after?.revision !== retained.revision) continue;
      if (continuation !== undefined) {
        const afterContinuation = checkpoints.effectRunState(runId,
          ref.runDefinitionCid);
        if (afterContinuation?.version !== continuation.version) continue;
      }
      if (state.status === 'running' && !dispatchOwner.live(ref) &&
          retained.physicalStartReserved === true) {
        continue;
      }
      // Only this revision-stable common Owner projection supplies status.
      projectRunObservation(ref, state, retained);
      try {
        return JSON.parse(journal.publishRunState(retained, state,
          moon, control));
      } catch (cause) {
        if (cause?.code === 'RunStateObservationChanged') continue;
        throw cause;
      }
    }
    throw new Error('RunStateObservationUnstable');
  };
  const cancelEffectContinuation = async ref => {
    if (checkpoints === undefined) return false;
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || !retained.cancellationRequested) {
      return false;
    }
    return cancelNodeRunContinuation({ref, journal, store, checkpoints, moon, control,
      currentDispatchIdle: () => dispatchOwner.operation(ref) === undefined &&
        !effectResumeFlights.has(ref.runDefinitionCid) &&
        !modelResumeFlights.has(ref.runDefinitionCid)});
  };
  const continueAcceptedCancellation = async (ref, accepted) => {
    if (accepted.kind === 'already_terminal') return;
    dispatchOwner.cancel(ref);
    try { await cancelEffectContinuation(ref); }
    finally { void checkpoints?.sweep(); }
  };
  // Request-level cancellation already owns its own pre-Run receipt. Its
  // transfer to a defined Run remains separate from a Client cancel operation.
  const cancelRequestRun = async ({ref, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientRunCancellationDenied');
    }
    // Authorization precedes existence queries. A late publication remains a
    // successful Run even if cancellation was accepted while it committed.
    const publicationCommitted =
      await store.confirmCommittedIndex(ref) !== undefined;
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined) throw clientOperationError('ClientRunCancellationDenied');
    const originalRunWire = retained.runAdmissionEvidence?.modelOriginalRunWire;
    if (!publicationCommitted && originalRunWire !== undefined) {
      if (checkpoints === undefined) throw clientOperationError('ModelCancellationJournalUnavailable');
      // The per-call transaction domain wins before the request's independent
      // journal write. A failed second commit is retried without removing the
      // sticky fence; no acknowledgement precedes both durable writes.
      checkpoints.journal.fenceRunCancellation({originalRunWire});
    }
    const accepted = journal.requestCancellation(ref, {
      currentAuthorization: true, publicationCommitted,
    }, moon, control);
    await continueAcceptedCancellation(ref, accepted);
    observation?.emit('run', 'cancellation_requested', {ref,
      revision: accepted.revision, outcome: accepted.outcome});
    return accepted;
  };
  const cancel = async ({ref, cancelId, expectedRevision, attemptRef, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      return journal.recordCancellationAttempt(ref, {attemptRef, cancelId, expectedRevision,
        currentAuthorization: false, publicationCommitted: false}, moon, control);
    }
    const publicationCommitted = await store.confirmCommittedIndex(ref) !== undefined;
    // Recheck current connection authority after the publication observation.
    // The journal then compares the original revision under its write lock.
    if (!hostConnection({principalId: actual, connection, ref})) {
      return journal.recordCancellationAttempt(ref, {attemptRef, cancelId, expectedRevision,
        currentAuthorization: false, publicationCommitted: false}, moon, control);
    }
    let recorded;
    try {
      recorded = journal.recordCancellationAttempt(ref, {
        attemptRef, cancelId, expectedRevision, currentAuthorization: true, publicationCommitted,
        modelCancellationOwner: checkpoints?.journal,
      }, moon, control);
    } catch (cause) {
      // A lost COMMIT acknowledgement can leave an accepted original operation.
      // Observe its exact durable identity before waking the existing stop and
      // continuation owners. Pending or unavailable custody grants no authority
      // to advance cancellation, and the lost reply remains unknown to the SDK.
      let retained;
      try {
        retained = journal.lookupCancellationOperation({...ref, cancelId, expectedRevision},
          {currentAuthorization: hostConnection({principalId: actual, connection, ref})},
          moon, control);
      } catch { /* Recovery remains with the durable journal and its existing sweep. */ }
      if (retained?.kind === 'found') {
        try { await continueAcceptedCancellation(ref, retained.cancellation); }
        catch { /* Preserve the original unknown reply; cleanup remains owned. */ }
      }
      throw cause;
    }
    if (recorded.kind === 'refused' || recorded.kind === 'conflict') return recorded;
    const accepted = recorded.cancellation;
    if (recorded.recorded) await continueAcceptedCancellation(ref, accepted);
    observation?.emit('run', 'cancellation_requested', {ref,
      revision: accepted.revision, outcome: accepted.outcome});
    const {recorded: _recorded, ...outcome} = recorded;
    return Object.freeze(outcome);
  };
  const lookupCancellation = ({ref, cancelId, expectedRevision, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientCancellationDenied');
    }
    return journal.lookupCancellationOperation({...ref, cancelId, expectedRevision},
      {currentAuthorization: true}, moon, control);
  };
  // Cancel a request by its ID. For a request this Host held, the
  // cancellation is first made durable on its prepare attempt, so a resume
  // (on this or a later start) cannot start it and hands it to the Run.
  // When the request has a Run (created before or concurrently), the same
  // cancellation is then applied to that Run through its own cancellation,
  // which the physical start reservation observes atomically.
  const cancelRequest = async ({principalId: actual, connection,
    requestId}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw clientOperationError('ClientRequestCancellationDenied');
    }
    const held = checkpoints?.heldOrigin(requestId)
      ? checkpoints.cancelHeld(requestId) : undefined;
    const existing = journal.lookupDefinition({namespaceId, authorityScopeCid,
      requestId}, moon, control);
    if (existing !== undefined) {
      const run = await cancelRequestRun({ref: existing.ref, principalId: actual,
        connection});
      void checkpoints?.sweep();
      return {requestId, ref: run.ref, revision: run.revision,
        kind: held?.outcome === 'accepted' && run.kind === 'already_requested'
          ? 'accepted' : run.kind};
    }
    if (held === undefined) {
      throw clientOperationError('ClientRequestNotFound');
    }
    void checkpoints.sweep();
    return {requestId, kind: held.outcome};
  };
  // Share one settlement reaction per original work Promise. A timed-out
  // waiter removes its own listener without abandoning or retaining the
  // original physical operation. Settlement is only a hint to read again.
  const waitWork = new WeakMap();
  const subscribeWaitWork = (promise, wake) => {
    if (promise === undefined) return () => {};
    let work = waitWork.get(promise);
    if (work === undefined) {
      work = {pending: true, listeners: new Set()};
      waitWork.set(promise, work);
      const settled = () => {
        work.pending = false;
        for (const listener of work.listeners) listener();
        work.listeners.clear();
      };
      promise.then(settled, settled);
    }
    if (work.pending) work.listeners.add(wake);
    return () => work.listeners.delete(wake);
  };
  const wait = async ({ref, principalId: actual, until, since, signal}) => {
    if (until !== null && until !== 'terminal') {
      throw clientOperationError('InvalidWaitCondition');
    }
    if (since !== null && (!Number.isSafeInteger(since) || since < 0)) {
      throw clientOperationError('InvalidWaitRevision');
    }
    const interruption = () => clientOperationError(
      signal?.reason?.name === 'TimeoutError' ? 'WaitTimeout' : 'WaitAborted');
    if (signal?.aborted) throw interruption();
    const observeStep = async promise => {
      let abort;
      const interrupted = new Promise((_, reject) => {
        abort = () => reject(interruption());
        signal?.addEventListener('abort', abort, {once:true});
        if (signal?.aborted) abort();
      });
      try { return await Promise.race([promise, interrupted]); }
      finally { signal?.removeEventListener('abort', abort); }
    };
    for (;;) {
      if (signal?.aborted) throw interruption();
      let wake, timer;
      const changed = new Promise(resolve => { wake = resolve; });
      const subscriptions = new Map();
      const captureWork = () => {
        for (const promise of [dispatchOwner.operation(ref),
          effectResumeFlights.get(ref.runDefinitionCid),
          modelResumeFlights.get(ref.runDefinitionCid)]) {
          if (promise !== undefined && !subscriptions.has(promise)) {
            subscriptions.set(promise, subscribeWaitWork(promise, wake));
          }
        }
      };
      try {
        // Register before observation so completion during its asynchronous
        // Store read remains latched even when that read still reports pending.
        captureWork();
        // Reuse the original read/authorization owner. A caller timeout does
        // not retire an unfinished Store read or the original physical work.
        const current = await observeStep(observeRun({ref, principalId:actual}));
        if (signal?.aborted) throw interruption();
        const decision = installedRunWaitDecision(moon, current, since);
        if (decision === 'ready') return current;
        if (decision !== 'pending') throw clientOperationError(decision);
        // Also retain work that started during observation. The unchanged
        // fallback observes other-process changes and later local work; neither
        // a notification nor a settled Promise is a completion/cleanup receipt.
        captureWork();
        await observeStep(Promise.race([changed,
          new Promise(resolve => { timer = setTimeout(resolve, 100); })]));
      } finally {
        clearTimeout(timer);
        for (const unsubscribe of subscriptions.values()) unsubscribe();
      }
    }
  };
  const missingModelExecutionRefusals = new WeakSet();
  const prepareInferSelection = (preparedProgram, occurrence, retain = true) => {
    // The Effect compiler retains this exact graph for the saved admission.
    // Current account/egress callbacks are checked again by physical dispatch.
    if (retain && occurrence !== undefined && inferSelections.has(preparedProgram)) return;
    const restoredRun = prepareSubmit.originalInferRun(preparedProgram);
    const restoredInfer = restoredRun === undefined ? undefined
      : selectRestoredInferOccurrence({moon, control, preparedProgram, restored: restoredRun, occurrence});
    const originalCompilation = updateTargetOriginals?.compilationFor(preparedProgram);
    let originalInfer;
    if (originalCompilation !== undefined) {
      try {
        originalInfer = typeof moon.clientProgramEffectCompilationInferOriginal === 'function'
          ? moon.clientProgramEffectCompilationInferOriginal(originalCompilation) : undefined;
        if (typeof originalInfer?.then === 'function') {
          void Promise.resolve(originalInfer).catch(() => {});
          throw new Error('InstalledInferOriginalCompilationUnavailable');
        }
        if (originalInfer === null || typeof originalInfer !== 'object' ||
            [runtimeField(originalInfer, 0), runtimeField(originalInfer, 1), runtimeField(originalInfer, 2)]
              .some(value => value === undefined || value === null)) {
          throw new Error('InstalledInferOriginalCompilationUnavailable');
        }
        // The reconstructed compilation owns this exact graph, occurrence and
        // execution. Current installation checks below cannot replace them.
        occurrence = runtimeField(originalInfer, 1);
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'original_model_compilation',
          code: cause.code, cause});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
    }
    const selectedStep = occurrence === undefined
      ? moon.clientProgramSelectedInferStep(preparedProgram)
      : runtimeField(moon.clientProgramInferOccurrenceCoordinates(occurrence), 2);
    if (selectedStep !== undefined) {
      const requestModelMaterials = preparation !== undefined
        ? (count, wireAt, containers) => preparation.prepareManagedModelMaterials(
          moon, preparedProgram, count, wireAt, containers) : undefined;
      let execution;
      try {
        if (restoredInfer !== undefined) execution = restoredInfer.execution;
        else if (originalInfer === undefined) {
          ({execution} = readInstalledModelExecution(moon, preparedProgram,
            modelInstallation, occurrence, requestModelMaterials));
        } else execution = runtimeField(originalInfer, 2);
      } catch (cause) {
        const absent = consumeInstalledModelPreparationRefusal(cause,
          preparedProgram, modelInstallation, occurrence, requestModelMaterials);
        diagnostic('infer_preparation_rejected', {boundary: 'model_execution',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramInferModelExecutionIssueKind(cause.cause) :
            undefined});
        const error = clientOperationError('ClientProgramUnsupported', cause);
        if (absent) missingModelExecutionRefusals.add(error);
        throw error;
      }
      let dependencies, originalMockInstallation;
      try {
        if (mockModels !== undefined) {
          const taskCid = occurrence === undefined
            ? moon.clientProgramInferModelTaskCid(preparedProgram, selectedStep)
            : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
          const original = mockModels.forTaskCid(moon, taskCid);
          if (original === undefined ||
              typeof moon.clientProgramReadOriginalMockModelDependencies !== 'function' ||
              typeof moon.clientProgramAdmitOriginalMockProvider !== 'function') {
            throw clientOperationError('InstalledMockModelOriginalUnavailable');
          }
          originalMockInstallation = original.installation;
        }
        dependencies = readInstalledModelDependencies(moon, execution,
          modelInstallation, requestModelMaterials, preparedProgram, occurrence, originalMockInstallation);
      } catch (cause) {
        const original = consumeInstalledModelPreparationRefusal(cause,
          preparedProgram, modelInstallation, occurrence, requestModelMaterials, execution);
        diagnostic('infer_preparation_rejected', {boundary: 'model_dependencies',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramInferModelDependencyIssueKind(cause.cause) :
            undefined});
        const error = clientOperationError('ClientProgramUnsupported', cause);
        if (original) missingModelExecutionRefusals.add(error);
        throw error;
      }
      let admittedProvider;
      try {
        if (mockModels === undefined) {
          admittedProvider = admitInstalledModelProvider(moon, execution, dependencies,
            modelProviders);
        } else {
          // The existing Model owner validates its own original Task, prompt,
          // execution and dependencies. No JS validator, always-true callback
          // or configured physical Provider can stand in for that admission.
          admittedProvider = checked(moon.clientProgramAdmitOriginalMockProvider(
            originalMockInstallation, execution, dependencies));
          mockModels.originalsForRuntime(moon);
        }
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_provider',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramModelProviderAdmissionIssueKind(cause.cause) :
            undefined});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
      if (mockModels !== undefined) {
        // Original Mock is a separate no-I/O purpose. Select only its checked
        // component here; the same Host admits the early Run/Scope below,
        // before preparing either Source. There is no fake SDK preflight,
        // egress observation, quantity grant or replacement Model Ledger.
        const effectful = prepareSubmit.kindOf(preparedProgram) === 'effectful';
        if (occurrence === undefined || restoredInfer !== undefined || originalInfer !== undefined) {
          throw clientOperationError('InstalledMockModelOriginalCompositionUnavailable');
        }
        const hasSerialization = (effectful ? moon.clientProgramEffectSerializationOccurrences
          : moon.clientProgramSerializationOccurrences)(preparedProgram).length !== 0;
        if (hasSerialization && preparation === undefined) {
          throw clientOperationError('InstalledMockModelOriginalCompositionUnavailable');
        }
        const serializationGraph = !hasSerialization ? undefined
          : selectInstalledSerializationGraph({moon, control, preparedProgram, effectful,
            resultDataPolicy: installedResultDataPolicy,
            prepareSerializationGraph: preparation === undefined ? undefined :
              (options, intermediate) => preparation.prepareManagedContentGraph(
                moon, preparedProgram, options, intermediate, effectful ? occurrence : undefined)}, true);
        const deferredGroup = !effectful && preparation !== undefined && !retain;
        const segments = serializationGraph !== undefined || deferredGroup ? undefined : checked(
          (effectful ? moon.clientProgramPrepareEffectInferSegments
            : moon.clientProgramPrepareComposedInferSegments)(preparedProgram,
          occurrence, registry, values, fragment, ordered));
        const graph = preparation !== undefined
          ? preparation.prepareManagedModelGraph(moon, preparedProgram, occurrence, execution, serializationGraph)
          : checked(moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
        const observeAccount = () => observeInstalledAccount(moon, authorization);
        const account = observeAccount();
        const providerBinding = admitInstalledModelProviderBinding(moon, 'mock', {
          bindingOriginals: mockModels.providerBindingOriginalsForRuntime(moon)},
        preparation !== undefined
          ? (providerId, installation, contract, configuration) => preparation.prepareManagedModelBinding(
            moon, preparedProgram, providerId, installation, contract, configuration) : undefined);
        const selection = Object.freeze({localMock: true, originalMockInstallation, step: selectedStep,
          occurrence, graph, computePrefix: segments === undefined ? undefined
            : effectful ? runtimeField(segments, 0) : runtimeOptionalField(segments, 0),
          computeSuffix: segments === undefined ? undefined
            : effectful ? runtimeOptionalField(segments, 1) : runtimeField(segments, 1),
          provider: moon.clientProgramAdmittedModelProvider(admittedProvider, execution),
          account, observeAccount, providerBinding,
          currentProvider() {mockModels.originalsForRuntime(moon); return true;}});
        if (retain) inferSelections.set(preparedProgram, selection);
        return selection;
      }
      const physical = modelProviders.get(moon.clientProgramInferProviderId(execution));
      // Legacy registrations only validate payloads. They cannot implicitly
      // opt into physical preparation or invent an egress observation.
      if (typeof physical?.physicalPreflight !== 'function' ||
          typeof physical?.observeEgress !== 'function' ||
          physical?.quantityCapacity === undefined) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_dispatch',
          code: 'InstalledInferDispatchNotConnected'});
        throw clientOperationError('ClientProgramUnsupported',
          new Error('InstalledInferDispatchNotConnected'));
      }
      let admissionBoundary = 'compute_suffix';
      try {
        // Actual Host/Provider currentness precedes new preparation. The
        // optional explicit startup recipe keeps its own history check; the
        // ordinary trusted Host is not required to supply that recipe.
        if (physical.originalReadInstallation !== undefined || physical.originalReadRecipe !== undefined) {
          admissionBoundary = 'original_startup';
          if (typeof physical.assertNewTrustedRuntime !== 'function') {
            throw clientOperationError('InferTrustedRuntimeViewUnavailable');
          }
          physical.assertNewTrustedRuntime();
          if (modelRuntimeStartupView !== undefined) {
            requireInferTrustedStartupView(modelRuntimeStartupView, runtimeOriginals());
          }
        }
        admissionBoundary = 'compute_suffix';
        const durableModel = modelController !== undefined && checkpoints?.configured === true;
        const step = selectedStep;
        // Intermediate Content owns its physical prefix separately from the
        // ordinary pure-Compute prefix. Select the common checked component
        // before admission, without inventing public Result roots.
        const effectful = prepareSubmit.kindOf(preparedProgram) === 'effectful';
        const effectGraph = preparation === undefined && effectful &&
          moon.clientProgramEffectSerializationOccurrences(preparedProgram).length !== 0
          ? runtimeOptionalField(originalInfer, 0) ?? checked(
            moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution))
          : undefined;
        const serializationGraph = originalInfer !== undefined
          ? control.inferSerializationGraph(runtimeField(originalInfer, 0)) : effectGraph !== undefined
          ? control.inferSerializationGraph(effectGraph)
          : (effectful ? moon.clientProgramEffectSerializationOccurrences
            : moon.clientProgramSerializationOccurrences)(preparedProgram).length !== 0
          ? selectInstalledSerializationGraph({moon, control, preparedProgram, effectful,
            resultDataPolicy: installedResultDataPolicy,
            prepareSerializationGraph: preparation === undefined ? undefined :
              (options, intermediate) => preparation.prepareManagedContentGraph(
                moon, preparedProgram, options, intermediate, effectful ? occurrence : undefined)}, true) : undefined;
        // This original installed Model's module now owns its actual input
        // lowering after the same Request debit. Do not allocate an early
        // standalone prefix/suffix before that backed constructor.
        const acquisitionCount = (effectful ? moon.clientProgramEffectAcquisitionCount
          : moon.clientProgramAcquisitionCount)(preparedProgram);
        const deferredModelInput = restoredInfer === undefined && preparation !== undefined &&
          occurrence !== undefined && serializationGraph === undefined &&
          prepareSubmit.kindOf(preparedProgram) === 'effect_free' &&
          (!retain || acquisitionCount === 1 ||
            acquisitionCount === 0 && physical.originalReadInstallation === undefined &&
              physical.originalReadRecipe === undefined);
        // A restored input already owns its original prefix. Its checked
        // suffix still has to run before the compiled Result can consume the
        // completion; select only that same occurrence's native suffix.
        const segments = deferredModelInput || restoredInfer !== undefined ||
          occurrence === undefined || serializationGraph !== undefined ? undefined : checked(
          (prepareSubmit.kindOf(preparedProgram) === 'effectful'
            ? moon.clientProgramPrepareEffectInferSegments : moon.clientProgramPrepareComposedInferSegments)(preparedProgram, occurrence,
            registry, values, fragment, ordered));
        const computeSuffix = deferredModelInput || effectGraph !== undefined ||
          effectful && serializationGraph !== undefined ? undefined : serializationGraph !== undefined
          ? checked(moon.clientProgramPrepareComposedInferComputeSuffix(preparedProgram,
            occurrence, registry, values, fragment, ordered))
          : occurrence === undefined
          ? checked(moon.clientProgramPrepareInferComputeSuffix(preparedProgram,
            step, registry, values, fragment, ordered))
          : restoredInfer !== undefined
          ? checked(moon.clientProgramPrepareComposedInferComputeSuffix(preparedProgram,
            occurrence, registry, values, fragment, ordered)) : runtimeField(segments, 1);
        admissionBoundary = 'egress';
        let egressAdmission;
        let egressFailure;
        try {
          egressAdmission = checked(occurrence === undefined
            ? moon.clientProgramAdmitInferEgress(preparedProgram, step, execution,
              physical.observeEgress)
            : moon.clientProgramAdmitComposedInferEgress(occurrence, execution,
              physical.observeEgress));
        } catch (error) {
          if (!durableModel) throw error;
          // Historical fixed inputs and saved responses remain readable.
          // Every fresh send must separately require a current egress owner.
          egressFailure = error;
        }
        admissionBoundary = 'account';
        const observeAccount = () => observeInstalledAccount(moon, authorization);
        const account = observeAccount();
        if (!durableModel) {
          const decision = moon.executionAuthorizationEvaluate(account, principalId,
            moon.clientProgramInferProviderId(execution),
            occurrence === undefined
              ? moon.clientProgramInferModelTaskCid(preparedProgram, step)
              : moon.clientProgramInferOccurrenceModelTaskCid(occurrence), 'infer');
          const outcome = JSON.parse(moon.executionAuthorizationEvaluationJson(decision));
          if (outcome.outcome !== 'allow') {
            throw Object.assign(new Error('InstalledInferAuthorityUnavailable'),
              {code: 'InstalledInferAuthorityUnavailable', cause: outcome});
          }
        }
        admissionBoundary = 'plan_graph';
        const graph = restoredInfer !== undefined ? restoredInfer.graph
          : originalInfer !== undefined ? runtimeField(originalInfer, 0)
          : effectGraph !== undefined ? effectGraph : preparation !== undefined && occurrence !== undefined
          ? preparation.prepareManagedModelGraph(moon, preparedProgram, occurrence, execution, serializationGraph)
          : serializationGraph !== undefined
          ? control.prepareCheckedClientSerializedInferGraph(occurrence, serializationGraph, execution)
          : checked(occurrence === undefined
          ? moon.clientProgramInstalledInferPlanGraph(preparedProgram, step, execution)
          : moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
        // This installed immutable recipe binds only DATA from the actual
        // already-backed Graph. It cannot prepare another Program/Request or
        // replace the native Plan's original/profile/whole-read checks.
        const selectedBounds = physical.originalReadRecipe === undefined ? undefined
          : checked(moon.clientProgramPreparedComposedInferBounds(occurrence, graph));
        let originalReadInstallation = physical.originalReadInstallation;
        if (physical.originalReadRecipe !== undefined) {
          const projectModelLedger = moon.clientProgramComposedInferModelLedgerBytes;
          if (typeof projectModelLedger !== 'function') {
            throw clientOperationError('NodeManagedRunRuntimeUnavailable');
          }
          const modelLedgerBytes = Reflect.apply(projectModelLedger, moon, [selectedBounds]);
          originalReadInstallation = bindInferOriginalReadRecipe(moon, physical.originalReadRecipe, graph,
            moon.clientProgramComposedInferRetainedLimits(selectedBounds), modelLedgerBytes);
        }
        admissionBoundary = 'provider_binding';
        const providerId = moon.clientProgramInferProviderId(execution);
        const providerBinding = durableModel
          ? admitInstalledModelProviderBinding(moon, providerId, physical,
            preparation !== undefined
              ? (id, installation, contract, configuration) => preparation.prepareManagedModelBinding(
                moon, preparedProgram, id, installation, contract, configuration) : undefined) : undefined;
        const selection = Object.freeze({step, graph, computeSuffix, serializationGraph, selectedBounds,
          ...(restoredRun === undefined ? {} : {restoredRun}),
          occurrence, computePrefix: runtimeOptionalField(segments, 0),
          provider: moon.clientProgramAdmittedModelProvider(admittedProvider, execution),
          egressAdmission, egressFailure, account, observeAccount, providerBinding,
          currentProvider: () => modelProviders.get(providerId) === physical,
          assertTrustedRuntime: physical.assertTrustedRuntime,
          assertNewTrustedRuntime() {
            physical.assertNewTrustedRuntime?.();
            if (modelRuntimeStartupView !== undefined) {
              requireInferTrustedStartupView(modelRuntimeView, runtimeOriginals());
            }
          },
          bindTrustedRuntimeScope(scope, compiled, definition, graph) {
            physical.assertTrustedRuntime?.();
            if (modelRuntimeView === undefined || modelRuntimeScopes.has(scope) ||
                typeof control.checkedClientInferOriginalReadScopeLive !== 'function' ||
                !control.checkedClientInferOriginalReadScopeLive(compiled, definition, graph, scope)) {
              throw clientOperationError('InferTrustedRuntimeScopeUnavailable');
            }
            // The caller records the actual issuer's Scope in its existing
            // cleanup custody BEFORE this fallible private association.
            const originals = {...runtimeOriginals(), installation: scope,
              transport: physical.provider};
            const view = issueInferTrustedRuntimeView(originals);
            if (modelRuntimeStartupView !== undefined) {
              borrowInferTrustedStartupView(modelRuntimeView, view, runtimeOriginals(), originals);
            }
            modelRuntimeScopes.set(scope, {view, compiled, definition, graph, physical});
            return view;
          },
          assertTrustedRuntimeScope(scope, view, compiled, definition, graph) {
            const borrowed = modelRuntimeScopes.get(scope);
            if (borrowed === undefined || borrowed.view !== view || borrowed.compiled !== compiled ||
                borrowed.definition !== definition || borrowed.graph !== graph ||
                borrowed.physical !== physical) {
              throw clientOperationError('InferTrustedRuntimeScopeUnavailable');
            }
            // Graceful Host closing forbids NEW Scopes, not this original
            // live/parked Run's existing borrow. Authority stays in Core.
            physical.assertTrustedRuntime();
            checkInferTrustedRuntimeView(view, {...runtimeOriginals(),
              installation: scope, transport: physical.provider});
            if (modelRuntimeStartupView !== undefined) {
              requireInferTrustedStartupView(view, {...runtimeOriginals(),
                installation: scope, transport: physical.provider});
            }
            if (!control.checkedClientInferOriginalReadScopeLive(compiled, definition, graph, scope)) {
              throw clientOperationError('InferTrustedRuntimeScopeUnavailable');
            }
          },
          finishTrustedRuntimeScope(scope, view, compiled, definition, graph) {
            const borrowed = modelRuntimeScopes.get(scope);
            if (borrowed === undefined || borrowed.view !== view || borrowed.compiled !== compiled ||
                borrowed.definition !== definition || borrowed.graph !== graph ||
                borrowed.physical !== physical) {
              throw clientOperationError('InferTrustedRuntimeScopeUnavailable');
            }
            // Ask the SAME Common cleanup Owner directly. Non-live/current
            // refusal is not final cleanup, and a caller Bool supplies no fact.
            // This installed caller reaches here only after its actual children
            // retire; Common's live-child census also prevents early release.
            const finished = control.finishCheckedClientInferOriginalReadScope(
              compiled, definition, graph, scope, true);
            if (finished !== true) return false;
            if (modelRuntimeStartupView !== undefined) forgetInferTrustedStartupView(view, host, host);
            forgetInferTrustedRuntimeView(view, host, host);
            modelRuntimeScopes.delete(scope);
            return true;
          },
          physicalPreflight: physical.physicalPreflight === undefined ? undefined
            : (request, ioNotification, rawCaptureBinder) => {
              physical.assertTrustedRuntime?.();
              // Never throw a post-factory current refusal before Common has
              // registered this returned cursor's cleanup responsibility.
              return physical.physicalPreflight(request, ioNotification,
                rawCaptureBinder, admittedProvider);
            },
          originalReadInstallation,
          // Private actual installation predicate for the closed role supplier.
          // Neither registration DATA nor an eager flag can provide it.
          requireEagerSdkStartup: physical.requireEagerSdkStartup,
          // DATA from the actual opened Store already bound by this Host,
          // never a dimension packet from the Provider or public request.
          // The normal supplier/current resource admission is still separate.
          originalStorageDimensions: originalReadInstallation === undefined
            ? undefined : selectedInferTrustedStoreDimensions(modelRuntimeView,
              runtimeOriginals(), store, publicationStoreModule),
          rawCaptureSelection: physical.rawCaptureSelection,
          entryPersistence: physical.entryPersistence,
          reconcileResponse: physical.reconcileResponse,
          quantityCapacity: physical.quantityCapacity});
        if (retain) inferSelections.set(preparedProgram, selection);
        return selection;
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: `model_admission.${admissionBoundary}`,
          code: cause.code, cause: cause.cause ?? cause});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
    }
  };
  // Preadmission and submission revisit the same Prepared through different
  // packet wrappers. Retain its original Request identity, not an equivalent
  // reconstruction that the live Run's exact-original fence must refuse.
  // Weak ownership neither keeps the Prepared alive nor grants another Run.
  const sourceFreeRequestIdentities = new WeakMap();
  const originalSourceFreeRequest = (preparedProgram, requestId, effectful = false) => {
    let original = sourceFreeRequestIdentities.get(preparedProgram);
    if (original === undefined) {
      const requested = (effectful ? moon.clientProgramEffectRequestIdentity : moon.clientProgramRequestIdentity)(preparedProgram,
        authorityScopeCid, requestId, moon.clientProgramSourceFreeInputIntentCid());
      if (requested === undefined) throw clientOperationError('ClientProgramNeedsInputs');
      original = Object.freeze({requestId, requested});
      sourceFreeRequestIdentities.set(preparedProgram, original);
    } else if (original.requestId !== requestId) {
      throw clientOperationError('ForeignInstalledComputeRun');
    }
    return original.requested;
  };
  const requestOf = ({preparedProgram, requestId}, retainWholeSourceRefusal) => {
    prepareSubmit.assertOwned(preparedProgram);
    if (prepareSubmit.kindOf(preparedProgram) === 'effectful') {
      const count = moon.clientProgramEffectAcquisitionCount(preparedProgram);
      const acquired = count > 0;
      const requested = originalSourceFreeRequest(preparedProgram, requestId, true);
      if (count > 0) {
        if (sourceProfile === undefined) throw clientOperationError('ClientProgramNeedsInputs');
        try {
          selectAcquiredEffectSources({moon, preparedEffect: preparedProgram,
            requestIdentity: requested, sourceProfile, registry, values, fragment, ordered});
        } catch (cause) {
          throw clientOperationError('ClientProgramUnsupported', cause);
        }
      }
      const occurrence = moon.clientProgramEffectInferOccurrence(preparedProgram);
      if (occurrence !== undefined) prepareInferSelection(preparedProgram, occurrence);
      const resultNames = [];
      for (let index = 0;
        index < moon.clientProgramEffectResultCount(preparedProgram);
        index++) {
        const name = moon.clientProgramEffectResultName(preparedProgram,
          index);
        if (name === undefined) {
          throw new Error('ClientProgramResultMissing');
        }
        resultNames.push(name);
      }
      return {requested, resultNames, acquired, acquisitionCount: count, effectful: true};
    }
    const acquisitionCount = moon.clientProgramAcquisitionCount(preparedProgram);
    // Reuse the actual checked selection retained before Content admission.
    // Selecting again constructs another handle, not the child original bound
    // into this Run's managed preparation.
    const keyedAcquisition = earlyContentPlans.get(preparedProgram)?.keyedAcquisition ??
      (typeof moon.clientProgramSelectSingleKeyedAcquisition === 'function'
        ? checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) : undefined);
    const acquired = acquisitionCount > 0;
    let modelCoordinates;
    if (acquired) {
      if (sourceProfile === undefined) throw clientOperationError('ClientProgramNeedsInputs');
      if (acquisitionCount > 2) {
        throw clientOperationError('ClientProgramUnsupported');
      }
      const requested = originalSourceFreeRequest(preparedProgram, requestId);
      modelCoordinates = preparation?.managedModelSourceCoordinates(moon, preparedProgram);
      if (modelCoordinates !== undefined && modelCoordinates.length !== acquisitionCount) {
        throw clientOperationError('InstalledSourcePreparationMismatch');
      }
      // Every occurrence is selected by its checked requirement before any I/O.
      for (let task = 0; task < acquisitionCount; task++) {
        let unsupportedWholeSource;
        try {
          const coordinates = keyedAcquisition === undefined ? undefined
            : moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
          const stage = modelCoordinates?.[task][0] ?? runtimeOptionalField(coordinates, 0) ?? task;
          const input = modelCoordinates?.[task][1] ?? runtimeOptionalField(coordinates, 1) ?? 0;
          const selectDomain = preparation?.selectManagedDomainSourceInput;
          if (preparation !== undefined && typeof selectDomain !== 'function') {
            throw clientOperationError('NodeManagedRunRuntimeUnavailable');
          }
          const domainSelection = preparation === undefined ? undefined
            : Reflect.apply(selectDomain, preparation, [moon, preparedProgram, requested, stage, input]);
          const selected = domainSelection === undefined
            ? checked(moon.clientProgramSelectInstalledSourceInput(preparedProgram, requested, stage, input))
            : domainSelection;
          const kind = moon.clientProgramSelectedSourceInputKind(selected);
          if (kind !== 'query' && kind !== 'whole-input' ||
              kind === 'whole-input' && (acquisitionCount !== 1 || keyedAcquisition !== undefined)) {
            throw new Error('InstalledSourcePreparationMismatch');
          }
          const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
          if (kind === 'query' && domainSelection === undefined) {
            const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
              preparedProgram, stage, input, registry, values, fragment, ordered));
            if (moon.clientProgramQueryRequirementSourceRef(requirement) !== sourceRef) {
              throw new Error('InstalledSourcePreparationMismatch');
            }
          }
          const adapter = installedSourceFor(sourceProfile, sourceRef);
          if (kind === 'whole-input' && typeof adapter.managedWholeSourceCapacity !== 'function') {
            const cause = new Error('InstalledSourceCapacityUnavailable');
            unsupportedWholeSource = {cause, adapter, sourceRef};
            throw cause;
          }
          if (acquisitionCount === 2 &&
              !installedSourceReadBindings(adapter).includes(sourceRef)) {
            throw new Error('InstalledMultiSourceUnsupported');
          }
        } catch (cause) {
          // Report only the boundary and typed discriminants: acquisition
          // bodies and authenticated source materials are not diagnostics.
          diagnostic('acquisition_preparation_rejected', {boundary: 'query_requirement',
            task, code: cause.code, issueTag: runtimeTag(cause.cause),
            requirementTag: runtimeTag(runtimeOptionalField(cause.cause, 0))});
          const error = clientOperationError('ClientProgramUnsupported', cause);
          // Only this original static implementation selection can issue the
          // same-candidate refusal. No reader, Model/Content or Run has begun.
          if (unsupportedWholeSource?.cause === cause &&
              !inferSelections.has(preparedProgram) &&
              moon.clientProgramSerializationOccurrences(preparedProgram).length === 0) {
            retainWholeSourceRefusal?.(error, requested,
              unsupportedWholeSource.adapter, unsupportedWholeSource.sourceRef);
          }
          throw error;
        }
      }
      if (keyedAcquisition !== undefined) {
        const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
        if (typeof installedSourceFor(sourceProfile, facts[0]).prepareKeyed !== 'function') {
          throw clientOperationError('ClientProgramUnsupported');
        }
      }
    }
    // Static ModelTask admission cannot authorize a model call. Until the
    // installed dependency/dispatch route is present, refuse before admitting
    // a Run rather than sending this acquisition into a Values fallback.
    // Bind this SAME nominal Request before the immutable Model inventory can
    // refuse. The failed path must not issue a replacement identity later.
    const requested = originalSourceFreeRequest(preparedProgram, requestId);
    const inventory = moon.clientProgramComposedInferOccurrences(preparedProgram);
    const occurrences = runtimeIsOkRequired(inventory) ? runtimeField(inventory, 0) : [];
    if (occurrences.length > 1) {
      // Funded preparation already retained this SAME Program's ordered
      // components. Submit consumes them after adoption without re-reading
      // Model contracts or constructing another Graph under that old borrow.
      if (!inferSelections.has(preparedProgram)) {
        const components = Object.freeze(occurrences.map(occurrence =>
          prepareInferSelection(preparedProgram, occurrence, false)));
        // Retain only one SAME installed declaration. Equal amounts from
        // different registrations do not establish one original quantity scope.
        let quantityCapacity = components[0].quantityCapacity;
        for (const component of components) {
          if (component.quantityCapacity !== quantityCapacity) {
            quantityCapacity = undefined;
            break;
          }
        }
        const restoredRun = prepareSubmit.originalInferRun(preparedProgram);
        const graph = restoredRun?.graph ?? Object.freeze(components.map(component => component.graph));
        if (!Array.isArray(graph) || graph.length !== components.length ||
            components.some((component, index) => component.graph !== graph[index] ||
              component.restoredRun !== restoredRun)) {
          throw new TypeError('ForeignInstalledInferOriginalGraph');
        }
        inferSelections.set(preparedProgram, Object.freeze({components, quantityCapacity, sourceCoordinates: modelCoordinates,
          ...(restoredRun === undefined ? {} : {restoredRun}), graph,
          egressFailure: components.find(component => component.egressFailure !== undefined)?.egressFailure}));
      }
    // The single occurrence can still belong to a multi-task/multi-Source
    // graph. Keep its compiler-owned identity instead of falling back to the
    // legacy single-task step lookup, which would miss that Model boundary.
    } else prepareInferSelection(preparedProgram, occurrences[0]);
    const resultNames = [];
    for (let index = 0;
      index < moon.clientProgramResultCount(preparedProgram); index++) {
      const name = moon.clientProgramResultName(preparedProgram, index);
      if (name === undefined) throw new Error('ClientProgramResultMissing');
      resultNames.push(name);
    }
    return {requested, resultNames, acquired, acquisitionCount, keyedAcquisition, effectful: false};
  };
  const modelSourceOccurrence = (prepared, index) => {
    const coordinates = inferSelections.get(prepared)?.sourceCoordinates?.[index];
    return coordinates === undefined ? undefined
      : Object.freeze({stage: coordinates[0], input: coordinates[1], task: coordinates[2]});
  };
  const prepareAcquisition = async (preparedProgram, sourceAccess, occurrence, preparedSource) => {
    occurrence ??= modelSourceOccurrence(preparedProgram, 0) ?? {stage: 0, input: 0, task: 0};
    const requestIdentity = sourceFreeRequestIdentities.get(preparedProgram)?.requested;
    if (requestIdentity === undefined) throw clientOperationError('ClientProgramNeedsInputs');
    const selected = checked(moon.clientProgramSelectInstalledSourceInput(
      preparedProgram, requestIdentity, occurrence.stage, occurrence.input));
    const kind = moon.clientProgramSelectedSourceInputKind(selected);
    if (kind !== 'query' && kind !== 'whole-input') {
      throw clientOperationError('InstalledSourcePreparationMismatch');
    }
    const adapter = installedSourceFor(sourceProfile,
      moon.clientProgramSelectedSourceInputRef(selected));
    try {
      const prepared = await adapter.prepare({preparedProgram, registry, values, fragment, ordered,
        sourceAccess: sourceAccess ?? adapter.sourceAccess, occurrence, requestIdentity,
        ...(preparedSource === undefined ? {} : {preparedSource}),
        requireImmediateReadAuthorization: checkpoints === undefined});
      if (prepared.selection !== undefined) diagnostic('acquisition_selection',
        {task: occurrence.task, selection: prepared.selection});
      return prepared;
    } catch (cause) {
      if (cause instanceof ExecutionAuthorizationError) {
        throw clientOperationError(cause.runtimeCode ?? 'ACTQL_E_DELEGATION_UNAVAILABLE', cause);
      }
      if (cause?.selection !== undefined) {
        diagnostic('acquisition_selection', {task: occurrence.task, selection: cause.selection});
        throw clientOperationError(cause.selection.status === 'deferred'
          ? 'ClientProgramRejected' : 'ClientProgramUnsupported', cause);
      }
      throw cause;
    }
  };
  const prepareAcquisitions = async preparedProgram => {
    const result = [];
    for (let task = 0; task < moon.clientProgramAcquisitionCount(preparedProgram); task++) {
      const occurrence = modelSourceOccurrence(preparedProgram, task) ?? Object.freeze({stage: task, input: 0, task});
      const prepared = await prepareAcquisition(preparedProgram, undefined, occurrence);
      // A held read has no selection before approval. Once authorized, keep
      // either typed acquisition owner; shared ledger admission happens before
      // dispatch and the provider rechecks this exact occurrence's read gate.
      if (prepared.selection !== undefined) {
        try { capturedDuckDBConfiguration(prepared); }
        catch (cause) { throw clientOperationError('ClientProgramUnsupported', cause); }
      }
      const adapter = installedSourceFor(sourceProfile, prepared.checkedSource.sourceRef);
      result.push(Object.freeze({occurrence, prepared, adapter, sourceAccess: adapter.sourceAccess}));
    }
    return Object.freeze(result);
  };
  const acquisitionDescriptor = prepared => ({checkedSource: prepared.checkedSource,
    readTuple: prepared.readTuple, physicalBinding: prepared.physicalBinding});
  const sourceDescriptors = ordinarySourceDescriptors;
  const installationBinding = adapter => ({connectorId: adapter.connectorBindings[0].connectorId,
    connectorRegistration: adapter.connectorRegistration, connectorRevision: adapter.connectorRevision,
    bindingCid: adapter.connectorBindings[0].bindingCid});
  const keyedDescriptors = (preparedSource, keyedSource) => [
    {...keyedSource.directOccurrence, ...acquisitionDescriptor(preparedSource),
      installationBinding: installationBinding(keyedSource.directAdapter)},
    {...keyedSource.occurrence, ...acquisitionDescriptor(keyedSource.prepared),
      installationBinding: installationBinding(keyedSource.adapter)},
  ];
  const prepareKeyedSources = async (preparedProgram, keyedAcquisition, requestIdentity) => {
    const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
    if (coordinates === undefined) throw clientOperationError('ClientProgramUnsupported');
    const directOccurrence = Object.freeze({stage: runtimeField(coordinates, 0), input: runtimeField(coordinates, 1), task: runtimeField(coordinates, 2)});
    const preparedSource = await prepareAcquisition(preparedProgram, undefined, directOccurrence);
    const directAdapter = installedSourceFor(sourceProfile, preparedSource.checkedSource.sourceRef);
    const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
    const adapter = installedSourceFor(sourceProfile, facts[0]);
    const selected = await adapter.prepareKeyed({preparedProgram, keyedAcquisition, requestIdentity});
    return {preparedSource, keyedSource: Object.freeze({...selected, adapter,
      sourceAccess: adapter.sourceAccess, acquisition: keyedAcquisition, requestIdentity,
      directOccurrence, directAdapter})};
  };
  const sourceInventory = (sources, preparedSource, keyedSource) => keyedSource !== undefined
    ? canonicalValueJson({version: 'actql-client-keyed-source-inventory/0.1', environmentCid: evidenceCid,
      acquisitions: keyedDescriptors(preparedSource, keyedSource)}, {dataKeys: true})
    : sources?.length === 2 ? (() => {
      const acquisitions = sourceDescriptors(sources);
      const bound = acquisitions.every(item => item.installationBinding !== undefined);
      const value = {version: bound ? BOUND_SOURCE_INVENTORY
        : 'actql-client-source-inventory/0.1', environmentCid: evidenceCid, acquisitions};
      return bound ? canonicalValueJson(value, {dataKeys: true}) : canonicalJson(value);
    })() : undefined;
  const captureSubmission = (submission, resultNames, preparedSource, preparedSources, keyedSource) => ({
    version: keyedSource !== undefined ? 'actql-remote-keyed-source-submission/0.1'
      : preparedSources?.length === 2
      ? (sourceDescriptors(preparedSources).every(item => item.installationBinding !== undefined)
        ? BOUND_SOURCE_SUBMISSION : 'actql-remote-multi-source-submission/0.1')
      : 'actql-remote-captured-submission/0.1',
    requestId: submission.requestId, principalId: submission.principalId,
    connection: submission.connection, kind: submission.kind, input: submission.input,
    parameters: submission.parameters, resultNames,
    ...capturedUpdateOriginal(submission),
    ...(submission.submission === undefined ? {} : {submission: submission.submission}),
    ...(keyedSource !== undefined ? {acquisitions: keyedDescriptors(preparedSource, keyedSource)}
      : preparedSources?.length === 2 ? {acquisitions: sourceDescriptors(preparedSources)}
      : preparedSource === undefined ? {} : {acquisition: acquisitionDescriptor(preparedSource)}),
  });
  const planFor = ({preparedProgram, requestId},
    retainedDefinitionWire, requestIdentity, keyedOriginal, constructingModel) => {
    prepareSubmit.assertOwned(preparedProgram);
    const earlyMock = earlyMockInferPlans.get(preparedProgram);
    if (constructingModel !== undefined && (earlyMock !== constructingModel ||
        !constructingModel.selecting || constructingModel.plan !== undefined)) {
      throw clientOperationError('ForeignInstalledModelPreparation');
    }
    if (earlyMock !== undefined && earlyMock !== constructingModel) {
      if (earlyMock.plan === undefined) throw clientOperationError('InstalledModelPlanSelectionPending');
      if (earlyMock.requestId !== requestId || retainedDefinitionWire !== undefined &&
          retainedDefinitionWire !== earlyMock.plan.runDefinition.wire) {
        throw clientOperationError('ForeignInstalledMockModelRun');
      }
      return earlyMock.plan;
    }
    const earlyContent = earlyContentPlans.get(preparedProgram);
    if (earlyContent !== undefined) {
      if (earlyContent.requestId !== requestId || retainedDefinitionWire !== undefined &&
          retainedDefinitionWire !== earlyContent.plan.runDefinition.wire) {
        throw clientOperationError('ForeignInstalledContentRun');
      }
      return earlyContent.plan;
    }
    const restored = prepareSubmit.originalInferRun(preparedProgram);
    if (restored !== undefined) {
      return restoreInferTaskRunAdmission({control, preparedProgram, restored, requestIdentity});
    }
    const common = {moon, control, preparedProgram,
      publicationOriginal: preparation?.managedComputePublicationOriginal?.(moon, preparedProgram),
      compilationOriginal: preparation?.managedComputeCompilationOriginal?.(moon, preparedProgram),
      publicationPreparation: preparation?.managedComputePublicationPreparation?.(moon, preparedProgram),
      invocationOriginal: preparation?.managedComputeInvocationOriginal?.(moon, preparedProgram),
      authorityScopeCid, namespaceId, requestId, storeAuthorityCid, now,
      ...(requestIdentity === undefined ? {} : {requestIdentity}),
      ...(retainedDefinitionWire === undefined ? {} :
        {retainedDefinitionWire})};
    const infer = inferSelections.get(preparedProgram);
    if (infer !== undefined) {
      // The retained occurrence uses the composed compiler even for one Task.
      // Keep its same component as the Run/Scope original; the bounded array
      // selects the existing compiler, not a replacement graph or admission.
      const compilationGraphs = infer.occurrence === undefined || Array.isArray(infer.graph)
        ? infer.graph : [infer.graph];
      const compilationOriginal = preparation?.prepareManagedModelCompilation?.(
        moon, preparedProgram, infer.graph);
      try {return Object.freeze({...inferTaskRunAdmission({...common,
        compilationOriginal, inferGraph: compilationGraphs}),
        inferGraph: infer.graph,
        ...(infer.serializationGraph === undefined ? {} : {serializationGraph: infer.serializationGraph})});}
      catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'task_compilation',
          code: cause.code, cause: cause.cause ?? cause});
        throw cause;
      }
    }
    if (moon.clientProgramSerializationOccurrences(preparedProgram).length !== 0) {
      try {
        // Select the component once. Its original Request compiler and the
        // Task issuer below must consume the SAME checked graph.
        const serializationGraph = selectInstalledSerializationGraph({...common,
          resultDataPolicy: installedResultDataPolicy,
          prepareSerializationGraph: preparation === undefined ? undefined :
            (options, intermediate) => preparation.prepareManagedContentGraph(
              moon, preparedProgram, options, intermediate)});
        const compilationOriginal = moon.clientProgramAcquisitionCount(preparedProgram) === 0
          ? preparation?.prepareManagedContentCompilation?.(moon, preparedProgram, serializationGraph)
          : preparation === undefined ? undefined : runContent.prepareManagedKeyedCompilation({
            preparedProgram, request: requestIdentity, serializationGraph, keyedAcquisition: keyedOriginal});
        return serializationTaskRunAdmission({...common,
          serializationGraph, compilationOriginal, resultDataPolicy: installedResultDataPolicy});
      } catch (cause) {
        diagnostic('content_preparation_rejected', {boundary: 'task_compilation',
          code: cause.code, cause: cause.cause ?? cause});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
    }
    return sourceProfile !== undefined &&
      moon.clientProgramAcquisitionCount(preparedProgram) > 0
      ? acquiredTaskRunAdmission(common)
      : moon.clientProgramRequiresTaskCompilation(preparedProgram)
        ? sourceFreeTaskPlan(common)
        : sourceFreeValuesPlan(common);
  };
  // Admit (or look up) the request's Run Definition: the durable Run.
  const admitDefinition = async (submission, requested, resultNames,
    held) => {
    const accepted = await journal.admitOrLookupDefinition(requested, {
      namespaceId, lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
      submission: submission.submission,
      resultNames, sourceInventory: sourceInventory(held.preparedSources, held.preparedSource, held.keyedSource),
      issueDefinition: () => {
        held.plan = planFor(submission, undefined, requested);
        if (held.plan.kind === 'infer') {
          // Retain the complete original compiler inventory at first admission.
          // Absence never authorizes a cold reconstruction or a new Source read.
          const originalInferRun = held.plan.serializationGraph !== undefined ? undefined : (() => {
              const inputs = prepareSubmit.originalInputs(submission.preparedProgram);
              return control.captureOriginalClientInferRun(held.plan.compiled,
                submission.preparedProgram, held.plan.runDefinition, requested,
                inputs.environment, inputs.parameters);
            })();
          return {
            runDefinition: held.plan.runDefinition,
            ...(originalInferRun === undefined ? {} : {originalInferRun}),
            runAdmissionEvidence: {
              prepared: held.plan.preparedEvidence.wire,
              authorization: held.plan.authorization.wire,
              modelOriginalRunWire: originalModelRunWire(held.plan.compiled,
                held.plan.runDefinition),
              ...(held.preparedSources?.length === 2 || held.keyedSource !== undefined ? {
                sourceInventory: sourceInventory(held.preparedSources, held.preparedSource, held.keyedSource)} : {}),
            }};
        }
        if (held.plan.kind === 'serialization') return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: {prepared: held.plan.preparedEvidence.wire,
            authorization: held.plan.authorization.wire,
            ...(held.preparedSources?.length === 2 || held.keyedSource !== undefined ? {
              sourceInventory: sourceInventory(held.preparedSources, held.preparedSource, held.keyedSource),
            } : {})}};
        if (held.preparedSources?.length === 2 || held.keyedSource !== undefined) return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: {prepared: held.plan.preparedEvidence.wire,
            authorization: held.plan.authorization.wire,
            sourceInventory: sourceInventory(held.preparedSources, held.preparedSource, held.keyedSource)},
          originalPlan: sourceFreePlanOriginal(held.plan)};
        const valuesEvidence = sourceFreeValuesAdmissionEvidence(held.plan);
        if (valuesEvidence !== undefined) return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: valuesEvidence,
          originalPlan: sourceFreePlanOriginal(held.plan)};
        return held.plan.runDefinition;
      },
    }, moon, control).catch(cause => {
      if (cause?.code === 'ClientRequestSourceInventoryMismatch') {
        // Caller input identity is unchanged. This Host cannot start the
        // retained Run against a different physical acquisition inventory.
        throw clientOperationError('ClientRunStartDenied', cause);
      }
      throw cause;
    });
    return accepted;
  };
  // Composition installs one owner for dispatch, cancellation, stop, and
  // cleanup. Checkpoint and HTTP paths share this owner.
  const observed = diagnostic;
  const runContent = installNodeContentRun({moon, core: runtimeCore(moon),
    registry, values, fragment, ordered, namespaceId, authorityScopeCid,
    storeAuthorityCid, ownerPrincipal: principalId, now,
    authorize: actual => hostConnection({principalId: actual, connection: {mode, owner: mode}}),
    preparedRunRequired: true,
    assertRunCurrent: preparation.assertContentRunCurrent.bind(preparation),
    retainPreparation: (prepared, original) => preparation.retainManagedContentPreparation(moon, prepared, original),
    prepareModelManagedRun: (prepared, request, model) => preparation.prepareManagedModelRun(moon, prepared, request, model),
    prepareSerializationManagedRun: (prepared, request, plan, limits, workspace, original) => preparation.prepareManagedSerializationRun(
      moon, prepared, request, plan, limits, workspace, original),
    prepareKeyedManagedRun: (prepared, request, graph, recipe, original) => {
      if (typeof sourceProfile?.prepareManagedContentRun !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      return sourceProfile.prepareManagedContentRun(prepared, request, recipe, graph, original);
    },
    borrowKeyedManagedLedger: (prepared, request, recipe,
      direct, keyed, capacity) => {
      if (typeof sourceProfile?.managedContentLedger !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      return sourceProfile.managedContentLedger(prepared, request, recipe, direct, keyed, capacity);
    },
    faultInjection: authorization?.faultInjection});
  function prepareInstalledRequestModelRun(submission, requested, selection) {
    const prepared = submission.preparedProgram;
    const acquisitionCount = moon.clientProgramAcquisitionCount(prepared);
    const group = selection.components !== undefined;
    if (preparation === undefined || typeof preparation.prepareManagedModelRun !== 'function' ||
        inferSelections.get(prepared) !== selection || selection.localMock ||
        !group && selection.originalReadInstallation === undefined &&
          (acquisitionCount > 1 || selection.serializationGraph !== undefined) ||
        (!group && selection.occurrence === undefined) ||
        (group && (!Array.isArray(selection.components) || !Object.isFrozen(selection.components) ||
          selection.components.length < 2 || !Array.isArray(selection.graph) ||
          selection.graph.length !== selection.components.length ||
          selection.components.some((member, index) => member.occurrence === undefined || member.graph !== selection.graph[index]))) ||
        acquisitionCount > (group ? 2 : 1)) {
      throw clientOperationError('HostResultPublicationPurposeUnavailable');
    }
    let early = earlyMockInferPlans.get(prepared);
    if (early !== undefined) {
      if (Object.hasOwn(early, 'failure')) throw early.failure;
      if (early.selecting) throw clientOperationError('InstalledModelPlanSelectionPending');
      if (early.requestId !== submission.requestId || early.requested !== requested ||
          early.model?.graph !== selection.graph || early.model?.originalReadInstallation !== selection.originalReadInstallation ||
          early.model?.closed || early.managed === undefined) throw clientOperationError('ForeignInstalledModelPreparation');
      if (preparation.prepareManagedModelRun(moon, prepared, requested, early.model) !== early.managed) {
        throw clientOperationError('ForeignInstalledModelPreparation');
      }
      return early.model;
    }
    early = {prepared, requestId: submission.requestId, requested, plan: undefined, model: undefined,
      managed: undefined, selecting: true, aliasesReleased: false};
    const model = {prepared, control, compiled: undefined, runDefinition: undefined,
      graph: selection.graph, occurrence: selection.occurrence, serializationGraph: selection.serializationGraph,
      originalReadInstallation: selection.originalReadInstallation, selection, component: undefined,
      scope: undefined, read: undefined,
      publicationCapacity: () => preparation.modelPublicationCapacity(prepared),
      releaseAliases() {
        if (this !== model) throw clientOperationError('ForeignInstalledModelPreparation');
        if (early.aliasesReleased) return;
        if (earlyMockInferPlans.get(early.prepared) !== early || early.model !== model ||
            model.scope !== undefined && model.scopeFinished !== true || model.read !== undefined) {
          throw clientOperationError('InstalledModelCleanupPending');
        }
        if (group && (model.components.some(member => member.read !== undefined ||
            member.scope !== undefined && member.scopeFinished !== true) ||
            model.scopes !== undefined && model.scopeFinished !== true)) {
          throw clientOperationError('InstalledModelCleanupPending');
        }
        if (group) for (const member of model.components) {
          for (const key of Object.keys(member)) member[key] = undefined;
          member.closed = true;
        }
        // Called only after checked same-Run retirement, or original failed
        // Request cleanup. No physical child or Scope is released by this cut.
        for (const key of Object.keys(model)) model[key] = undefined;
        model.closed = true;
        early.prepared = early.requestId = early.requested = early.plan = early.managed = early.failure = undefined;
        early.aliasesReleased = true;
      }};
    if (group) {
      model.scopes = undefined;
      model.components = Object.freeze(selection.components.map(member => ({prepared, control,
        compiled: undefined, runDefinition: undefined, graph: member.graph, occurrence: member.occurrence,
        serializationGraph: member.serializationGraph, originalReadInstallation: member.originalReadInstallation,
        selection: member, group: model, scope: undefined, read: undefined, component: undefined,
        publicationCapacity: model.publicationCapacity})));
    }
    early.model = model;
    earlyMockInferPlans.set(prepared, early); // Retain before compiler/Definition/Plan can fail.
    try {
      early.plan = planFor(submission, undefined, requested, undefined, early);
      model.compiled = early.plan.compiled; model.runDefinition = early.plan.runDefinition;
      model.queryTimePreparation = early.plan.queryTimePreparation;
      if (group) for (const member of model.components) {
        member.compiled = model.compiled; member.runDefinition = model.runDefinition;
      }
      if (model.serializationGraph !== undefined) {
        runContent.prepareModelRun({preparedProgram: prepared, plan: early.plan, request: requested, model});
        early.managed = model.contentPreparation?.managed;
      } else early.managed = preparation.prepareManagedModelRun(moon, prepared, requested, model);
      if (early.managed === undefined) throw clientOperationError('NodeManagedRunAdmissionUnavailable');
      model.managed = early.managed;
      if (group) for (const member of model.components) member.managed = early.managed;
      return model;
    } catch (cause) {early.failure = cause; throw cause;}
    finally {early.selecting = false;}
  }
  const runInfer = installNodeInferRun({moon, core: runtimeCore(moon), fragment, ordered,
    registry, values, selections: inferSelections, namespaceId, authorityScopeCid,
    storeAuthorityCid, now, modelController, inferEvidence: evidenceConfiguration,
    checkpoints, prepareAcquisition, runContent,
    prepareOriginalModelRun(prepared, plan, selection) {
      const early = earlyMockInferPlans.get(prepared);
      if (early === undefined || early.plan !== plan || early.model === undefined) {
        throw clientOperationError('InstalledModelOperationalAdmissionUnavailable');
      }
      return prepareInstalledRequestModelRun({preparedProgram: prepared, requestId: early.requestId},
        early.requested, selection);
    },
    prepareOriginalMockRun(prepared, plan) {
      const early = earlyMockInferPlans.get(prepared);
      if (early === undefined || early.plan !== plan ||
          typeof sourceProfile?.modelPreparation !== 'function') {
        throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
      }
      return sourceProfile.modelPreparation(prepared, plan);
    },
    prepareKeyedRecovery: async ({preparedProgram, plan, submission}) => {
      // Reuse the declared pre-acquisition Run envelope; reopening input does
      // not list files, obtain keyed rows, fabricate Source completion or create
      // a separate restoration Ledger. The original Model root and generated
      // Content prefix each derive their own checked finite envelope.
      const acquisition = checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram));
      const requestIdentity = moon.clientProgramRequestIdentity(preparedProgram,
        authorityScopeCid, submission.requestId, moon.clientProgramSourceFreeInputIntentCid());
      if (acquisition === undefined || requestIdentity === undefined) {
        throw new Error('InstalledCapturedContentSelectionUnavailable');
      }
      const {preparedSource, keyedSource} = await prepareKeyedSources(preparedProgram, acquisition, requestIdentity);
      const capacity = keyedSource.adapter.keyedLedgerCapacity(acquisition);
      const prepareLedger = plan.serializationGraph === undefined ? runInfer.prepareKeyedLedger
        : runContent.prepareKeyedLedger;
      const ledger = prepareLedger({preparedProgram, plan,
        direct: keyedSource.directAdapter.ledgerCapacity(preparedSource), acquisition,
        capacity, capturedContent: true});
      return {keyedSource, ledger};
    },
    sourceAccessFor: prepared => installedSourceFor(sourceProfile, prepared.checkedSource.sourceRef).sourceAccess,
    sourceAdapterFor: prepared => installedSourceFor(sourceProfile, prepared.checkedSource.sourceRef),
    faultInjection: authorization?.faultInjection,
    computeConfigurations: {local: localSnapshotConfiguration}});
  dispatchOwner = installNodeClientDispatchOwner({moon, control,
    journal, store, checkpoints, startRun, hostConnection, beforeDispatch,
    observed, prepareAcquisition, planFor, sourceProfile, registry, values,
    faultInjection: authorization?.faultInjection,
    fragment, ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
    runInfer, runContent, retainedRelationOutput, observation,
    preparationCustody: localPreparationCustody,
    beforePublication: prepared => preparation.managedComputeReservePublication(moon, prepared),
    managedComputeRequired: true,
    computeConfigurations: {local:localSnapshotConfiguration}});
  const startDispatch = dispatchOwner.start;
  const restoreEffectManagedPreparation = async (ref, signal) => {
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || typeof retained.requestId !== 'string') {
      throw clientOperationError('EffectRecoveryRequestMismatch');
    }
    const owned = journal.lookupOwnedDefinition({namespaceId, authorityScopeCid,
      requestId: retained.requestId, runDefinitionCid: ref.runDefinitionCid}, moon, control);
    if (owned?.runDefinition?.identity !== ref.runDefinitionCid) throw clientOperationError('EffectRecoveryRequestMismatch');
    const selected = preparation.retainedEffectManagedPlan(moon, owned.requestIdentity, owned.runDefinition);
    if (selected !== undefined) return Object.freeze({managedEffect: selected});
    if (owned.runAdmissionEvidence?.updateTargetRunOriginal === undefined &&
        typeof owned.runAdmissionEvidence?.effectOriginalRunWire !== 'string') {
      throw clientOperationError('EffectRecoveryOriginalSelectionUnavailable');
    }
    const originalSubmittedIntent = journal.originalSubmittedIntent(owned.requestIdentity,
      {namespaceId}, moon, control);
    if (originalSubmittedIntent === undefined) throw clientOperationError('EffectRecoveryOriginalSelectionUnavailable');
    originalSubmittedIntent.assertCurrent();
    signal?.throwIfAborted();
    // This is the actual pending restoration call, not a new logical Request
    // or a submitted transport packet. Its original typed identity stays with
    // the independently selected Journal row throughout construction/adoption.
    const request = {requestId: retained.requestId, signal};
    const materialWire = owned.runAdmissionEvidence.updateTargetRunOriginal?.materialsWire ??
      owned.runAdmissionEvidence.effectOriginalRunWire;
    const input = preparation.retainEffectRequestInput(moon, request,
      originalSubmittedIntent.intent, undefined, materialWire);
    let terminal = 'failed';
    try {
      const prepared = await prepareSubmit(request);
      preparation.bindSourceRequest(request, prepared);
      prepareSubmit.assertSubmittedIntent(prepared, originalSubmittedIntent.intent);
      if (prepareSubmit.kindOf(prepared) !== 'effectful') throw clientOperationError('EffectRecoveryOriginalSelectionUnavailable');
      const occurrence = moon.clientProgramEffectInferOccurrence(prepared);
      if (occurrence !== undefined) prepareInferSelection(prepared, occurrence);
      const original = await effectRun.restoreRetainedPreparation({prepared, identity: owned.requestIdentity,
        namespaceId, ref, originalSubmittedIntent});
      const managed = preparation.effectManagedPlanRun(moon, prepared, owned.requestIdentity);
      signal?.throwIfAborted();
      terminal = 'returned';
      return Object.freeze({managedEffect: managed, original});
    } finally {
      try {input.finish(terminal);}
      catch (cause) {if (terminal !== 'failed') throw cause;}
    }
  };
  const recoverEffectCapture = (ref, signal, managed, retainRecoveryResources, boundOriginal) => {
    // An existing live Request already owns this exact compiler. Its saved
    // material admission must bind that original instead of compiling again.
    // A wire-only cold restoration still needs its own funded continuation.
    const originalCompilation = managed?.definitionOriginal?.compilation;
    if (managed !== undefined && originalCompilation === undefined) {
      throw clientOperationError('ForeignInstalledEffectManagedRun');
    }
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || typeof retained.requestId !== 'string') {
      throw new Error('EffectRecoveryRequestMismatch');
    }
    const requestId = retained.requestId;
    return recoverAdmittedEffectRun({requests: journal, store,
      key: {namespaceId, authorityScopeCid, requestId,
        runDefinitionCid: ref.runDefinitionCid}, principalId,
      contractLimits: localContractLimits, signal,
      retainRecoveryResources,
      prepareRecoveryResources: options => {
        if (typeof preparation?.prepareEffectCaptureRecovery !== 'function') {
          throw clientOperationError('EffectRecoveryResourcesUnavailable');
        }
        return preparation.prepareEffectCaptureRecovery(moon, options.requestIdentity,
          options.runDefinition, options.contractLimits, managed,
          options.assertOriginalCurrent, options.retain);
      },
      restoreOriginal: (saved, requestIdentity) => {
        if (boundOriginal !== undefined) {
          // This operation just admitted the full materials while constructing
          // this SAME managed Plan. Keep its original outputs, not a second
          // parser/codec/compiler pass. Fresh Journal/current fences remain.
          if (managed === undefined || boundOriginal.prepared !== managed.prepared ||
              boundOriginal.compilation !== originalCompilation ||
              boundOriginal.allowed !== managed.definitionOriginal.allowed ||
              boundOriginal.definition !== managed.definitionOriginal.definition ||
              moon.clientRequestRelation(boundOriginal.identity, requestIdentity) !== 1 ||
              boundOriginal.runDefinition.identity !== saved.runDefinition.identity ||
              moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(boundOriginal.allowed)) !== saved.runAdmissionEvidence.prepared ||
              moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(boundOriginal.allowed)) !== saved.runAdmissionEvidence.authorization) {
            throw clientOperationError('EffectRecoveryOriginalSelectionUnavailable');
          }
          boundOriginal.originalSubmittedIntent.assertCurrent();
          return boundOriginal;
        }
        const original = saved.runAdmissionEvidence?.updateTargetRunOriginal;
        let restored = original === undefined ? {} : updateTargetOriginals.restoreRun(
          original, saved.runDefinition, requestIdentity, originalCompilation);
        if (original === undefined && managed?.definitionOriginal !== undefined) {
          // The live Request already owns these admitted materials. Ordinary
          // STORE recovery needs the same allowed compilation too, even when
          // its submitted intent did not request commit-stop signing.
          const current = managed.definitionOriginal;
          if (current.prepared !== managed.prepared || current.compilation !== originalCompilation ||
              current.allowed === undefined || current.definition === undefined ||
              moon.clientRequestRelation(current.identity, requestIdentity) !== 1 ||
              moon.strategyPublicationContractIdentity(current.definition) !== saved.runDefinition.identity ||
              moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(current.allowed)) !==
                saved.runAdmissionEvidence.prepared ||
              moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(current.allowed)) !==
                saved.runAdmissionEvidence.authorization) {
            throw clientOperationError('EffectRecoveryOriginalSelectionUnavailable');
          }
          restored = current;
        }
        const originalSubmittedIntent = journal.originalSubmittedIntent(requestIdentity,
          {namespaceId}, moon, control);
        if (originalSubmittedIntent !== undefined &&
            moon.clientSubmittedIntentRequestsCommitStop(originalSubmittedIntent.intent)) {
          if (restored.materials === undefined) {
            const wire = saved.runAdmissionEvidence?.effectOriginalRunWire;
            if (typeof wire !== 'string' || updateTargetOriginals === undefined) {
              throw new Error('RequestedEffectStopOriginalUnavailable');
            }
            restored = updateTargetOriginals.restoreEffectMaterials(wire,
              saved.runDefinition, requestIdentity, originalCompilation);
          }
          if (moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(restored.allowed)) !==
                saved.runAdmissionEvidence.prepared ||
              moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(restored.allowed)) !==
                saved.runAdmissionEvidence.authorization) {
            throw new Error('EffectRecoveryOriginalSelectionUnavailable');
          }
        }
        originalSubmittedIntent?.assertCurrent();
        return Object.freeze({...restored, originalSubmittedIntent});
      },
      authorizeEvidenceRead: binding => hostConnection({principalId,
        connection: {mode, owner: mode}, ref}) &&
        binding.namespaceId === namespaceId &&
        binding.authorityScopeCid === authorityScopeCid &&
        binding.requestId === requestId &&
        binding.runDefinitionCid === ref.runDefinitionCid &&
        binding.storeAuthorityCid === storeAuthorityCid},
    async () => moon);
  };
  const answerLocalCheckpoint = (summary, decision, signal) => {
    assertProjectRuntime();
    if (mode !== 'local' || mockAccount === undefined ||
        mockAccount.reviewer === undefined || checkpoints === undefined) {
      throw clientOperationError('CheckpointSignerUnavailable');
    }
    preparation.assertResultPublicationCurrent();
    if (localCheckpointAnswer === undefined) {
      localSigningMetadata ??= runtimeCore(moon).localSigningMetadata();
      localCheckpointAnswer = createLocalCheckpointAnswer({moon, checkpoints, mockAccount, store,
        authorityScopeCid, principalId, metadata: localSigningMetadata,
        assertCurrent() {
          assertProjectRuntime(); preparation.assertResultPublicationCurrent();
        },
        async loadRunOriginal(view, signal, consume) {
          if (typeof consume !== 'function') throw clientOperationError('LocalSigningOriginalConflict');
          const ref = {namespaceId, authorityScopeCid, runDefinitionCid: view.runDefinitionCid};
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined || retained.cancellationRequested) {
            throw clientOperationError('LocalSigningOriginalConflict');
          }
          let restored = await restoreEffectManagedPreparation(ref, signal);
          let recovered = await recoverEffectCapture(ref, signal, restored.managedEffect, undefined, restored.original);
          localSigningRecoveries.add(recovered);
          let originalFailure, failed = false;
          try {
            if (recovered.materials === undefined || recovered.originalSubmittedIntent === undefined ||
                control.effectComputationPreviewSemanticCid(recovered.computation.preview) !== view.requiredArtifact.cid) {
              throw clientOperationError('LocalSigningOriginalConflict');
            }
            const current = () => {
              if (recovered === undefined) throw clientOperationError('LocalSigningOriginalConflict');
              assertProjectRuntime(); preparation.assertResultPublicationCurrent();
              recovered.originalSubmittedIntent.assertCurrent();
              recovered.assertUpdateSelectionCurrent?.();
              const next = journal.lookupRunDefinition(ref, moon, control);
              if (next === undefined || next.cancellationRequested || next.revision !== retained.revision ||
                  next.runDefinition.wire !== retained.runDefinition.wire) {
                throw clientOperationError('LocalSigningOriginalConflict');
              }
            };
            current();
            // Consume while SAME original capture/Request backing remains live.
            // Returning metadata and closing here would strand its consumer.
            return await Reflect.apply(consume, undefined, [Object.freeze({materials: recovered.materials,
              requestIdentity: recovered.requestIdentity,
              referenceWire: recovered.originalSubmittedIntent.referenceWire,
              invocation: recovered.computation.invocation, assertCurrent: current})]);
          } catch (cause) {originalFailure = cause; failed = true; throw cause;}
          finally {
            let original = recovered;
            recovered = restored = undefined;
            try {
              const release = releaseLocalSigningRecovery(original);
              original = undefined;
              await release;
            }
            catch (cleanup) {
              if (failed) throw Object.assign(new AggregateError([originalFailure, cleanup],
                'Original signing capture and cleanup failed', {cause: originalFailure}),
              {code: 'LocalSigningCaptureCleanupPending', cleanupPending: true});
              throw cleanup;
            }
          }
        }});
    }
    return localCheckpointAnswer(summary, decision, signal);
  };
  const openEffectTargetReads = async (facts, {signal, resume, activeResume, journalPort,
    allowDefer = true,
    observeCancellation = journal.observeRunCancellation(facts.ref, moon, control)} = {}) => {
    const selected = installedEffect === undefined ? effectInstallation : selectedInstalledEffect(facts);
    const assertCurrent = () => {
      facts.assertUpdateSelectionCurrent?.();
      if (observeCancellation()?.cancellationRequested !== false) {
        throw Object.assign(new Error('ClientRunCancellationRequested'),
          {code: 'ClientRunCancellationRequested'});
      }
      activeResume?.assertCurrent();
    };
    if (facts.updateTargetSelections !== undefined) assertCurrent();
    if (typeof selected.targetReadInventory !== 'function') return undefined;
    return effectTargetReadContinuation({checkpoints,
      ...(installedEffect?.effects === undefined ? {} : {
        effectTargetAuthority: selected.targetReadAuthorization}),
      runId: control.runDefinitionRunId(facts.runDefinition),
      runDefinitionCid: facts.ref.runDefinitionCid,
      unitId: moon.clientProgramEffectCompilationUnitId(facts.compilation),
      declaredResults: moon.clientProgramEffectCompilationResultNames(facts.compilation),
      submission: effectSubmissions.get(facts.prepared),
      inventory: selected.targetReadInventory({...facts, moon,
        ...(facts.updateTargetSelections === undefined ? {} : {assertUpdateSelectionCurrent: assertCurrent})}), principalId,
      signal, resume, allowDefer, journalPort,
      ...(facts.updateTargetSelections === undefined ? {} : {
        assertOriginalCurrent: assertCurrent,
      }),
      assertCurrent,
    });
  };
  const executeEffectComputation = (facts, sourceResume, targetResume, modelResume) => {
    const activeResume = sourceResume ?? targetResume ?? modelResume;
    // This original continuation shares only immutable row admission. Every
    // probe still selects current storage; target and resume gates stay live.
    const observeCancellation = journal.observeRunCancellation(facts.ref, moon, control);
    const assertRunNotCancelled = () => {
      if (observeCancellation()?.cancellationRequested !== false) {
        throw clientOperationError('ClientRunCancellationRequested');
      }
    };
    let assertOriginalUpdateSelectionCurrent;
    if (facts.updateTargetSelections !== undefined) {
      const original = facts.assertUpdateSelectionCurrent;
      assertOriginalUpdateSelectionCurrent = () => {
        original();
        assertRunNotCancelled();
      };
      facts = Object.freeze({...facts, assertUpdateSelectionCurrent() {
        assertOriginalUpdateSelectionCurrent();
        activeResume?.assertCurrent();
      }});
    }
    // CREATE has no Mapping selection, but still consumes this SAME captured
    // Run/Journal continuation. A resumed original already checks cancellation
    // and its own claim; do not query the same state again at that boundary.
    const assertContinuationCurrent = () => {
      if (activeResume === undefined) assertRunNotCancelled();
      else activeResume.assertCurrent();
    };
    const readResume = sourceResume ?? targetResume;
    const parentResume = readResume?.active === true
      ? {claim: readResume.claim, checkpointCid: readResume.view.checkpointCid}
      : modelResume?.parentResume;
    const nextJournal = activeResume?.active !== true ? undefined : {
      ...checkpoints.journal,
      persistCheckpoint: checkpoint => checkpoints.journal.completeResume(
        activeResume.claim, {checkpoint}),
      ...(parentResume === undefined ? {} : {
        modelParentResume: parentResume,
        attachModelCallSetCheckpoint: checkpoint => checkpoints.journal.completeResume(
          parentResume.claim, {checkpoint, attachImmediateModelCallSet: true}),
      }),
    };
    const sourceCheckpoints = targetResume === undefined && modelResume === undefined ? checkpoints : {
      ...checkpoints,
      computationSourceAuthorization: options => checkpoints.computationSourceAuthorization({
        ...options, journalPort: nextJournal}),
    };
    return dispatchOwner.track(facts.ref, {
        run: async ({signal, retainExecution, beginPhysicalWork,
          observePreEffectFailure}) => {
          const managedEffect = preparation.effectManagedPlanRun(moon, facts.prepared, facts.identity);
          const managedRun = managedEffect.value;
          let targetReads;
          try {
            targetReads = await openEffectTargetReads(facts, {signal,
              resume: targetResume, activeResume, allowDefer: sourceResume === undefined,
              journalPort: modelResume === undefined ? undefined : nextJournal,
              observeCancellation});
          } catch (error) { observePreEffectFailure(); throw error; }
          return effectInstallation.execute(
          Object.freeze({...facts, signal, retainExecution, targetReads, observation, managedEffect,
            beginPhysicalWork, observePreEffectFailure, moon, control,
            assertContinuationCurrent,
            publicationPlan: facts.preparedExecution,
            store, storeAuthorityCid, authorityScopeCid,
            observeRun: ({ref}) => observeRun({ref, principalId}),
            openComputation: async ({retainComputationOwner} = {}) => {
              facts.assertUpdateSelectionCurrent?.();
              if (inferSelections.has(facts.prepared) ||
                  moon.clientProgramEffectSerializationOccurrences(facts.prepared).length > 0 ||
                  moon.clientProgramEffectAcquisitionCount(facts.prepared) > 0) {
                let ownedModelToken;
                try {
                  let retainedModel = modelResume;
                  if (retainedModel === undefined && targetResume !== undefined &&
                      inferSelections.has(facts.prepared) && modelController !== undefined) {
                    activeResume.assertCurrent();
                    const taskIndex = runtimeField(moon.clientProgramInferPlanBoundary(
                      inferSelections.get(facts.prepared).graph), 0);
                    const records = modelController.discover(
                      control.runDefinitionRunId(facts.runDefinition))
                      .filter(record => record.inventory.taskIndex === taskIndex);
                    if (records.length > 1) throw new Error('ModelResumeScopeAmbiguous');
                    if (records.length === 1) {
                      const record = records[0];
                      const token = ownedModelToken = await modelController.prime(record);
                      facts.assertUpdateSelectionCurrent?.();
                      modelController.state(record.inventory);
                      activeResume.assertCurrent();
                      retainedModel = {record, token, view: targetResume.view};
                    }
                  }
                  const selectedSources = selectAcquiredEffectSources({moon,
                    preparedEffect: facts.prepared, sourceProfile,
                    registry, values, fragment, ordered,
                    queryTimePreparation: facts.queryTimePreparation, requestIdentity: facts.identity,
                    managedPlan: checked(moon.clientProgramInstalledEffectManagedOperationPlan(
                      managedRun, facts.prepared, facts.identity))});
                  const sourceContinuation = acquiredEffectContinuation({
                    checkpoints: (selectedSources.length === 0 ||
                      selectedSources.every(({adapter}) => typeof adapter.retainedCapture === 'function'))
                      ? sourceCheckpoints : undefined,
                    moon, acquired: facts.preparedExecution,
                    submission: effectSubmissions.get(facts.prepared),
                    declaredResults: moon.clientProgramEffectCompilationResultNames(facts.compilation),
                    unitId: moon.clientProgramEffectCompilationUnitId(facts.compilation),
                    principalId, signal, resume: sourceResume,
                    assertUpdateSelectionCurrent: assertOriginalUpdateSelectionCurrent,
                    assertContinuationCurrent: activeResume?.assertCurrent,
                    ...(retainedModel?.token.snapshot.sourceContinuation === undefined ? {} : {
                      restore: {view: retainedModel.view,
                        continuation: retainedModel.token.snapshot.sourceContinuation},
                    }),
                    currentRun: () => observeCancellation()
                      ?.cancellationRequested === false});
                  if (retainedModel !== undefined &&
                      moon.clientProgramEffectAcquisitionCount(facts.prepared) > 0 &&
                      retainedModel.token.snapshot.sourceContinuation === undefined) {
                    throw new Error('ModelSourceClosureCustodyUnavailable');
                  }
                  return await openAcquiredEffectComputation({moon,
                    owner: facts.owner, acquired: facts.preparedExecution, managedRun,
                    originalContent: managedEffect.contentOriginal,
                    originalModelComponent: managedEffect.modelComponent,
                    originalModelSelection: managedEffect.modelSelection,
                    sourceProfile, registry, values, fragment, ordered,
                    sourceAccess: sourceProfile?.sourceAccess, signal, now,
                    assertUpdateSelectionCurrent: assertOriginalUpdateSelectionCurrent,
                    assertContinuationCurrent: activeResume?.assertCurrent,
                    retainComputationOwner, infer: inferSelections.get(facts.prepared),
                    ...(managedEffect.model === undefined ? {} : {
                      originalModelPlan: {compiled: managedEffect.model.compiled, runDefinition: facts.runDefinition},
                      originalPreparation: installedEffectModelPreparation(managedEffect,
                        () => preparation.modelPublicationCapacity(facts.prepared),
                        () => preparation.effectManagedPlanRun(moon, facts.prepared, facts.identity)),
                    }),
                    computeConfigurations: {local: localSnapshotConfiguration},
                    withComputePauseHandler: (configurations, handlePause) => ({
                      ...configurations,
                      local: withLocalExecutionPauseHandler(configurations.local, handlePause),
                    }),
                    store, principalId, contentRun: runContent, faultInjection: authorization?.faultInjection,
                    observe: (event, detail) => diagnostic(event,
                      {...detail, ref: facts.ref}), sourceContinuation,
                    modelController, submission: effectSubmissions.get(facts.prepared),
                    existingModel: retainedModel?.record,
                    modelClaim: modelResume?.parentResume === undefined ? modelResume?.claim : undefined,
                    parentResume, modelJournalPort: nextJournal});
                } finally { modelController?.release(ownedModelToken); }
              }
              const setup = openSourceFreeEffectComputation({moon, facts, managedRun});
              if (setup === undefined) {
                throw new Error('InstalledEffectProgramUnsupported');
              }
              return runCapturedEffectComputation(setup, {}, signal).then(
                execution => Object.freeze({execution, checkedHost: setup}));
            },
            recoverCapture: ({signal: recoverySignal, retainRecoveryResources} = {}) =>
              recoverEffectCapture(facts.ref, recoverySignal, managedEffect, retainRecoveryResources),
            effectAuthorization: checkpoints === undefined ? undefined : options =>
              checkpoints.effectAuthorization({...options,
                runDefinition: facts.retained?.runDefinition ?? facts.runDefinition,
                ...(nextJournal === undefined ? {} : {journalPort: nextJournal})}),
            recordReconciliation: (...args) =>
              effectRun.recordReconciliation(...args)}));
        },
        observeStopped: terminalOutcome => {
          recordNodeRunPhysicalStop({ref: facts.ref, journal, moon, control},
            activeResume === undefined ? terminalOutcome : null);
          modelResume?.observeStopped?.();
          if (activeResume !== undefined) activeResume.observedTerminalOutcome = terminalOutcome;
        },
        barrierFailureOutcome: 'failed',
      });
  };
  const effectRun = effectInstallation === undefined ? undefined :
    installNodeClientEffectRun({moon, publicationControl: control, journal,
      requestIdentityFor({prepared, authorityScopeCid: scope, requestId}) {
        if (scope !== authorityScopeCid) throw clientOperationError('ClientProgramNeedsInputs');
        return originalSourceFreeRequest(prepared, requestId, true);
      },
      assertRequestedStopAvailable() {
        if (checkpoints === undefined) {
          throw clientOperationError('ClientProgramUnsupported',
            clientOperationError('RequestedEffectStopUnavailable'));
        }
      },
      now, inferPlanFor: prepared => inferSelections.get(prepared)?.graph,
      prepareDefinition: facts => {
        preparation.admitEffectResultPublicationRun(facts.prepared);
        const selected = selectedInstalledEffect(facts);
        selected.assertPrepared?.({moon, prepared: facts.prepared, compilation: facts.compilation});
        preparation.prepareManagedEffectPlanRun(moon, facts, selected,
          {registry, values, fragment, ordered, sourceProfile}, inferSelections.get(facts.prepared),
          moon.clientProgramEffectSerializationOccurrences(facts.prepared).length === 0 ? undefined
            : retainCleanup => runContent.prepareEffectFamily({facts, store, principalId, retainCleanup}));
        if (mockEffectObservation !== undefined) retainMockEffectRunOriginal(facts);
      },
      updateTargetOriginals,
      validateInstallation(facts) {
        try { selectedInstalledEffect(facts); }
        catch (cause) { throw clientOperationError('ClientProgramUnsupported', cause); }
      },
      resultPolicyOriginalFor: prepared => {
        if (moon.clientProgramEffectAcquisitionCount(prepared) !== 0 ||
            !inferSelections.has(prepared) &&
              moon.clientProgramEffectSerializationOccurrences(prepared).length === 0) {
          return undefined;
        }
        if (installedResultDataPolicy === undefined) {
          throw new TypeError('MissingHostResultDataPolicyOriginal');
        }
        return installedResultDataPolicy;
      },
      authorizeRequest: async ({principalId: actual, connection}) => {
        if (!hostConnection({principalId: actual, connection})) return null;
        const createdAt = now();
        return Object.freeze({
          executionContextCid: cid({version:
            'actql-installed-effect-execution-context/0.1',
          authorityScopeCid, evidenceCid, principalId: actual}),
          hostPolicyCid: checkpoints?.binding.authorizationContextCid ??
            cid({version: 'actql-installed-effect-missing-policy/0.1',
              authorityScopeCid}),
          createdAt, expiresAt: plus(createdAt, 24 * 60 * 60 * 1000),
        });
      },
      authorizeRunStart: ({principalId: actual, connection, ref}) =>
        hostConnection({principalId: actual, connection, ref}),
      prepareExecution: ({prepared, compilation, allowed, definition,
        resultPolicyOriginal, queryTimePreparation, queryTime, identity}) => {
        const sourceFreeInfer = inferSelections.has(prepared) &&
          moon.clientProgramEffectAcquisitionCount(prepared) === 0;
        const retainedResultDataPolicy = sourceFreeInfer
          ? control.admitSourceFreeResultPolicy(
            resultPolicyOriginal, localContractLimits)
          : undefined;
        const options = {moon, control, prepared,
          compilation, allowed, definition, authorityScopeCid, namespaceId,
          storeAuthorityCid, now, resultDataPolicy: retainedResultDataPolicy,
          queryTimePreparation, queryTime, identity};
        return inferSelections.has(prepared) ||
          moon.clientProgramEffectSerializationOccurrences(prepared).length > 0 ||
          moon.clientProgramEffectAcquisitionCount(prepared) > 0
          ? acquiredEffectPublicationAdmission(options)
          : sourceFreeEffectPublicationPlan(options);
      },
      execute: executeEffectComputation,
    });
  const runIdOf = accepted => control.runDefinitionRunId(
    accepted.runDefinition?.wire === undefined
      ? journal.lookupRunDefinition(accepted.ref, moon, control).runDefinition
      : accepted.runDefinition);
  const admitEffectDefinition = submission => {
    const {requestId, principalId, connection, kind, input, parameters} = submission;
    effectSubmissions.set(submission.preparedProgram, JSON.parse(canonicalValueJson({
      requestId, principalId, connection, kind, input, parameters,
      ...capturedUpdateOriginal(submission),
      ...(submission.submission === undefined ? {} : {submission: submission.submission})}, {dataKeys: true})));
    return effectRun.accept({
    prepared: submission.preparedProgram, authorityScopeCid,
    requestId: submission.requestId, namespaceId,
    principalId: submission.principalId, connection: submission.connection,
    submission: submission.submission,
    lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
    });
  };
  const submitEffect = async (submission, requested, resultNames) => {
    const {requestId, principalId: actual, connection, kind, input,
      parameters, preparedProgram} = submission;
    // A deferred approval must be answerable by this installed profile.
    // Reject unsupported checked shapes before retaining a Checkpoint.
    effectRun.checkSupported(preparedProgram);
    if (checkpoints?.heldOrigin(requestId)) {
      const existing = journal.resolveDefinition(requested, {namespaceId}, moon,
        control);
      if (existing !== undefined) {
        void checkpoints.sweep();
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    if (runAcceptance !== undefined &&
        (checkpoints?.heldOrigin(requestId) ||
         journal.lookup({namespaceId, authorityScopeCid, requestId}, moon) ===
           undefined)) {
      const requestedFacts = {
        logicalRequestScopeCid: moon.clientRequestScopeCid(requested),
        intentFingerprintCid: moon.clientRequestIntentCid(requested),
      };
      const captured = {version: 'actql-remote-captured-submission/0.1',
        requestId, principalId: actual, connection, kind, input,
        parameters, resultNames,
        ...capturedUpdateOriginal(submission),
        ...(submission.submission === undefined ? {} : {submission: submission.submission})};
      const decided = await runAcceptance.acceptRun({requested: requestedFacts,
        captured});
      if (decided.kind !== 'dispatch') {
        const existing = journal.lookupDefinition({namespaceId,
          authorityScopeCid, requestId}, moon, control);
        void checkpoints.sweep();
        if (existing !== undefined) {
          return {ref: existing.ref, durability: existing.durability,
            revision: existing.revision};
        }
        if (decided.held === undefined) {
          throw new Error('HeldRunDefinitionMissing');
        }
        return decided.held;
      }
    }
    const accepted = await admitEffectDefinition(submission);
    // The durable accepted Ref is returned before physical work settles.
    // Its start claim cannot be reset by a lost response or a second submit.
    const settlement = effectRun.start(accepted).catch(error => {
      diagnostic('effect_start_failed', {ref: accepted.ref,
        code: error?.code ?? error?.message, cause: error?.cause});
    }).finally(() => settleHeldRun(accepted, runIdOf(accepted)))
      .catch(error => diagnostic('effect_settlement_failed', {
        ref: accepted.ref, code: error?.code ?? error?.message}));
    try {observation?.retainOperation?.(settlement);} catch { /* Optional metadata. */ }
    return {ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision};
  };
  const prepareTimedRunInvocation = (preparedProgram, requestIdentity, compilationOriginal, retainedInvocation) => {
    const retained = journal.resolveDefinition(requestIdentity, {namespaceId}, moon, control);
    const kind = moon.clientProgramAcquisitionCount(preparedProgram) > 0 ||
      moon.clientProgramRequiresTaskCompilation(preparedProgram) ? 'tasks' : 'values';
    return prepareTimedClientInvocation({control, preparedProgram, requestIdentity,
      compilationOriginal, kind, authorityScopeCid, namespaceId, now, retainedInvocation,
      retainedDefinitionWire: retained?.runDefinition.wire});
  };
  const prepareOrdinaryManagedRun = captureInstalledManagedRunRoute({
    sourceProfile, preparation, moon, prepareInvocation: prepareTimedRunInvocation});
  const submit = async submission => {
    const {requestId, principalId: actual, connection, kind, input,
      parameters} = submission;
    if (!hostConnection({principalId: actual, connection})) {
      throw clientOperationError('ClientConnectionDenied');
    }
    if (Object.hasOwn(submission, 'readOnly')) {
      const intent = moon.clientSubmittedIntent(canonicalValueJson({kind, input,
        parameters, readOnly: submission.readOnly,
        ...(Object.hasOwn(submission, 'stopBefore') ? {stopBefore: submission.stopBefore} : {})},
      {dataKeys: true}), 1048576, 65536, 64);
      if (intent === undefined) throw clientOperationError('ClientProgramInvalidInput');
      prepareSubmit.assertSubmittedIntent(submission.preparedProgram, intent);
    }
    const {requested, resultNames, acquired, acquisitionCount, keyedAcquisition, effectful} =
      requestOf(submission);
    const selectedModel = inferSelections.get(submission.preparedProgram);
    if (selectedModel?.egressFailure !== undefined &&
        journal.resolveDefinition(requested, {namespaceId}, moon, control) === undefined) {
      diagnostic('infer_preparation_rejected', {boundary: 'model_admission',
        code: selectedModel.egressFailure.code, cause: selectedModel.egressFailure.cause});
      throw clientOperationError('ClientProgramUnsupported', selectedModel.egressFailure);
    }
    if (effectful) {
      return submitEffect(submission, requested, resultNames);
    }
    const serializationCount = moon.clientProgramSerializationOccurrences(submission.preparedProgram).length;
    // A reserved physical start can only be reconciled from its original
    // durable Run. Do this before rebuilding physical source preparations.
    // INFER continues to its existing saved-capture replay owner below.
    const retainedStart = journal.resolveDefinition(requested, {namespaceId}, moon, control);
    if (retainedStart?.physicalStartReserved === true &&
        retainedStart.runAdmissionEvidence?.modelOriginalRunWire !== undefined) {
      // The durable Model owner reopens its original fixed input. Missing
      // inventory after a crash is never permission to reacquire a Source or
      // recompute the prefix through the legacy completed-capture fallback.
      void checkpoints?.sweep();
      return {ref: retainedStart.ref, durability: retainedStart.durability,
        revision: retainedStart.revision};
    }
    if (retainedStart?.physicalStartReserved === true &&
        !inferSelections.has(submission.preparedProgram)) {
      return {ref: retainedStart.ref, durability: retainedStart.durability,
        revision: retainedStart.revision};
    }
    preparation?.admitResultPublicationRun(submission.preparedProgram);
    let managedSourceRun;
    if (selectedModel?.localMock) {
      const early = earlyMockInferPlans.get(submission.preparedProgram);
      if (early === undefined) throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
      managedSourceRun = sourceProfile.prepareManagedMockModelRun(submission.preparedProgram, requested,
        control, early.plan, selectedModel,
        () => preparation.modelPublicationCapacity(submission.preparedProgram));
    } else if (selectedModel !== undefined) {
      const model = prepareInstalledRequestModelRun(submission, requested, selectedModel);
      const managed = earlyMockInferPlans.get(submission.preparedProgram).managed;
      if (managed.model !== model || managed.value === undefined || model.managed !== managed) {
        throw clientOperationError('ForeignInstalledModelPreparation');
      }
      // Dispatch and the original Source wrapper consume the same nominal
      // Run, never the private JS record that retains it.
      managedSourceRun = managed.value;
    } else if (serializationCount !== 0) {
      if (acquisitionCount > 0) {
        const early = earlyContentPlans.get(submission.preparedProgram);
        if (early === undefined) throw clientOperationError('InstalledContentRunPreparationUnavailable');
        runContent.prepareManagedKeyedRun({preparedProgram: submission.preparedProgram,
          plan: early.plan, request: requested, keyedAcquisition: early.keyedAcquisition});
      }
    } else {
      managedSourceRun = prepareOrdinaryManagedRun({preparedProgram: submission.preparedProgram,
        requestIdentity: requested, acquisitionCount, model: selectedModel, serializationCount});
    }
    const managedRun = managedSourceRun;
    const preparedSources = acquisitionCount === 2
      ? await prepareAcquisitions(submission.preparedProgram) : undefined;
    const keyedPrepared = keyedAcquisition === undefined ? undefined :
      await prepareKeyedSources(submission.preparedProgram, keyedAcquisition, requested);
    const keyedSource = keyedPrepared?.keyedSource;
    const preparedSource = keyedPrepared?.preparedSource ?? (acquired && acquisitionCount !== 2
      ? await prepareAcquisition(submission.preparedProgram) : undefined);
    // Run acceptance on the protected Site is decided before any Run
    // Definition exists. A request that was held is never started from here:
    // submitting it again returns its held state, or its existing Run, and
    // only wakes the durable resume owner, which starts it under the resumed
    // authorization. Other admitted requests are looked up, not decided
    // again.
    // A held request whose Run exists is compared with the request
    // journal's own identity (no side effect): another intent conflicts,
    // whatever the state of the held evidence.
    if (checkpoints?.heldOrigin(requestId)) {
      const existing = journal.resolveDefinition(requested, {namespaceId}, moon,
        control);
      if (existing !== undefined) {
        if (existing.physicalStartReserved !== true &&
            existing.runAdmissionEvidence?.sourceInventory !== sourceInventory(preparedSources, preparedSource, keyedSource)) {
          throw clientOperationError('ClientRunStartDenied',
            clientOperationError('ClientRequestSourceInventoryMismatch'));
        }
        void checkpoints.sweep();
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    if (runAcceptance !== undefined &&
        (checkpoints?.heldOrigin(requestId) ||
         journal.lookup({namespaceId, authorityScopeCid, requestId}, moon) ===
           undefined)) {
      const requestedFacts = {
        logicalRequestScopeCid: moon.clientRequestScopeCid(requested),
        intentFingerprintCid: moon.clientRequestIntentCid(requested),
      };
      const captured = captureSubmission(submission, resultNames, preparedSource, preparedSources, keyedSource);
      let decided = await runAcceptance.acceptRun({requested: requestedFacts,
        captured});
      // Run acceptance allowed or permitted: a Program that reads the
      // installed source has its read decided before any Run exists.
      if (decided.kind === 'dispatch' && checkpoints !== undefined) {
        decided = await checkpoints.acceptAcquisition({
          requested: requestedFacts, captured});
      }
      if (decided.kind !== 'dispatch') {
        const existing = journal.lookupDefinition({namespaceId,
          authorityScopeCid, requestId}, moon, control);
        void checkpoints.sweep();
        if (existing === undefined) {
          if (decided.held === undefined) {
            throw new Error('HeldRunDefinitionMissing');
          }
          return decided.held;
        }
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    const held = {preparedSource, preparedSources, keyedSource, managedRun,
      preparedSourceAccess: preparedSource === undefined ? undefined :
        installedSourceFor(sourceProfile, preparedSource.checkedSource.sourceRef).sourceAccess};
    const accepted = await admitDefinition(submission, requested,
      resultNames, held);
    if (managedRun !== undefined && observation?.canMeasureResources()) {
      try {preparation.bindManagedComputeRunObservation(submission.preparedProgram, accepted.ref);}
      catch {observation.noteLoss();}
    }
    if (inferSelections.has(submission.preparedProgram) &&
        accepted.physicalStartReserved === true &&
        accepted.observedTerminalOutcome === null &&
        !accepted.cancellationRequested &&
        dispatchOwner.operation(accepted.ref) === undefined &&
        await store.confirmCommittedIndex(accepted.ref) === undefined) {
      // Re-submission of the exact accepted request may reopen its saved
      // evidence, never reserve another provider dispatch. Missing evidence
      // leaves the original unknown Run intact.
      const flight = dispatchOwner.track(accepted.ref, {
        run: async ({signal, retainExecution, beginPhysicalWork, acquireSource}) => {
          const current = journal.lookupRunDefinition(accepted.ref, moon, control);
          if (current === undefined || current.cancellationRequested ||
              current.observedTerminalOutcome !== null) return;
          const plan = planFor(submission, current.runDefinition.wire, requested);
          let acquiredInfer;
          if (acquired) {
            // Reacquisition uses the current installed read admission. It
            // grants no permission to dispatch the model again; saved slot
            // replay separately binds the original evidence and actual input.
            const sourceAccess = checkpoints?.acquisitionAccess(
              submission.requestId, sourceProfile.sourceAccess) ?? sourceProfile.sourceAccess;
            const preparedSource = await prepareAcquisition(submission.preparedProgram,
              sourceAccess);
            const {captured, sourceEvidence, captureStartedAt, captureCompletedAt} =
              await acquireSource({preparedProgram: submission.preparedProgram,
                preparedSource, sourceAccess});
            const input = control.admitInferCapturedInput(
              submission.preparedProgram, captured, sourceEvidence, authorityScopeCid,
              captured.checkedSource.sourceDataPolicyCid, captureStartedAt, captureCompletedAt);
            acquiredInfer = {input, sourceEvidence};
          }
          await runInfer({preparedProgram: submission.preparedProgram, plan,
            store, principalId: actual, signal, retainExecution,
            beginPhysicalWork, acquiredInfer, replay: true});
        },
        observeStopped: async () => {
          // Only the existing publication owner can make recovery successful.
          // A reader refusal does not resolve the original physical outcome.
          if (await store.confirmCommittedIndex(accepted.ref) !== undefined) {
            recordNodeRunPhysicalStop({ref: accepted.ref, journal, moon, control}, null);
          }
        },
      });
      void flight.catch(error => diagnostic('infer_replay_failed', {
        ref: accepted.ref, code: error?.code ?? error?.message}));
      return {ref: accepted.ref, durability: accepted.durability,
        revision: accepted.revision};
    }
    // A resumed request's journal Run (if any) ends with its dispatch.
    startDispatch(submission, requested, accepted, held,
      checkpoints === undefined ? undefined : status =>
        settleHeldRun(accepted, runIdOf(accepted)));
    return {ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision};
  };
  // Continue one approved held request (called by the Checkpoint sweep with
  // the captured submission and the claim's admission). The admission is
  // entered synchronously immediately before the Run Definition is
  // admitted; the resume intent completes with the created Run.
  const heldSubmission = async captured => {
    const submission = {principalId: captured.principalId,
      connection: captured.connection, requestId: captured.requestId,
      kind: captured.kind, input: captured.input,
      parameters: captured.parameters,
      ...(captured.updateTargetPreparedOriginal === undefined ? {} :
        {updateTargetPreparedOriginal: captured.updateTargetPreparedOriginal}),
      ...(captured.submission === undefined ? {} : {submission: captured.submission})};
    // This is an actual pending Checkpoint restoration, not an SDK ingress or
    // authority inferred from equal DATA. Keep its original captured input and
    // Request parent through the existing Run admission/start handoff.
    const requestInput = preparation.retainEffectRequestInput(moon, submission, undefined, captured);
    try {
    localPreparationCustody.attach(submission,
      localPreparationCustody.adopt(await prepareCapturedSubmission(submission), submission));
    preparation.bindSourceRequest(submission, submission.preparedProgram);
    const {requested, resultNames, acquired, acquisitionCount, keyedAcquisition, effectful} = requestOf(submission);
    const resolved = {submission, requested, resultNames, effectful, requestInput,
      managedRun: undefined};
    // A restored non-Effect request needs the SAME pre-admitted Plan as a
    // fresh submission before Source preparation or publication reads it.
    // Effect definitions retain their existing constructor below.
    if (!effectful) admitPreparedSubmission(submission, resolved);
    const preparedSources = acquisitionCount === 2
      ? await prepareAcquisitions(submission.preparedProgram) : undefined;
    const keyedPrepared = keyedAcquisition === undefined ? undefined :
      await prepareKeyedSources(submission.preparedProgram, keyedAcquisition, requested);
    const keyedSource = keyedPrepared?.keyedSource;
    const preparedSource = keyedPrepared?.preparedSource ?? (acquired && acquisitionCount !== 2
      ? await prepareAcquisition(submission.preparedProgram) : undefined);
    const reproduced = captureSubmission(submission, resultNames, preparedSource, preparedSources, keyedSource);
    if (canonicalValueJson(reproduced, {dataKeys: true}) !==
        canonicalValueJson(captured, {dataKeys: true})) {
      throw new Error('HeldAcquisitionChanged');
    }
    if (JSON.stringify(resultNames) !==
        JSON.stringify(captured.resultNames)) {
      throw new Error('HeldRequestChanged');
    }
    return Object.assign(resolved, {preparedSource, preparedSources, keyedSource});
    } catch (cause) {
      // The original failed producer remains owned if retirement refuses.
      // Preserve the primary cause and the SAME retry; no reprepare or ACK.
      throw retainInstalledHostRuntimeFailure(cause, () => requestInput.finish('failed'));
    }
  };
  const definitionOf = captured => journal.lookupDefinition({namespaceId,
    authorityScopeCid, requestId: captured.requestId}, moon, control);
  const terminal = status => ['succeeded', 'failed', 'cancelled']
    .includes(status);
  // Recover only from the accepted Run and the committed publication owner.
  // A reserved start without an available publication cannot be treated as
  // an unstarted read or reconstructed by fetching the source again.
  const inspectAcquisition = async ({requestId, principalId: actual,
    connection}) => {
    if (sourceProfile === undefined ||
        !hostConnection({principalId: actual, connection})) {
      throw new Error('AcquisitionInspectionDenied');
    }
    const accepted = journal.lookupDefinition({namespaceId,
      authorityScopeCid, requestId}, moon, control);
    if (accepted === undefined || accepted.physicalStartReserved !== true) {
      return {state: 'not_started'};
    }
    const current = await observeRun({ref: accepted.ref,
      principalId: actual});
    const availability = Object.values(current.result_availability);
    if (current.status === 'succeeded' && availability.length > 0 &&
        availability.every(result => result.state === 'available')) {
      return {state: 'completed_retained', ref: accepted.ref,
        resultNames: Object.keys(current.result_availability)};
    }
    return {state: 'started_unknown', ref: accepted.ref};
  };
  // The physical state of a held request's Run: `absent` (no Run
  // Definition yet), `unstarted` (no physical start reserved), `cancelled`
  // (cancelled before any physical start), `abandoned` (failed before
  // dispatch), `started` (reserved: running, or unknown after a crash) or
  // `terminal`.
  const inspectHeld = async captured => {
    const acquisition = captured.acquisition === undefined && captured.acquisitions === undefined ? undefined :
      await inspectAcquisition({requestId: captured.requestId,
        principalId: captured.principalId, connection: captured.connection});
    const accepted = definitionOf(captured);
    if (accepted === undefined) return {state: 'absent', acquisition};
    const runId = runIdOf(accepted);
    if (accepted.preDispatchFailureConfirmed) {
      return {state: 'abandoned', runId, acquisition};
    }
    if (accepted.physicalStartReserved !== true) {
      // A Run cancelled before any physical start is terminal, not
      // resumable: its public state is the Run's own projection.
      if (accepted.cancellationRequested) {
        const current = await observeRun({ref: accepted.ref, principalId});
        if (current.status === 'cancelled') {
          return {state: 'cancelled', runId, acquisition};
        }
      }
      return {state: 'unstarted', runId, acquisition};
    }
    const current = await observeRun({ref: accepted.ref, principalId});
    return terminal(current.status)
      ? {state: 'terminal', runId, status: current.status, acquisition}
      : {state: 'started', runId, status: current.status, acquisition};
  };
  // After a held request's dispatch ends, its journal Run ends only with the
  // Run's observed terminal state; a Run whose physical stop is unknown (for
  // example after a cancel) stays with its owners and is observed again by
  // the sweep. Nothing is inferred from how the dispatch returned.
  const settleHeldRun = async (accepted, runId) => {
    // Account-only acceptance has no held Checkpoint Run to settle. The
    // original request Journal still owns its actual Run and physical stop.
    if (checkpoints === undefined) return;
    let status;
    try {
      status = (await observeRun({ref: accepted.ref, principalId})).status;
    } catch {}
    if (terminal(status)) checkpoints.runFinished(runId, status);
    else void checkpoints.sweep();
  };
  // Continue one approved held request whose physical start is not
  // reserved. The Run Definition is admitted (or looked up); the common
  // resumed admission is entered synchronously immediately before the
  // physical start reservation, and the resume intent completes with the
  // Run right after it. Resolves with 'started', {refused} or 'not_started'.
  // The Run cancellation of a held request's defined Run (the Host itself
  // applies a durable request cancellation to its Run).
  const cancelHeldRun = async captured => {
    const accepted = definitionOf(captured);
    if (accepted === undefined) return;
    const publicationCommitted =
      await store.confirmCommittedIndex(accepted.ref) !== undefined;
    const result = journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted}, moon, control);
    if (result.kind !== 'already_terminal') {
      dispatchOwner.cancel(accepted.ref);
    }
  };
  const resumeHeld = async ({captured, beforePhysicalStart, started,
    step, renew, preparationCancelled}) => {
    // A request whose physical target or result inventory differs from the
    // one held is refused before anything is admitted or read: the earlier
    // approval does not cover it.
    let resolved;
    try { resolved = await heldSubmission(captured); }
    catch (error) {
      if (['HeldAcquisitionChanged', 'HeldRequestChanged']
        .includes(error?.message)) {
        return {refused: Object.assign(error, {code: error.message})};
      }
      throw error;
    }
    const {submission, requested, resultNames, preparedSource, preparedSources, keyedSource, managedRun,
      effectful, requestInput} = resolved;
    let failed = false;
    try {
    if (effectful) {
      effectRun.checkSupported(submission.preparedProgram);
      const accepted = await admitEffectDefinition(submission);
      await step('definition_admitted', {ref: accepted.ref});
      try { renew(); }
      catch (error) { return {refused: error}; }
      if (preparationCancelled()) {
        await cancelHeldRun(captured);
        return 'not_started';
      }
      if (definitionOf(captured)?.cancellationRequested) {
        return 'not_started';
      }
      const runId = runIdOf(accepted);
      let settle;
      const observedStart = new Promise(resolve => { settle = resolve; });
      let startObserved = false;
      const flight = effectRun.start(accepted, {
        beforePhysicalStart,
        started() {
          startObserved = true;
          try { started(runId); }
          finally { settle('started'); }
        },
      });
      const settlement = flight.then(result => {
        if (!startObserved) {
          settle(result.kind === 'started' ? 'started' : 'not_started');
        }
      }, error => {
        if (!startObserved) settle({refused: error});
        diagnostic('effect_start_failed', {ref: accepted.ref,
          code: error?.code ?? error?.message, cause: error?.cause});
      }).finally(() => settleHeldRun(accepted, runId))
        .catch(error => diagnostic('effect_settlement_failed', {
          ref: accepted.ref, code: error?.code ?? error?.message}));
      try {observation?.retainOperation?.(settlement);} catch { /* Optional metadata. */ }
      return await observedStart;
    }
    const held = {preparedSource, preparedSources, keyedSource, managedRun,
      preparedSourceAccess: preparedSource === undefined ? undefined :
        installedSourceFor(sourceProfile, preparedSource.checkedSource.sourceRef).sourceAccess};
    const accepted = await admitDefinition(submission, requested,
      resultNames, held);
    await step('definition_admitted', {ref: accepted.ref});
    try { renew(); }
    catch (error) { return {refused: error}; }
    // A request cancellation recorded meanwhile (even before this Run
    // existed) is applied to the Run now; a Run cancellation is read from
    // the journal, not from the admitted snapshot. Either way the Run is not
    // dispatched.
    if (preparationCancelled()) {
      await cancelHeldRun(captured);
      return 'not_started';
    }
    if (definitionOf(captured)?.cancellationRequested) return 'not_started';
    const runId = runIdOf(accepted);
    return await startDispatch(submission, requested, accepted, held,
      () => settleHeldRun(accepted, runId),
      {beforePhysicalStart, started: () => started(runId)});
    } catch (cause) {
      failed = true;
      throw retainInstalledHostRuntimeFailure(cause, () => requestInput.finish('failed'));
    } finally {
      if (!failed) {
        try {requestInput.finish('returned');}
        catch (cause) {
          // Start already returned. Retry only this SAME input retirement;
          // never replay the physical-start handoff or infer cleanup ACK.
          throw retainInstalledHostRuntimeFailure(cause, () => requestInput.finish('returned'));
        }
      }
    }
  };
  // A held request whose authorization no longer holds before any physical
  // start: its Run (if already defined) fails before dispatch; nothing runs.
  const abandonHeld = async captured => {
    const accepted = definitionOf(captured);
    if (accepted === undefined || accepted.physicalStartReserved === true ||
        accepted.preDispatchFailureConfirmed) return;
    if (accepted.dispatchReserved !== true) {
      const restored = await heldSubmission(captured);
      let start;
      try {
        start = await startRun({identity: restored.requested,
          namespaceId, principalId: captured.principalId, connection: captured.connection});
      } catch (cause) {
        // A failed admission (even `throw undefined`) remains the primary.
        // Input cleanup belongs to its original retry, not another startRun.
        throw retainInstalledHostRuntimeFailure(cause, () => restored.requestInput.finish('failed'));
      }
      try {restored.requestInput.finish('returned');}
      catch (cause) {
        throw retainInstalledHostRuntimeFailure(cause, () => restored.requestInput.finish('returned'));
      }
      if (start.kind !== 'reserved' && start.kind !== 'reconcile') return;
    }
    journal.markPreDispatchFailure(accepted.ref);
  };
  // A Run whose physical start is reserved is only observed: a terminal Run
  // ends its journal Run; an unknown one is never sent again.
  const observeHeldRun = async ({captured}) => {
    const accepted = definitionOf(captured);
    if (accepted === undefined) throw new Error('HeldRunDefinitionMissing');
    return (await observeRun({ref: accepted.ref, principalId})).status;
  };
  // A held request is looked up through the Checkpoint journal until its Run
  // exists; then the request journal answers with its RunRef.
  const lookupHeld = async value => {
    const found = await lookupRequest(value);
    if (checkpoints === undefined || found.kind !== 'not_found') return found;
    if (authorizedScope(value) === undefined) return found;
    return checkpoints.heldLookup(value.requestId) ?? found;
  };
  const selectedRequestPreparation = preparation?.requestPreparation();
  // An unselected installed Host must supply no callback, not a no-op that
  // still selects the Source request/Promise retention path downstream.
  const bindOwnedRequest = selectedRequestPreparation === undefined ? undefined :
    preparation.bindSourceRequest;
  // The existing Host operation retains only a failed callback's original
  // requested identity until its paired reader consumes that same candidate.
  const admissionFailures = new WeakMap();
  const holderRefusal = preparation === undefined ? undefined :
    Object.getOwnPropertyDescriptor(preparation, 'isOriginalManagedComputePreparationRefusal')?.value;
  const admitPreparedSubmission = preparation === undefined ? undefined : Object.freeze(Object.assign(
    function(submission, held) {
      let requested, sourceRefusal;
      try {
        const selected = requestOf(submission, (error, request, adapter, sourceRef) => {
          sourceRefusal = Object.freeze({error, request, adapter, sourceRef,
            profile: sourceProfile, requestId: submission.requestId});
        });
        requested = selected.requested;
        const {acquisitionCount, keyedAcquisition, effectful} = selected;
        const selection = inferSelections.get(submission.preparedProgram);
        if (effectful) {
          if (installedEffect === undefined && effectInstallation === undefined ||
              typeof preparation.prepareManagedEffectPlanRun !== 'function') {
            throw clientOperationError('HostEffectRunPreparationUnavailable');
          }
          preparation.admitEffectResultPublicationRun(submission.preparedProgram);
          return;
        }
        if (selection !== undefined && !selection.localMock) {
          preparation.admitResultPublicationRun(submission.preparedProgram);
          const retained = journal.resolveDefinition(requested, {namespaceId}, moon, control);
          // Saved physical work keeps its original recovery owner. Do not
          // allocate another Model Scope for a previously started Run.
          if (retained?.physicalStartReserved === true) return;
          const model = prepareInstalledRequestModelRun(submission, requested, selection);
          // A historical Source continuation dispatches this SAME adopted
          // Model Run and its input borrow, just as fresh admission does.
          if (held !== undefined) held.managedRun = model.managed.value;
          return;
        }
        const serializationCount = moon.clientProgramSerializationOccurrences(submission.preparedProgram).length;
        if (serializationCount !== 0) {
          // Content has its own pre-admitted prefix and real Store writers. A
          // Result service or Source/Model allowance cannot supply that work.
          if (selection !== undefined || acquisitionCount !== 0 &&
              (keyedAcquisition === undefined ||
                typeof sourceProfile?.prepareManagedContentRun !== 'function')) {
            throw clientOperationError('InstalledContentRunPreparationUnsupported');
          }
          preparation.admitResultPublicationRun(submission.preparedProgram);
          const retained = journal.resolveDefinition(requested, {namespaceId}, moon, control);
          // A prior physical start is observed through its saved Run. Resource
          // preparation cannot regenerate Content or replace an uncertain write.
          if (retained?.physicalStartReserved === true) return;
          let early = earlyContentPlans.get(submission.preparedProgram);
          if (early === undefined) {
            early = {requestId: submission.requestId,
              keyedAcquisition,
              plan: planFor(submission, retained?.runDefinition.wire, requested, keyedAcquisition)};
            earlyContentPlans.set(submission.preparedProgram, early);
          }
          if (acquisitionCount === 0) runContent.prepareRun({preparedProgram: submission.preparedProgram, plan: early.plan, request: requested});
          else runContent.prepareManagedKeyedRun({preparedProgram: submission.preparedProgram,
            plan: early.plan, request: requested, keyedAcquisition: early.keyedAcquisition});
          return;
        }
        preparation.admitResultPublicationRun(submission.preparedProgram);
        if (selection?.localMock) {
          if (acquisitionCount !== 0 && acquisitionCount !== 2 ||
              typeof sourceProfile?.prepareManagedMockModelRun !== 'function') {
            throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
          }
          let early = earlyMockInferPlans.get(submission.preparedProgram);
          if (early === undefined) {
            early = {requestId: submission.requestId, plan: planFor(submission, undefined, requested)};
            earlyMockInferPlans.set(submission.preparedProgram, early);
          }
          sourceProfile.prepareManagedMockModelRun(submission.preparedProgram, requested,
            control, early.plan, selection,
            () => preparation.modelPublicationCapacity(submission.preparedProgram));
        } else {
          const managedRun = prepareOrdinaryManagedRun({preparedProgram: submission.preparedProgram,
            requestIdentity: requested, acquisitionCount, model: selection, serializationCount});
          // Resume consumes the Run issued by this SAME admission. Its local
          // handoff is not the SDK callback's return value or another Plan.
          if (held !== undefined) held.managedRun = managedRun;
        }
      } catch (error) {
        if (missingModelExecutionRefusals.has(error)) {
          requested = sourceFreeRequestIdentities.get(submission.preparedProgram)?.requested;
        }
        admissionFailures.set(submission, Object.freeze({error, requested,
          prepared: submission.preparedProgram, sourceRefusal}));
        throw error;
      }
    }, {isOriginalPreparationRefusal(error, submission) {
      if (this !== admitPreparedSubmission) return false;
      const original = admissionFailures.get(submission);
      admissionFailures.delete(submission);
      if (original === undefined || original.error !== error ||
          original.prepared !== submission.preparedProgram) return false;
      if (missingModelExecutionRefusals.has(error)) {
        missingModelExecutionRefusals.delete(error);
        const input = sourceFreeRequestIdentities.get(original.prepared);
        if (input?.requested !== original.requested || input?.requestId !== submission.requestId ||
            original.requested === undefined || inferSelections.has(original.prepared) ||
            error.cleanupPending === true || error.cleanupHandle !== undefined) return false;
        prepareSubmit.assertOwned(original.prepared);
        if (prepareSubmit.kindOf(original.prepared) !== 'effect_free' ||
            moon.clientProgramAcquisitionCount(original.prepared) !== 0 ||
            moon.clientProgramSerializationOccurrences(original.prepared).length !== 0) return false;
        preparation.assertUnadmittedSourceRequest(moon, original.prepared, original.requested);
        if (journal.resolveDefinition(original.requested, {namespaceId}, moon, control) !== undefined) return false;
        preparation.assertUnadmittedSourceRequest(moon, original.prepared, original.requested);
        return true;
      }
      const source = original.sourceRefusal;
      if (source !== undefined) {
        if (source.error !== error || source.requestId !== submission.requestId ||
            source.profile !== sourceProfile || source.request === undefined ||
            error.cleanupPending === true || error.cleanupHandle !== undefined ||
            sourceFreeRequestIdentities.get(original.prepared)?.requested !== source.request ||
            sourceFreeRequestIdentities.get(original.prepared)?.requestId !== source.requestId) return false;
        preparation.assertUnadmittedSourceRequest(moon, original.prepared, source.request);
        prepareSubmit.assertOwned(original.prepared);
        if (prepareSubmit.kindOf(original.prepared) !== 'effect_free' ||
            inferSelections.has(original.prepared) ||
            moon.clientProgramSerializationOccurrences(original.prepared).length !== 0 ||
            installedSourceFor(sourceProfile, source.sourceRef) !== source.adapter ||
            typeof source.adapter.managedWholeSourceCapacity === 'function' ||
            journal.resolveDefinition(source.request, {namespaceId}, moon, control) !== undefined) return false;
        preparation.assertUnadmittedSourceRequest(moon, original.prepared, source.request);
        return true;
      }
      if (typeof holderRefusal !== 'function') return false;
      return Reflect.apply(holderRefusal, preparation,
        [error, original.prepared, original.requested]);
    }}));
  const submissionService = installNodeClientSubmission({journal, moon,
    authorizedScope: value => hostConnection(value) ? authorizedScope(value) : undefined,
    prepareSubmit, submit, lookupRequest: lookupHeld, checkSubmissionInput: check,
    observeOriginalPreparationFailure: preparation === undefined ? undefined : async (failure, value) => {
      if (!hostConnection(value)) throw clientOperationError('ClientConnectionDenied');
      const outcome = await preparation.observeOriginalCheckOutcome(value, failure, project =>
        checkSource.projectOriginal({principalId: value.principalId,
          connection: value.connection, kind: value.kind === 'program' ? 'program' : 'text',
          scope: 'bound_input', input: value.input, parameters: value.parameters, signal: value.signal}, project));
      if (!hostConnection(value)) throw clientOperationError('ClientConnectionDenied');
      return outcome;
    },
    bindOwnedRequest,
    preparationCustody: localPreparationCustody,
    submittedIntentOriginal: value => preparation?.submittedIntentOriginal?.(value),
    admitPreparedSubmission});
  const checkpointOperations = checkpoints === undefined ? {} : {
    checkpoints: value => checkpoints.listCheckpoints({principalId: value.principalId,
      after: value.after, limit: value.limit,
      ...(Object.hasOwn(value, 'checkpointId') ? {checkpointId: value.checkpointId} : {})}),
    checkpointReview: ({principalId: actual, checkpointCid, maxBytes,
      signal}) => checkpoints.reviewCheckpoint({principalId: actual,
      checkpointCid, maxBytes, signal}),
    async resolve({principalId: actual, items}) {
      const result = await checkpoints.resolve({principalId: actual, items});
      try { if (observation !== undefined) for (const item of result.results) {
        if (item.status !== 'committed') continue;
        const view = checkpoints.journal.inspect(item.checkpointCid);
        if (view?.runDefinitionCid === undefined) continue;
        observation?.emit('approval', 'checkpoint_resolved', {ref: {
          namespaceId, authorityScopeCid, runDefinitionCid: view.runDefinitionCid},
          outcome: 'committed'});
      } } catch { observation?.noteLoss(); }
      return result;
    },
  };
  const checkpointOperation = new Set(['checkpoints', 'checkpoint-review',
    'resolve']);
  // Reviewers and review readers may connect and use only the Checkpoint
  // operations; every Run operation still requires the owner.
  const checkpointConnection = value => checkpoints !== undefined &&
    value.ref === undefined && value.connection.mode === mode &&
    value.connection.owner === mode &&
    checkpoints.admitsCheckpointPrincipal(value.principalId);
  const effectResumeFlights = new Map();
  const effectRetirementFlights = new Map();
  const retiredEffectCaptures = new Set();
  const retireEffectCapture = ref => {
    const key = ref.runDefinitionCid;
    if (retiredEffectCaptures.has(key)) return Promise.resolve(false);
    const existing = effectRetirementFlights.get(key);
    if (existing !== undefined) return existing;
    const flight = (async () => {
      if (dispatchOwner.operation(ref) !== undefined) {
        throw new Error('EffectCaptureExecutionStillOwned');
      }
      if (await store.confirmCommittedIndex(ref) !== undefined) {
        retiredEffectCaptures.add(key);
        return false;
      }
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained?.runDefinition?.identity !== key) {
        throw new Error('EffectRetirementRunDefinitionMissing');
      }
      const owned = journal.lookupOwnedDefinition({namespaceId, authorityScopeCid,
        requestId:retained.requestId, runDefinitionCid:key}, moon, control);
      if (owned?.runDefinition?.identity !== key ||
          typeof preparation?.prepareEffectCaptureRetirement !== 'function') {
        throw clientOperationError('EffectRetirementResourcesUnavailable');
      }
      let resources, result;
      try {
        const selected = preparation.prepareEffectCaptureRetirement(moon, owned.requestIdentity,
          owned.runDefinition, localContractLimits,
          () => preparation.assertResultPublicationCurrent(), original => {resources = original;});
        if (selected !== resources) throw clientOperationError('EffectRetirementResourcesUnavailable');
        result = await retireCompletedEffectfulCapture({store, control,
          runDefinition: owned.runDefinition, contractLimits: localContractLimits}, resources);
      } catch (cause) {
        try {await resources?.close();} catch { /* Same Host bag retains original cleanup. */ }
        throw cause;
      }
      if (await resources.close() !== true) throw clientOperationError('EffectCaptureResourceCleanupPending');
      retiredEffectCaptures.add(key);
      return result;
    })().finally(() => {
      if (effectRetirementFlights.get(key) === flight) {
        effectRetirementFlights.delete(key);
      }
    });
    effectRetirementFlights.set(key, flight);
    return flight;
  };
  const retireIncompleteEffects = async () => {
    const failures = [];
    let after = '';
    for (;;) {
      const page = await store.listEffectCaptureCustodies({after, limit: 100});
      for (const run of page) {
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: run.identity});
        try {
          // Cleanup discovery is not a new start claim. A live invocation
          // still owns its preparation; only absent local owners are eligible.
          if (dispatchOwner.operation(ref) !== undefined ||
              effectResumeFlights.has(run.identity)) continue;
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined) continue; // Another authority scope.
          if (retained.runDefinition.wire !== run.wire) {
            throw new Error('EffectCaptureCustodyRunMismatch');
          }
          const runId = control.runDefinitionRunId(run);
          // Durable custody still exists only before transfer to a Checkpoint
          // or physical dispatch. A complete private record is not sufficient
          // to establish that transfer. The original unknown Run stays intact.
          if (checkpoints.effectRunState(runId, ref.runDefinitionCid) !== undefined) {
            continue;
          }
          await retireEffectCapture(ref);
        } catch (error) { failures.push(error); }
      }
      if (page.length < 100) break;
      after = page.at(-1).identity;
    }
    if (failures.length > 0) {
      throw new AggregateError(failures, 'EffectCaptureCleanupPending');
    }
  };
  const retireTerminalEffects = async () => {
    if (effectRun === undefined || checkpoints === undefined) return;
    let after = '';
    const failures = [];
    try { await retireIncompleteEffects(); }
    catch (error) { failures.push(error); }
    for (;;) {
      const page = checkpoints.journal.listRunCheckpoints({after, limit: 100});
      for (const view of page) {
        if (!['effect_set', 'read_access'].includes(view.kind) || view.prepareAttemptId !== null ||
            !['failed', 'cancelled'].includes(
              checkpoints.journal.getRunState(view.runId)?.status)) continue;
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: view.runDefinitionCid});
        try { await retireEffectCapture(ref); }
        catch (error) { failures.push(error); }
      }
      if (page.length < 100) break;
      after = page.at(-1).checkpointCid;
    }
    if (failures.length > 0) {
      throw new AggregateError(failures, 'EffectCaptureCleanupPending');
    }
  };
  const sweepEffectRuns = async ({reconcileRef} = {}) => {
    if (effectRun === undefined || checkpoints === undefined) return false;
    let busy = false;
    // A requested observation owns only its original Run. Global capture
    // retirement belongs to ordinary sweeps and final Host shutdown.
    try { if (reconcileRef === undefined) await retireIncompleteEffects(); }
    catch (error) {
      busy = true;
      diagnostic('effect_capture_retirement_failed', {
        code: error?.code ?? error?.message});
    }
    let after = '';
    for (;;) {
      const page = checkpoints.journal.listRunCheckpoints({after, limit: 100});
      for (const view of page) {
        if (reconcileRef !== undefined &&
            (view.runDefinitionCid !== reconcileRef.runDefinitionCid ||
             view.kind !== 'effect_set')) continue;
        if (!['effect_set', 'read_access'].includes(view.kind) || view.prepareAttemptId !== null) {
          continue;
        }
        const key = view.runDefinitionCid;
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: key});
        if (await cancelEffectContinuation(ref)) {
          busy = true;
        }
        const runStatus = checkpoints.journal.getRunState(view.runId)?.status;
        if (runStatus === 'failed' || runStatus === 'cancelled') {
          try { await retireEffectCapture(ref); }
          catch (error) {
            busy = true;
            diagnostic('effect_capture_retirement_failed', {ref,
              code: error?.code ?? error?.message});
          }
          continue;
        }
        const observing = reconcileRef !== undefined && runStatus === 'needs_reconciliation';
        if (runStatus !== 'resuming' && !observing) continue;
        if (!observing && checkpoints.journal.currentResume(view.checkpointCid)?.state === 'completed') continue;
        if (effectResumeFlights.has(key) ||
            dispatchOwner.operation(ref) !== undefined) {
          busy = true;
          if (observing && effectResumeFlights.has(key)) {
            await effectResumeFlights.get(key);
          }
          continue;
        }
        try {
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined ||
              retained.runDefinition.identity !== key) {
            throw new Error('EffectResumeRunDefinitionMissing');
          }
          if (view.kind === 'read_access') {
            // Check before claiming: changed bindings must not turn an
            // earlier entered physical continuation into an unsent failure.
            // Retained inputs cannot prove that later work never started.
            if (checkpoints.journal.hasStartedResume(view.checkpointCid)) {
              // Another owner can publish after this observation. Keep the
              // existing sweep alive without authorizing another execution.
              busy = true;
              const reconciliation = effectRun.reconciliation(ref);
              if (reconciliation !== undefined) {
                checkpoints.journal.settleObservedEffectResume(view.checkpointCid,
                  ref.runDefinitionCid, JSON.stringify(reconciliation));
                continue;
              }
              if (await store.confirmCommittedIndex(ref) !== undefined) {
                const published = await inspectAuthorizedRunState(stateService,
                  {indexKey: ref, principalId, purpose: 'inspect'});
                if (published.status === 'succeeded') {
                  checkpoints.journal.settleObservedEffectResume(view.checkpointCid,
                    ref.runDefinitionCid, JSON.stringify(published));
                  busy = true;
                }
              }
              continue;
            }
            const claimed = checkpoints.journal.claimResume(view.runId, {
              claimant: `source-host-${process.pid}-${randomUUID()}`,
              leaseMs: authorization?.leaseMs ?? 60000,
              binding: checkpoints.binding, preserveStarted: true,
              expectedCheckpointCid: view.checkpointCid});
            if (claimed.action !== 'claimed') {
              if (claimed.action === 'admitted' || claimed.action === 'busy') busy = true;
              continue;
            }
            if (claimed.checkpointCid !== view.checkpointCid) continue;
            const flight = (async () => {
              let sourceResume;
              let targetResumption = false;
              let leaseFailure;
              let requestInput, inputFailed = false;
              const leaseMs = authorization?.leaseMs ?? 60000;
              const renewal = setInterval(() => {
                try {
                  if (checkpoints.journal.currentResume(view.checkpointCid)?.state ===
                      'completed') return;
                  checkpoints.journal.renewResume(claimed.claim, leaseMs);
                }
                catch (error) { leaseFailure = error; }
              }, Math.max(1, Math.min(1000, Math.floor(leaseMs / 3))));
              renewal.unref?.();
              try {
              try {
                const continuation = await checkpoints.runUnitReadContinuation(view);
                targetResumption = continuation.version === EFFECT_TARGET_CONTINUATION;
                const submission = {...continuation.submission};
                // This is the independently admitted Checkpoint's pending
                // restoration, not a new SDK request. Retain its same captured
                // input before preparation, as on the existing held-request path.
                requestInput = preparation.retainEffectRequestInput(moon,
                  submission, undefined, continuation.submission);
                localPreparationCustody.attach(submission,
                  localPreparationCustody.adopt(await prepareCapturedSubmission(submission, ref), submission));
                preparation.bindSourceRequest(submission, submission.preparedProgram);
                const request = requestOf(submission);
                if (!request.effectful || !targetResumption && inferSelections.has(submission.preparedProgram)) {
                  throw new Error('UnsupportedAcquiredEffectContinuation');
                }
                const accepted = await admitEffectDefinition(submission);
                if (accepted.ref.runDefinitionCid !== ref.runDefinitionCid) {
                  throw new Error('EffectContinuationRunMismatch');
                }
                const facts = await effectRun.restoreComputation(accepted);
                sourceResume = {claim: claimed.claim, view, continuation, active: true,
                  assertCurrent() {
                    if (leaseFailure !== undefined) throw leaseFailure;
                    if (journal.lookupRunDefinition(ref, moon, control)?.cancellationRequested) {
                      throw Object.assign(new Error('ClientRunCancellationRequested'),
                        {code: 'ClientRunCancellationRequested'});
                    }
                    return checkpoints.journal.admitResume(claimed.claim,
                      {checkpointCid: view.checkpointCid});
                  }};
                const result = await executeEffectComputation(facts,
                  targetResumption ? undefined : sourceResume,
                  targetResumption ? sourceResume : undefined);
                // Resume exits only through the existing terminal outcome
                // or atomic next-Checkpoint transition, never a fabricated
                // resuming-to-running intermediate public state.
                if (checkpoints.journal.getRunState(view.runId)?.status === 'resuming') {
                  const ended = effectRun.reconciliation(ref) ?? await observeRun({ref, principalId});
                  if (terminal(ended.status) || ended.status === 'needs_reconciliation') {
                    const {control: _control, ...state} = ended;
                    checkpoints.journal.completeResume(claimed.claim, {
                      runStateWire: JSON.stringify(state)});
                  } else if (['failed_without_effect_dispatch', 'failed_effect_set']
                    .includes(result?.status)) {
                    checkpoints.journal.completeResume(claimed.claim, {status: 'failed'});
                  }
                }
              } catch (error) {
                if (['ResumeClaimStale', 'PriorAdmissionUnresolved'].includes(error?.code) ||
                    error?.authorization?.detail === 'ResumeClaimStale') throw error;
                const refusal = (targetResumption
                  ? checkpoints.journal.refuseUnsentReadResume
                  : checkpoints.journal.refuseUnsentSourceResume)(
                  view.checkpointCid, view.runDefinitionCid, claimed.claim);
                // A started source with an unresolved physical owner stays
                // with its original claim and custody. Never reacquire it.
                if (refusal.outcome === 'admitted' &&
                    ['failed', 'cancelled'].includes(sourceResume?.observedTerminalOutcome)) {
                  checkpoints.journal.completeResume(claimed.claim, {
                    status: sourceResume.observedTerminalOutcome});
                }
                throw error;
              }
              } catch (cause) {
                inputFailed = true;
                if (requestInput === undefined) throw cause;
                throw retainInstalledHostRuntimeFailure(cause, () => requestInput.finish('failed'));
              } finally {
                clearInterval(renewal);
                if (requestInput !== undefined && !inputFailed) {
                  try {requestInput.finish('returned');}
                  catch (cause) {
                    throw retainInstalledHostRuntimeFailure(cause, () => requestInput.finish('returned'));
                  }
                }
              }
            })();
            effectResumeFlights.set(key, flight);
            const settlement = flight.catch(error => diagnostic('source_resume_failed', {
              ref, code: error?.code ?? error?.message,
              detail: error?.authorization?.detail,
              cause: error?.authorization?.error?.code,
              missingModule: error?.code === 'ERR_MODULE_NOT_FOUND' ? error.url : undefined})).finally(() => {
              effectResumeFlights.delete(key);
              if (checkpoints.journal.getRunState(view.runId)?.status !== 'resuming') {
                void checkpoints.sweep();
              }
            });
            try {observation?.retainOperation?.(settlement);} catch { /* Optional metadata. */ }
            busy = true;
            continue;
          }
          const continuation = await checkpoints.effectContinuation(view);
          const flight = dispatchOwner.track(ref, {
            run: async ({signal, retainExecution, beginPhysicalWork}) => {
              let restored = await restoreEffectManagedPreparation(ref, signal);
              const managedEffect = restored.managedEffect;
              try {
              return await effectInstallation.resume(Object.freeze({ref, view, observation, managedEffect,
                reconciliationOnly: observing,
                assertContinuationCurrent() {
                  if (journal.lookupRunDefinition(ref, moon, control)?.cancellationRequested !== false) {
                    throw clientOperationError('ClientRunCancellationRequested');
                  }
                },
                continuation, retained, moon, control, store, principalId, contentRun: runContent,
                storeAuthorityCid, authorityScopeCid, signal,
                retainExecution, beginPhysicalWork,
                observeRun: ({ref}) => observeRun({ref, principalId}),
                recoverCapture: ({signal: recoverySignal, retainRecoveryResources} = {}) =>
                  recoverEffectCapture(ref, recoverySignal, managedEffect, retainRecoveryResources, restored.original),
                checkpointJournal: checkpoints.journal,
                checkpointBinding: checkpoints.binding,
                effectAuthorization: checkpoints.effectAuthorization,
                prepareTargetReads: async claimed => {
                  const records = await checkpoints.inspectEffectTargetApprovals(
                    view.runId, ref.runDefinitionCid);
                  const capturedTarget = continuation.target_read_binding;
                  if (records.length === 0 && capturedTarget === undefined) return undefined;
                  if (capturedTarget !== undefined) assertEffectTargetReadBinding(capturedTarget);
                  const submission = {...(capturedTarget?.submission ?? records[0].continuation.submission)};
                  if (submission.requestId !== retained.requestId) throw new Error('EffectContinuationRunMismatch');
                  const {prepared, compilation, identity} = managedEffect.definitionOriginal;
                  if (submission.updateTargetPreparedOriginal !== undefined) {
                    updateTargetOriginals.validatePreparedOriginal(prepared, compilation, submission.updateTargetPreparedOriginal);
                  } else if (updateTargetOriginals.selectionsOf(prepared) !== undefined) {
                    throw new Error('EffectContinuationRunMismatch');
                  }
                  // Apply refresh is another consumer of this SAME original
                  // Plan, not a new submission or compiler/Execution Owner.
                  const facts = restored.original ?? Object.freeze({ref,
                    ...managedEffect.definitionOriginal, identity,
                    runDefinition: retained.runDefinition,
                    ...updateTargetOriginals.validateRun({prepared, compilation, identity,
                      evidence: retained.runAdmissionEvidence, runDefinition: retained.runDefinition})});
                  effectSubmissions.set(prepared, submission);
                  const reads = await openEffectTargetReads(facts, {signal, allowDefer: false,
                    activeResume: {assertCurrent() {
                      return checkpoints.journal.admitResume(claimed.claim,
                        {checkpointCid: view.checkpointCid});
                    }}});
                  try {
                    if (capturedTarget !== undefined) {
                      assertEffectTargetReadBinding(reads?.captureBinding(), capturedTarget);
                    }
                  } catch (error) { reads?.close(); throw error; }
                  return reads;
                },
                recordReconciliation: (...args) =>
                  effectRun.recordReconciliation(...args)}));
              } finally {
                // This operation's admitted-material alias is no longer a
                // caller root before the managed parent can retire on drain.
                restored = undefined;
              }
            },
            // The original Compute stopped before the Effect Checkpoint.
            // Its nonterminal stop observation is immutable. Effect failure
            // and reconciliation belong to the Checkpoint and Effect owners.
            observeStopped: () => recordNodeRunPhysicalStop({ref, journal, moon, control}, null),
          });
          effectResumeFlights.set(key, flight);
          const settlement = flight.catch(error => {
            diagnostic('effect_resume_failed', {ref,
              code: error?.code ?? error?.message});
          }).finally(() => {
            effectResumeFlights.delete(key);
            if (checkpoints.journal.getRunState(view.runId)?.status !==
                'resuming') {
              void checkpoints.sweep();
            }
          });
          try {observation?.retainOperation?.(settlement);} catch { /* Optional metadata. */ }
          if (observing) await flight;
        } catch (error) {
          diagnostic('effect_resume_failed', {ref,
            code: error?.code ?? error?.message});
          if (reconcileRef !== undefined) throw error;
        }
        busy = true;
      }
      if (page.length < 100) break;
      after = page.at(-1).checkpointCid;
    }
    return busy;
  };
  const reconcile = async ({ref, principalId: actual, connection, signal}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('RunStateAccessDenied');
    }
    signal?.throwIfAborted();
    const state = await observeRun({ref, principalId: actual});
    // An explicit Effect observation never restarts Compute, reopens approval
    // or converts an execution-unknown Run into an invented Effect inventory.
    if (state.status === 'needs_reconciliation' && state.next_action?.kind === 'reconcile_run') {
      await observeNodeRestoredLocalStop({ref, journal, store, checkpoints, moon, control});
    }
    if (state.status === 'needs_reconciliation' &&
        state.next_action?.kind === 'reconcile') {
      await sweepEffectRuns({reconcileRef: ref});
    }
    return observeRun({ref, principalId: actual});
  };
  const modelResumeFlights = new Map();
  const sweepModelRuns = async () => {
    if (modelController === undefined || checkpoints === undefined) return false;
    let busy = false;
    let after = '';
    for (;;) {
      const page = checkpoints.journal.discoverModelCallSets({after, limit: 100});
      for (const record of page) {
        let token, transferred = false;
        try {
          const originalOwner = modelController.verifier.admitOriginalRun({
            originalRunWire: record.originals.originalRunWire});
          if (originalOwner.runId !== record.inventory.runId ||
              originalOwner.runDefinitionCid !== record.inventory.runDefinitionCid) {
            throw new Error('ModelResumeRunDefinitionMismatch');
          }
          const prior = checkpoints.journal.getRunState(originalOwner.runId);
          if (prior !== undefined && checkpoints.journal.isTerminalRunOutcome(prior.status) &&
              !checkpoints.journal.hasUnresolvedModelCalls(originalOwner.runId)) {
            // Terminal scopes with no unknown attempts may already have had
            // their private input retired. Discovery is not a new read grant.
            modelController.retire(record);
            continue;
          }
          // Discovery is routing only. Authenticate original Store custody,
          // re-admit the entire inventory, then repair saved response markers
          // before inspecting cancellation or current send permission.
          token = await modelController.prime(record);
          let calls = checkpoints.journal.readModelCalls(record.inventory);
          for (const slot of calls.slots) for (const entry of slot.attempts) {
            await modelController.observe(entry);
          }
          calls = checkpoints.journal.readModelCalls(record.inventory);
          const runId = calls.runId;
          const ref = Object.freeze({namespaceId, authorityScopeCid,
            runDefinitionCid: calls.runDefinitionCid});
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined || retained.runDefinition.identity !== calls.runDefinitionCid ||
              retained.runAdmissionEvidence?.modelOriginalRunWire !== record.originals.originalRunWire) {
            throw new Error('ModelResumeRunDefinitionMissing');
          }
          if (modelResumeFlights.has(ref.runDefinitionCid) || dispatchOwner.operation(ref) !== undefined) {
            busy = true;
            continue;
          }
          const unresolved = checkpoints.journal.hasUnresolvedModelCalls(runId);
          if (retained.cancellationRequested) {
            checkpoints.journal.fenceRunCancellation({originalRunWire: record.originals.originalRunWire});
            await cancelEffectContinuation(ref);
            if (unresolved) busy = true;
            continue;
          }
          const runState = checkpoints.journal.getRunState(runId);
          if (runState === undefined) throw new Error('ModelResumeRunStateMissing');
          if (checkpoints.journal.isTerminalRunOutcome(runState.status)) {
            if (unresolved) busy = true;
            continue;
          }
          const active = checkpoints.journal.activeRunCheckpoint(runId);
          const parentCheckpoint = record.checkpointCid === null && active?.kind === 'read_access'
            ? active : undefined;
          if (active !== undefined && parentCheckpoint === undefined && (active.kind !== 'model_invocation' ||
              active.checkpointCid !== record.checkpointCid)) {
            // A later Source/Effect continuation owns this same Run now.
            if (unresolved) busy = true;
            continue;
          }
          let claim;
          const claimCheckpointCid = record.checkpointCid ?? parentCheckpoint?.checkpointCid;
          if (claimCheckpointCid !== undefined) {
            if (runState.status !== 'resuming' || active === undefined) {
              if (unresolved) busy = true;
              continue;
            }
            const claimed = checkpoints.journal.claimResume(runId, {
              claimant: `model-host-${process.pid}-${randomUUID()}`,
              leaseMs: authorization?.leaseMs ?? 60000, binding: checkpoints.binding,
              expectedCheckpointCid: claimCheckpointCid});
            if (claimed.action !== 'claimed') {
              if (['busy', 'admitted'].includes(claimed.action)) busy = true;
              continue;
            }
            claim = claimed.claim;
          } else if (runState.status !== 'running') {
            if (unresolved) busy = true;
            continue;
          }
          let leaseFailure;
          const leaseMs = authorization?.leaseMs ?? 60000;
          const renewal = claim === undefined ? undefined : setInterval(() => {
            try { checkpoints.journal.renewResume(claim, leaseMs); }
            catch (error) {
              leaseFailure = error;
              dispatchOwner.cancel(ref);
            }
          }, Math.max(1, Math.min(1000, Math.floor(leaseMs / 3))));
          renewal?.unref?.();
          const observeRestoredRun = journal.observeRunCancellation(ref, moon, control);
          const assertCurrent = () => {
            if (leaseFailure !== undefined) throw leaseFailure;
            if (observeRestoredRun()?.cancellationRequested !== false) {
              throw new Error('ClientRunCancellationRequested');
            }
            // Ownership only here. Model send permission is checked by its
            // own activation and per-call entry; Effect approval is separate.
            if (claim !== undefined) checkpoints.journal.renewResume(claim, leaseMs);
          };
          let restorationDispatchEntered = false;
          let restorationStopConfirmed = false;
          // An older physical-close record cannot acknowledge a new
          // continuation's reclamation. Only its current owner can do that.
          const restorationReclaimed = () => !restorationDispatchEntered || restorationStopConfirmed;
          const retainStoppedModelReconciliation = () => {
            const stopped = journal.lookupRunDefinition(ref, moon, control);
            if (!checkpoints.journal.hasUnresolvedModelCalls(runId) ||
                effectRun?.reconciliation(ref) !== undefined ||
                !restorationReclaimed() || stopped?.physicalCloseConfirmed !== true ||
                dispatchOwner.operation(ref) !== undefined) return false;
            const reconciliation = issueInstalledUnpublishedRunState(moon, {runId,
              observedAt: now(), resultNames: stopped.resultNames,
              dispatchReserved: true, preDispatchFailureConfirmed: false,
              cancelledBeforeStart: false, observedTerminalOutcome: 'none',
              executionUnknown: true});
            if (journal.lookupRunDefinition(ref, moon, control)?.revision !== stopped.revision) return false;
            const lifecycle = checkpoints.journal.getRunState(runId);
            if (claim !== undefined && lifecycle?.status === 'resuming' && leaseFailure === undefined) {
              checkpoints.journal.completeResume(claim, {runStateWire: JSON.stringify(reconciliation)});
            } else if (claim === undefined && lifecycle?.status === 'running') {
              checkpoints.journal.finishRun(runId, {status: 'needs_reconciliation',
                runStateWire: JSON.stringify(reconciliation)});
            }
            return checkpoints.journal.getRunState(runId)?.status === 'needs_reconciliation';
          };
          const runRestoredModel = async () => {
            let recovery;
            try {
            assertCurrent();
            const current = journal.lookupOwnedDefinition({...ref, requestId: retained.requestId}, moon, control);
            if (current === undefined || current.ref.runDefinitionCid !== ref.runDefinitionCid) {
              throw new Error('ModelResumeRunDefinitionMissing');
            }
            const submission = JSON.parse(canonicalValueJson(token.snapshot.submission));
            if (submission.requestId !== current.requestId ||
                !hostConnection(submission)) throw new Error('ModelResumeSubmissionMismatch');
            const inferOriginal = current.runAdmissionEvidence?.inferRunOriginal;
            if (inferOriginal !== undefined) {
              recovery = preparation.retainModelRecoveryInput(moon, submission,
                current.requestIdentity, current.runDefinition, assertCurrent,
                () => !restorationReclaimed());
              submission.preparedProgram = prepareSubmit.restoreInferOriginal(
                inferOriginal, current.runDefinition, current.requestIdentity,
                current.runAdmissionEvidence, submission);
            } else {
              // Restore through the SAME funded Request entrance used by cold
              // Effect recovery. A saved Prepared projection cannot stand in
              // for this pending Request's actual compiler/borrower.
              const originalIntent = journal.originalSubmittedIntent(current.requestIdentity,
                {namespaceId}, moon, control);
              const materialWire = current.runAdmissionEvidence?.updateTargetRunOriginal?.materialsWire ??
                current.runAdmissionEvidence?.effectOriginalRunWire;
              if (originalIntent === undefined || typeof materialWire !== 'string') {
                throw new Error('ModelResumeOriginalMaterialsUnavailable');
              }
              originalIntent.assertCurrent();
              recovery = preparation.retainEffectRequestInput(moon,
                submission, originalIntent.intent, undefined, materialWire);
              const prepared = await prepareSubmit(submission);
              prepareSubmit.assertSubmittedIntent(prepared, originalIntent.intent);
              localPreparationCustody.attach(submission,
                localPreparationCustody.adopt(prepared, submission));
            }
            preparation.bindSourceRequest(submission, submission.preparedProgram);
            const requested = requestOf(submission);
            const admitted = journal.resolveDefinition(requested.requested,
              {namespaceId}, moon, control);
            if (admitted?.ref.runDefinitionCid !== ref.runDefinitionCid) {
              throw new Error('ModelResumeRunDefinitionMismatch');
            }
            assertCurrent();
            if (requested.effectful) {
              if (effectRun === undefined) throw new Error('InstalledEffectContinuationUnavailable');
              const accepted = await admitEffectDefinition(submission);
              if (accepted.ref.runDefinitionCid !== ref.runDefinitionCid) {
                throw new Error('ModelResumeRunDefinitionMismatch');
              }
              const facts = await effectRun.restoreComputation(accepted);
              assertCurrent();
              const modelResume = {record, token, claim, active: claim !== undefined,
                view: record.checkpointCid === null ? Object.freeze({kind: 'model_invocation',
                  prepareAttemptId: null, runId, runDefinitionCid: ref.runDefinitionCid}) : active,
                ...(parentCheckpoint === undefined ? {} : {parentResume: {
                  claim, checkpointCid: parentCheckpoint.checkpointCid}}),
                assertCurrent, observeStopped: () => { restorationStopConfirmed = true; }};
              restorationDispatchEntered = true;
              const result = await executeEffectComputation(facts, undefined, undefined, modelResume);
              recovery.finish('returned');
              recovery = undefined;
              return result;
            }
            if (parentCheckpoint !== undefined) throw new Error('ModelReadParentRunMismatch');
            if (inferOriginal === undefined) throw new Error('ModelResumeOriginalMaterialsUnavailable');
            const plan = planFor(submission, current.runDefinition.wire, requested.requested);
            if (originalModelRunWire(plan.compiled, plan.runDefinition) !== record.originals.originalRunWire) {
              throw new Error('ModelResumeOriginalAdmissionChanged');
            }
            restorationDispatchEntered = true;
            const result = await dispatchOwner.track(ref, {
              run: async ({signal, retainExecution, beginPhysicalWork}) => {
                assertCurrent();
                signal.throwIfAborted();
                return runInfer({preparedProgram: submission.preparedProgram, plan,
                  store, principalId, signal, retainExecution, beginPhysicalWork,
                  submission: token.snapshot.submission, existingModel: record, modelClaim: claim,
                  assertCurrent});
              },
              observeStopped: async () => {
                await observeNodeRestoredModelStop({ref,
                  journal, store, checkpoints, moon, control, cleanupConfirmed: true,
                  physicalStopConfirmed: true});
                restorationStopConfirmed = true;
              },
            });
            recovery?.finish('returned');
            recovery = undefined;
            return result;
            } catch (cause) {
              if (recovery === undefined) throw cause;
              throw retainInstalledHostRuntimeFailure(cause, () => recovery.finish('failed'));
            }
          };
          const flight = runRestoredModel().then(async result => {
            if (leaseFailure !== undefined) throw leaseFailure;
            if (result?.status === 'waiting_checkpoint') return;
            const lifecycle = checkpoints.journal.getRunState(runId);
            if (result?.status === 'needs_reconciliation') {
              const unresolvedModel = checkpoints.journal.hasUnresolvedModelCalls(runId);
              const effectReconciliation = effectRun?.reconciliation(ref);
              // This restoration returned only after its physical Owner's
              // stop and cleanup. Retain its unresolved outcome in the same
              // Run journal, so later sweeps do not reopen a Running frame.
              if (unresolvedModel) {
                retainStoppedModelReconciliation();
                return;
              }
              const reconciliation = effectReconciliation;
              if (reconciliation !== undefined) {
                if (claim !== undefined && lifecycle?.status === 'resuming') {
                  checkpoints.journal.completeResume(claim,
                    {runStateWire: JSON.stringify(reconciliation)});
                } else if (claim === undefined && lifecycle?.status === 'running') {
                  checkpoints.journal.finishRun(runId, {status: 'needs_reconciliation',
                    runStateWire: JSON.stringify(reconciliation)});
                }
              }
              return;
            }
            if (['failed_without_effect_dispatch', 'failed_effect_set'].includes(result?.status)) {
              if (!checkpoints.journal.hasUnresolvedModelCalls(runId) &&
                  dispatchOwner.operation(ref) === undefined) {
                if (claim !== undefined && lifecycle?.status === 'resuming') {
                  checkpoints.journal.completeResume(claim, {status: 'failed'});
                } else if (claim === undefined && lifecycle?.status === 'running') {
                  checkpoints.journal.finishRun(runId, {status: 'failed'});
                }
              }
              return;
            }
            if (await store.confirmCommittedIndex(ref) === undefined) return;
            const published = await inspectAuthorizedRunState(stateService,
              {indexKey: ref, principalId, purpose: 'inspect'});
            if (published.status !== 'succeeded') return;
            const current = checkpoints.journal.getRunState(runId);
            if (claim !== undefined && current?.status === 'resuming') {
              checkpoints.journal.completeResume(claim, {runStateWire: JSON.stringify(published)});
            } else if (claim === undefined && current?.status === 'running') {
              checkpoints.journal.finishRun(runId, {status: 'succeeded',
                runStateWire: JSON.stringify(published)});
            }
          }).catch(async error => {
            const code = error?.code ?? error?.message;
            // Cancellation can win before this restoration physically enters.
            // Its confirmed prior stop still retains unknown Model responsibility;
            // it must not leave a Running journal that only public lookup projects.
            if (retainStoppedModelReconciliation()) return;
            const stopped = journal.lookupRunDefinition(ref, moon, control);
            if (stopped?.physicalCloseConfirmed === true &&
                await confirmNodeRunCancellation({ref, journal, store, checkpoints,
                  moon, control, cleanupConfirmed: restorationReclaimed(),
                  physicalStopConfirmed: stopped.physicalCloseConfirmed}) &&
                restorationReclaimed() &&
                journal.lookupRunDefinition(ref, moon, control)?.revision === stopped.revision) {
              const state = checkpoints.journal.getRunState(runId);
              if (claim !== undefined && state?.status === 'resuming' && leaseFailure === undefined) {
                checkpoints.journal.completeResume(claim, {status: 'cancelled'});
              } else if (claim === undefined && state?.status === 'running') {
                checkpoints.journal.finishRun(runId, {status: 'cancelled'});
              }
              return;
            }
            if (code === 'ModelSavedTerminalFailure' && stopped?.physicalCloseConfirmed === true && restorationReclaimed() &&
                !checkpoints.journal.hasUnresolvedModelCalls(runId)) {
              const state = checkpoints.journal.getRunState(runId);
              if (claim !== undefined && state?.status === 'resuming' && leaseFailure === undefined) {
                checkpoints.journal.completeResume(claim, {status: 'failed'});
              } else if (claim === undefined && state?.status === 'running') {
                checkpoints.journal.finishRun(runId, {status: 'failed'});
              }
              return;
            }
            const detail = error?.authorization?.detail;
            const policyRefusal = error?.authorization?.action === 'deny' ||
              ['ApprovalExpired', 'ModelRunExpired', 'ModelProviderBindingChanged',
                'ModelCheckpointConfigurationChanged', 'InstalledInferAuthorityUnavailable',
                'InstalledModelEgressUnavailable'].includes(code) ||
              ['ApprovalExpired', 'ModelRunExpired'].includes(detail);
            if (claim !== undefined && parentCheckpoint === undefined && policyRefusal && leaseFailure === undefined &&
                dispatchOwner.operation(ref) === undefined) {
              try {
                const current = checkpoints.journal.readModelCalls(record.inventory);
                if (current.slots.every(slot => slot.attempts.length === 0)) {
                  checkpoints.journal.refuseUnsentModelResume(record.checkpointCid,
                    ref.runDefinitionCid, claim);
                }
              } catch (failure) {
                diagnostic('model_refusal_unresolved', {ref,
                  code: failure?.code ?? failure?.message});
              }
            }
            diagnostic('model_resume_failed', {ref, code});
          }).finally(() => {
            if (renewal !== undefined) clearInterval(renewal);
            modelResumeFlights.delete(ref.runDefinitionCid);
            modelController.release(token);
          });
          transferred = true;
          modelResumeFlights.set(ref.runDefinitionCid, flight);
          try {observation?.retainOperation?.(flight);} catch { /* Optional metadata. */ }
          busy = true;
        } catch (error) {
          busy = true;
          diagnostic('model_recovery_failed', {scopeCid: record.scopeCid,
            code: error?.code ?? error?.message});
        } finally { if (!transferred) modelController.release(token); }
      }
      if (page.length < 100) break;
      after = page.at(-1).scopeCid;
    }
    return busy;
  };
  const ownerCursorCodec = authorization?.hostKey === undefined ? undefined :
    createClientOwnerCursorCodec({privateKey:authorization.hostKey.privateKey,
      publicKey:createPublicKey(authorization.hostKey.privateKey)});
  const authorizeObservation = value => hostConnection(value) &&
    journal.lookupRunDefinition(value.ref,moon,control) !== undefined;
  ownerViews=installedEffect === undefined ? undefined : installClientEffectObservations({moon,
    root:join(root,'state','effects','ledger'),authorize:authorizeObservation});
  const observeOwners = installClientOwnerObservations({
    authorizeRun:authorizeObservation, codec:ownerCursorCodec,maxEntries:1000,maxWireBytes:65536,
    sourcesFor:value => {
      const {ref,principalId:actual}=value;
      const retained=journal.lookupRunDefinition(ref,moon,control);
      const owned=ownerViews === undefined ? undefined : journal.lookupOwnedDefinition({
        ...ref,requestId:retained.requestId},moon,control);
      return [{owner:{kind:'run',scopeCid:ref.authorityScopeCid,streamCid:ref.runDefinitionCid},
        history:'not_provided',authorize:authorizeObservation,
        readSnapshot:async () => ({value:await observeRun({ref,principalId:actual})})},
        ...(ownerViews === undefined ? [] : owned === undefined ? [{kind:'problem',
          ownerKind:'effect',problem:'acquisition_failed',authorize:authorizeObservation}] :
          ownerViews.sources(owned.requestIdentity,value))];
    },
  });
  const runPlan = installClientRunPlan({authorize: authorizeObservation, control,
    lookupOriginal: ref => journal.lookupRunDefinition(ref, moon, control)});
  const inspectRun = installClientRunInspect({
    authorize: authorizeObservation, observeOwners, control,
    lookupOriginal: ref => journal.lookupRunDefinition(ref, moon, control),
  });
  const runReadOperations = new Set(['status', 'wait', 'attach', 'run-plan', 'inspect-run',
    'owner-observations', 'lookup-request', 'lookup-submission']);
  const hostOperations = {
    observe: observed,
    // A service Workspace is an installed network target label. It does not
    // replace the Local namespace, root-derived authority scope or policy.
    workspaceForPrincipal: () => workspaceId,
    authorizeConnection: async value => {
      if (checkpointOperation.has(value.operation)) return checkpointConnection(value);
      const connected = hostConnection(value) || value.operation === 'connect' &&
        checkpointConnection(value);
      if (!connected || !runReadOperations.has(value.operation)) return connected;
      // This is the original public operation entry, before any Journal read.
      // Internal observation/revision loops consume that decision; they do not
      // reevaluate it. Named Result access keeps its separate exact permission.
      return authorizeLocalRun({principalId: value.principalId,
        indexKey: value.ref ?? {namespaceId, authorityScopeCid}, purpose: 'inspect'});
    },
    negotiate, prepareSubmit, check, plan, inspectRun, runPlan, attach,
    // New execution requires the authenticated original intent. Historical
    // request/Run observation remains available without relabeling its identity.
    submit: async () => {throw clientOperationError('ClientSubmissionReferenceRequired');},
    submitIntent: submissionService.submitAttempt,
    submitNamedIntent: submissionService.submitNamedAttempt,
    lookupSubmission: submissionService.lookupSubmission,
    lookupRequest: lookupHeld,
    stateService, resultService, observeRun, observeOwners, wait, reconcile, cancel, lookupCancellation, cancelRequest,
    ...checkpointOperations,
    // Discovery of the installed source, when its adapter serves it.
    ...(sourceProfile?.discovery ?? {}),
  };
  if (checkpoints !== undefined) {
    await checkpoints.start({inspect: inspectHeld, resume: resumeHeld,
      abandon: abandonHeld, observe: observeHeldRun,
      cancelRun: cancelHeldRun,
      models: modelController === undefined ? undefined : {
        sweep: sweepModelRuns,
        drain: () => Promise.allSettled([...modelResumeFlights.values()]),
      },
      effects: effectRun === undefined ? undefined :
        {sweep: sweepEffectRuns}});
  }
  const ingress = createNodeInProcessClientHost({
    authenticate: () => principalId,
    bindOwnedRequest,
    captureResultObservation: observation === undefined ? undefined : ref => {
      if (!observation.canMeasureResources()) return undefined;
      return captureManagedRunObservation(observation, ref,
        preparation?.managedComputeUsageReader(ref));
    },
    captureResultOperation: observation === undefined ? undefined
      : () => observation.captureCurrentOperation(),
    ...hostOperations, maxRowBytes: 1024 * 1024,
  });
  const requestPreparation = preparation?.requestPreparation();
  if (requestPreparation !== selectedRequestPreparation) {
    throw clientOperationError('InstalledSourcePreparationChanged');
  }
  const port = observation === undefined && requestPreparation === undefined &&
    mockAccount === undefined ? ingress : Object.freeze({
    ...(requestPreparation === undefined ? {} : {[sourcePreparationPort]: requestPreparation}),
    ...(mockAccount === undefined ? {} : {answerCheckpoint: answerLocalCheckpoint}),
    perform: (operation, request, signal) => observation === undefined
      ? ingress.perform(operation, request, signal)
      : observation.run(operation, undefined, () => ingress.perform(operation, request, signal)),
  });
  return Object.assign(host, {port, store, journal, hostOperations, checkpoints, runAcceptance, diagnostic,
    closeRequestJournal: closeHostRequestJournal,
    ...(preparation === undefined ? {closePublicationOwnership: closeHostPublicationOwnership} : {}),
    observation, ownerViews,
    ...(preparation === undefined ? {} : {initialControl: preparation.initialControl}),
    dispatchOwner, inspectAcquisition, sourceProfile, installedEffect,
    retireTerminalEffects,
    stopModelRuntime() { modelRuntimeClosing = true; }, retireModelRuntime});
  } catch (cause) {
    diagnostic?.close();
    effectEvidenceKey?.key.fill(0);
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, closeJournal: closeHostRequestJournal, store, checkpoints: runAcceptance, dispatchOwner,
        sourceProfile, installedEffect, observation, ownerViews,
        closeInitializationJournal: publicationOpeningFailure !== undefined && publicationOpeningFailure.cause === cause
          ? closeHostRequestJournal : undefined,
        publicationOwnership: preparation === undefined ? {close: closeHostPublicationOwnership} : undefined});
  }
    };
    const activate = () => {
      if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
      if (activationFlight === undefined) {
        // One actual Host and one optional service construction. Publish the
        // flight before any fallible constructor; retain its original failure
        // and cleanup rather than trying another Store/key/Host on retry.
        activationFlight = Promise.resolve().then(initializePublicationServices)
          .catch(cause => {
            activationFailure = {cause,cleanupObserved:false,statusObserved:false,retryObserved:false};
            modelRuntimeClosing = true;
            // Retain successful observations as soon as the original failure
            // is owned, before another continuation or the first shutdown can
            // replace them. A failed getter has supplied no observation and
            // remains retryable under this same holding, never a new owner.
            try {
              activationFailure.cleanup = cause?.cleanupHandle;
              activationFailure.cleanupObserved = true;
            } catch { /* The same failed initializer still owns this duty. */ }
            if (activationFailure.cleanupObserved) {
              try {
                activationFailure.status = activationFailure.cleanup?.status;
                activationFailure.statusObserved = true;
              } catch { /* Retry only the still-unobserved getter at shutdown. */ }
              try {
                activationFailure.retry = activationFailure.cleanup?.retry;
                activationFailure.retryObserved = true;
              } catch { /* Status failure cannot discard another observed method. */ }
            }
            throw cause;
          });
      }
      return activationFlight;
    };
    // Local retains its deferred services. Remote preserves its existing
    // eager construction, now under the SAME selected preparation owner.
    if (preparation === undefined || mode === 'remote') return await activate();
    const bootstrapIngress = createNodeInProcessClientHost({
      authenticate: () => principalId,
      authorizeConnection: hostConnection,
      workspaceForPrincipal: () => workspaceId,
      negotiate, maxRowBytes: 1024 * 1024, observe: diagnostic,
      bindOwnedRequest: originalRequestPreparation === undefined ? undefined :
        (parent,derived) => preparation.bindSourceRequest(parent,derived),
      async performInstalledRequest(operation,request,signal) {
        const opened = await activate();
        if (opened !== host) throw clientOperationError('InstalledHostPreparationChanged');
        if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
        preparation.beforeResultPublicationOperation(operation);
        const result = await opened.port.perform(operation,request,signal);
        preparation.assertResultPublicationCurrent();
        return result;
      },
    });
    const bootstrapPort = Object.freeze({
      ...(originalRequestPreparation === undefined ? {} :
        {[sourcePreparationPort]: originalRequestPreparation}),
      ...(originalSourcePreparation === undefined ? {} : {
        async answerCheckpoint(summary, decision, signal) {
          if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
          const opened = await activate();
          if (opened !== host || modelRuntimeClosing ||
              typeof opened.port.answerCheckpoint !== 'function') {
            throw clientOperationError('CheckpointSignerUnavailable');
          }
          return Reflect.apply(opened.port.answerCheckpoint, opened.port, [summary, decision, signal]);
        },
      }),
      async perform(operation, request, signal) {
        if (modelRuntimeClosing) throw clientOperationError('ClientHostClosing');
        return bootstrapIngress.perform(operation,request,signal);
      },
    });
    return Object.assign(host, {port:bootstrapPort,journal,sourceProfile,installedEffect,
      closeRequestJournal: closeHostRequestJournal,
      diagnostic,observation,initialControl:preparation.initialControl,
      stopModelRuntime() { modelRuntimeClosing = true; },retireModelRuntime,
      async prepareShutdown() {
        // Stop new work, then observe the SAME already-started activation to
        // terminal. Never interrupt a child or treat its Promise as an ACK.
        modelRuntimeClosing = true;
        if (activationFlight !== undefined) {
          try { await activationFlight; }
          catch {
            const cause = activationFailure.cause;
            // Retain each successfully observed callback and its receiver.
            // Only a getter that has not produced an observation may be
            // observed again; later replacement cannot ACK this failure.
            if (!activationFailure.cleanupObserved) {
              activationFailure.cleanup = cause?.cleanupHandle;
              activationFailure.cleanupObserved = true;
            }
            const cleanup = activationFailure.cleanup;
            if (!activationFailure.statusObserved) {
              activationFailure.status = cleanup?.status;
              activationFailure.statusObserved = true;
            }
            if (!activationFailure.retryObserved) {
              activationFailure.retry = cleanup?.retry;
              activationFailure.retryObserved = true;
            }
            const status = activationFailure.status, retry = activationFailure.retry;
            if (typeof status !== 'function' || typeof retry !== 'function') throw cause;
            if (Reflect.apply(status,cleanup,[])?.pending !== false) {
              await Reflect.apply(retry,cleanup,[]);
            }
            if (Reflect.apply(status,cleanup,[])?.pending !== false) throw cause;
          }
        }
        for (const recovered of localSigningRecoveries) await releaseLocalSigningRecovery(recovered);
      },
      closePublicationStore() {
        // No Store exists before activation. An acquired or partially opened
        // Store remains with its original initialization/physical cleanup.
        if (store !== undefined) return store.close();
      },
    });
  } catch (cause) {
    // The optional initializer already retained/attempted these exact child
    // duties. Do not add another close of the same Journal/Store here.
    if (activationFlight !== undefined) throw cause;
    diagnostic?.close();
    effectEvidenceKey?.key.fill(0);
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, closeJournal: closeHostRequestJournal, store, checkpoints: runAcceptance, dispatchOwner,
        sourceProfile, installedEffect, observation, ownerViews,
        publicationOwnership: preparation === undefined ? {close: closeHostPublicationOwnership} : undefined});
  }
  } catch (cause) {
    modelRuntimeClosing = true;
    // Retain the same original failure/child and Host reference finalizer,
    // including readonly exceptions and partial nominal retirement.
    // The original initializer (including its pending physical child) closes
    // first, then the same installation control, then runtime references.
    if (preparation === undefined) {
      throw retainInstalledHostRuntimeFailure(cause, retireModelRuntime);
    }
    const failure = await retainInstalledHostInitializationFailure(cause,
      {initialControl: preparation.initialControl});
    const retained = retainInstalledHostRuntimeFailure(failure, retireModelRuntime);
    // Use the owned carrier through finalization, not the original exception's
    // potentially effectful cleanup getters. Only completed duties expose it.
    if (retained === failure && failure.cleanupHandle.status().pending === false) throw cause;
    throw retained;
  }
}

// This HTTP ingress uses the installed Host's common owner and physical
// services. Embedded Local continues to use the in-process port above.
//
// `authorization` installs Run-acceptance protection for the Host's Site:
// {accountConfig | accountConfiguration, reviewers: [{keyId, reviewerId,
// principalId, publicKey}], reviewReaders: [principal], hostKey: {keyId,
// privateKey}, siteKey?, decide?, answeringAuthorities?, checkpointTtlMs?,
// leaseMs?, maxReviewBytes?, resumeAfterAnswer?, sweepPage?, observe?,
// faultInjection?}.
// Approved requests are resumed at Host start and, unless
// `resumeAfterAnswer` is false, after an answer is stored; each sweep step
// handles at most `sweepPage` items and continues until none remain.
// `observe(step, detail)` is bounded best-effort diagnostics and cannot stop
// execution. `faultInjection(step, detail)` is an explicit awaited test hook;
// `beforeDispatch` remains a required execution barrier. Without a
// configuration the Missing account denies every request; nothing allows it.
export function openInstalledRemoteHttpHost(options) {
  return openPreparedInstalledHost(options, 'remote');
}

function installedRemoteHttpTransport(host, {authenticate, loopbackHttp}, shutdown, prepareRequest) {
  const handle = createClientHttpHandler({
    ...host.hostOperations, authenticate, maxRequestBytes: 65536, loopbackHttp, prepareRequest,
  });
  // A request's handling can outlive its response: a Result read records
  // its delivery attempt after the last bytes are sent. Close waits for
  // every request still being handled; once closing, new requests are
  // refused before they touch the Store.
  const handling = new Set();
  let closing = false;
  return Object.freeze({
    handler(request, response) {
      if (closing) {
        response.writeHead(503, {'content-type': 'application/json'});
        response.end(JSON.stringify({code: 'ClientHostClosing'}));
        return Promise.resolve();
      }
      const handled = Promise.resolve(host.observation === undefined
        ? handle(request, response) : host.observation.run('http',
          observationTraceParent(request.headers), () => handle(request, response),
          {http: {method: request.method, response}}));
      handling.add(handled);
      handled.finally(() => handling.delete(handled)).catch(() => {});
      return handled;
    },
    inspectAcquisition: host.inspectAcquisition,
    observationStatus: () => host.observation?.status(),
    // Stop accepting requests and wait for those being handled, stop
    // starting resumes, let running dispatches finish and record their
    // ends, settle retention, then release the journals and the Store
    // owner. Returns what remains for the next owner instead of hiding it.
    async close() {
      closing = true;
      while (handling.size > 0) {
        await Promise.allSettled([...handling]);
      }
      const result = await shutdown.close();
      // Failed shutdown still owns retryable physical cleanup. Keep its
      // bounded observation alive until those owners confirm final release.
      return Object.freeze({...result,
        diagnosticDeliveryPending: host.diagnostic.status().active !== 0});
    },
  });
}

function localPublicationStoreAuthorityCid(root, principalId) {
  return cid({version: 'actql-local-store-owner/0.1', root, principalId});
}

function localPublicationStoreOptions(root, storeAuthorityCid, privateEvidenceKey) {
  return {
    directory: join(root, 'publication'), storeAuthorityCid,
    capacityBytes: 512 * 1024 * 1024,
    maxObjectBytes: localOutputLimits.maxWireBytes,
    // A JSON value node occupies at least one byte in the selected wire.
    // This is parser support, not an additional memory/resource grant.
    maxObjects: 10000, maxContractNodes: localOutputLimits.maxWireBytes,
    maxContractDepth: 64, privateEvidenceKey,
  };
}

// Publishing is an explicit pre-start operation. Keep its actual first Root
// admission through key creation and Store adoption, instead of leaving a
// marker that makes the later Host look like an existing, keyless installation.
// These existing owners grant no Run, Site, request or provider operation.
async function preparePublicationRoot(root, principalId) {
  const host = {};
  const originals = {host, installation: {root}, generation: host,
    supplier: preparePublicationRoot, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(originals);
  const closeJournal = originalInitialControlClose(journal);
  let result, closeResult;
  async function closeServices() {
    if (closeResult !== undefined) await closeResult();
    await closeJournal();
  }
  try {
    const rootCreation = await journal.admitRootFormat(root);
    if (rootCreation === 'new') {
      await prepareOrdinaryLocalAccount({root, principal: principalId,
        preparedOriginal: journal.privateEvidenceInitializationOwnership(), rootCreation});
    }
    journal.assertInitializationCurrent();
    const moon = await import(runtimeUrl.href);
    const control = runtimeCore(moon).publicationControl;
    const storeAuthorityCid = localPublicationStoreAuthorityCid(root, principalId);
    result = prepareOrdinaryHostResult(originals, Object.freeze({root, storeAuthorityCid, control}),
      readHostResultPublicationRunRequirements, readHostEffectResultPublicationRunRequirements);
    closeResult = originalInitialControlClose(result);
    await result.initialize();
    await result.openStore(localPublicationStoreOptions(root, storeAuthorityCid), control);
    await closeServices();
    return moon;
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause, {journal, closeJournal: closeServices});
  }
}

// Publish the installed source's declaration for a Host state directory
// (the embedded Local Host's by default) from its source profile
// (`ACTQL_LOCAL_SOURCE_PROFILE` by default). This is the explicit step a Host
// start restores without provider I/O.
export async function publishInstalledSource({sourceProfilePath, directory,
  resolveSourceSecret, signal, connectorTable} = {}) {
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  const principalId = userInfo().username;
  const moon = await preparePublicationRoot(root, principalId);
  return publishInstalledSourceProfile(
    sourceProfilePath ?? process.env.ACTQL_LOCAL_SOURCE_PROFILE, {root,
      principalId, moon, runtimeUrl,
      resolveSecret: resolveSourceSecret, signal, connectorTable});
}

// Publish the installed Effect's generation (its declaration, execution
// Mappings and Check Environment) for a Host state directory (the embedded
// Local Host's by default) from its Effect profile
// (`ACTQL_LOCAL_EFFECT_PROFILE` by default). This is the explicit step a Host
// start restores without provider I/O.
export async function publishInstalledEffect({effectProfilePath, directory,
  resolveEffectSecret, signal, hostCapacityPolicy, hostLookupExecutionPolicy, connectorTable} = {}) {
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
  hostLookupExecutionPolicy = snapshotHostLookupExecutionPolicy(hostLookupExecutionPolicy);
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  const principalId = userInfo().username;
  const moon = await preparePublicationRoot(root, principalId);
  const baseEnvironmentWire = selectInstalledHostEnvironment(moon, (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd(), hostCapacityPolicy,
    hostLookupExecutionPolicy);
  return publishInstalledEffectProfile(
    effectProfilePath ?? process.env.ACTQL_LOCAL_EFFECT_PROFILE, {root,
      principalId, moon, runtimeUrl,
      baseEnvironmentWire, resolveSecret: resolveEffectSecret, signal, connectorTable});
}

// Only the actual early startup captures this operation. It admits the selected
// raw Local connect/open input before invoking this receiver. This operation
// alone cannot manufacture that admission or inspect the caller's packet.
export function connectInitialControlHostPreparation(kind, rawInput) {
  if (kind === 'connect') return connectEmbeddedLocal(rawInput, 'connect');
  if (kind !== 'open') {
    throw clientOperationError('NodeInitialControlInputUnavailable');
  }
  return connectEmbeddedLocal(rawInput, 'open');
}

export function connectEmbeddedLocal(options, initialEntry) {
  return openPreparedInstalledHost(options, initialEntry);
}

// The same original Host, prior control and preparation bundle serve Local and
// Remote entry. Only Local discovers a Project or leases an in-process Client.
async function openPreparedInstalledHost(options, initialEntry) {
  // The actual Host generation and original installation are allocated here,
  // not reconstructed from a later view, Project DATA or current config. Their
  // minimal candidate record belongs to the selected prior startup envelope.
  const host = {};
  let originalInstallation = {};
  let originals = Object.freeze({host, installation: originalInstallation,
    generation: host, supplier: openPreparedInstalledHost, moduleLifetime: import.meta});
  profiles.registerPreparation(host, originalInstallation, host);
  let control, controlClose, duty, observedClose, referenceRetirement;
  let moon, project, projectProfile, mockPreparation, projectSourcePreparation, sourceManaged, sourceManagedClose;
  let computeManaged, computeManagedClose, computeManagedFlight;
  let resultPublication, resultPublicationClose, resultPublicationFlight;
  let hostJournal, hostJournalClose, hostJournalOpen, hostJournalOwnership, hostJournalFlight;
  let hostJournalAdmitRootFormat;
  let hostJournalOpenAttempted = false;
  let mockAnswers, mockModelProfile, mockModelProfileRetire, mockModelFlight;
  let adopted = false, referencesRetired = false;
  let hostInitialization, sourceInitializationServices, sourceInitializationSelection;
  const record = {};
  function assertSourceInitializationSelection() {
    const selection = sourceInitializationSelection;
    if (selection === undefined) return;
    if (selection.runtime !== moon || selection.root !== originalInstallation.root ||
        project !== undefined &&
          installedProjectOriginalsForRuntime(project, moon) !== selection.projectOriginal) {
      throw clientOperationError('ForeignInstalledSourceInitialization');
    }
    if (selection.hostCurrent !== undefined) selection.hostCurrent();
  }
  function retirePreparationReferences() {
    if (referencesRetired) return;
    // The Root can fail after its fixed callback retained a view but before
    // returning the Source installation to this caller. That same candidate
    // still owns its semantic references; do not abandon it on this path.
    const retainedMock = profiles.retainedMockPreparation(host, originalInstallation, host);
    (mockPreparation ?? retainedMock?.view)?.retire(moon);
    projectSourcePreparation?.retire(moon);
    // The Model owner can decline retirement while the original execution
    // still uses these answers. Keep every original and callback on failure;
    // Source, Journal, Promise settlement and process exit cannot ACK it.
    mockAnswers?.retire(moon);
    if (mockModelProfile !== undefined) {
      if (Reflect.apply(mockModelProfileRetire, moon, [mockModelProfile]) !== true) {
        throw clientOperationError('InstalledMockModelCleanupPending');
      }
      mockModelProfile = mockModelProfileRetire = undefined;
    }
    mockAnswers = mockModelFlight = undefined;
    if (referenceRetirement !== undefined) referenceRetirement();
    else {
      projectProfile?.retire(moon);
      if (project !== undefined) retireInstalledProjectConfiguration(project, moon);
    }
    mockPreparation = projectSourcePreparation = projectProfile = project = moon = referenceRetirement = undefined;
    for (const key of Object.keys(record)) record[key] = undefined;
    // This private installation bag holds backreferences, not canonical DATA.
    // Its opaque identity remains the same for the original cleanup pair.
    for (const key of Object.keys(originalInstallation)) originalInstallation[key] = undefined;
    duty?.releaseReferences(record);
    referencesRetired = true;
  }
  const initialControl = Object.freeze({async close() {
    if (observedClose !== undefined) return observedClose;
    record.retireUndispatched?.();
    // Dispatch has stopped its actual computation/Effect children. Capture
    // decode custody still needs the original Store open for failed schemas
    // and retained result owners, and SAME live Run capacity before its parent
    // can retire. Never close Store/Journal first to manufacture their ACK.
    for (const run of record.computeLiveRuns ?? []) {
      if (run.preparationKind !== 'effect-capture-recovery' || run.closed) continue;
      if (run.selecting || run.resources === undefined || await run.resources.close() !== true) {
        throw clientOperationError('EffectCaptureResourceCleanupPending');
      }
    }
    for (const run of record.computeLiveRuns ?? []) {
      if (run.preparationKind === 'effect-capture-recovery') continue;
      if (run.contentCleanup !== undefined) {
        if (await run.contentCleanup.close() !== true || run.contentCleanup.cleanupPending()) {
          throw clientOperationError('InstalledContentPhysicalCleanupPending');
        }
      }
      if (run.finishRetirement !== undefined) {run.finishRetirement(); continue;}
      if (run.closed) continue;
      if (run.preparationKind === 'model-plan' || run.preparationKind === 'serialization-plan' ||
          run.preparationKind === 'keyed-content-plan' ||
          run.preparationKind === 'effect-plan' && (run.preparationFunded || run.requestInput !== undefined)) {
        const finish = preparation.retireManagedComputeRun(run.prepared);
        finish?.();
        continue;
      }
      // Dispatch has closed its actual children before this initial duty.
      // Source-free Runs on either joint Source/Compute or Compute-only
      // installations retire before their same parent service can close.
      finishInstalledEffectModelScope(run, true, checked);
      if (run.value !== undefined) checked(Reflect.apply(run.retire, run.runtime, [run.value]));
      else if (run.admission !== undefined) checked(Reflect.apply(run.cleanup, run.runtime, [run.admission]));
      run.closed = true;
      run.preAdmissionRefusal = undefined;
    }
    if (sourceManaged !== undefined) {
      const observation = await Reflect.apply(sourceManagedClose, sourceManaged, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        throw clientOperationError('InstalledSourcePreparationCleanupPending');
      }
      sourceManaged = sourceManagedClose = undefined;
    }
    if (computeManaged !== undefined) {
      // The acquired original survives a failed first callback observation.
      // An observed close is captured once and cannot be replaced during
      // another child's await. Closing the Journal is not this child's ACK.
      computeManagedClose ??= computeManaged.close;
      if (typeof computeManagedClose !== 'function') {
        throw clientOperationError('InstalledComputePreparationCleanupPending');
      }
      const observation = await Reflect.apply(computeManagedClose, computeManaged, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        throw clientOperationError('InstalledComputePreparationCleanupPending');
      }
      computeManaged = computeManagedClose = computeManagedFlight = undefined;
      record.computeManaged = undefined;
    }
    if (resultPublication !== undefined) {
      resultPublicationClose ??= resultPublication.close;
      if (typeof resultPublicationClose !== 'function') {
        throw clientOperationError('HostResultPublicationCleanupPending');
      }
      const observation = await Reflect.apply(resultPublicationClose, resultPublication, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        throw clientOperationError('HostResultPublicationCleanupPending');
      }
      resultPublication = resultPublicationClose = resultPublicationFlight = undefined;
      record.resultPublication = undefined;
    }
    if (hostJournal !== undefined) {
      // Capture a successfully observed callback/receiver once, before the
      // first invocation. An unobserved getter failure retains the original
      // holding and may be observed again by this same cleanup duty.
      hostJournalClose ??= hostJournal.close;
      if (typeof hostJournalClose !== 'function') {
        throw clientOperationError('HostJournalInstallationCleanupPending');
      }
      const observation = await Reflect.apply(hostJournalClose, hostJournal, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        throw clientOperationError('HostJournalInstallationCleanupPending');
      }
      hostJournal = hostJournalClose = hostJournalOpen = hostJournalOwnership = undefined;
      hostJournalAdmitRootFormat = undefined;
      hostJournalFlight = undefined;
      record.hostJournal = undefined;
    }
    // Unconstructed declaration/Mapping contexts still belong to this SAME
    // initial Source material. Failure retirement ends their constructor duty,
    // never reports a metadata holder as a successfully installed adapter.
    await originalInstallation.declaredFileInstallationInventory?.fail(
      clientOperationError('DeclaredFileInstallationClosed'));
    if (hostInitialization !== undefined) {
      if (sourceInitializationServices !== undefined &&
          retireInstalledSourceInitialization(sourceInitializationServices) !== true) {
        throw clientOperationError('InstalledSourceInitializationCleanupPending');
      }
      sourceInitializationServices = record.sourceInitializationServices = undefined;
      // Source close above must settle the SAME domain/borrow inventory. The
      // Core carrier refuses a still-live selected token, including zero bytes.
      closeHostInitializationPreparation(hostInitialization);
      hostInitialization = record.hostInitialization = undefined;
      sourceInitializationSelection = record.sourceInitializationSelection = undefined;
    }
    retirePreparationReferences();
    const observed = await Reflect.apply(controlClose, control, []);
    if (observed?.pending === false) {
      if (observedClose !== undefined) return observedClose;
      if (!adopted) profiles.retirePreparation(host, originalInstallation, host);
      // Retain the actual original observation, not a newly authored ACK.
      observedClose = observed;
      control = controlClose = originals = duty = undefined;
      originalInstallation = undefined;
    }
    return observed;
  }});
  function prepareEffectCaptureFrame(runtime, request, definition, limits, managed, originalCurrent, retain, assertHost) {
    assertHost(originals);
    if (runtime !== moon || typeof originalCurrent !== 'function' || typeof retain !== 'function') {
      throw clientOperationError('EffectRecoveryResourcesUnavailable');
    }
    const liveRuns = record.computeLiveRuns ??= new Set();
    if (liveRuns.size >= 4096) throw clientOperationError('InstalledComputeRunLimit');
    if (managed !== undefined && (record.computeRuns?.get(managed.prepared) !== managed ||
        !liveRuns.has(managed) || managed.runtime !== runtime || managed.closed ||
        runtime.clientRequestRelation(request, managed.request) !== 1 ||
        runtime.strategyPublicationContractIdentity(managed.definitionOriginal?.definition) !== definition.identity)) {
      throw clientOperationError('ForeignInstalledEffectManagedRun');
    }
    const managedParent = managed?.value, managedPrepared = managed?.prepared;
    const managedRequest = managed?.request, managedDefinition = managed?.definitionOriginal?.definition;
    const entry = {preparationKind:'effect-capture-recovery', resources:undefined,
      selecting:true, closed:false};
    liveRuns.add(entry);
    const current = () => {
      assertHost(originals);
      originalCurrent();
      if (record.computeLiveRuns !== liveRuns || !liveRuns.has(entry) || entry.closed) {
        throw clientOperationError('ForeignEffectCaptureResources');
      }
      if (managed !== undefined && (preparation.effectManagedPlanRun(runtime,
          managedPrepared, managedRequest) !== managed || managed.value !== managedParent ||
          managed.prepared !== managedPrepared || managed.request !== managedRequest ||
          managed.definitionOriginal?.definition !== managedDefinition)) {
        throw clientOperationError('ForeignInstalledEffectManagedRun');
      }
    };
    try {
      return prepareEffectCaptureResources({moon:runtime,
        control:runtimeCore(runtime).publicationControl, request, runDefinition:definition,
        contractLimits:limits, managed, assertCurrent:current,
        retain(view) {entry.resources = view; retain(view);},
        retired:retireEffectCaptureResourceFrame.bind(undefined, record, liveRuns, entry)});
    } finally {entry.selecting = false;}
  }
  const preparation = Object.freeze({host, initialControl,
    sourceInitializationServices(runtime, root, principalId, hostCurrent) {
      assertInitialControlHostPreparation(originals);
      if (runtime !== moon || record.runtime !== runtime || root !== originalInstallation.root ||
          typeof principalId !== 'string' || !principalId ||
          hostCurrent !== undefined && typeof hostCurrent !== 'function') {
        throw clientOperationError('ForeignInstalledSourceInitialization');
      }
      if (sourceInitializationSelection === undefined) {
        // Retain the actual tuple before parent/current callbacks. The first
        // identity read and later Source loaders borrow this SAME service.
        sourceInitializationSelection = {runtime, root, principalId,
          projectOriginal: project === undefined ? undefined :
            installedProjectOriginalsForRuntime(project, runtime), hostCurrent};
        record.sourceInitializationSelection = sourceInitializationSelection;
        const initialPreparation = preparation.hostInitializationPreparation(runtime);
        sourceInitializationServices = createInstalledHostServices({root, principalId,
          moon: runtime, initialPreparation, assertCurrent() {
            assertInitialControlInstallationCurrent(control, originals);
            assertSourceInitializationSelection();
          }});
        record.sourceInitializationServices = sourceInitializationServices;
      } else {
        const selection = sourceInitializationSelection;
        if (selection.principalId !== principalId || selection.root !== root ||
            selection.runtime !== runtime || sourceInitializationServices === undefined ||
            hostCurrent !== undefined && selection.hostCurrent !== undefined &&
              selection.hostCurrent !== hostCurrent) {
          throw clientOperationError('ForeignInstalledSourceInitialization');
        }
        if (hostCurrent !== undefined) selection.hostCurrent = hostCurrent;
        assertInitialControlInstallationCurrent(control, originals);
        assertSourceInitializationSelection();
      }
      return sourceInitializationServices;
    },
    borrowSourceInitializationMaterial() {
      assertInitialControlHostPreparation(originals);
      if (sourceInitializationServices === undefined) return undefined;
      const context = originalInstallation.closedValuesPreparationContext;
      if (context === undefined) throw clientOperationError('InstalledSourceInitializationPending');
      return borrowInstalledSourceInitialization(sourceInitializationServices,
        originalInstallation, context.preparedEnvironment);
    },
    hostInitializationPreparation(runtime) {
      assertInitialControlHostPreparation(originals);
      if (runtime !== moon || record.runtime !== runtime) {
        throw clientOperationError('ForeignInstalledHostPreparation');
      }
      if (hostInitialization !== undefined) {
        if (hostInitialization.parent === undefined) {
          throw clientOperationError('InstalledHostPreparationChanged');
        }
        return hostInitialization.parent;
      }
      // Retain before the actual Resource/start/reservation constructors.
      // Failure keeps this original state for the same initial close duty.
      hostInitialization = {};
      record.hostInitialization = hostInitialization;
      return openHostInitializationPreparation(hostInitialization, runtime,
        originalInstallation,
        () => {
          assertInitialControlInstallationCurrent(control, originals);
          assertSourceInitializationSelection();
        },
        () => sourceManaged !== undefined);
    },
    retainHostJournalPreparation(root, principalId, journalDirectory) {
      assertInitialControlHostPreparation(originals);
      if (root !== originalInstallation.root || typeof principalId !== 'string' ||
          !principalId || journalDirectory !== join(root, 'requests')) {
        throw clientOperationError('InstalledHostPreparationChanged');
      }
      const view = Object.freeze({root, principalId, journalDirectory,
        assertCurrent() {
          assertInitialControlHostPreparation(originals);
          if (this !== view || originalInstallation.root !== root ||
              profiles.hostJournalPreparation(host, originalInstallation, host) !== view) {
            throw clientOperationError('InstalledHostPreparationChanged');
          }
        }});
      profiles.retainHostJournalPreparation(host, originalInstallation, host, view);
      view.assertCurrent();
    },
    prepareHostJournal() {
      assertInitialControlHostPreparation(originals);
      if (hostJournalFlight !== undefined) return hostJournalFlight;
      // Install the single flight before invoking the fallible supplier. A
      // partial failure remains the same owned carrier, never a replacement
      // facility or another initialization attempt.
      hostJournalFlight = Promise.resolve().then(async () => {
        const original = await prepareHostJournalInstallation(originals);
        if (original === undefined || original === null) {
          throw clientOperationError('HostJournalInstallationUnavailable');
        }
        hostJournal = original;
        record.hostJournal = original;
        hostJournalClose = original.close;
        if (typeof hostJournalClose !== 'function') {
          throw clientOperationError('HostJournalInstallationCleanupPending');
        }
        hostJournalOpen = original.openRequestJournal;
        hostJournalOwnership = original.publicationOwnership;
        hostJournalAdmitRootFormat = original.admitRootFormat;
        const current = original.assertCurrent;
        if (typeof current !== 'function') {
          throw clientOperationError('HostJournalPreparationUnavailable');
        }
        Reflect.apply(current, original, []);
        assertInitialControlHostPreparation(originals);
        return original;
      });
      return hostJournalFlight;
    },
    admitRootFormat(root) {
      assertInitialControlHostPreparation(originals);
      if (hostJournal === undefined || typeof hostJournalAdmitRootFormat !== 'function') {
        throw clientOperationError('HostJournalPreparationUnavailable');
      }
      return Reflect.apply(hostJournalAdmitRootFormat, hostJournal, [root]);
    },
    openRequestJournal(directory, options) {
      assertInitialControlHostPreparation(originals);
      if (hostJournalOpenAttempted || hostJournal === undefined ||
          typeof hostJournalOpen !== 'function') {
        throw clientOperationError('HostJournalPreparationUnavailable');
      }
      // Mark the same physical attempt before invoking the captured receiver.
      // A throw may retain a partial native child; no replacement is issued.
      hostJournalOpenAttempted = true;
      return Reflect.apply(hostJournalOpen, hostJournal, [directory, options]);
    },
    publicationOwnership() {
      assertInitialControlHostPreparation(originals);
      if (hostJournal === undefined || typeof hostJournalOwnership !== 'function') {
        throw clientOperationError('HostJournalPreparationUnavailable');
      }
      return Reflect.apply(hostJournalOwnership, hostJournal, []);
    },
    prepareResultPublication() {
      assertInitialControlHostPreparation(originals);
      if (resultPublicationFlight !== undefined) return resultPublicationFlight;
      resultPublicationFlight = Promise.resolve().then(async () => {
        const original = await prepareHostResultPublicationInstallation(originals);
        if (original === undefined || original === null) throw clientOperationError('HostResultPublicationUnavailable');
        resultPublication = original;
        record.resultPublication = original;
        resultPublicationClose = original.close;
        if (typeof resultPublicationClose !== 'function') throw clientOperationError('HostResultPublicationCleanupPending');
        original.assertCurrent();
        assertInitialControlHostPreparation(originals);
        return original;
      });
      return resultPublicationFlight;
    },
    assertResultPublicationCurrent() {
      if (resultPublication === undefined) throw clientOperationError('HostResultPublicationUnavailable');
      resultPublication.assertCurrent();
    },
    beforeResultPublicationOperation(operation) {
      if (resultPublication === undefined) throw clientOperationError('HostResultPublicationUnavailable');
      resultPublication.beforeOperation(operation);
    },
    openResultPublicationStore(options, control) {
      if (resultPublication === undefined) throw clientOperationError('HostResultPublicationUnavailable');
      return resultPublication.openStore(options, control);
    },
    admitResultPublicationRun(prepared) {
      if (resultPublication === undefined) throw clientOperationError('HostResultPublicationUnavailable');
      resultPublication.admitRun(prepared);
    },
    admitEffectResultPublicationRun(prepared) {
      if (resultPublication === undefined || typeof resultPublication.admitEffectRun !== 'function') {
        throw clientOperationError('HostEffectResultPublicationUnavailable');
      }
      resultPublication.admitEffectRun(prepared);
    },
    assertContentRunCurrent() {
      assertInitialControlHostPreparation(originals);
      // This is the existing ordinary factory's actual Journal/Store, not
      // initial/preload provenance or another purpose's resource credit.
      ordinaryHostJournalInstallation(originals).assertCurrent();
      if (resultPublication === undefined) throw clientOperationError('HostResultPublicationUnavailable');
      resultPublication.assertContentCurrent();
    },
    modelPublicationCapacity(prepared) {
      if (resultPublication === undefined || typeof resultPublication.modelPublicationCapacity !== 'function') {
        throw clientOperationError('HostResultPublicationUnavailable');
      }
      return resultPublication.modelPublicationCapacity(prepared);
    },
    bindSourceRequest(parent, derived) {
      if (sourceManaged !== undefined) {
        assertSourceManagedInstallationCurrent(sourceManaged, originals);
      } else if (computeManaged !== undefined) {
        assertManagedComputeInstallationCurrent(computeManaged, originals);
      } else return;
      profiles.bindSourceRequest(host, originalInstallation, host, parent, derived);
    },
    prepareManagedCompute() {
      assertInitialControlHostPreparation(originals);
      if (mockPreparation !== undefined || projectSourcePreparation !== undefined) {
        throw clientOperationError('ForeignInstalledComputePreparation');
      }
      if (computeManagedFlight !== undefined) return computeManagedFlight;
      // The real Host calls only after its original Journal opens. A failed
      // factory/partial carrier stays on this same flight; no replacement.
      computeManagedFlight = Promise.resolve().then(async () => {
        const original = await prepareManagedComputeInstallation(originals);
        if (original === undefined || original === null) {
          throw clientOperationError('NodeManagedRunAdmissionUnavailable');
        }
        computeManaged = original;
        record.computeManaged = original;
        computeManagedClose = original.close;
        if (typeof computeManagedClose !== 'function') {
          throw clientOperationError('InstalledComputePreparationCleanupPending');
        }
        assertManagedComputeInstallationCurrent(original, originals);
        assertInitialControlHostPreparation(originals);
        return original;
      });
      return computeManagedFlight;
    },
    requestPreparation() {
      // Reuse the one private SDK lineage protocol, not Source authority.
      // Source installation/model selection below remains a separate entry.
      if (sourceManaged !== undefined) {
        assertSourceManagedInstallationCurrent(sourceManaged, originals);
        return sourceManaged;
      }
      if (computeManaged === undefined) throw clientOperationError('NodeManagedRunAdmissionUnavailable');
      assertManagedComputeInstallationCurrent(computeManaged, originals);
      return computeManaged;
    },
    submittedIntentOriginal(request) {
      const manager = sourceManaged ?? computeManaged;
      if (manager === undefined) return undefined;
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.submittedIntentOriginal?.(originalSourceManagedHostRequest(originals, request));
    },
    retainModelRecoveryInput(runtime, request, identity, definition, assertCurrent, childrenPending) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.retainModelRecovery !== 'function') {
        throw clientOperationError('InstalledModelRecoveryPreparationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      let settled;
      const pending = new Promise(resolve => {settled = resolve;});
      profiles.retainRequest(host, originalInstallation, host, request, pending);
      let original, finished = false;
      const finishProducer = manager.finishSourceProducer;
      try {original = manager.retainModelRecovery(request, identity, definition, assertCurrent, childrenPending);}
      catch (cause) {settled(); throw cause;}
      return Object.freeze({finish(terminal) {
        if (finished) return;
        try {
          Reflect.apply(finishProducer, manager, [original.receipt, terminal]);
          finished = true;
        } finally {settled();}
      }});
    },
    restoreManagedModelOriginal(runtime, request, original, definition, identity, construct) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.restoreModelOriginal !== 'function') {
        throw clientOperationError('InstalledModelRecoveryPreparationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.restoreModelOriginal(originalSourceManagedHostRequest(originals, request),
        original, definition, identity, construct);
    },
    retainEffectRequestInput(runtime, request, intent, captured, materialWire) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.retainRequestInput !== 'function') {
        throw clientOperationError('InstalledEffectRequestPreparationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      let settled;
      const pending = new Promise(resolve => {settled = resolve;});
      profiles.retainRequest(host, originalInstallation, host, request, pending);
      let original, finished = false;
      const finishProducer = manager.finishSourceProducer;
      try {original = captured === undefined ? manager.retainRequestInput(request, intent, undefined, materialWire)
        : manager.retainRequestInput(request, undefined, captured);}
      catch (cause) {settled(); throw cause;}
      return Object.freeze({body: original.body,
        finish(terminal) {
          if (finished) return;
          try {
            Reflect.apply(finishProducer, manager, [original.receipt, terminal]);
            finished = true;
          } finally {
            // This ends only the actual pending Host call. Failed physical
            // cleanup remains with the same manager/producer bag, not an ACK.
            settled();
          }
        }});
    },
    retainedEffectManagedPlan(runtime, request, definition) {
      if (runtime !== moon) throw clientOperationError('ForeignInstalledEffectManagedRun');
      let selected;
      for (const run of record.computeLiveRuns ?? []) {
        if (run.preparationKind !== 'effect-plan' || run.closed || run.runtime !== runtime ||
            runtime.clientRequestRelation(run.request, request) !== 1) continue;
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        if (run.definitionOriginal?.definition === undefined ||
            runtime.strategyPublicationContractIdentity(run.definitionOriginal.definition) !== definition.identity ||
            selected !== undefined) throw clientOperationError('ForeignInstalledEffectManagedRun');
        selected = run;
      }
      if (selected === undefined) return undefined;
      const current = preparation.effectManagedPlanRun(runtime, selected.prepared, selected.request);
      if (current !== selected || selected.closed || !record.computeLiveRuns?.has(selected)) {
        throw clientOperationError('ForeignInstalledEffectManagedRun');
      }
      return current;
    },
    fundedPreparation(request, environment, originalVerifier, signal) {
      const manager = sourceManaged ?? computeManaged;
      if (manager === undefined) return undefined;
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.fundedPreparation(originalSourceManagedHostRequest(originals, request), environment,
        originalVerifier, signal);
    },
    observeOriginalCheckOutcome(request, failure, visit) {
      const manager = sourceManaged ?? computeManaged;
      if (manager === undefined) return undefined;
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.observeOriginalCheckOutcome?.(
        originalSourceManagedHostRequest(originals, request), failure, visit);
    },
    borrowManagedPreparation(prepared, request) {
      const manager = sourceManaged ?? computeManaged;
      if (manager === undefined) return undefined;
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.borrowPreparation?.(prepared, originalSourceManagedHostRequest(originals, request));
    },
    bindManagedSources(runtime, profile) {
      if (runtime !== moon || record.managedSourceProfile !== undefined) {
        throw clientOperationError('ForeignInstalledSourcePreparation');
      }
      const sources = profile?.sources ?? (profile === undefined ? [] : [profile]);
      if (sources.length === 0 || typeof profile.prepareManagedRun === 'function' ||
          !sources.every(source => typeof source.managedCaptureCapacity === 'function')) return profile;
      const selected = bindInstalledManagedSources(profile, prepared => {
        const run = record.computeRuns?.get(prepared);
        if (run === undefined || run.closed || run.runtime !== runtime ||
            run.prepared !== prepared || run.sourceProfile !== selected) {
          throw clientOperationError('ForeignInstalledSourcePreparation');
        }
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        if (run.value === undefined) throw clientOperationError('NodeManagedRunAdmissionUnavailable');
        const parent = run.value, request = run.request, kind = run.preparationKind;
        // The original Effect record carries a bound Plan getter, not a Pure
        // check. One current operation reads that SAME original tuple; no
        // independent check or Plan reconstruction precedes Source work.
        const effect = kind === 'effect-plan';
        const observe = effect ? run.readPlan : run.check;
        const plan = effect ? run.operationPlan : undefined;
        if (typeof observe !== 'function' || effect && plan === undefined) {
          throw clientOperationError('ForeignInstalledSourcePreparation');
        }
        const observed = checked(Reflect.apply(observe, runtime, [parent, prepared, request]));
        // The current callback can retire or replace this original Run.
        // Recheck before the Source can prepare or expose its capacity.
        if (record.computeRuns?.get(prepared) !== run || run.closed ||
            run.runtime !== runtime || run.prepared !== prepared || run.request !== request ||
            run.preparationKind !== kind || run.sourceProfile !== selected || run.value !== parent ||
            (effect ? observed !== plan || run.operationPlan !== plan || run.readPlan !== observe
              : run.check !== observe)) {
          throw clientOperationError('ForeignInstalledSourcePreparation');
        }
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        return parent;
      });
      record.managedSourceProfile = originalInstallation.managedSourceProfile = selected;
      return selected;
    },
    managesInstalledSources() {return record.managedSourceProfile !== undefined;},
    managedModelSourceCoordinates(runtime, prepared) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.modelSourceCoordinates !== 'function') {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      return manager.modelSourceCoordinates(prepared, originalSourceManagedHostRequest(originals, prepared));
    },
    selectManagedDomainSourceInput(runtime, prepared, identity, stage, sourceIndex) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.selectDomainSourceInput !== 'function') {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      return manager.selectDomainSourceInput(prepared,
        originalSourceManagedHostRequest(originals, prepared), identity, stage, sourceIndex);
    },
    prepareManagedSourceRun(runtime, prepared, request, sourceProfile, prepareInvocation) {
      if (sourceProfile === undefined || sourceProfile !== record.managedSourceProfile) {
        throw clientOperationError('ForeignInstalledSourcePreparation');
      }
      return preparation.prepareManagedComputeRun(runtime, prepared, request, sourceProfile, prepareInvocation);
    },
    prepareManagedEffectPlanRun(runtime, facts, selection, inputs, modelSelection, prepareContent) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined) throw clientOperationError('ForeignInstalledComputePreparation');
      const current = () => (sourceManaged === undefined
        ? assertManagedComputeInstallationCurrent : assertSourceManagedInstallationCurrent)(manager, originals);
      current();
      const runs = record.computeRuns ??= new WeakMap(), liveRuns = record.computeLiveRuns ??= new Set();
      originalInstallation.computeRuns = runs;
      const model = modelSelection === undefined ? undefined : runs.get(facts.prepared)?.model ??
        Object.freeze({kind: modelSelection.localMock === true ? 'local-mock' : 'installed-model',
          compiled: facts.modelCompiled, definition: facts.definition,
          occurrence: modelSelection.occurrence, graph: modelSelection.graph});
      const hasSources = runtime.clientProgramEffectAcquisitionCount(facts.prepared) !== 0;
      return prepareInstalledEffectManagedPlanRun({runs, liveRuns, runtime, manager,
        prepared: facts.prepared, request: facts.identity,
        requestInput: originalSourceManagedHostRequest(originals, facts.prepared),
        selection, facts, inputs: Object.freeze({...inputs,
          queryContract: hasSources ? readInitialControlInstallationAsset(control, originals, 'spec/contracts/actql-query-acquisition.json') : undefined,
          evidenceContract: hasSources ? readInitialControlInstallationAsset(control, originals, 'spec/contracts/actql-query-process-evidence.json') : undefined,
          installedContracts: prepareInstalledSequenceContractOriginal(originals).admission}),
        sourceProfile: inputs.sourceProfile, model, modelSelection,
        publicationControl: runtimeCore(runtime).publicationControl, prepareContent, assertCurrent: current, checked});
    },
    prepareEffectCaptureRecovery(runtime, request, definition, limits, managed, originalCurrent, retain) {
      return prepareEffectCaptureFrame(runtime, request, definition, limits, managed,
        originalCurrent, retain, assertInitialControlHostPreparation);
    },
    prepareEffectCaptureRetirement(runtime, request, definition, limits, originalCurrent, retain) {
      // Only the terminal cleanup caller selects this path for its existing
      // journal-owned Request/Definition. Closed ingress is not retirement of
      // that same Host generation; normal recovery still requires open ingress.
      return prepareEffectCaptureFrame(runtime, request, definition, limits, undefined,
        originalCurrent, retain, assertRetainedSourceManagedHost);
    },
    effectManagedRun(runtime, prepared, request) {
      return preparation.effectManagedPlanRun(runtime, prepared, request).value;
    },
    effectManagedPlanRun(runtime, prepared, request) {
      if (runtime !== moon) throw clientOperationError('ForeignInstalledEffectManagedRun');
      const manager = sourceManaged ?? computeManaged;
      if (manager === undefined) throw clientOperationError('InstalledEffectPlanUnavailable');
      const current = () => (sourceManaged === undefined
        ? assertManagedComputeInstallationCurrent : assertSourceManagedInstallationCurrent)(manager, originals);
      return readInstalledEffectManagedPlanRun({runs: record.computeRuns, liveRuns: record.computeLiveRuns,
        runtime, prepared, request, assertCurrent: current, checked});
    },
    retainManagedContentPreparation(runtime, prepared, contentPreparation) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || typeof manager?.retainContentPreparation !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      const releaseSelection = Object.getOwnPropertyDescriptor(originalInstallation,
        'releaseRequestDomainAliases')?.value;
      const field = Object.getOwnPropertyDescriptor(contentPreparation, 'releaseSelection');
      if (typeof releaseSelection !== 'function' || field?.writable !== true ||
          !Object.hasOwn(field, 'value') || field.value !== undefined) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      contentPreparation.releaseSelection = releaseSelection;
      return manager.retainContentPreparation(prepared,
        originalSourceManagedHostRequest(originals, prepared), contentPreparation);
    },
    prepareManagedKeyedContentRun(runtime, prepared, request, graph, recipe, constructPlan, contentPreparation) {
      const manager = sourceManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareKeyedContentRun !== 'function' ||
          record.managedSourceProfile === undefined || typeof constructPlan !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      assertSourceManagedInstallationCurrent(manager, originals);
      const runs = record.computeRuns ??= new WeakMap(), liveRuns = record.computeLiveRuns ??= new Set();
      originalInstallation.computeRuns = runs;
      const prior = runs.get(prepared);
      if (prior !== undefined) {
        if (Object.hasOwn(prior, 'failure')) throw prior.failure;
        if (prior.closed || prior.preparationKind !== 'keyed-content-plan' || prior.runtime !== runtime ||
            prior.request !== request || prior.manager !== manager || prior.contentGraph !== graph ||
            prior.contentRecipe !== recipe) throw clientOperationError('ForeignInstalledContentRun');
        checked(Reflect.apply(prior.check, runtime, [prior.value, prepared, request])); return prior;
      }
      if (liveRuns.size === 4096) throw clientOperationError('InstalledComputeRunLimit');
      const run = {runtime, prepared, request, manager, contentGraph: graph, contentRecipe: recipe,
        preparationKind: 'keyed-content-plan', original: undefined, value: undefined,
        selectedKeyed: undefined, contentCompilation: undefined, closed: false, selecting: true};
      if (contentPreparation?.prepared !== prepared || contentPreparation.inputHolder === undefined ||
          typeof Object.getOwnPropertyDescriptor(contentPreparation, 'releaseAliases')?.value !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      run.contentPreparation = contentPreparation;
      run.releaseContentAliases = contentPreparation.releaseAliases;
      contentPreparation.managed = run;
      if (contentPreparation.localPreparation !== undefined) contentPreparation.localPreparation.hostRun = run;
      runs.set(prepared, run); liveRuns.add(run);
      try {
        run.retire = runtime.clientProgramInstalledManagedRunRetire;
        run.check = runtime.clientProgramInstalledManagedRunCheck;
        if (![run.retire, run.check].every(method => typeof method === 'function')) {
          throw clientOperationError('NodeManagedRunRuntimeUnavailable');
        }
        const control = runtimeCore(runtime).publicationControl;
        const adopted = manager.prepareKeyedContentRun(prepared,
          originalSourceManagedHostRequest(originals, prepared), request, graph,
          (parent, input) => {
            // Complete C backing must precede the actual selected constructor.
            run.selectedKeyed = Reflect.apply(constructPlan, undefined, [parent, input]);
            return run.selectedKeyed;
          }, (parent, input, selected, originalGraph) => {
            run.contentCompilation = control.prepareCheckedClientRequestKeyedSerializationCompilation(
              parent, input, selected, originalGraph);
            return run.contentCompilation;
          }, contentPreparation);
        run.original = adopted.original; run.value = adopted.value; run.preparationFunded = true;
        checked(Reflect.apply(run.check, runtime, [run.value, prepared, request]));
        assertSourceManagedInstallationCurrent(manager, originals);
        return run;
      } catch (cause) {run.failure = cause; throw cause;}
      finally {run.selecting = false;}
    },
    prepareManagedSerializationRun(runtime, prepared, request, plan, limits, workspace, contentPreparation) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareSerializationRun !== 'function' ||
          plan.kind !== 'serialization') throw clientOperationError('InstalledContentRunPreparationUnavailable');
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      const runs = record.computeRuns ??= new WeakMap(), liveRuns = record.computeLiveRuns ??= new Set();
      originalInstallation.computeRuns = runs;
      const prior = runs.get(prepared);
      if (prior !== undefined) {
        if (Object.hasOwn(prior, 'failure')) throw prior.failure;
        if (prior.closed || prior.preparationKind !== 'serialization-plan' || prior.runtime !== runtime ||
            prior.request !== request || prior.manager !== manager || prior.contentPlan !== plan ||
            prior.contentLimits !== limits || prior.contentWorkspace !== workspace) {
          throw clientOperationError('ForeignInstalledContentRun');
        }
        checked(Reflect.apply(prior.check, runtime, [prior.value, prepared, request])); return prior;
      }
      if (liveRuns.size === 4096) throw clientOperationError('InstalledComputeRunLimit');
      // The actual Content record retains the facade that issued this
      // workspace. A new facade has a different private original registry.
      const content = Object.getOwnPropertyDescriptor(contentPreparation, 'contentControl')?.value;
      if (content === undefined) throw clientOperationError('InstalledContentRunPreparationUnavailable');
      const run = {runtime, prepared, request, manager, content, contentPlan: plan,
        contentLimits: limits, contentWorkspace: workspace, preparationKind: 'serialization-plan',
        original: undefined, value: undefined, serialization: undefined, serializationCleaned: false,
        closed: false, selecting: true};
      if (contentPreparation?.prepared !== prepared || contentPreparation.inputHolder === undefined ||
          typeof Object.getOwnPropertyDescriptor(contentPreparation, 'releaseAliases')?.value !== 'function') {
        throw clientOperationError('InstalledContentRunPreparationUnavailable');
      }
      run.contentPreparation = contentPreparation;
      run.releaseContentAliases = contentPreparation.releaseAliases;
      contentPreparation.managed = run;
      if (contentPreparation.localPreparation !== undefined) contentPreparation.localPreparation.hostRun = run;
      runs.set(prepared, run); liveRuns.add(run);
      try {
        run.retire = runtime.clientProgramInstalledManagedRunRetire;
        run.check = runtime.clientProgramInstalledManagedRunCheck;
        run.cleanupSerialization = content.cleanupRequestPrefix;
        if (![run.retire, run.check, run.cleanupSerialization, content.prepareRequestPrefix]
          .every(method => typeof method === 'function')) throw clientOperationError('NodeManagedRunRuntimeUnavailable');
        const adopted = manager.prepareSerializationRun(prepared,
          originalSourceManagedHostRequest(originals, prepared), request, (parent, input) => {
            // C's full same-parent construction/output/failed-child backing
            // belongs before this exact constructor, not in these DATA limits.
            run.serialization = content.prepareRequestPrefix(parent, input, request,
              plan.compiled, plan.runDefinition, limits, workspace);
            return run.serialization;
          }, contentPreparation);
        run.original = adopted.original; run.value = adopted.value; run.preparationFunded = true;
        checked(Reflect.apply(run.check, runtime, [run.value, prepared, request]));
        return run;
      } catch (cause) {run.failure = cause; throw cause;}
      finally {run.selecting = false;}
    },
    prepareManagedModelRun(runtime, prepared, request, model) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareModelRun !== 'function' ||
          model.control !== runtimeCore(runtime).publicationControl) {
        throw clientOperationError('InstalledMockModelOperationalAdmissionUnavailable');
      }
      const releaseModelSelection = Object.getOwnPropertyDescriptor(originalInstallation,
        'releaseRequestDomainAliases')?.value;
      if (typeof releaseModelSelection !== 'function') {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      const runs = record.computeRuns ??= new WeakMap(), liveRuns = record.computeLiveRuns ??= new Set();
      originalInstallation.computeRuns = runs;
      const sourceProfile = model.components !== undefined
        ? record.managedSourceProfile ?? record.mockSourceProfile
        : model.originalReadInstallation === undefined && runtime.clientProgramAcquisitionCount(prepared) === 0
          ? record.mockSourceProfile : record.managedSourceProfile;
      const prior = runs.get(prepared);
      if (prior !== undefined) {
        if (Object.hasOwn(prior, 'failure')) throw prior.failure;
        if (prior.closed || prior.runtime !== runtime || prior.model !== model || prior.request !== request ||
            prior.manager !== manager || prior.sourceProfile !== sourceProfile) {
          throw clientOperationError('ForeignInstalledModelPreparation');
        }
        checked(Reflect.apply(prior.check, runtime, [prior.value, prepared, request]));
        return prior;
      }
      if (liveRuns.size === 4096) throw clientOperationError('InstalledComputeRunLimit');
      const run = {runtime, prepared, request, model, manager, sourceProfile,
        preparationKind: 'model-plan', original: undefined, value: undefined, closed: false, selecting: true,
        queryTimePreparation: model.queryTimePreparation};
      runs.set(prepared, run); liveRuns.add(run);
      try {
        run.retire = runtime.clientProgramInstalledManagedRunRetire;
        run.check = runtime.clientProgramInstalledManagedRunCheck;
        run.releaseModelAliases = model.releaseAliases;
        run.releaseModelSelection = releaseModelSelection;
        if (model.serializationGraph !== undefined) {
          const content = model.contentPreparation;
          if (content?.prepared !== prepared || content.inputHolder === undefined ||
              content.plan.compiled !== model.compiled || content.plan.runDefinition !== model.runDefinition ||
              content.plan.serializationGraph !== model.serializationGraph ||
              typeof Object.getOwnPropertyDescriptor(content, 'releaseAliases')?.value !== 'function' ||
              typeof content.contentControl?.cleanupRequestPrefix !== 'function') {
            throw clientOperationError('InstalledContentRunPreparationUnavailable');
          }
          run.contentPreparation = content;
          run.releaseContentAliases = content.releaseAliases;
          run.content = content.contentControl;
          run.cleanupSerialization = content.contentControl.cleanupRequestPrefix;
          run.serializationCleaned = false;
          content.managed = run;
        }
        if (![run.retire, run.check, run.releaseModelAliases, run.releaseModelSelection]
          .every(method => typeof method === 'function')) {
          throw clientOperationError('NodeManagedRunRuntimeUnavailable');
        }
        const original = originalSourceManagedHostRequest(originals, prepared);
        const adopted = manager.prepareModelRun(prepared, original, request, model,
          (parent, input, compilation) => prepareRequestMockModelPlan(originals,
            run, model, compilation, parent, input));
        run.original = adopted.original; run.value = adopted.value; run.preparationFunded = true;
        run.preparedSequences = run.modelPlan = run.modelSourceSelection = run.modelSourceSelections = undefined;
        checked(Reflect.apply(run.check, runtime, [run.value, prepared, request]));
        (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
        return run;
      } catch (cause) {run.failure = cause; throw cause;}
      finally {run.selecting = false;}
    },
    prepareManagedComputeRun(runtime, prepared, request, sourceProfile, prepareInvocation) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined) {
        throw clientOperationError('ForeignInstalledComputePreparation');
      }
      const assertCurrent = sourceManaged === undefined
        ? assertManagedComputeInstallationCurrent : assertSourceManagedInstallationCurrent;
      assertCurrent(manager, originals);
      const runs = record.computeRuns ??= new WeakMap();
      // Exact Prepared lookup is not a second strong payload owner. The live
      // record inventory, including uncertain setup, owns actual cleanup.
      const liveRuns = record.computeLiveRuns ??= new Set();
      // Same existing Run inventory, shared only with this installation's
      // fixed requirements reader. Retirement cuts the bag's backreference.
      originalInstallation.computeRuns = runs;
      let run = runs.get(prepared);
      if (run !== undefined) {
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        if (run.closed || run.runtime !== runtime || run.prepared !== prepared ||
            run.request !== request || run.manager !== manager || run.sourceProfile !== sourceProfile) {
          throw clientOperationError('ForeignInstalledComputeRun');
        }
        const value = run.value;
        checked(Reflect.apply(run.check, runtime, [value, prepared, request]));
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        assertCurrent(manager, originals);
        if (Object.hasOwn(run, 'failure')) throw run.failure;
        if (record.computeRuns !== runs || runs.get(prepared) !== run ||
            record.computeLiveRuns !== liveRuns || !liveRuns.has(run) ||
            run.closed || run.runtime !== runtime || run.prepared !== prepared ||
            run.request !== request || run.manager !== manager ||
            run.sourceProfile !== sourceProfile || run.value !== value) {
          throw clientOperationError('ForeignInstalledComputeRun');
        }
        return value;
      }
      run = {runtime, prepared, request, manager, sourceProfile, original: undefined, admission: undefined,
        value: undefined, closed: false};
      if (liveRuns.size === 4096) throw clientOperationError('InstalledComputeRunLimit');
      runs.set(prepared, run);
      liveRuns.add(run);
      try {
        // Capture cleanup before acquiring the original. Failure after start
        // cannot be repaired by issuing another admission or a zero report.
        run.retire = runtime.clientProgramInstalledManagedRunRetire;
        run.cleanup = runtime.clientProgramNodeManagedRunCleanup;
        run.check = runtime.clientProgramInstalledManagedRunCheck;
        if (![run.retire, run.check].every(value => typeof value === 'function')) {
          throw clientOperationError('NodeManagedRunRuntimeUnavailable');
        }
        const originalRequest = originalSourceManagedHostRequest(originals, prepared);
        const constructInvocation = typeof prepareInvocation !== 'function' ? undefined : artifact => {
          if (run.queryInvocation !== undefined) throw clientOperationError('ForeignInstalledComputeRun');
          // The same Request backed this complete invocation group before the
          // callback. Retain partial originals on the existing Host record,
          // before the next issuer/current/Module step can fail.
          const retainedInvocation = {preparedProgram: prepared, requestIdentity: request,
            compiled: undefined, runDefinition: undefined, createdAt: undefined,
            validUntil: undefined, queryTimePreparation: undefined, queryTime: undefined};
          run.queryInvocation = retainedInvocation;
          const invocation = Reflect.apply(prepareInvocation, undefined,
            [prepared, request, artifact, retainedInvocation]);
          if (invocation.retained !== retainedInvocation) throw clientOperationError('ForeignInstalledComputeRun');
          // Only the necessary immutable view survives ModuleBody. Its
          // temporary opaque Option carrier is not another retained root.
          run.queryInvocation = invocation.retained;
          run.queryTimePreparation = invocation.retained.queryTimePreparation;
          return invocation.original;
        };
        const funded = sourceProfile === undefined
          ? manager.adoptPreparation?.(prepared, originalRequest, request, constructInvocation)
          : manager.adoptCapturePreparation?.(prepared, originalRequest, request,
            invocation => prepareManagedComputeCapturePlan(originals, run, invocation), constructInvocation);
        if (funded !== undefined) {
          run.original = funded.original;run.value = funded.value;run.preparationFunded = true;
          // Core now retains the same inventory through its original Plan.
          // Do not leave a second strong preparation graph on the Host record.
          run.sourceCapacities = undefined;
        } else {
          // An explicitly separate, not Request-owned purpose keeps its
          // original admission. A failed Request constructor never lands here.
          run.prepare = runtime.clientProgramNodeManagedRunPrepare;
          run.begin = sourceProfile === undefined ? runtime.clientProgramInstalledManagedSourceFreeBegin
            : runtime.clientProgramInstalledManagedRunBegin;
          if (![run.cleanup, run.prepare, run.begin].every(value => typeof value === 'function')) {
            throw clientOperationError('NodeManagedRunRuntimeUnavailable');
          }
          run.original = manager.prepareRun(prepared);
          assertCurrent(manager, originals);
          run.admission = checked(Reflect.apply(run.prepare, runtime, [run.original, prepared]));
          run.value = checked(Reflect.apply(run.begin, runtime,
            [run.admission, prepared, request, run.preparedSequences]));
        }
        run.preparedSequences = undefined;
        assertCurrent(manager, originals);
        checked(Reflect.apply(run.check, runtime, [run.value, prepared, request]));
        return run.value;
      } catch (error) {run.failure = error; throw error;}
    },
    canRetireManagedPreparation() {
      return typeof (sourceManaged ?? computeManaged)?.retireRun === 'function';
    },
    retireManagedComputeRun(prepared) {
      const runs = record.computeRuns, liveRuns = record.computeLiveRuns;
      const run = runs?.get(prepared);
      if (run === undefined) return;
      if (run.prepared !== prepared || run.runtime !== moon) {
        throw clientOperationError('ForeignInstalledComputeRun');
      }
      // This private operation is called by the complete dispatch retirement
      // predicate, not by a terminal result projection or handler completion.
      const contentRetirement = run.preparationKind === 'serialization-plan' || run.preparationKind === 'keyed-content-plan' ||
        run.preparationKind === 'model-plan' && run.contentPreparation !== undefined;
      const modelRetirement = run.preparationKind === 'model-plan';
      const modelOriginal = run.model;
      const mockSourceRetirement = run.mockSourceReads !== undefined;
      const effectRetirement = run.preparationKind === 'effect-plan';
      const effectValue = run.value, effectRequest = run.request, effectOriginal = run.original,
        effectPlan = run.operationPlan;
      if (modelRetirement && run.retiringModel) throw clientOperationError('InstalledModelCleanupPending');
      if (contentRetirement && run.retiringContent) throw clientOperationError('InstalledContentRunCleanupPending');
      if (mockSourceRetirement && run.retiringMockSources) throw clientOperationError('InstalledMockSourceCleanupPending');
      if (effectRetirement && run.retiringEffect) throw clientOperationError('InstalledEffectRunCleanupPending');
      if (modelRetirement) run.retiringModel = true;
      if (contentRetirement) run.retiringContent = true;
      if (mockSourceRetirement) run.retiringMockSources = true;
      if (effectRetirement) run.retiringEffect = true;
      try {
        if (run.selecting) throw clientOperationError('InstalledEffectPlanSelectionPending');
        if (['serialization-plan', 'keyed-content-plan'].includes(run.preparationKind) && run.value === undefined) {
          // No prefix start can precede an adopted Run. The original Request
          // still owns its partial constructor and aborts it on existing cleanup.
          record.computeRuns.delete(prepared); record.computeLiveRuns.delete(run);
          for (const key of Object.keys(run)) run[key] = undefined;
          run.closed = true; return;
        }
        if (run.preparationKind === 'model-plan' && run.value === undefined) {
          // Construction unwound; a Scope can predate a refused completion.
          // This failed preparation has entered neither dispatch nor a read.
          const model = modelOriginal;
          if (model === undefined) throw clientOperationError('ForeignInstalledModelPreparation');
          const scope = model.scope, compiled = model.compiled,
            definition = model.runDefinition, graph = model.graph;
          const releaseAliases = run.releaseModelAliases, releaseSelection = run.releaseModelSelection;
          if (model.taken || model.read !== undefined || model.components?.some(member => member.taken || member.read !== undefined)) {
            throw clientOperationError('InstalledMockModelCleanupPending');
          }
          if (scope !== undefined && model.scopeFinished !== true) {
            const finished = model.components === undefined
              ? model.control.finishCheckedClientInferOriginalReadScope(compiled, definition, graph, scope, true)
              : finishNodeInferOriginalReadScopes(model);
            if (finished !== true) {
              throw clientOperationError('InstalledMockModelCleanupPending');
            }
            if (model.scope !== scope || model.compiled !== compiled ||
                model.runDefinition !== definition || model.graph !== graph) {
              throw clientOperationError('ForeignInstalledModelPreparation');
            }
            model.scopeFinished = true;
          }
          // Scope finish crosses its original reservation/current callback.
          // A successful old Scope finish cannot retire a replaced Host bag,
          // Model carrier, request or cleanup method from that callback.
          if (record.computeRuns !== runs || record.computeLiveRuns !== liveRuns ||
              runs.get(prepared) !== run || liveRuns?.has(run) !== true ||
              run.prepared !== prepared || run.runtime !== moon || run.closed ||
              run.model !== model || run.preparationKind !== 'model-plan' ||
              run.value !== effectValue || run.request !== effectRequest || run.original !== effectOriginal ||
              run.releaseModelAliases !== releaseAliases || run.releaseModelSelection !== releaseSelection) {
            throw clientOperationError('ForeignInstalledModelPreparation');
          }
          Reflect.apply(releaseAliases, model, []);
          Reflect.apply(releaseSelection, run, [prepared]);
          runs.delete(prepared); liveRuns.delete(run);
          for (const key of Object.keys(run)) run[key] = undefined;
          run.closed = true;
          return;
        }
        if (modelRetirement && modelOriginal?.selection !== undefined &&
            !modelOriginal.taken && modelOriginal.read === undefined &&
            modelOriginal.scope !== undefined && modelOriginal.scopeFinished !== true) {
          const finished = modelOriginal.components === undefined
            ? modelOriginal.control.finishCheckedClientInferOriginalReadScope(modelOriginal.compiled,
              modelOriginal.runDefinition, modelOriginal.graph, modelOriginal.scope, true)
            : finishNodeInferOriginalReadScopes(modelOriginal);
          if (finished !== true) {
            throw clientOperationError('InstalledModelCleanupPending');
          }
          modelOriginal.scopeFinished = true;
          if (record.computeRuns.get(prepared) !== run || !record.computeLiveRuns.has(run) ||
              run.prepared !== prepared || run.runtime !== moon || run.closed || run.model !== modelOriginal ||
              run.preparationKind !== 'model-plan' || run.value !== effectValue ||
              run.request !== effectRequest || run.original !== effectOriginal) {
            throw clientOperationError('ForeignInstalledModelPreparation');
          }
        }
        if (run.contentCleanup?.cleanupPending()) throw clientOperationError('InstalledContentPhysicalCleanupPending');
        finishInstalledEffectModelScope(run, true, checked);
        if (effectRetirement && (record.computeRuns.get(prepared) !== run || !record.computeLiveRuns.has(run) ||
            run.prepared !== prepared || run.runtime !== moon || run.closed ||
            run.preparationKind !== 'effect-plan' || run.value !== effectValue || run.request !== effectRequest ||
            run.original !== effectOriginal || run.operationPlan !== effectPlan)) {
          throw clientOperationError('ForeignInstalledEffectManagedRun');
        }
        if (run.preparationKind === 'effect-plan' && run.controlConstruction !== undefined) {
          if (typeof run.retireControlConstruction !== 'function' ||
              Reflect.apply(run.retireControlConstruction, run.controlConstruction, []) !== true) {
            throw clientOperationError('InstalledEffectControlConstructionCleanupPending');
          }
        }
        if (effectRetirement && (record.computeRuns.get(prepared) !== run || !record.computeLiveRuns.has(run) ||
            run.prepared !== prepared || run.runtime !== moon || run.closed ||
            run.preparationKind !== 'effect-plan' || run.value !== effectValue || run.request !== effectRequest ||
            run.original !== effectOriginal || run.operationPlan !== effectPlan)) {
          throw clientOperationError('ForeignInstalledEffectManagedRun');
        }
        if (run.preparationFunded) {
          if ((run.preparationKind === 'serialization-plan' || run.preparationKind === 'model-plan' &&
              run.serialization !== undefined) && !run.serializationCleaned) {
            if (Reflect.apply(run.cleanupSerialization, run.content, [run.value, run.serialization]) !== true) {
              throw clientOperationError('InstalledContentRunCleanupPending');
            }
            // Spend only this original prefix's ACK before parent retirement
            // can sever its payload or a consumed borrow return can throw.
            run.serializationCleaned = true;
          }
          const sameValue = run.value, sameRequest = run.request, sameOriginal = run.original;
          const sameSourceReads = run.mockSourceReads, releaseSourceAliases = run.releaseMockSourceAliases;
          try {checked(Reflect.apply(run.retire,run.runtime,[run.value]));}
          catch (cause) {
            const severed = effectRetirement
              ? moon.clientProgramInstalledPreparationPayloadSevered(effectValue,effectRequest)
              : run.runtime.clientProgramInstalledPreparationPayloadSevered(run.value,run.request);
            if (severed!==true) throw cause;
          }
          // Both the original retire and its one existing fallback observation
          // can call current. Neither may replace the same Effect record before
          // its aliases are cut and its original Request borrower is consumed.
          if (effectRetirement && (record.computeRuns.get(prepared) !== run || !record.computeLiveRuns.has(run) ||
              run.prepared !== prepared || run.runtime !== moon || run.closed ||
              run.preparationKind !== 'effect-plan' || run.value !== effectValue || run.request !== effectRequest ||
              run.original !== effectOriginal || run.operationPlan !== effectPlan)) {
            throw clientOperationError('ForeignInstalledEffectManagedRun');
          }
          if (modelRetirement && (record.computeRuns.get(prepared) !== run ||
              !record.computeLiveRuns.has(run) || run.prepared !== prepared || run.runtime !== moon ||
              run.closed || run.model !== modelOriginal || run.preparationKind !== 'model-plan' ||
              run.value !== sameValue || run.request !== sameRequest || run.original !== sameOriginal)) {
            throw clientOperationError('ForeignInstalledModelPreparation');
          }
          if (mockSourceRetirement) {
            // Native retirement and physical close are separate duties. Cut
            // only this installation's SAME acknowledged read records before
            // returning the parent borrower, including a consumed-return error.
            if (record.computeRuns.get(prepared) !== run || run.prepared !== prepared || run.closed ||
                run.runtime !== moon || run.value !== sameValue || run.request !== sameRequest ||
                run.original !== sameOriginal || run.mockSourceReads !== sameSourceReads ||
                run.releaseMockSourceAliases !== releaseSourceAliases || typeof releaseSourceAliases !== 'function') {
              throw clientOperationError('InstalledSourcePreparationMismatch');
            }
            Reflect.apply(releaseSourceAliases, run, [prepared, sameRequest]);
          }
          if (contentRetirement) {
            if (record.computeRuns.get(prepared) !== run || run.prepared !== prepared || run.closed ||
                run.value !== sameValue || run.request !== sameRequest || run.original !== sameOriginal) {
              throw clientOperationError('ForeignInstalledContentRun');
            }
            if (!run.contentAliasesReleased) {
              if (run.contentPreparation?.managed !== run || typeof run.releaseContentAliases !== 'function') {
                throw clientOperationError('ForeignInstalledContentRun');
              }
              Reflect.apply(run.releaseContentAliases, run.contentPreparation, [run]);
              run.contentAliasesReleased = true;
              run.releaseContentAliases = run.contentPreparation = undefined;
            }
          }
          // The Scope's census has acknowledged physical retirement. Cut its
          // raw compiler/definition/graph aliases before returning the original
          // typed preparation borrower and completing that same parent debit.
          if (run.preparationKind === 'model-plan' && !run.modelAliasesReleased) {
            // The original receiver must survive its own alias release. Spend
            // that managed retirement before returning a consumed parent borrow.
            Reflect.apply(run.releaseModelAliases, modelOriginal, []);
            run.releaseModelSelection(prepared);
            run.modelAliasesReleased = true;
          }
          run.modelScope=run.model=run.modelDemand=run.definitionOriginal=run.operationPlan=undefined;
          run.contentOriginal=run.contentCleanup=undefined;
          run.modelSelection=run.modelComponent=run.modelComponents=run.sourceInputs=undefined;
          run.publicationControl=run.modelRunDefinition=run.modelPreparation=run.modelRead=undefined;
          run.mockSourceReads=undefined;
          run.requestInput=run.selection=run.selectionResult=run.selectionFailure=undefined;
          run.contentGraph = run.contentRecipe = run.selectedKeyed = run.contentCompilation = undefined;
          run.contentPlan = run.contentLimits = run.contentWorkspace = run.serialization = undefined;
          // Retire all immutable invocation aliases before consuming the
          // original input borrower, whose parent settlement can still fail.
          run.queryInvocation=run.queryTimePreparation=undefined;
          run.manager.severPreparation(prepared,run.original);
          run.prepared=undefined;run.closed=true;
          // Keep a weak-key tombstone but no Prepared in this continuation.
          // Returning registry/handler holders may now complete the same debit.
          run.finishRetirement = managedPreparationRetirementContinuation(run,record);
          return run.finishRetirement;
        }
        finishInstalledEffectModelScope(run, true, checked);
        if (run.value !== undefined) checked(Reflect.apply(run.retire, run.runtime, [run.value]));
        else if (run.admission !== undefined) checked(Reflect.apply(run.cleanup, run.runtime, [run.admission]));
        // A failed same-Request Model constructor has no adopted manager Run.
        // Its existing producer/input cleanup owns that original initial parent.
        if (run.original !== undefined && !(run.preparationKind === 'effect-plan' &&
            run.requestInput !== undefined && run.value === undefined)) run.manager.retireRun(prepared, run.original);
        run.closed = true;
        record.computeRuns.delete(prepared);
        record.computeLiveRuns.delete(run);
        for (const key of Object.keys(run)) run[key] = undefined;
      } finally {
        if (modelRetirement) run.retiringModel = false;
        if (contentRetirement) run.retiringContent = false;
        if (mockSourceRetirement) run.retiringMockSources = false;
        if (effectRetirement) run.retiringEffect = false;
      }
    },
    assertUnadmittedSourceRequest(runtime, prepared, request) {
      if (runtime !== moon || request === undefined || record.computeRuns?.has(prepared)) {
        throw clientOperationError('ForeignInstalledComputeRun');
      }
      assertInitialControlHostPreparation(originals);
      if (sourceManaged !== undefined) assertSourceManagedInstallationCurrent(sourceManaged, originals);
      else if (computeManaged !== undefined) assertManagedComputeInstallationCurrent(computeManaged, originals);
      else throw clientOperationError('NodeManagedRunAdmissionUnavailable');
      originalSourceManagedHostRequest(originals, prepared);
    },
    isOriginalManagedComputePreparationRefusal(error, prepared, request) {
      const run = record.computeRuns?.get(prepared), original = run?.preAdmissionRefusal;
      if (original === undefined || request === undefined || original.error !== error || run.failure !== error ||
          run.prepared !== prepared || original.prepared !== prepared || run.request !== request ||
          original.request !== request || run.runtime !== moon || run.closed ||
          run.original !== undefined || run.admission !== undefined || run.value !== undefined ||
          original.control !== originalInstallation.initialControl ||
          error.cleanupPending === true || error.cleanupHandle !== undefined) return false;
      assertInitialControlHostPreparation(originals);
      if (computeManaged !== undefined) assertManagedComputeInstallationCurrent(computeManaged, originals);
      else if (sourceManaged !== undefined) assertSourceManagedInstallationCurrent(sourceManaged, originals);
      else return false;
      return true;
    },
    managedComputePublicationPreparation(runtime, prepared) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined || !run.preparationFunded) return undefined;
      if (run.runtime !== runtime || run.prepared !== prepared || run.closed || Object.hasOwn(run, 'failure')) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      return run.manager.publicationPreparation(prepared);
    },
    managedComputeReservePublication(runtime, prepared) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined || !run.preparationFunded || run.runtime !== runtime ||
          run.prepared !== prepared || run.closed || Object.hasOwn(run, 'failure')) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      return run.manager.reservePublication(prepared);
    },
    managedComputeInvocationOriginal(runtime, prepared) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined) return undefined;
      if (run.runtime !== runtime || run.prepared !== prepared || run.closed || Object.hasOwn(run, 'failure')) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      if (!run.preparationFunded) return undefined;
      if (run.queryInvocation === undefined) return undefined; // Existing untimed module.
      return runtimeCore(runtime).publicationControl.checkedClientManagedQueryInvocationOriginal(
        run.value, prepared, run.queryInvocation);
    },
    prepareManagedContentGraph(runtime, prepared, options, intermediate, modelOccurrence) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareContentGraph !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      const control = runtimeCore(runtime).publicationControl;
      return manager.prepareContentGraph(prepared, originalSourceManagedHostRequest(originals, prepared),
        (parent, input, contracts, effectful = false) => {
          if (effectful ? !intermediate || modelOccurrence === undefined : modelOccurrence !== undefined) {
            throw clientOperationError('ForeignInstalledSourceProducer');
          }
          const acquisitions = effectful ? runtime.clientProgramEffectAcquisitionCount
            : runtime.clientProgramAcquisitionCount;
          return Reflect.apply(acquisitions, runtime, [prepared]) === 0
            ? control.prepareCheckedClientRequestSerializationGraph(
              parent, input, contracts, prepared, options, intermediate, modelOccurrence)
            : control.prepareCheckedClientRequestAcquiredSerializationGraph(
              parent, input, contracts, prepared, options, intermediate, modelOccurrence);
        });
    },
    prepareManagedContentCompilation(runtime, prepared, graph) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareContentCompilation !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      const control = runtimeCore(runtime).publicationControl;
      return manager.prepareContentCompilation(prepared, originalSourceManagedHostRequest(originals, prepared), graph,
        (parent, input, originalGraph, contracts) => control.prepareCheckedClientRequestSerializationCompilation(
          parent, input, originalGraph, contracts));
    },
    prepareManagedModelMaterials(runtime, prepared, count, wireAt, containers) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareModelMaterials !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.prepareModelMaterials(prepared,
        originalSourceManagedHostRequest(originals, prepared), count, wireAt, containers);
    },
    prepareManagedModelBinding(runtime, prepared, providerId, installation, contract, configuration) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareModelBinding !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.prepareModelBinding(prepared,
        originalSourceManagedHostRequest(originals, prepared), providerId, installation, contract, configuration);
    },
    prepareManagedModelGraph(runtime, prepared, occurrence, execution, serializationGraph) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareModelGraph !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      const control = runtimeCore(runtime).publicationControl;
      return manager.prepareModelGraph(prepared,
        originalSourceManagedHostRequest(originals, prepared), occurrence, execution, serializationGraph,
        serializationGraph === undefined ? undefined :
          (parent, input, originalOccurrence, selected, originalExecution, contracts) =>
            control.prepareClientRequestSerializedInferGraph(parent, input, originalOccurrence,
              selected, originalExecution, contracts));
    },
    prepareManagedModelCompilation(runtime, prepared, graph) {
      const manager = sourceManaged ?? computeManaged;
      if (runtime !== moon || manager === undefined || typeof manager.prepareModelCompilation !== 'function') {
        throw clientOperationError('NodeManagedRunCompilationUnavailable');
      }
      (sourceManaged === undefined ? assertManagedComputeInstallationCurrent
        : assertSourceManagedInstallationCurrent)(manager, originals);
      return manager.prepareModelCompilation(prepared,
        originalSourceManagedHostRequest(originals, prepared), graph);
    },
    managedComputeCompilationOriginal(runtime, prepared) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined || !run.preparationFunded) return undefined;
      if (run.runtime !== runtime || run.prepared !== prepared || run.closed || Object.hasOwn(run, 'failure')) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      // The driver owns the staged compilation under this Run's existing
      // preparation borrow. No cache, recompile or copied wire creates it.
      const original = run.manager.compilationOriginal(prepared);
      if (original === undefined) throw clientOperationError('NodeManagedRunCompilationUnavailable');
      return original;
    },
    managedComputePublicationOriginal(runtime, prepared) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined) return undefined; // Explicit non-managed compatibility path.
      if (run.runtime !== runtime || run.prepared !== prepared || run.closed) {
        throw clientOperationError('NodeManagedRunRuntimeUnavailable');
      }
      // Before admission, borrow the staged pure preparation. After begin, its
      // canonical owner has moved into the live Core Run. Neither path creates
      // a Run, reruns proof, nor retains a second strong plan cache.
      if (run.value !== undefined) return Object.freeze({kind: 'installed_run', value: run.value});
      if (run.preparedSequences !== undefined) return Object.freeze({kind: 'preparation', value: run.preparedSequences});
      throw clientOperationError('NodeManagedRunRuntimeUnavailable');
    },
    bindManagedComputeRunObservation(prepared, ref) {
      const run = record.computeRuns?.get(prepared);
      if (run === undefined || run.value === undefined || run.closed) return;
      // Index only an actually admitted Run's existing holding. This does
      // not cache authority, reconstruct a preparation or scan other Runs.
      const key = JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);
      const index = record.computeRunObservations ??= new Map();
      const prior = index.get(key);
      if (prior !== undefined && prior !== run) throw clientOperationError('ForeignInstalledComputeRun');
      index.set(key, run);
      // Capture the same native method without sampling or extending the
      // Core Run lifetime. Final retirement supplies its last live DATA.
      if (!Object.hasOwn(run, 'usage')) run.usage = run.runtime.clientProgramInstalledManagedRunAccounting;
    },
    managedComputeUsageReader(ref) {
      const key = JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);
      if (record.computeRunObservations?.get(key) === undefined) return undefined;
      // Capture only the public key and existing installation bag. Final
      // retirement clears that bag, including this index, so a held response
      // cannot keep a prepared Program, Core Run or Ledger alive afterward.
      return () => {
        const run = record.computeRunObservations?.get(key);
        if (run === undefined) return undefined;
        if (run.closed) return run.finalAccounting;
        if (run.value === undefined) return undefined;
        if (!Object.hasOwn(run, 'usage')) run.usage = run.runtime.clientProgramInstalledManagedRunAccounting;
        if (typeof run.usage !== 'function') return undefined;
        return checked(Reflect.apply(run.usage, run.runtime, [run.value]));
      };
    },
    sourcePreparation() {
      if (sourceManaged === undefined) return undefined;
      // Missing or retired selected coverage cannot become an unselected SDK
      // connection. Check the exact wrapper in its private original inventory.
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      return sourceManaged;
    },
    localFilesLookupExecutionPolicy(runtime) {
      if (runtime !== moon) throw clientOperationError('ForeignInstalledProjectSourcePreparation');
      if ((projectSourcePreparation === undefined) === (mockPreparation === undefined)) return undefined;
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      let selected;
      if (projectSourcePreparation !== undefined) {
        const bundle = projectSourcePreparation.originalsForRuntime(moon);
        selected = localFilesLookupExecutionPolicy(bundle.sources.map(source => source.limits));
      } else {
        const bundle = mockPreparation.originalsForRuntime(moon);
        if (bundle.physicalKind !== 'declared-json-document') return undefined;
        // The selected Local installation supplies its existing service policy,
        // not a file-count assertion about this declaration or sample data.
        selected = localFilesLookupExecutionPolicy([LOCAL_FILES_DEFAULT_LIMITS]);
      }
      return localResourceLookupExecutionPolicy(moon, moon.clientLocalResourcePolicyOriginal(), selected);
    },
    installProjectSources(runtime, baseEnvironmentWire, authorizationFor) {
      if (runtime !== moon || projectSourcePreparation === undefined || mockPreparation !== undefined) {
        throw clientOperationError('ForeignInstalledProjectSourcePreparation');
      }
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      const prepare = preparation.prepareManagedSourceRun;
      // Forward the existing SAME Host service, not a Connector-owned Root or
      // an independently selected manager. The actual returned profile below
      // is the same one required by that service's original identity fence.
      const acquired = installPreparedProjectLocalFiles({moon, preparation: projectSourcePreparation,
        sourceManaged, baseEnvironmentWire, authorizationFor, nativeFilesystem: localProjectFilesystem(),
        prepareManagedContentRun(prepared, request, graph, recipe, constructPlan, contentPreparation) {
          return preparation.prepareManagedKeyedContentRun(moon, prepared, request, graph, recipe, constructPlan, contentPreparation);
        },
        prepareManagedRun({preparedProgram, requestIdentity, sourceProfile, prepareInvocation}) {
          return Reflect.apply(prepare, preparation,
            [moon, preparedProgram, requestIdentity, sourceProfile, prepareInvocation]);
        }});
      return acquired.then(async profile => {
        if (record.managedSourceProfile !== undefined) {
          throw await retainInstalledHostInitializationFailure(
            clientOperationError('InstalledSourcePreparationChanged'), {sourceProfile: profile});
        }
        record.managedSourceProfile = originalInstallation.managedSourceProfile = profile;
        return profile;
      });
    },
    localFilesEffectLimits(runtime) {
      if (runtime !== moon || projectSourcePreparation === undefined || mockPreparation !== undefined) {
        throw clientOperationError('ForeignInstalledProjectSourcePreparation');
      }
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      const bundle = projectSourcePreparation.originalsForRuntime(moon);
      // These supported request ceilings are derived from the retained Local
      // installation and existing Effect limits, not physical backing or Allow.
      // Each connector still enforces its own original entry's file ceiling.
      let maxFileBytes = 0;
      for (const entry of bundle.sources) maxFileBytes = Math.max(maxFileBytes, entry.limits.maxFileBytes);
      return Object.freeze({maxFileBytes,
        maxRows: 100, maxRequestBytes: 100000, maxResponseBytes: 65536, maxEffects: 16});
    },
    async installProjectEffects(runtime, baseEnvironmentWire, authorizationFor, principalId,
      effectResources, sourceBindings, installationServices) {
      if (runtime !== moon || projectSourcePreparation === undefined || mockPreparation !== undefined) {
        throw clientOperationError('ForeignInstalledProjectSourcePreparation');
      }
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      const nativeFilesystem = localProjectFilesystem();
      const runtimeBundleCid = await installedRuntimeBundleCid(runtimeUrl);
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      return installPreparedProjectLocalFileEffects({moon, preparation: projectSourcePreparation,
        sourceManaged, baseEnvironmentWire, authorizationFor, principalId, sourceBindings, installationServices,
        runtimeBundleCid, ledgerRoot: join(originalInstallation.root, 'state', 'effects', 'ledger'),
        nativeFilesystem, effectResources,
        assertCurrent: () => assertSourceManagedInstallationCurrent(sourceManaged, originals)});
    },
    async installMockSources(runtime, baseEnvironmentWire, authorizationFor, installationServices) {
      if (runtime !== moon || mockPreparation === undefined) {
        throw clientOperationError('ForeignInstalledMockPreparation');
      }
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      const prepareSource = preparation.prepareManagedSourceRun;
      if (typeof prepareSource !== 'function') throw clientOperationError('NodeManagedRunAdmissionUnavailable');
      const profile = await installPreparedProjectMockSources({moon, mockPreparation, sourceManaged, installationServices,
        baseEnvironmentWire, authorizationFor,
        readAsset: path => readInitialControlInstallationAsset(control, originals, path),
        effectManagedRun: (prepared, request) => preparation.effectManagedPlanRun(moon, prepared, request),
        prepareManagedSourceRun({preparedProgram, requestIdentity, prepareInvocation}) {
          const value = Reflect.apply(prepareSource, preparation,
            [moon, preparedProgram, requestIdentity, record.managedSourceProfile, prepareInvocation]);
          const run = record.computeRuns?.get(preparedProgram);
          if (run?.value !== value || run.runtime !== moon || run.prepared !== preparedProgram ||
              run.request !== requestIdentity || run.sourceProfile !== record.managedSourceProfile || run.closed) {
            throw clientOperationError('ForeignInstalledSourcePreparation');
          }
          return run;
        },
        prepareManagedModelRun: (prepared, request, model) => preparation.prepareManagedModelRun(moon,
          prepared, request, model)});
      if (record.managedSourceProfile !== undefined) {
        throw await retainInstalledHostInitializationFailure(
          clientOperationError('InstalledSourcePreparationChanged'), {sourceProfile: profile});
      }
      record.managedSourceProfile = originalInstallation.managedSourceProfile = profile;
      record.mockSourceProfile = profile;
      return profile;
    },
    async installMockEffects(runtime, baseEnvironmentWire, authorizationFor, principalId, effectResources,
      sourceBinding) {
      if (runtime !== moon || mockPreparation === undefined) {
        throw clientOperationError('ForeignInstalledMockPreparation');
      }
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      const bundle = mockPreparation.originalsForRuntime(moon);
      if (bundle.writable === undefined ||
          sourceBinding?.connectorId !== bundle.writable.source.catalogue.connectorId ||
          typeof sourceBinding.bindingCid !== 'string' ||
          !/^sha256:[0-9a-f]{64}$/u.test(sourceBinding.bindingCid)) {
        throw clientOperationError('ForeignInstalledMockSourceBinding');
      }
      return installPreparedProjectMockEffects({moon, mockPreparation, baseEnvironmentWire,
        authorizationFor, principalId, effectResources,
        runtimeBundleCid: await installedRuntimeBundleCid(runtimeUrl),
        // Correspondence DATA from the actual same Host's Source factory.
        // The Mapping cannot redefine that physical installation identity;
        // this CID grants no Run, resource original or target authority.
        bindingCid: sourceBinding.bindingCid,
        ledgerRoot: join(originalInstallation.root, 'state', 'effects', 'ledger'),
        assertCurrent: () => assertSourceManagedInstallationCurrent(sourceManaged, originals)});
    },
    async prepareStandardAccount(principal, operatorAuthorization, rootCreation) {
      assertInitialControlHostPreparation(originals);
      const journal = ordinaryHostJournalInstallation(originals);
      const ownership = journal.privateEvidenceInitializationOwnership();
      const prepared = await prepareOrdinaryLocalAccount({root: originalInstallation.root,
        principal, preparedOriginal: ownership, rootCreation, operatorAuthorization});
      assertInitialControlHostPreparation(originals);
      return prepared;
    },
    async initializeMockAccount(runtime, principal, operatorAuthorization, models) {
      if (runtime !== moon || mockPreparation === undefined || project === undefined) {
        throw clientOperationError('ForeignInstalledMockPreparation');
      }
      assertInitialControlHostPreparation(originals);
      const journal = ordinaryHostJournalInstallation(originals);
      const bundle = mockPreparation.originalsForRuntime(moon);
      const tasks = models.originalsForRuntime(moon).map(entry => entry.taskCid);
      const sources = bundle.sources.flatMap(entry => entry.catalogue.views.map(view =>
        [entry.catalogue.connection, view.resource]));
      const requestRealization = installedMockRequestRealization(mockPreparation, moon);
      const updates = bundle.writable === undefined ? [] :
        [[bundle.writable.source.catalogue.connection, bundle.writable.write.resource]];
      if (updates.length > 1) throw clientOperationError('InstalledMockCatalogueUnavailable');
      const binding = await initializeOrdinaryMockAccount({moon, root: originalInstallation.root, principal,
        subject: {projectDirectory: project.directory,
          configurationCid: bytesCid(Buffer.from(installedProjectOriginalsForRuntime(project, moon).configurationWire)),
          sources: bundle.sources.map(entry => ({connection: entry.catalogue.connection,
            registration: entry.catalogue.registration, declarationCid: bytesCid(Buffer.from(entry.wire))})),
          modelTasks: tasks, requestRealization},
        sources, modelTasks: tasks, requestTarget: ['local-mock', requestRealization],
        updateTarget: updates[0], explicitSelection: record.explicitMockSelection,
        assertExclusiveCurrent: () => {assertInitialControlHostPreparation(originals); journal.assertInitializationCurrent();},
        operatorAuthorization});
      // Retain the actual initialized keys/configuration before the following
      // current fence. A failed caller still owns this same preparation.
      record.mockAccount = originalInstallation.mockAccount = binding;
      assertInitialControlHostPreparation(originals);
      return binding;
    },
    installMockModels(runtime) {
      if (runtime !== moon || mockPreparation === undefined) {
        throw clientOperationError('ForeignInstalledMockPreparation');
      }
      assertInitialControlInstallationCurrent(control, originals);
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
      if (mockModelFlight !== undefined) return mockModelFlight;
      mockModelFlight = Promise.resolve().then(async () => {
        const install = moon.clientProgramInstallMockProfile;
        mockModelProfileRetire = moon.clientProgramRetireMockProfile;
        if (typeof install !== 'function' || typeof mockModelProfileRetire !== 'function') {
          throw clientOperationError('InstalledMockModelRuntimeUnavailable');
        }
        const limits = Object.freeze({maxTasks:128,maxBytes:65536,maxNodes:4096,
          maxDepth:64,maxMembers:256,contractNodes:4096,contractDepth:64,
          contractTextBytes:65536,maxWork:2097152,valueNodes:4096,valueDepth:64,
          valueTextBytes:65536,maxEntries:128});
        const assertCurrent = () => {
          assertInitialControlInstallationCurrent(control, originals);
          assertSourceManagedInstallationCurrent(sourceManaged, originals);
          mockPreparation.originalsForRuntime(moon);
        };
        assertCurrent();
        mockModelProfile = checked(Reflect.apply(install, moon, [limits.maxBytes,
          limits.maxNodes,limits.maxDepth,limits.maxMembers,limits.contractNodes,
          limits.contractDepth,limits.contractTextBytes,limits.maxWork]));
        record.mockModelProfile = mockModelProfile;
        assertCurrent();
        mockAnswers = await loadInstalledProjectMockAnswers(moon, project, projectProfile,
          {limits,assertCurrent});
        record.mockAnswers = mockAnswers;
        const models = mockAnswers.bindModelsForRuntime(moon, mockModelProfile, now);
        record.mockModels = models;
        assertCurrent();
        return models;
      });
      return mockModelFlight;
    },
    readEnvironmentSource() {
      return readInitialControlInstallationAsset(control, originals,
        'spec/local-check-environment.json');
    },
    // Fixed checking artifacts borrow their original captured image through
    // this SAME preparation. Missing/current-refused images never fall back
    // to a pathname or acquire another installation's source bytes.
    readSequenceContracts() {
      return prepareInstalledSequenceContractOriginal(originals);
    },
    readAsset(path) {
      return readInitialControlInstallationAsset(control, originals, path);
    },
    retainUndispatchedRetirement(original, initial, releaseModelSelection) {
      if (record.retireUndispatched !== undefined || typeof original !== 'function' ||
          typeof initial !== 'function' || typeof releaseModelSelection !== 'function') {
        throw clientOperationError('InstalledHostPreparationChanged');
      }
      record.retireUndispatched = original;
      originalInstallation.retireInitialPreparation = initial;
      originalInstallation.releaseRequestDomainAliases = releaseModelSelection;
    },
    retainReferenceRetirement(original) {
      if (referenceRetirement !== undefined || typeof original !== 'function') {
        throw clientOperationError('InstalledHostPreparationChanged');
      }
      referenceRetirement = original;
    }});
  // Fixed private callback supply for the same Source producer owner. Capture
  // the existing method/receiver; no later caller envelope selects a parent.
  const sourceInitializationBorrow = preparation.borrowSourceInitializationMaterial;
  originalInstallation.borrowSourceInitializationMaterial = () =>
    Reflect.apply(sourceInitializationBorrow,preparation,[]);
  async function releaseUnadopted() {
    const failure = await retainInstalledHostInitializationFailure(
      new Error('InstalledHostPreparationCleanupPending'), {initialControl});
    if (failure.cleanupHandle.status().pending) throw failure;
  }
  try {
  // Before options snapshot, Common import, Project read, normalization or
  // Provider installation. Missing actual startup coverage remains unavailable.
  const omittedOpenInput = initialEntry === 'open' && options === undefined;
  const begun = beginInitialControlInstallation(originals, options);
  // Begin synchronously captures the admitted original packet. Keep only
  // that supplier-owned snapshot across its initialization await, not a raw
  // caller object whose backing can grow while the call is pending.
  options = undefined;
  // The actual prior startup envelope must already cover this same candidate
  // and primitive path observation. Preserve open's call-time directory before
  // initialization awaits; do not resolve it again from a later process cwd.
  // A path failure still awaits and retains the original scope for cleanup.
  if (initialEntry === 'open') {
    try { record.openWorkingDirectory = resolve('.'); }
    catch (cause) { record.openPathFailure = {cause}; }
  }
  control = await begun;
  controlClose = control.close;
  assertInitialControlInstallationCurrent(control, originals);
  duty = control.retainPreparation(record);
  // Only the actual startup may snapshot raw options, synchronously before
  // begin's first await and after covering their original acquisition. Read
  // that SAME nominal snapshot, never the caller again after initialization.
  // Its supplier retains opaque/callback backing and partial-failure custody;
  // this record owns only the Host's additional managed packet reference.
  options = readInitialControlInstallationInput(control, originals);
  record.input = options;
  if (record.openPathFailure !== undefined) throw record.openPathFailure.cause;
  if (initialEntry === 'remote') {
    let {directory, authenticate, beforeDispatch, authorization, workspaceId, connectorTable,
      sourceProfilePath, sourceProfilePaths, sourceNamespace, sourceSelectorNamespace,
      loopbackHttp = false, resolveSourceSecret, effectProfilePath, effectProfilePaths,
      resolveEffectSecret, effectInstallation, modelInstallation, registerModelProviders,
      calendarArtifact, resultDataPolicy, inferEvidence, retainedRelationOutput,
      hostCapacityPolicy, hostLookupExecutionPolicy, verifyRequestValuePolicy,
      valuesMaxRows, observation} = options;
    calendarArtifact = snapshotInstalledCalendar(calendarArtifact);
    hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
    hostLookupExecutionPolicy = snapshotHostLookupExecutionPolicy(hostLookupExecutionPolicy);
    if (typeof directory !== 'string' || !directory ||
        typeof authenticate !== 'function' || typeof loopbackHttp !== 'boolean' ||
        beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
      throw new TypeError('InvalidInstalledRemoteHost');
    }
    Object.assign(originalInstallation, {root: resolve(directory), mode: 'remote',
      initialControl: control, workspaceId, beforeDispatch, authorization, connectorTable,
      sourceProfilePath, sourceProfilePaths, sourceNamespace, sourceSelectorNamespace,
      resolveSourceSecret, effectProfilePath, effectProfilePaths, resolveEffectSecret,
      effectInstallation, modelInstallation, registerModelProviders, calendarArtifact,
      resultDataPolicy, inferEvidence,
      retainedRelationOutput: retainedRelationOutput === undefined ? false : retainedRelationOutput,
      hostCapacityPolicy, hostLookupExecutionPolicy, verifyRequestValuePolicy, valuesMaxRows, observation});
    record.installation = originalInstallation;
    moon = await import(runtimeUrl.href);
    record.runtime = moon;
    originalInstallation.projectRuntime = moon;
    assertInitialControlInstallationCurrent(control, originals);
    // No cwd, Project read, Local profile selection or in-process SDK Client.
    const opened = await openInstalledHost(originalInstallation, preparation);
    const shutdown = installedHostShutdown(opened);
    try {
      return installedRemoteHttpTransport(opened, {authenticate, loopbackHttp}, shutdown,
        installHttpRequestPreparation(preparation, profiles, originals));
    } catch (cause) {
      // No transport was returned. The SAME Host shutdown owns all acquired
      // children, including a failed close; initial control is its last duty.
      throw await retainInstalledHostInitializationFailure(cause, {initialControl: shutdown});
    }
  }

  if (initialEntry === 'open') {
    // Omission still corresponds to the same original empty packet. An
    // explicit open packet uses that supplier's immutable snapshot, never a
    // later caller read or another installation's admitted connect options.
    if (omittedOpenInput && Reflect.ownKeys(options).length !== 0) {
      throw clientOperationError('NodeInitialControlOriginalChanged');
    }
    if (options === null || typeof options !== 'object' || Array.isArray(options)) {
      throw clientOperationError('InvalidOpenOptions');
    }
    for (const key of Object.keys(options)) {
      if (!['stateDir', 'installation', 'durability', 'consentRefs', 'profile'].includes(key)) {
        throw clientOperationError('InvalidOpenOptions');
      }
    }
    // Freeze preserves the captured object's prototype, not its later state.
    // Read only original own DATA after the await; an inherited option added
    // meanwhile is unsupported backing, never a getter this Host may invoke.
    const openFields = Object.create(null);
    for (const name of ['stateDir', 'installation', 'durability', 'consentRefs', 'profile']) {
      const field = Object.getOwnPropertyDescriptor(options, name);
      if (field === undefined) {
        if (name in options) throw clientOperationError('NodeInitialControlInputUnavailable');
      } else {
        if (!Object.hasOwn(field, 'value')) throw clientOperationError('NodeInitialControlOriginalChanged');
        openFields[name] = field.value;
      }
    }
    if (openFields.stateDir !== undefined &&
          (typeof openFields.stateDir !== 'string' || !openFields.stateDir) ||
        openFields.installation !== undefined &&
          (openFields.installation === null || typeof openFields.installation !== 'object' ||
          Array.isArray(openFields.installation) || Object.hasOwn(openFields.installation, 'directory'))) {
      throw clientOperationError('InvalidOpenOptions');
    }
    // Resolve against the original call-time working directory after reading
    // the captured stateDir. Initialization awaits cannot redirect this Host.
    record.openStateDirectory = resolve(record.openWorkingDirectory, openFields.stateDir ?? '.actql');
    options = Object.assign(Object.create(null), {mode: 'local', owner: 'local',
      ...(openFields.durability === undefined ? {} : {durability: openFields.durability}),
      ...(openFields.consentRefs === undefined ? {} : {consentRefs: openFields.consentRefs}),
      ...(openFields.profile === undefined ? {} : {profile: openFields.profile}),
      installation: Object.assign(Object.create(null), openFields.installation,
        {directory: record.openStateDirectory})});
    record.openOptions = options;
  }
  if (initialEntry === 'connect' && options.mode === 'local' && options.owner === undefined) {
    // The same original supplier has already captured every descriptor. Match
    // the Local provider's explicit default without dropping hidden/unknown
    // fields or observing caller-owned options after the initialization await.
    options = Object.create(Object.getPrototypeOf(options), {
      ...Object.getOwnPropertyDescriptors(options),
      owner: {value: 'local', enumerable: true},
    });
    record.connectOptions = options;
  }
  // Host-owned values never enter the SDK's transport-options packet. Snapshot
  // both once before awaits; selecting a profile is not silently ignoring it.
  const {installation: suppliedInstallation, profile: requestedProfile,
    ...clientOptions} = options;
  // Only an explicit trusted caller selection consents to initial limited
  // Mock setup. A profile discovered later in Project data is not consent.
  record.explicitMockSelection = Object.hasOwn(options, 'profile') && requestedProfile === 'mock';
  let installation = suppliedInstallation;
  if (requestedProfile !== undefined && (typeof requestedProfile !== 'string' ||
      !requestedProfile || !requestedProfile.isWellFormed() ||
      requestedProfile.length > 65536)) {
    throw new TypeError('InvalidInstalledProjectProfile');
  }
  if (installation !== undefined && (installation === null ||
      typeof installation !== 'object' || Array.isArray(installation))) {
    throw new TypeError('InvalidInstalledHostOptions');
  }
  if (installation?.retainedRelationOutput !== undefined &&
      typeof installation.retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidLocalRetainedOutputConfiguration');
  }
  if (installation !== undefined) {
    const {hostCapacityPolicy: selected, hostLookupExecutionPolicy: lookupSelected,
      calendarArtifact: suppliedCalendar, valuesMaxRows, ...rest} = installation;
    validateValuesMaxRows(valuesMaxRows);
    const hostCapacityPolicy = snapshotHostCapacityPolicy(selected);
    const hostLookupExecutionPolicy = snapshotHostLookupExecutionPolicy(lookupSelected);
    const calendarArtifact = snapshotInstalledCalendar(suppliedCalendar);
    installation = {...rest, hostCapacityPolicy, hostLookupExecutionPolicy, calendarArtifact, valuesMaxRows};
    if (installation.effectProfilePaths !== undefined) {
      installation.effectProfilePaths = installedEffectPaths(installation);
    }
  }
  // Discover only on the Local installation side. The same module instance
  // admits and later consumes these originals; Remote clients do no such I/O.
  const projectDirectory = process.cwd();
  enableNodeCompileCache();
  moon = await import(runtimeUrl.href);
  assertInitialControlInstallationCurrent(control, originals);
  record.runtime = moon;
  project = await loadInstalledProjectConfiguration(moon, {directory: projectDirectory,
    initialControl: control, initialControlOriginals: originals});
  assertInitialControlInstallationCurrent(control, originals);
  record.project = project;
  projectProfile = selectInstalledProjectProfile(moon, project, requestedProfile, 65536);
  record.projectProfile = projectProfile;
  const selectedProfile = projectProfile.originalsForRuntime(moon);
  originalInstallation.initialControl = control;
  const root = installation?.directory === undefined ? project?.stateDirectory ?? localStateRoot() :
    resolve(installation.directory);
  Object.assign(originalInstallation, {root, project, projectProfile, projectRuntime: moon,
    authorization: installation?.authorization,
    connectorTable: installation?.connectorTable,
    sourceProfilePath: installation?.sourceProfilePath,
    sourceProfilePaths: installation?.sourceProfilePaths,
    sourceSelectorNamespace: installation?.sourceSelectorNamespace,
    sourceNamespace: installation?.sourceNamespace,
    resolveSourceSecret: installation?.resolveSourceSecret,
    effectProfilePath: installation?.effectProfilePath,
    effectProfilePaths: installation?.effectProfilePaths,
    resolveEffectSecret: installation?.resolveEffectSecret,
    modelInstallation: installation?.modelInstallation,
    calendarArtifact: installation?.calendarArtifact,
    registerModelProviders: installation?.registerModelProviders,
    verifyRequestValuePolicy: installation?.verifyRequestValuePolicy,
    resultDataPolicy: installation?.resultDataPolicy,
    inferEvidence: installation?.inferEvidence,
    hostCapacityPolicy: installation?.hostCapacityPolicy,
    hostLookupExecutionPolicy: installation?.hostLookupExecutionPolicy,
    retainedRelationOutput: installation?.retainedRelationOutput === undefined
      ? false : installation.retainedRelationOutput,
    observation: installation?.observation,
    valuesMaxRows: installation?.valuesMaxRows});
  record.installation = originalInstallation;
  if (selectedProfile.selected === 'mock') {
    const services = preparation.sourceInitializationServices(moon, root, userInfo().username);
    const baseEnvironmentWire = selectInstalledLocalMaterializationEnvironment(moon,
      preparation.readEnvironmentSource().trimEnd(), originalInstallation.hostCapacityPolicy,
      originalInstallation.hostLookupExecutionPolicy ?? localResourceLookupExecutionPolicy(moon,
        moon.clientLocalResourcePolicyOriginal(), localFilesLookupExecutionPolicy([LOCAL_FILES_DEFAULT_LIMITS])));
    originalInstallation.declaredFileBaseEnvironmentWire = baseEnvironmentWire;
    // Retain before module/runtime selection and before the first dynamic
    // declaration. Later Host installation borrows this same service/parent.
    record.declaredFileInstallationInventory = originalInstallation.declaredFileInstallationInventory =
      createDeclaredFileInstallationInventory({moon, project, services, baseEnvironmentWire, runtimeUrl,
        assertCurrent: () => assertInitialControlInstallationCurrent(control, originals)});
    // The actual Source admission precedes its connection/catalogue/control
    // preparation. Initial control cannot fund those allocations or file I/O.
    // A missing original refuses here, with no legacy snapshot/read fallback.
    sourceManaged = await prepareSourceManagedInstallation(originals);
    sourceManagedClose = sourceManaged.close;
    record.sourceManaged = sourceManaged;
    // The same actual Root called the fixed operation above under its own
    // prior managed holding, then acquired the original file/child backing.
    // Do not reconstruct missing metadata after its returned admission.
    const retained = profiles.mockPreparation(host, originalInstallation, host);
    mockPreparation = retained.view;
    if (mockPreparation === undefined || retained.runtime !== moon) {
      throw clientOperationError('InstalledMockPreparationUnavailable');
    }
    record.mockPreparation = mockPreparation;
    mockPreparation.originalsForRuntime(moon);
    sourceManaged.assertCurrent();
  } else if (selectedProfile.selected === undefined && project !== undefined) {
    // This existing Connector prepares declaration DATA without business
    // discovery. Retain its actual factory result before post-await current;
    // the later Host installs real Root/readers on the same joint service.
    projectSourcePreparation = await prepareInstalledProjectLocalFiles(moon, project, {
      limits: LOCAL_FILES_DEFAULT_LIMITS,
      assertCurrent: () => assertInitialControlInstallationCurrent(control, originals),
    });
    record.projectSourcePreparation = projectSourcePreparation;
    originalInstallation.projectSourcePreparation = projectSourcePreparation;
    assertInitialControlInstallationCurrent(control, originals);
    if (projectSourcePreparation !== undefined) {
      sourceManaged = await prepareProjectSourceManagedInstallation(originals);
      record.sourceManaged = sourceManaged;
      sourceManagedClose = sourceManaged.close;
      assertSourceManagedInstallationCurrent(sourceManaged, originals);
    }
  }
  if (selectedProfile.selected !== undefined && selectedProfile.selected !== 'mock') {
    // No other named physical-profile supplier exists here. Keep its original
    // admitted choice unavailable instead of falling back to live profiles.
    throw clientOperationError('InstalledProjectProfileUnavailable');
  }
  const configurationReader = originalInstallation.sourceProfilePath === undefined &&
    originalInstallation.sourceProfilePaths === undefined && process.env.ACTQL_LOCAL_SOURCE_PROFILE === undefined ? undefined :
    installedSourceConfigurationReader(preparation.sourceInitializationServices(moon, root, userInfo().username));
  const identity = await embeddedInstallationIdentity(root, installation, project, moon,
    projectSourcePreparation, configurationReader);
  assertInitialControlInstallationCurrent(control, originals);
  const client = await profiles.connect(root, identity,
    () => {
      // This same registry entry now owns even a refused opening/current gate.
      adopted = true;
      assertInitialControlInstallationCurrent(control, originals);
      return openInstalledHost(originalInstallation, preparation);
    }, clientOptions, host, releaseUnadopted, initialControl);
  return initialEntry === 'open'
    ? Object.freeze({...client, info: Object.freeze({stateDir: root})}) : client;
  } catch (cause) {
    // An unadopted preparation is released here. An opened or failed
    // Host, however, keeps this same view until its existing shutdown finishes.
    if (adopted) throw cause; // The original opened/failed Host owns cleanup.
    if (observedClose !== undefined) throw cause;
    if (control === undefined) {
      throw retainInstalledHostRuntimeFailure(cause,
        () => {
          retirePreparationReferences();
          profiles.retirePreparation(host, originalInstallation, host);
        });
    }
    const retained = await retainInstalledHostInitializationFailure(cause, {initialControl});
    if (retained.cleanupHandle.status().pending === false) throw cause;
    throw retained;
  }
}
