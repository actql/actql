import {explainRunObservationFailure} from '@actql/sdk';
import {runStateProtocol} from '@actql/client-wire';
const view = explainRunObservationFailure(new Error());
if (view) {
  const operation: 'status' | 'wait' | 'reconcile' = view.operation;
  const read: 'status' = view.next.operation;
  if (view.kind === 'uninterpretable') {
    const problem: 'unknown_state' = view.problem;
    void problem;
  }
  // @ts-expect-error Rejected observations do not establish a status.
  view.status;
  // @ts-expect-error Original lookup identity is immutable.
  view.next.ref.runDefinitionCid = 'changed';
  void operation; void read;
}
const state: 'preparing' | 'running' | 'waiting_checkpoint' | 'resuming' |
  'needs_reconciliation' | 'succeeded' | 'failed' | 'cancelled' = runStateProtocol.statuses[0];
void state;
