// Project Common entry facts only. Diagnostic delivery times are not the
// physical invocation clock, and no event proves network delivery or success.
export function createInferPhysicalObservation({observation, reference, receiptAt}) {
  let physical;
  return facts => {
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
