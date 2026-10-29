import {effectReviewProjectionBindingFacts, type RunEvidence} from '@actql/run-host-core';
declare const review: RunEvidence;
const facts = effectReviewProjectionBindingFacts(review);
const preview: string = facts.previewCid;
const authoring: string = facts.authoringContextCid;
const scope: string = facts.authorityScopeCid;
const claims: readonly string[] = facts.approvalClaims;
// @ts-expect-error The original evidence is required, not its wire.
effectReviewProjectionBindingFacts('wire');
// @ts-expect-error Returned binding DATA is immutable.
facts.approvalClaims.push('partial_application_accepted');
