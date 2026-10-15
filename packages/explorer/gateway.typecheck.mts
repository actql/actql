import type {Client, RunReference} from '@actql/sdk';
import {createExplorerGateway, startExplorerGateway} from './gateway.js';
import {createExplorerBrowserSource} from './browser-source.js';
declare const client: Client;
declare const ref: RunReference;
const gateway = createExplorerGateway({client, origin: 'http://127.0.0.1:43210'});
const server = await startExplorerGateway({client});
const browser = createExplorerBrowserSource({origin: server.origin});
await browser.connect(gateway.issueBootstrap().bootstrap);
const launch = await browser.launchView();
if (launch?.kind === 'run') {const original: RunReference = launch.originalPlan.runRef; void original;}
if (launch?.kind === 'program') {const sourceIO: 0 = launch.plan.providerIO; void sourceIO;}
const plan = await browser.plan('SELECT 1 AS n', {format: 'sql', maxNodes: 10});
const noProviderIO: 0 = plan.providerIO;
const view = await browser.inspect(ref);
const notAtomic: 'non_atomic' = view.consistency;
const original = await browser.runPlan(ref);
const boundReference: RunReference = original.runRef;
await browser.describe(ref, 'answer');
// @ts-expect-error The launcher owns no Run cancellation operation.
await server.cancel(ref);
// @ts-expect-error This transport cannot read a Result payload or allocate a grant.
await browser.rows(ref, 'answer');
// @ts-expect-error No implicit public bind is allowed.
await startExplorerGateway({client, hostname: '0.0.0.0'});
// @ts-expect-error Launch input is presentation only, with no start operation.
await startExplorerGateway({client, launchInput: {kind: 'program', text: 'SELECT 1', format: 'sql', start: true}});
void noProviderIO; void notAtomic;
void boundReference;
const originalCancellation = {cancelRef: {...ref, cancelId: 'original', expectedRevision: 4},
  attemptRef: {operation: 'cancel' as const, attemptId: 'explicit-original-invocation'}};
const cancellation = await browser.cancel(originalCancellation);
if (cancellation.state === 'observed') {const outcome: string = cancellation.outcome.kind; void outcome;}
if (cancellation.state === 'unknown') {
  // @ts-expect-error Unknown presentation is not an accepted Owner attempt.
  cancellation.outcome;
}
await browser.lookupCancellation(originalCancellation.cancelRef);
// @ts-expect-error Explicit original control revision cannot be replaced by a string.
await browser.cancel({...originalCancellation, cancelRef: {...originalCancellation.cancelRef, expectedRevision: '4'}});
// @ts-expect-error No arbitrary Host authority or request-force field.
await startExplorerGateway({client, allowCancellation: 'force'});
