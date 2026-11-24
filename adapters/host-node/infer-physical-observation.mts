// Project Common entry facts only. Diagnostic delivery times are not the
// physical invocation clock, and no event proves network delivery or success.
type Reference = Readonly<{namespaceId: string; authorityScopeCid: string}>;
type Receipt = Readonly<{
  attemptCid: string; runDefinitionCid: string; taskIndex: number; ordinal: number; attemptIndex: number;
}>;
type Facts = Readonly<{event: string; slot: number; attemptCid: string; outcome?: string}>;
type TransportObservation = Readonly<{
  ref: Reference & Readonly<{runDefinitionCid: string}>;
  task: number; slot: number; attempt: number; attemptCid: string; outcome: string | undefined;
}>;
type ObservationOptions = Readonly<{
  observation: Readonly<{
    noteLoss(): void;
    emit(owner: 'infer', event: 'transport_completed', data: TransportObservation): void;
  }>;
  reference: Reference;
  receiptAt(slot: number): Receipt | undefined;
}>;

export function createInferPhysicalObservation({observation, reference, receiptAt}: ObservationOptions) {
  let physical: Pick<Facts, 'slot' | 'attemptCid'> | undefined;
  return (facts: Facts) => {
    try {
      if (facts.event === 'before_invoke') return;
      if (facts.event === 'started') {
        physical = {slot: facts.slot, attemptCid: facts.attemptCid};
        return;
      }
      const interval = physical;
      physical = undefined;
      const receipt = receiptAt(facts.slot);
      if (!['returned', 'failed', 'cancelled'].includes(facts.event) ||
          interval === undefined || interval.slot !== facts.slot ||
          interval.attemptCid !== facts.attemptCid ||
          receipt?.attemptCid !== facts.attemptCid) {
        observation.noteLoss(); return;
      }
      observation.emit('infer', 'transport_completed', {
        ref: {...reference, runDefinitionCid: receipt.runDefinitionCid},
        task: receipt.taskIndex, slot: receipt.ordinal, attempt: receipt.attemptIndex,
        attemptCid: facts.attemptCid, outcome: facts.outcome,
      });
    } catch { observation.noteLoss(); }
  };
}
