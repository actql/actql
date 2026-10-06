import {explainSubmission, explainCancellation, explainReadFailure,
  explainEffectUncertainty, getOperationPresentationInfo, type OperationExplanationOptions,
  type SubmissionExplanation, type CancellationExplanation, type ReadFailureExplanation,
  type EffectUncertaintyExplanation} from '@actql/sdk';
const options: OperationExplanationOptions = {locale: 'ja'};
const submission: SubmissionExplanation | undefined = explainSubmission({}, options);
const cancellation: CancellationExplanation | undefined = explainCancellation({}, options);
const read: ReadFailureExplanation | undefined = explainReadFailure({}, options);
const effect: EffectUncertaintyExplanation | undefined = explainEffectUncertainty({}, options);
const locale: 'en' | 'ja' = getOperationPresentationInfo(options).locale;
void [submission, cancellation, read, effect, locale];
// @ts-expect-error Operation explanation options cannot grant execution permission.
explainCancellation({}, {locale: 'ja', confirmStop: true});
