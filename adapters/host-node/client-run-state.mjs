// Public fallback observation uses the same original request Journal as the
// ordinary Host. Publication success alone cannot issue a state revision.
import {authorizeRunStateRequest, inspectAuthorizedRunState} from
  '../host-common/run-state-access.mjs';
import {observeOriginalClientRequestJournalCustody} from
  './client-request-journal.mjs';

const observations = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function installNodeClientRunStateObservation({journal, requestControl,
  publicationControl}) {
  // Only the existing physical Journal constructor installs this nominal
  // member. A copied Journal, callback or object returning a revision cannot.
  const custody = observeOriginalClientRequestJournalCustody(journal);
  if (custody.journalClosed) fail('RunStateObservationUnavailable');
  const observation = Object.freeze({});
  observations.set(observation, {journal, requestControl, publicationControl,
    lookup: journal.lookupRunDefinition, publish: journal.publishRunState});
  return observation;
}

export async function observeClientRunState(observation, service, request) {
  const installed = observations.get(observation);
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
      if (error?.code !== 'RunStateObservationChanged') throw error;
    }
  }
  fail('RunStateObservationUnstable');
}
