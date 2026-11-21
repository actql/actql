// Public fallback observation uses the same original request Journal as the
// ordinary Host. Publication success alone cannot issue a state revision.
import {authorizeRunStateRequest, inspectAuthorizedRunState} from
  '../host-common/run-state-access.mjs';
import {observeOriginalClientRequestJournalCustody} from './client-request-journal.mjs';

import type {WireRunRef, WireRunState} from '../../packages/client-wire/index.js';
import type {RunStateRequest, RunStateService} from '../host-common/run-state-access.mjs';

type Journal = Readonly<{
  lookupRunDefinition(ref: WireRunRef, requestControl: unknown, publicationControl: unknown):
    object | undefined;
  publishRunState(frame: object, state: WireRunState, requestControl: unknown,
    publicationControl: unknown): string;
}>;
type ObservationInstallation = Readonly<{
  journal: Journal;
  requestControl: unknown;
  publicationControl: unknown;
}>;
declare const observationBrand: unique symbol;
type Observation = Readonly<{[observationBrand]: true}>;
type SelectedObservation = ObservationInstallation & Readonly<{
  lookup: Journal['lookupRunDefinition'];
  publish: Journal['publishRunState'];
}>;

const observations = new WeakMap<Observation, SelectedObservation>();
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };

export function installNodeClientRunStateObservation({journal, requestControl,
  publicationControl}: ObservationInstallation): Observation {
  // Only the existing physical Journal constructor installs this nominal
  // member. A copied Journal, callback or object returning a revision cannot.
  const custody: Readonly<{journalClosed: boolean}> = observeOriginalClientRequestJournalCustody(journal);
  if (custody.journalClosed) fail('RunStateObservationUnavailable');
  const observation = Object.freeze({}) as Observation;
  observations.set(observation, {journal, requestControl, publicationControl,
    lookup: journal.lookupRunDefinition, publish: journal.publishRunState});
  return observation;
}

export async function observeClientRunState(observation: Observation | undefined,
  service: RunStateService, request: RunStateRequest): Promise<WireRunState> {
  // WeakMap.get returns undefined for the optional absent installation too.
  const installed = observations.get(observation as Observation);
  const selected = Object.freeze({...request,
    indexKey: Object.freeze({...request.indexKey})});
  // Keep authorization before existence queries, including missing ports.
  await authorizeRunStateRequest(service, selected);
  if (installed === undefined) fail('RunStateObservationUnavailable');
  const {journal, requestControl, publicationControl, lookup, publish} = installed;
  for (let attempt = 0; attempt < 8; attempt++) {
    const original = lookup.call(journal, selected.indexKey, requestControl,
      publicationControl);
    if (original === undefined) fail('RunStateAccessDenied');
    const state = await inspectAuthorizedRunState(service, selected);
    try {
      return Object.freeze(JSON.parse(publish.call(journal, original, state,
        requestControl, publicationControl)));
    } catch (error) {
      // Only a stale pre-commit frame is reobserved. Unknown COMMIT and all
      // other failures propagate without replay, replacement or counter reset.
      if ((error as {code?: unknown} | null)?.code !== 'RunStateObservationChanged') throw error;
    }
  }
  fail('RunStateObservationUnstable');
}
