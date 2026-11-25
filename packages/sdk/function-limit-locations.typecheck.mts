import {type CheckOutcome, explainCheckReason} from '@actql/sdk';
declare const outcome: CheckOutcome;
if (outcome.outcome === 'completed') {
  for (const limit of outcome.report.coverage.limits) {
    const reason = explainCheckReason(limit);
    if ('facts' in limit && limit.facts.issue === 'function_lowering_unresolved' && limit.location) {
      const source: 'source' = limit.location.document_id;
      const kind: 'text' = limit.location.kind;
      const start: number = limit.location.start_byte;
      void source; void kind; void start;
    } else if ('location' in limit && limit.location?.kind === 'structured') {
      const document: 'program' = limit.location.document_id;
      const pointer: string = limit.location.pointer;
      void document; void pointer;
    }
    void reason;
  }
}
// @ts-expect-error Check explanations confer no retry permission.
explainCheckReason({code: 'implementation_limit'}).next;
