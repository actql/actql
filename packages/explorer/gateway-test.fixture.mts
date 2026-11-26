import assert from 'node:assert/strict';
import {createExplorerGateway} from './gateway.mjs';
import type {Client, Execution, RunReference} from '../sdk/index.mjs';
import type {ExplorerGatewayOptions} from './gateway.d.ts';

type Method<Function extends (...args: never[]) => unknown> =
  (...args: Parameters<Function>) => unknown;
type FixtureExecution = Partial<{
  [Key in 'inspect' | 'observeOwners' | 'plan' | 'explain' | 'explainContext' | 'wait' |
    'cancel' | 'lookupCancellation' | 'status' | 'sample' | 'prepareResume' | 'resume' | 'lookupControlOperation']: Method<Execution[Key]>;
}> & {result?(name: string): {describe(): unknown; rows?(): unknown}};
type FixtureClient = {
  attach(ref: RunReference): FixtureExecution | Promise<FixtureExecution>;
  plan?: Method<Client['plan']>;
  explain?: Method<Client['explain']>;
  start?: Method<Client['start']>;
  submit?(): unknown;
  cancel?(): unknown;
  close?(): unknown;
};
type GatewayOptions = Omit<ExplorerGatewayOptions, 'client'> & {
  origin?: string;
  client?: FixtureClient;
};
type FixtureHeaders = Record<string, string | undefined>;
type Session = {body: {csrf: string; scopeEpoch: number; capabilities: Partial<Record<string, boolean>>};
  cookie: string; issued: ReturnType<ReturnType<typeof createExplorerGateway>['issueBootstrap']>};

// Fixtures model only the selected API, including deliberate malformed replies.
export const gatewayClient = (client: FixtureClient) => client as unknown as ExplorerGatewayOptions['client'];

export const origin = 'http://127.0.0.1:43210';
export const ref = {namespaceId: 'original', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
export const tick = () => new Promise<void>(resolve => setImmediate(resolve));
export function harness(options: GatewayOptions = {}) {
  const calls: unknown[] = [];
  const client: FixtureClient = {async attach(selected) {
    calls.push(['attach', structuredClone(selected)]);
    return {inspect(limits) {calls.push(['inspect', limits]); return {status: 'fixture'};},
      result(name) {calls.push(['result', name]); return {
        describe() {calls.push(['describe']); return {name, marker: '<script>not HTML</script> e\u0301\r\n'};},
        rows() {assert.fail('no payload open');},
      };},
    };
  }, close() {assert.fail('borrowed client is not owned by Gateway');},
  submit() {assert.fail('no business work');}, cancel() {assert.fail('no cancellation');}};
  const {client: selected = client, ...configuration} = options;
  const gateway = createExplorerGateway({origin, ...configuration,
    client: gatewayClient(selected)});
  const send = (path: string, body?: unknown, headers: FixtureHeaders = {}, method = 'POST') => gateway.fetch(new Request(`${origin}${path}`, {
    method, headers: {Host: '127.0.0.1:43210', Origin: origin,
      'Content-Type': 'application/json',
      ...Object.fromEntries(Object.entries(headers).filter(([, value]) => value !== undefined))},
    ...(method === 'POST' ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {}),
  }));
  async function connect(): Promise<Session> {
    const issued = gateway.issueBootstrap();
    const response = await send('/api/session', {bootstrap: issued.bootstrap});
    assert.equal(response.status, 200);
    const cookie = response.headers.get('set-cookie');
    assert(cookie);
    return {body: await response.json(), cookie: cookie.split(';')[0], issued};
  }
  const read = (kind: string, body: unknown, session: Session, more: FixtureHeaders = {}) => send(`/api/read/${kind}`, body,
    {Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf, ...more});
  return {gateway, send, connect, read, calls, client};
}
