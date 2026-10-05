import {type CheckOutcome, type Client, explainCheckReason} from '@actql/sdk';

type Reason = Extract<CheckOutcome, {outcome: 'completed'}>['report']['reasons'][number];
const reason: Reason = {code: 'query_expression_invalid', facts: {issue: 'expected_boolean'}};
explainCheckReason(reason);
// @ts-expect-error Known facts remain closed to a private provider issue.
const unknownIssue: Reason = {code: 'query_expression_invalid', facts: {issue: 'private_provider_issue'}};
// @ts-expect-error Public predicate facts contain no submitted value.
const privateValue: Reason = {code: 'query_expression_invalid', facts: {issue: 'expected_boolean', value: 1}};
void unknownIssue; void privateValue;

declare const client: Client;
const outcome = await client.check('SELECT id FROM records WHERE id', {format: 'sql'});
if (outcome.outcome === 'completed') {
  for (const reason of outcome.report.reasons) {
    if (reason.facts && 'issue' in reason.facts && reason.facts.issue === 'expected_boolean') {
      const explanation = explainCheckReason(reason);
      const summary: string = explanation.summary;
      void summary;
      // @ts-expect-error An advisory explanation is not an executable edit.
      explanation.apply();
    }
  }
}
