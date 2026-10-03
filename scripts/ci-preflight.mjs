// Read-only admission at the end of preflight. Existing contents:read suffices;
// no actions cancellation/write permission, polling delay, or evidence reuse.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const sha = /^[0-9a-f]{40}$/u;
export function revisionToCheck(env, payload) {
  assert(sha.test(env.GITHUB_SHA), 'Missing tested revision');
  assert(/^[\w.-]+\/[\w.-]+$/u.test(env.GITHUB_REPOSITORY ?? ''), 'Invalid repository');
  if (env.GITHUB_EVENT_NAME === 'pull_request') {
    assert(Number.isSafeInteger(payload?.number) && payload.number > 0, 'Missing PR number');
    assert(sha.test(payload?.pull_request?.head?.sha), 'Missing PR head revision');
    return {ref: `pull/${payload.number}/head`, expected: payload.pull_request.head.sha};
  }
  assert(['push', 'workflow_dispatch'].includes(env.GITHUB_EVENT_NAME), 'Unsupported admission event');
  assert(/^refs\/(?:heads|tags)\/.+/u.test(env.GITHUB_REF ?? ''), 'Missing source ref');
  return {ref: env.GITHUB_REF.slice(5), expected: env.GITHUB_SHA};
}

export async function assertCurrentRevision(env, payload, fetchRef) {
  const {ref, expected} = revisionToCheck(env, payload);
  const current = await fetchRef(env.GITHUB_REPOSITORY, ref);
  assert(sha.test(current), 'Latest revision lookup returned no exact SHA');
  assert.equal(current, expected, 'Revision superseded during preflight; refusing expensive fan-out');
  return {ref, revision: current};
}

export async function readRef(repository, ref, {token, apiUrl = 'https://api.github.com', fetchImpl = fetch} = {}) {
  assert(token, 'Missing read-only GitHub token');
  const url = new URL(`${apiUrl}/repos/${repository}/git/ref/${ref.split('/').map(encodeURIComponent).join('/')}`);
  assert.equal(url.protocol, 'https:', 'GitHub API must use HTTPS');
  const response = await fetchImpl(url, {headers: {Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
  redirect: 'error', signal: AbortSignal.timeout(30_000)});
  assert(response.ok, `Latest revision lookup failed (${response.status})`);
  const result = await response.json();
  assert.equal(result.ref, `refs/${ref}`, 'GitHub returned a different ref');
  assert.equal(result.object?.type, 'commit', 'Source ref is not an exact commit');
  return result.object.sha;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const env = process.env;
  const payload = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const result = await assertCurrentRevision(env, payload, (repository, ref) => readRef(repository, ref,
    {token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL}));
  console.log(`Current ${result.ref}: ${result.revision}; mandatory preflight passed`);
}
