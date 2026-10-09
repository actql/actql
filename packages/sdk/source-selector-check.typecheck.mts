import {getCheckReasonCatalogEntry, getCheckInput, resolveCheckLocation,
  explainCheckReason, type Client, type CheckOutcome, type KnownCheckReasonCode} from '@actql/sdk';
declare const client: Client;
const code: KnownCheckReasonCode = 'source_selector_unregistered';
const facts: Extract<NonNullable<Extract<CheckOutcome, {outcome: 'completed'}>['report']['reasons'][number]['facts']>, {connector: string}> = {
  namespace: 'registrations', connector: 'missing', resource: 'r', view: 'records',
};
const result = await client.check({version: 'actql/0.1', id: 'authored'}, {kind: 'program', scope: 'bound_input'});
if (result.outcome === 'completed') {
  for (const reason of result.report.reasons) {
    void explainCheckReason(reason);
    if (reason.location?.kind === 'structured') {
      const input = getCheckInput(result, 'program', reason.location.revision);
      void resolveCheckLocation(result, reason.location, input);
    }
  }
}
void facts; void getCheckReasonCatalogEntry(code);
