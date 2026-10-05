import {type CheckOutcome, type Client, explainCheckReason} from '@actql/sdk';

type Reason = Extract<CheckOutcome, {outcome: 'completed'}>['report']['reasons'][number];
const reason: Reason = {code: 'query_expression_invalid', facts: {issue: 'expected_boolean'}};
explainCheckReason(reason);
// @ts-expect-error Known facts remain closed to a private provider issue.
const unknownIssue: Reason = {code: 'query_expression_invalid', facts: {issue: 'private_provider_issue'}};
// @ts-expect-error Public predicate facts contain no submitted value.
const privateValue: Reason = {code: 'query_expression_invalid', facts: {issue: 'expected_boolean', value: 1}};
void unknownIssue; void privateValue;

const selector: Reason = {code: 'graph_operation_invalid',
  facts: {operation: 'subgraph', issue: 'invalid_node_selector'}};
explainCheckReason(selector);
// @ts-expect-error Operation and issue must belong to the same closed facts variant.
const mismatchedSelector: Reason = {code: 'graph_operation_invalid', facts: {operation: 'subgraph', issue: 'invalid_kind'}};
// @ts-expect-error The selector explanation does not contain a submitted value.
const privateSelector: Reason = {code: 'graph_operation_invalid', facts: {operation: 'subgraph', issue: 'invalid_node_selector', value: [1]}};
void mismatchedSelector; void privateSelector;

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

const defaultReason: Reason = {code: 'parameter_default_type_mismatch',
  facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
  location: {kind: 'structured', document_id: 'parameter_declarations',
    revision: `rev:${'1'.repeat(64)}`, pointer: '/minimum/default'}};
explainCheckReason(defaultReason);
// @ts-expect-error Default facts cannot carry an unregistered actual type.
const unknownDefaultType: Reason = {code: 'parameter_default_type_mismatch', facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'private_provider_type'}};
// @ts-expect-error Default facts never carry submitted values.
const privateDefault: Reason = {code: 'parameter_default_type_mismatch', facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string', value: 'private-default'}};
// @ts-expect-error Structured diagnostics cannot claim a text source document.
const wrongDefaultDocument: Reason = {code: 'parameter_default_type_mismatch', facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'}, location: {kind: 'structured', document_id: 'source', revision: `rev:${'1'.repeat(64)}`, pointer: '/minimum/default'}};
void unknownDefaultType; void privateDefault; void wrongDefaultDocument;
