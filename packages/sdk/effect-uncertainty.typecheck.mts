import {explainEffectUncertainty} from '@actql/sdk';

declare const response: unknown;
const explanation = explainEffectUncertainty(response);
if (explanation) {
  const observation: 'effect_outcome_unknown' = explanation.observation;
  const stop: 'confirmed' | 'unknown' = explanation.physicalStop;
  const revision: number | undefined = explanation.controlRevision;
  const operation: 'status' = explanation.next.operation;
  const runDefinitionCid: string = explanation.next.ref.runDefinitionCid;
  const effects: readonly string[] = explanation.effects;
  void observation; void stop; void revision; void operation;
  void runDefinitionCid; void effects;
  // @ts-expect-error This advice does not authorize resending a write.
  const write: 'submit' = explanation.next.operation;
  // @ts-expect-error Absence of a control observation leaves the revision unknown.
  const certainRevision: number = explanation.controlRevision;
  // @ts-expect-error Effect identities in the observation are immutable.
  explanation.effects.push('new-effect');
  // @ts-expect-error The original Run reference cannot be replaced.
  explanation.next.ref.runDefinitionCid = 'edited-run';
  // @ts-expect-error Physical stop does not supply a resource-release receipt.
  explanation.resourcesReleased;
  // @ts-expect-error No private provider response is available in this explanation.
  explanation.providerError;
  void write; void certainRevision;
}
