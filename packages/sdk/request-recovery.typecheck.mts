import type {Client, RequestLookupTarget, RequestRecovery, RunReference} from './index.js';
declare const client: Client;
declare const original: unknown;
const recovery: RequestRecovery = client.recoverRequest(original);
const target: RequestLookupTarget = recovery.target;
const restored = client.recoverRequest(JSON.parse(JSON.stringify(target)));
const observation = await restored.lookup({signal: new AbortController().signal});
if (observation.kind === 'found') {
  const execution = await restored.attach(observation);
  const run: RunReference = execution.ref;
  void run;
} else {
  // @ts-expect-error No Run can be attached from held or unresolved lookup branches.
  restored.attach(observation);
}
// @ts-expect-error The locator remains immutable.
target.requestId = 'changed';
// @ts-expect-error A pre-Run recovery handle has no Run reference.
recovery.ref;
// @ts-expect-error Recovery does not resubmit a request.
recovery.submit();
