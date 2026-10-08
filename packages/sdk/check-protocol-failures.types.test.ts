import {explainCheckFailure, getCheckFailureInput, ClientError,
  type CheckFailureExplanation} from '@actql/sdk';
import {checkOutcomeProtocol} from '@actql/client-wire';
const error: unknown = new ClientError('InvalidHostCheckOutcome');
const explanation: CheckFailureExplanation | undefined = explainCheckFailure(error, {locale: 'ja'});
if (explanation?.kind === 'uninterpretable') {
  const problem: 'unknown_outcome' = explanation.problem;
  void problem;
  // @ts-expect-error A failed observation has no successful check verdict.
  explanation.verdict;
  // @ts-expect-error Presentation does not authorize retry.
  explanation.next;
}
const input = getCheckFailureInput(error);
if (input?.kind === 'text') {
  const text: string = input.text;
  void text;
  // @ts-expect-error No Host document revision is fabricated for a rejected reply.
  input.revision;
  // @ts-expect-error Submitted snapshots are immutable.
  input.text = 'edited';
}
if (input?.kind === 'program') {
  const program: Readonly<Record<string, unknown>> = input.program;
  void program;
  // @ts-expect-error A structured snapshot has no invented source text.
  input.text;
}
const variant: 'completed' | 'failed' | 'unavailable' | undefined = checkOutcomeProtocol.outcomes[0];
void variant;
