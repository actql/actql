import {type CheckOutcome, explainCheckReason} from '@actql/sdk';
declare const outcome: CheckOutcome;
if (outcome.outcome === 'completed') {
  for (const limit of outcome.report.coverage.limits) {
    const reason = explainCheckReason(limit);
    if ('location' in limit && limit.location) {
      const source: 'source' = limit.location.document_id;
      const kind: 'text' = limit.location.kind;
      void source; void kind;
    }
    void reason;
  }
}
// @ts-expect-error Check explanations confer no retry permission.
explainCheckReason({code: 'implementation_limit'}).next;
