import {explainCheckOutcome, getCheckRequirementFrontier, type CheckOutcome} from '@actql/sdk';
declare const outcome: CheckOutcome;
if (outcome.outcome === 'completed') {
  const flag: true | undefined = outcome.report.omissions?.requirements;
  // @ts-expect-error The Host exposes no omitted count.
  outcome.report.omissions?.count;
  // @ts-expect-error A received omissions fact is readonly.
  outcome.report.omissions!.requirements = false;
  void flag;
}
const explanation = explainCheckOutcome(outcome);
if (explanation && explanation.outcome === 'completed') {
  const flag: true | undefined = explanation.report.omissions?.requirements;
  void flag;
}
const frontier = getCheckRequirementFrontier(outcome);
// A truncated known Requirement enumeration returns undefined.
void frontier;
