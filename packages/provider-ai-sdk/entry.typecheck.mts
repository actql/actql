import {createInstalledOpenAIChatRegistration,
  type OpenAIChatRegistrationOptions, type ModelProviderRegistration} from '@actql/provider-ai-sdk';
import type {HostInstallation} from '../local-node/index.js';

declare const options: OpenAIChatRegistrationOptions;
const registration: ModelProviderRegistration = createInstalledOpenAIChatRegistration(options);
const installed: HostInstallation['registerModelProviders'] = registration;
void installed;

// @ts-expect-error Original Host selections are required; defaults cannot fund a Run.
createInstalledOpenAIChatRegistration({providerId: 'models/unfunded'});
// @ts-expect-error Quantities retain the existing Int64 BigInt domain.
const amount: OpenAIChatRegistrationOptions['quantityCapacity']['limits']['tokens'] = 1;
void amount;
// @ts-expect-error Low-level transport is not an exported consumer operation.
import {startSdkTransport} from '@actql/provider-ai-sdk';
void startSdkTransport;
// @ts-expect-error Native Decision is not an accepted exported profile.
import {prepareTypeSafeDecisionRequest} from '@actql/provider-ai-sdk';
void prepareTypeSafeDecisionRequest;
