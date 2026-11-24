// Existing Run/Request borrower and existing observation queue only. This is
// metadata, not a task scheduler, Sample, control grant or fallback identity.
import {checked} from '../host-common/runtime-result.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';

import type {installHostObservation} from '../host-common/observation.mjs';
import type {WireRunRef} from '@actql/client-wire';

type Projection = NonNullable<ReturnType<typeof installHostObservation>>;
type CoreRecord = (record: unknown) => unknown;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Control = Readonly<{
  prepareClientLogicalObservation(run: unknown, executionOwner: unknown,
    definition: unknown, limits: Limits): unknown;
}>;
type Moon = Readonly<{
  clientProgramPrepareLogicalObservation?: (run: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, bytes: number, nodes: number, depth: number) => unknown;
  clientProgramLogicalObservationCleanup?: (result: unknown) => unknown;
  clientProgramAttachLogicalObservation?: (original: unknown, captured: unknown) => unknown;
  clientProgramBeginLogicalObservation?: (original: unknown, phase: string) => unknown;
  clientProgramCaptureLogicalObservationRecord?: CoreRecord;
  clientProgramLogicalObservationRecordState?: CoreRecord;
  clientProgramLogicalObservationRecordKey?: CoreRecord;
  clientProgramLogicalObservationRecordPhase?: CoreRecord;
  clientProgramReturnLogicalObservationRecord?: (record: unknown) => void;
  clientProgramReturnLogicalObservation?: CoreRecord;
}>;
type AuthorizedOperation = Readonly<{
  principalId: string | undefined; indexKey: WireRunRef | undefined; purpose: 'run-plan';
}>;
type Authorize = (operation: AuthorizedOperation) => boolean;

// Positional originals avoid constructing an unbacked per-Run option bag. The
// complete Core/Host control quote precedes createOwnedObservation's objects.
export function prepareInstalledLogicalObservation(moon: Moon, control: Control, managedRun: unknown,
  executionOwner: unknown, definition: unknown, observation: unknown) {
  if (!isHostObservationProjection(observation) ||
      !observation.canObserveLogicalBoundaries() || managedRun === undefined ||
      executionOwner === undefined ||
      typeof moon.clientProgramPrepareLogicalObservation !== 'function' ||
      typeof moon.clientProgramLogicalObservationCleanup !== 'function' ||
      typeof moon.clientProgramAttachLogicalObservation !== 'function' ||
      typeof moon.clientProgramBeginLogicalObservation !== 'function' ||
      typeof moon.clientProgramCaptureLogicalObservationRecord !== 'function' ||
      typeof moon.clientProgramLogicalObservationRecordState !== 'function' ||
      typeof moon.clientProgramLogicalObservationRecordKey !== 'function' ||
      typeof moon.clientProgramLogicalObservationRecordPhase !== 'function' ||
      typeof moon.clientProgramReturnLogicalObservationRecord !== 'function' ||
      typeof moon.clientProgramReturnLogicalObservation !== 'function') return undefined;
  // Capture all installed functions/receiver before Core current callbacks or
  // the first await. No later namespace replacement changes an original loan.
  const cleanup = moon.clientProgramLogicalObservationCleanup,
    attach = moon.clientProgramAttachLogicalObservation,
    begin = moon.clientProgramBeginLogicalObservation,
    capture = moon.clientProgramCaptureLogicalObservationRecord,
    state = moon.clientProgramLogicalObservationRecordState,
    key = moon.clientProgramLogicalObservationRecordKey,
    phase = moon.clientProgramLogicalObservationRecordPhase,
    release = moon.clientProgramReturnLogicalObservationRecord,
    close = moon.clientProgramReturnLogicalObservation;
  let original: unknown, enabled = true, result: unknown;
  try {
    result = control.prepareClientLogicalObservation(managedRun, executionOwner, definition, localContractLimits);
    original = checked(result);
  }
  catch {
    enabled = false;
    observation.logicalBoundaryUnavailable();
    // Only the typed constructor's SAME pending-return token can be retained.
    // A refusal is not a projected/unavailable boundary or known Run outcome.
    if (result === undefined) return undefined;
    original = Reflect.apply(cleanup, moon, [result]);
    if (original === undefined) return undefined;
  }
  return createOwnedObservation(moon, original, observation, enabled,
    attach, begin, capture, state, key, phase, release, close);
}

