// Run-unit Source approval retains the original Account and read occurrence.
// The installed Source reader and Journal still own physical entry and cleanup.
import {contentCid} from './local-account-config.mjs';
import {computationSourceCheckpointId, fail, IDENTIFIER} from './client-checkpoint-admission-inputs.mjs';

import type {CapturedOccurrence} from './client-checkpoint-admission-inputs.mjs';
import type {createLocalAuthorizationGate as installGate} from './local-account-config.mjs';
import type {openContinuationEvidence} from './local-continuation-evidence.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

type Options = NonNullable<Parameters<typeof installGate>[0]>;
type Gate = Awaited<ReturnType<typeof installGate>>;
type Configuration = Pick<Options, 'accountConfiguration' | 'context'> & Readonly<{sourceRef?: string}>;
type Source = Readonly<{configuration: Configuration; gate: Pick<Gate, 'configurationCid' | 'contextCid'>}>;
type View = NonNullable<ReturnType<ReturnType<typeof openSqliteCheckpointJournal>['inspect']>>;
type Deferral = NonNullable<Options['deferral']>;
type AuthorizationInput = Readonly<{
  runId: string; runDefinitionCid: string; unitId: string; occurrence: CapturedOccurrence;
  declaredResults: readonly string[]; continuation(): Promise<string> | string; beforeDefer(): unknown;
  journalPort?: Deferral['journal'];
}>;
type Ports = Readonly<{
  installedSource: ReturnType<typeof createCheckpointSourceSelection>;
  createLocalAuthorizationGate: typeof installGate;
  journal: Deferral['journal'];
  evidence: Pick<ReturnType<typeof openContinuationEvidence>, 'hold' | 'abandon' | 'settle' | 'open'>;
  accountConstruction: Options['accountConstruction'];
  decisionOptions: Pick<Options, 'decisionBudget' | 'decisionTimeoutMs'>;
  decide: Options['decide']; answeringAuthorities: Options['answeringAuthorities'];
  authorities: Deferral['authorities']; binding: Deferral['binding'];
  authorityScopeCid: string; ownerPrincipal: string; now(): number;
  maxReviewBytes: number; checkpointTtlMs: number;
}>;

export function createCheckpointSourceSelection<Installed extends Source>({sources, installedSources}:
  Readonly<{sources: readonly Configuration[] | undefined; installedSources: readonly Installed[]}>) {
  function installedSource(occurrence: CapturedOccurrence) {
    const installed = sources === undefined ? installedSources[0]
      : installedSources.find(item => item.configuration.sourceRef ===
        occurrence.checkedSource.sourceRef);
    if (installed === undefined ||
        (installed.configuration.sourceRef !== undefined &&
          installed.configuration.sourceRef !== occurrence.checkedSource.sourceRef)) {
      fail('HeldAcquisitionChanged');
    }
    return installed;
  }
  return installedSource;
}

