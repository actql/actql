import type {CheckOutcome} from '@actql/sdk';
import {explainCheckReason, getCheckInput, resolveCheckLocation} from '@actql/sdk';
declare const outcome: CheckOutcome;
if (outcome.outcome === 'completed') {
  for (const reason of outcome.report.reasons) {
    if (reason.facts && 'document' in reason.facts) {
      const document: 'parameters' | 'parameter_declarations' = reason.facts.document;
      const input = getCheckInput(outcome, document);
      const explanation = explainCheckReason(reason);
      const location = reason.location && resolveCheckLocation(outcome, reason.location, input);
      void explanation; void location;
      // @ts-expect-error Source text is not a binding-JSON input document.
      const text: 'source' = document;
      void text;
    }
  }
}
