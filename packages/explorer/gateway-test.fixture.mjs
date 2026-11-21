import assert from 'node:assert/strict';
import {createExplorerGateway} from './gateway.mjs';

export const origin = 'http://127.0.0.1:43210';
export const ref = {namespaceId: 'original', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
export const tick = () => new Promise(resolve => setImmediate(resolve));
export function harness(options = {}) {
  const calls = [];
  const client = {async attach(selected) {
    calls.push(['attach', structuredClone(selected)]);
    return {inspect(limits) {calls.push(['inspect', limits]); return {status: 'fixture'};},
      result(name) {calls.push(['result', name]); return {
        describe() {calls.push(['describe']); return {name, marker: '<script>not HTML</script> e\u0301\r\n'};},
        rows() {assert.fail('no payload open');},
      };},
    };
  }, close() {assert.fail('borrowed client is not owned by Gateway');},
  submit() {assert.fail('no business work');}, cancel() {assert.fail('no cancellation');}};
  const gateway = createExplorerGateway({client, origin, ...options});
  const send = (path, body, headers = {}, method = 'POST') => gateway.fetch(new Request(`${origin}${path}`, {
    method, headers: {Host: '127.0.0.1:43210', Origin: origin,
      'Content-Type': 'application/json', ...headers},
    ...(method === 'POST' ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {}),
  }));
  async function connect() {
    const issued = gateway.issueBootstrap();
    const response = await send('/api/session', {bootstrap: issued.bootstrap});
    assert.equal(response.status, 200);
    return {body: await response.json(), cookie: response.headers.get('set-cookie').split(';')[0], issued};
  }
  const read = (kind, body, session, more = {}) => send(`/api/read/${kind}`, body,
    {Cookie: session.cookie, 'X-Actql-CSRF': session.body.csrf, ...more});
  return {gateway, send, connect, read, calls, client};
}