function createOwnedObservation(moon: Moon, original: unknown, observation: Projection, enabled: boolean,
  attach: NonNullable<Moon['clientProgramAttachLogicalObservation']>,
  begin: NonNullable<Moon['clientProgramBeginLogicalObservation']>,
  capture: CoreRecord, state: CoreRecord, key: CoreRecord, phase: CoreRecord,
  release: NonNullable<Moon['clientProgramReturnLogicalObservationRecord']>, close: CoreRecord) {
  let active = enabled, closing = false, authorize: Authorize | undefined, ref: WireRunRef | undefined,
    principalId: string | undefined, runId: string | undefined;
  return Object.freeze({
    attach(captured: unknown, selectedRef: WireRunRef, principal: string,
      authorizeRead: Authorize, acceptedRunId: unknown) {
      if (!active || closing) return;
      // All Node wrappers, method environments and operation memos are within
      // the already admitted SAME Request control/record construction quote.
      ref = selectedRef; principalId = principal; authorize = authorizeRead;
      try {
        if (typeof authorize !== 'function') throw new TypeError('LogicalObservationAuthorityUnavailable');
        if (typeof acceptedRunId !== 'string' || acceptedRunId.length > 128) {
          throw new TypeError('LogicalObservationRunIdentityUnavailable');
        }
        checked(Reflect.apply(attach, moon, [original, captured]));
        // Borrow the SAME accepted definition's original, not another Journal
        // lookup or an identity inferred from the graph, task or Facts CID.
        runId = acceptedRunId;
      } catch {observation.logicalBoundaryUnavailable(); active = false;}
    },
    project(selectedPhase: string, task: number) {
      if (!active || closing || original === undefined || authorize === undefined || runId === undefined) return undefined;
      let record: unknown;
      try {record = checked(Reflect.apply(begin, moon, [original, selectedPhase]));}
      catch {observation.logicalBoundaryUnavailable(); return undefined;}
      // Closures, copied metadata and Account memos follow admission.
      // The immediate authority path never awaits an application answer. Each current outstanding delivery has its own real loan.
      const operation: AuthorizedOperation = Object.freeze({principalId, indexKey: ref, purpose: 'run-plan'});
      let transferred = false;
      const current = (selected: AuthorizedOperation) => {
        if (record === undefined || authorize!(selected) !== true) return false;
        checked(Reflect.apply(state, moon, [record]));
        if (authorize!(selected) !== true) return false;
        checked(Reflect.apply(state, moon, [record]));
        return true;
      };
      const custody = Object.freeze({
        current() {
          // SAME bounded DATA tuple, fresh actual Account/Common observation.
          // The immediate Owner does not cache any prior allowed decision.
          return current(operation);
        },
        release() {
          if (record === undefined) return;
          // The queue drops copied payload aliases before this original token.
          // A thrown return retains the SAME token for the existing queue retry.
          Reflect.apply(release, moon, [record]);
          record = undefined;
        },
      });
      {
        try {
          if (authorize(operation) !== true) return;
          checked(Reflect.apply(capture, moon, [record]));
          if (current(operation) !== true) return;
          const projected = checked(Reflect.apply(state, moon, [record]));
          const boundary = projected === 'projected'
            ? {state: projected, keyWire: checked(Reflect.apply(key, moon, [record])),
              phase: checked(Reflect.apply(phase, moon, [record]))}
            : projected === 'not_projected'
              ? {state: projected, reason: 'not_projected'} : undefined;
          if (boundary === undefined) throw new TypeError('InvalidLogicalObservationProjection');
          if (current(operation) !== true) return;
          // This fixed Host projection consumes custody even when selection,
          // durable budget or queue admission drops the optional event.
          transferred = true;
          observation.logicalBoundary({ref, task, runId}, boundary, custody);
        } catch {observation.logicalBoundaryUnavailable();}
        finally {if (!transferred) observation.returnLogicalBoundary(custody);}
      }
    },
    close() {
      closing = true; active = false;
      // Queued records own their already admitted copies. Drop this producer
      // alias before the lower owner may acknowledge or retry its return.
      runId = undefined;
      if (original === undefined) return;
      // No producer semantic alias may outlive the lower ACK. A
      // pending return keeps the SAME cleanup token and authority for queued
      // deliveries; it does not permit further projection or task work.
      checked(Reflect.apply(close, moon, [original]));
      original = authorize = ref = principalId = undefined;
    },
  });
}
