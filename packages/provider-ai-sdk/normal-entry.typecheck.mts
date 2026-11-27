import {createRegisteredSdkProvider, createRegisteredSdkProviders,
  type RegisteredSdkProviderOptions,
  type ConfiguredModelProviderRegistration} from './index.js';
import type {HostInstallation} from '../local-node/index.js';

declare const options: RegisteredSdkProviderOptions;
const configured: ConfiguredModelProviderRegistration = createRegisteredSdkProvider(options);
const host: HostInstallation['registerModelProviders'] = configured;
void host;
// @ts-expect-error Configuration needs the actual Host context as well as runtime.
configured({});
const result: Promise<readonly Readonly<Record<string, unknown>>[]> = configured({}, {});
void result;
// @ts-expect-error Credential references are selected by the Host registration.
createRegisteredSdkProvider({...options, apiKeyFile: './key'});
const {observeEgress: egress, ...missingEgress} = options;
void egress;
// @ts-expect-error Explicit current egress observation is required.
createRegisteredSdkProvider(missingEgress);
// @ts-expect-error Numeric quantities do not replace the original Int64 domain.
createRegisteredSdkProvider({...options, budget: {...options.budget, maxCalls: 2}});
// @ts-expect-error Programs cannot replace the selected physical transport.
createRegisteredSdkProvider({...options, fetch: globalThis.fetch});
// @ts-expect-error Applications do not supply a per-Program Task identity.
createRegisteredSdkProvider({...options, taskCid: 'sha256:authored'});
// @ts-expect-error Current observation returns typed DATA, not a void notification.
createRegisteredSdkProvider({...options, observeEgress() {}});

const usage: NonNullable<HostInstallation['inferEvidence']> = {
  kind: 'usage', target: 'answer', destination: 'local:usage', maxBytes: 4096,
  authorize: async () => true,
  sink: {capture: async () => ({status: 'complete'}), record: async () => {}},
};
void usage;
// @ts-expect-error Only the existing full, typed-input or usage disclosure is supported.
const unknownEvidence: NonNullable<HostInstallation['inferEvidence']> = {...usage, kind: 'tokens-debug'};
void unknownEvidence;

// @ts-expect-error Registered providers require the whole-call timeout.
createRegisteredSdkProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, bodyMs: 300}});
createRegisteredSdkProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, bodyMs: 300, callMs: 400}});
// @ts-expect-error Only the explicit callMs field selects the total request/read clock.
createRegisteredSdkProvider({...options, transportTimeouts: {connectMs: 100, headersMs: 200, overallMs: 300}});
// @ts-expect-error Timeout quantities are explicit finite milliseconds, not strings.
createRegisteredSdkProvider({...options, transportTimeouts: {connectMs: '100', headersMs: 200, bodyMs: 300}});

// @ts-expect-error The consuming Host owns the registered endpoint.
createRegisteredSdkProvider({...options, baseURL: 'https://127.0.0.1:1234/v1'});
// @ts-expect-error Model IDs belong to the registered route.
createRegisteredSdkProvider({...options, modelId: 'other-model'});
