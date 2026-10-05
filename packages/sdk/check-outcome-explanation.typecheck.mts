import {explainCheckOutcome, explainCheckReason, getCheckPresentationInfo,
  type CheckExplanationOptions, type CheckOutcome} from '@actql/sdk';

const language: CheckExplanationOptions = {locale: 'ja'};
const translated = explainCheckOutcome({} as CheckOutcome, language);
const info = getCheckPresentationInfo(language);
const locale: 'en' | 'ja' = info.locale;
const translationRevision: string = info.translationRevision;
void translated; void locale; void translationRevision;
explainCheckReason({code: 'parameter_value_required'}, language);
// @ts-expect-error Translation metadata does not confer permission.
info.next.operation;
// @ts-expect-error Translation selection is immutable metadata.
info.locale = 'en';
// @ts-expect-error Locale options do not alter the submitted input or scope.
explainCheckOutcome({} as CheckOutcome, {locale: 'ja', scope: 'template'});

declare const outcome: CheckOutcome;
const explanation = explainCheckOutcome(outcome);
if (explanation?.outcome === 'completed') {
  const verdict: 'invalid' | 'undetermined' | 'verified' = explanation.report.verdict;
  const completeness: 'complete' = explanation.report.completeness;
  const context: string = explanation.report.contextRef;
  const scope: 'bound_input' = explanation.report.scope.kind;
  void verdict; void completeness; void context; void scope;
  // @ts-expect-error A presentation object does not execute the checked input.
  explanation.execute();
  // @ts-expect-error The reported scope is immutable.
  explanation.report.scope.kind = 'template';
  // @ts-expect-error Successful checking has no Problem reference.
  explanation.correlationRef;
}
if (explanation?.outcome === 'failed') {
  const correlation: string = explanation.correlationRef;
  void correlation;
  // @ts-expect-error Reporting failure does not authorize another check or execution.
  explanation.next.operation;
  // @ts-expect-error A Problem reference cannot restore submitted source.
  explanation.input.text;
  // @ts-expect-error The observed reference is immutable.
  explanation.correlationRef = 'another attempt';
}
if (explanation?.outcome === 'failed' && explanation.report) {
  const verdict: 'invalid' | 'undetermined' = explanation.report.verdict;
  const completeness: 'partial' = explanation.report.completeness;
  void verdict; void completeness;
  // @ts-expect-error Partial reports never verify.
  const verified: 'verified' = explanation.report.verdict;
  void verified;
}
if (explanation?.outcome === 'unavailable') {
  const correlation: string = explanation.correlationRef;
  void correlation;
  // @ts-expect-error Unavailable has no report, scope or verdict.
  explanation.report.verdict;
  // @ts-expect-error A safe explanation cannot restore the submitted text.
  explanation.input.text;
}
