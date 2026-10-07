import {explainDeliveryAttempt, formatDeliveryAttempt,
  type DeliveryAttemptLookup, type DeliveryObservationExplanation} from '@actql/sdk';
declare const lookup: DeliveryAttemptLookup;
const explanation: DeliveryObservationExplanation | undefined = explainDeliveryAttempt(lookup);
if (explanation) {
  const operation: 'deliveryAttempt' = explanation.next.operation;
  void operation;
  // @ts-expect-error An observation does not authorize a new payload read.
  explanation.next.operation = 'rows';
  // @ts-expect-error Original lookup targets are immutable.
  explanation.next.ref.runDefinitionCid = 'sha256:changed';
  // @ts-expect-error Sink-confirmed bytes are not yielded rows.
  const rows: number = explanation.rowsYielded;
  // @ts-expect-error A Host release receipt is not application persistence.
  const persisted: boolean = explanation.applicationPersisted;
  if (explanation.observation === 'host_delivery_succeeded') {
    const receipt: string = explanation.hostReleaseReceiptCid;
    const bytes: number = explanation.hostConfirmedByteCount;
    void [receipt, bytes];
  }
  if (explanation.observation === 'lookup_unresolved') {
    // @ts-expect-error An absent lookup has no receipt or confirmed byte count.
    const bytes: number = explanation.hostConfirmedByteCount;
  }
}
const rendered: string | undefined = formatDeliveryAttempt(lookup, {format: 'json'});
void rendered;
