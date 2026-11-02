// Read-only admission at the end of preflight. Existing contents:read suffices;
// no actions cancellation/write permission, polling delay, or evidence reuse.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const sha = /^[0-9a-f]{40}$/u;
export function revisionToCheck(env, payload) {
  assert(sha.test(env.GITHUB_SHA), 'Missing tested revision');
  assert(/^[\w.-]+\/[\w.-]+$/u.test(env.GITHUB_REPOSITORY ?? ''), 'Invalid repository');
  if (env.GITHUB_EVENT_NAME === 'pull_request') {
    assert(Number.isSafeInteger(payload?.number) && payload.number > 0, 'Missing PR number');
    assert(sha.test(payload?.pull_request?.head?.sha), 'Missing PR head revision');
    return {ref: `pull/${payload.number}/head`, expected: payload.pull_request.head.sha};
  }
  assert(['push', 'workflow_dispatch', 'schedule'].includes(env.GITHUB_EVENT_NAME), 'Unsupported admission event');
  if (env.GITHUB_EVENT_NAME === 'schedule') assert.equal(env.GITHUB_REF, 'refs/heads/main', 'Scheduled verification requires main');
  assert(/^refs\/(?:heads|tags)\/.+/u.test(env.GITHUB_REF ?? ''), 'Missing source ref');
  return {ref: env.GITHUB_REF.slice(5), expected: env.GITHUB_SHA};
}

// An admitted main run owns its immutable event SHA until completion. Advancing
// main must not starve it. This exception is unavailable to PRs/working branches,
// and is tied to the real repository, event and checked-out commit, not a flag.
export function assertFixedMainRevision(env, payload, checkoutRevision) {
  assert(['push', 'workflow_dispatch', 'schedule'].includes(env.GITHUB_EVENT_NAME), 'Not a main integration event');
  assert.equal(env.GITHUB_REF, 'refs/heads/main', 'Not the main branch');
  assert(sha.test(env.GITHUB_SHA), 'Missing tested revision');
  assert.equal(checkoutRevision, env.GITHUB_SHA, 'Main checkout differs from event revision');
  assert.equal(payload?.repository?.full_name, env.GITHUB_REPOSITORY, 'Different main repository');
  assert(Number.isSafeInteger(payload.repository.id) && payload.repository.id > 0
    && String(payload.repository.id) === env.GITHUB_REPOSITORY_ID, 'Different main repository identity');
  assert.equal(env.GITHUB_WORKFLOW_SHA, env.GITHUB_SHA, 'Different main workflow revision');
  assert.equal(env.GITHUB_WORKFLOW_REF,
    `${env.GITHUB_REPOSITORY}/.github/workflows/ci.yml@refs/heads/main`, 'Different main workflow');
  assert.equal(payload.repository.visibility, 'public', 'Main integration requires public visibility');
  assert.equal(payload.repository.private, false, 'Main integration requires a public repository');
  assert(![true, 'true'].includes(payload?.inputs?.performance_matrix)
    && ![true, 'true'].includes(payload?.inputs?.packed_query_evidence_probe), 'Not normal main integration');
  if (env.GITHUB_EVENT_NAME === 'push') {
    assert.equal(payload.ref, env.GITHUB_REF, 'Different pushed main ref');
    assert.equal(payload.after, env.GITHUB_SHA, 'Different pushed main revision');
    assert.equal(payload.deleted, false, 'Deleted main ref');
  }
  return {ref: 'heads/main', revision: checkoutRevision};
}

export async function assertCurrentRevision(env, payload, fetchRef, {checkoutRevision = null} = {}) {
  const {ref, expected} = revisionToCheck(env, payload);
  assert.equal(checkoutRevision, env.GITHUB_SHA, 'Checkout differs from the tested event revision');
  if (['push', 'workflow_dispatch', 'schedule'].includes(env.GITHUB_EVENT_NAME) && env.GITHUB_REF === 'refs/heads/main') {
    return assertFixedMainRevision(env, payload, checkoutRevision);
  }
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
    {token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL}),
  {checkoutRevision: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim()});
  console.log(`Admitted ${result.ref}: ${result.revision}; mandatory preflight passed`);
}
