/** Admit existing canonical Checkpoint bytes through the common Owner.
 * Returns its JSON success/refusal envelope; performs no physical I/O. */
export declare function checkpointAdmit(wire: string): string;

/** Confirm exact persisted bytes before projecting waiting state.
 * The Host must separately commit its Run transition before publishing this
 * projection. A projection grants neither approval nor permission to resume. */
export declare function checkpointWaitingState(sealedWire: string,
  storedWire: string, updatedAt: string, declaredResultsJson: string): string;
