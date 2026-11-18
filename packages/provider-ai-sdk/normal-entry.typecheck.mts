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

const usage: NonNullable<HostInstallation['inferEvidence']> = {
  kind: 'usage', target: 'answer', destination: 'local:usage', maxBytes: 4096,
  authorize: async () => true,
  sink: {capture: async () => ({status: 'complete'}), record: async () => {}},
};
void usage;
// @ts-expect-error Only the existing full, typed-input or usage disclosure is supported.
const unknownEvidence: NonNullable<HostInstallation['inferEvidence']> = {...usage, kind: 'tokens-debug'};
void unknownEvidence;

createOpenAIChatProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, bodyMs: 300}});
createOpenAIChatProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, bodyMs: 300, callMs: 400}});
// @ts-expect-error Only the explicit callMs field selects the total request/read clock.
createOpenAIChatProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, overallMs: 300}});
// @ts-expect-error Timeout quantities are explicit finite milliseconds, not strings.
createOpenAIChatProvider({...options, transportTimeouts: {connectMs: '100', headersMs: 200, bodyMs: 300}});

import {createInstalledUndiciOpenAIChatRegistration, type UndiciOpenAIChatRegistrationOptions} from './index.js';
declare const legacyOriginals: UndiciOpenAIChatRegistrationOptions;
// @ts-expect-error Public low-level originals cannot carry an unbound normal configuration override.
createInstalledUndiciOpenAIChatRegistration({...legacyOriginals, transportTimeouts: {connectMs: 1, headersMs: 1, bodyMs: 1}});
