import {getSubmissionCheckObservation, getCheckInput, resolveCheckLocation,
  resolveCheckTextRange, getCheckFixes, explainCheckReason} from '@actql/sdk';
import type {Client} from '@actql/sdk';
declare const client: Client;
try {
  await client.start({version: 'actql/0.1', id: 'p'});
} catch (error: unknown) {
  const checked = getSubmissionCheckObservation(error);
  if (checked?.outcome === 'completed') for (const reason of checked.report.reasons) {
    void explainCheckReason(reason);
    if (reason.location?.kind === 'structured' && reason.location.document_id === 'program') {
      const original = getCheckInput(checked, 'program', reason.location.revision);
      if (original?.kind === 'structured') {
        const snapshot: unknown = original.value;
        const located = resolveCheckLocation(checked, reason.location, original);
        const pointer: string | undefined = located?.kind === 'structured' ? located.pointer : undefined;
        void snapshot; void pointer;
        void resolveCheckTextRange(checked, reason.location, original);
      }
    }
  }
  if (checked) void getCheckFixes(checked);
}