export function createCheckpointComputationSource({installedSource, createLocalAuthorizationGate,
  journal, evidence, accountConstruction, decisionOptions, decide, answeringAuthorities,
  authorities, binding, authorityScopeCid, ownerPrincipal, now, maxReviewBytes, checkpointTtlMs}: Ports) {
  return {
    // A Source read inside an admitted Effect Run uses the same durable
    // Run-unit owner as Effect commit, but its own Source account and exact
    // acquisition occurrence. An Effect answer is never a read permit.
    async computationSourceAuthorization({runId, runDefinitionCid, unitId,
      occurrence, declaredResults, continuation, beforeDefer, journalPort = journal}: AuthorizationInput) {
      // The checked Program/Plan owns Source cardinality. This original port's
      // ordinal is not a second Host limit on the number of acquired Sources.
      if (!IDENTIFIER.test(runId ?? '') || !IDENTIFIER.test(unitId ?? '') ||
          typeof runDefinitionCid !== 'string' ||
          typeof continuation !== 'function' || typeof beforeDefer !== 'function' ||
          !Array.isArray(declaredResults) ||
          ![occurrence?.stage, occurrence?.input, occurrence?.task]
            .every(value => Number.isSafeInteger(value) && value! >= 0)) {
        fail('InvalidComputationSourceContinuation');
      }
      occurrence = JSON.parse(JSON.stringify(occurrence));
      const freeze = (value: unknown) => {
        if (value !== null && typeof value === 'object') {
          for (const item of Object.values(value)) freeze(item);
          Object.freeze(value);
        }
        return value;
      };
      freeze(occurrence);
      declaredResults = Object.freeze([...declaredResults]);
      const {configuration, gate: current} = installedSource(occurrence);
      const scope = Object.freeze({version: 'actql-effect-source-read-scope/0.1',
        run_definition_cid: runDefinitionCid, unit_id: unitId,
        authority_scope_cid: authorityScopeCid,
        principal_id: ownerPrincipal, occurrence});
      const scopeCid = contentCid(scope);
      const read = await createLocalAuthorizationGate({accountConstruction,
        accountConfiguration: configuration.accountConfiguration,
        context: configuration.context, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: journalPort, authorities, binding,
          async describe(view) {
            if (view.boundary !== 'acquisition' ||
                view.subject.subject_cid !== scopeCid) {
              fail('InvalidComputationSourceCheckpointBoundary');
            }
            // The acquisition owner confirms durable custody before the
            // continuation may refer to any earlier completed Source.
            await beforeDefer();
            const wire = await continuation();
            if (typeof wire !== 'string') fail('InvalidComputationSourceContinuation');
            const reviewWire = JSON.stringify({scope,
              configuration_cid: current.configurationCid,
              context_cid: current.contextCid});
            if (Buffer.byteLength(reviewWire) > maxReviewBytes) fail('CheckpointReviewTooLarge');
            const refs = await evidence.hold(`effect-${runId}`, runDefinitionCid, [
              {name: 'review_projection', wire: reviewWire},
              {name: 'continuation_record', wire},
            ]);
            const created = now();
            return {priorStatus: 'running', declaredResults, body: {
              checkpoint_id: computationSourceCheckpointId(runId, scopeCid),
              run_id: runId, run_definition_cid: runDefinitionCid,
              continuation_state_cid: refs[1],
              subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                continuation: 'resume_unit'},
              kind: 'read_access',
              required_artifact: {artifact_type: 'read_scope', artifact_cid: scopeCid},
              review_projection_cid: refs[0],
              human_summary: `Read ${occurrence.checkedSource.sourceRef} for Run ${runId}`,
              created_at: new Date(created).toISOString(),
              expires_at: new Date(created + checkpointTtlMs).toISOString(),
            }};
          },
        }});
      if (read.configurationCid !== current.configurationCid ||
          read.contextCid !== current.contextCid) {
        read.close();
        fail('SourceCheckpointConfigurationChanged');
      }
      return Object.freeze({scopeCid,
        assertCurrent: () => read.assertConfigurationCurrent(),
        authorize: (options?: Parameters<Gate['authorize']>[2]) => read.authorize('acquisition', occurrence.readTuple,
          {...options, subjectCid: scopeCid}),
        resume: (options?: Parameters<Gate['resume']>[2]) => read.resume('acquisition', occurrence.readTuple,
          {...options, subjectCid: scopeCid}),
        close: () => read.close(),
      });
    },
    async retainComputationSource(runId: string, runDefinitionCid: string, wire: string) {
      if (!IDENTIFIER.test(runId ?? '') || typeof runDefinitionCid !== 'string') {
        fail('InvalidComputationSourceContinuation');
      }
      const [semanticCid] = await evidence.hold(`effect-${runId}`, runDefinitionCid,
        [{name: 'source_capture', wire}]);
      return semanticCid;
    },
    // Called only by the acquisition custody owner after confirmed physical
    // close. A durable waiting/resuming Run still owns its evidence; a failed
    // pre-Checkpoint persistence has no Run row and can now retire safely.
    async retireComputationSources(runId: string) {
      if (!IDENTIFIER.test(runId ?? '')) fail('InvalidComputationSourceContinuation');
      await evidence.abandon(`effect-${runId}`);
      return evidence.settle();
    },
    async readComputationSource(view: View, semanticCid: string, maxBytes?: number) {
      if (view?.prepareAttemptId !== null ||
          !['read_access', 'model_invocation'].includes(view.kind)) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.bytes('source_capture', semanticCid, {maxBytes});
    },
    async computationSourceReferences(view: View) {
      if (view?.prepareAttemptId !== null ||
          !['read_access', 'model_invocation'].includes(view.kind)) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.held('source_capture');
    },
    async computationContinuation(view: View) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.record('continuation_record', view.continuationStateCid);
    },
  };
}
