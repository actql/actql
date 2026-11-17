import {createOpenAIChatProvider, type OpenAIChatProviderOptions,
  type ConfiguredModelProviderRegistration, type ModelProviderRegistration} from './index.js';
import type {HostInstallation} from '../local-node/index.js';

declare const options: OpenAIChatProviderOptions;
const configured: ConfiguredModelProviderRegistration = createOpenAIChatProvider(options);
const host: HostInstallation['registerModelProviders'] = configured;
void host;
// @ts-expect-error Configuration needs the actual Host context as well as runtime.
configured({});
const result: Promise<readonly Readonly<Record<string, unknown>>[]> = configured({}, {});
void result;
// @ts-expect-error The normal configured callback is asynchronous and has two inputs.
const legacy: ModelProviderRegistration = configured;
void legacy;
const {apiKeyFile: secret, ...missingSecret} = options;
void secret;
// @ts-expect-error No ambient API key or environment fallback.
createOpenAIChatProvider(missingSecret);
const {observeEgress: egress, ...missingEgress} = options;
void egress;
// @ts-expect-error Explicit current egress observation is required.
createOpenAIChatProvider(missingEgress);
// @ts-expect-error Numeric quantities do not replace the original Int64 domain.
createOpenAIChatProvider({...options, budget: {...options.budget, maxCalls: 2}});
// @ts-expect-error Programs cannot replace the selected physical transport.
createOpenAIChatProvider({...options, fetch: globalThis.fetch});
// @ts-expect-error Applications do not supply a per-Program Task identity.
createOpenAIChatProvider({...options, taskCid: 'sha256:authored'});
// @ts-expect-error Current observation returns typed DATA, not a void notification.
createOpenAIChatProvider({...options, observeEgress() {}});
