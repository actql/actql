import type {OriginalReadInstallationData, OriginalReadRecipeData} from '@actql/provider-ai-sdk';

declare const installed: OriginalReadInstallationData;
// @ts-expect-error The recipe cannot carry coordinates from an already checked Graph.
const prebound: OriginalReadRecipeData = installed;
void prebound;
