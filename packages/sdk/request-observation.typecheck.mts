import {explainRequestLookup, explainSubmission, formatRequestLookup,
  type RequestLookup, type RequestLookupExplanation} from '@actql/sdk';
declare const lookup: RequestLookup;
const explanation: RequestLookupExplanation | undefined = explainRequestLookup(lookup);
if (explanation) {
  // @ts-expect-error An observation grants no execution permission.
  const accepted: boolean = explanation.accepted;
  // @ts-expect-error Original lookup references are immutable.
  explanation.next.operation = 'submit';
  if (explanation.observation === 'request_held') {
    const state: 'waiting_checkpoint' | 'resuming' | 'ended' = explanation.preparationState;
    const durability: 'durable' = explanation.durability;
    void [state, durability];
    // @ts-expect-error Held preparation has no Run status fact.
    const status: string = explanation.runStatus;
  }
  if (explanation.observation === 'run_reference_received') {
    const operation: 'status' = explanation.next.operation;
    const definition: string = explanation.next.ref.runDefinitionCid;
    void [operation, definition];
  }
  if (explanation.observation === 'lookup_unresolved') {
    // @ts-expect-error Absence supplies no preparation facts.
    const state: string = explanation.preparationState;
  }
}
const submission = explainSubmission(lookup);
if (submission?.observation === 'request_held') {
  const preparation: string = submission.prepareAttemptId;
  void preparation;
}
const text: string | undefined = formatRequestLookup(lookup, {format: 'json'});
void text;
