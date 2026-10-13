import {createInstalledHttpChatRegistration,
  type HttpChatRegistrationOptions, type ModelProviderRegistration} from '@actql/provider-http';
import type {HostInstallation} from '../local-node/index.js';

declare const options: HttpChatRegistrationOptions;
const registration: ModelProviderRegistration = createInstalledHttpChatRegistration(options);
const installed: HostInstallation['registerModelProviders'] = registration;
void installed;

// @ts-expect-error Original Host selections are required; defaults cannot fund a Run.
createInstalledHttpChatRegistration({providerId: 'models/unfunded'});
// @ts-expect-error Headers are exact name/value pairs, not an endpoint capability.
const header: HttpChatRegistrationOptions['headers'] = [['authorization']];
void header;
// @ts-expect-error Low-level physical preflight is not a consumer operation.
import {createHttpChatPreflight} from '@actql/provider-http';
void createHttpChatPreflight;
