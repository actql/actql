import {explainReadFailure, type ReadFailureExplanation} from '@actql/sdk';

declare const error: unknown;
const explanation: ReadFailureExplanation | undefined = explainReadFailure(error);
if (explanation) {
  const observation: 'read_incomplete' | 'cleanup_unknown' = explanation.observation;
  const count: number = explanation.rowsYielded;
  const cleanup: 'unknown' | undefined = explanation.cleanup;
  void cleanup;
  const operation: 'deliveryAttempt' = explanation.next.operation;
  const attemptId: string = explanation.next.attemptId;
  const resultName: string = explanation.next.resultName;
  const runDefinitionCid: string = explanation.next.ref.runDefinitionCid;
  void observation; void count; void operation; void attemptId; void resultName; void runDefinitionCid;
  // @ts-expect-error A lookup target cannot be replaced by another read.
  explanation.next.attemptId = 'changed';
  // @ts-expect-error Returned rows are not retained as explanation facts.
  explanation.rows;
  // @ts-expect-error Read progress does not establish a successful Run.
  explanation.runSucceeded;
  // @ts-expect-error A presentation hint is not retry permission.
  explanation.retryAllowed;
}
