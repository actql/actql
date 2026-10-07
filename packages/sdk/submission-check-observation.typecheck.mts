import {getSubmissionCheckObservation, getCheckInput, resolveCheckLocation} from './index.mjs';
import type {CheckOutcome} from './index.mjs';
const checked: CheckOutcome | undefined = getSubmissionCheckObservation(new Error());
if (checked?.outcome === 'completed') {
  for (const reason of checked.report.reasons) {
    if (reason.location) {
      const original = getCheckInput(checked, reason.location.document_id, reason.location.revision);
      void resolveCheckLocation(checked, reason.location, original);
    }
  }
}
