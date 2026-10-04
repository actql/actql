import assert from 'node:assert/strict';
import {open, mkdtemp, unlink} from 'node:fs/promises';
import {join} from 'node:path';

// Reuse the existing bounded ZIP reader after transport. Never extract or
// execute an archive, forward the Actions token to blob storage, or include
// presigned URLs/HTTP bodies in errors. The directory belongs to this call.
export async function downloadArtifact({repository, artifactId, token, directory, fetchImpl = fetch}) {
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(repository));
  assert(Number.isSafeInteger(artifactId) && artifactId > 0);
  assert(typeof token === 'string' && token.length > 0);
  const signal = AbortSignal.timeout(60000);
  const response = await fetchImpl(`https://api.github.com/repos/${repository}/actions/artifacts/${artifactId}/zip`, {
    headers: {accept: 'application/vnd.github+json', authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28'},
    redirect: 'manual', signal});
  assert.equal(response.status, 302, 'Artifact download is unavailable');
  let location;
  try { location = new URL(response.headers.get('location')); }
  catch { throw new Error('Invalid artifact storage redirect'); }
  assert(location.protocol === 'https:' && !location.username && !location.password && !location.port &&
    (/^[a-z0-9-]+\.blob\.core\.windows\.net$/u.test(location.hostname) ||
      /^[a-z0-9.-]+\.actions\.githubusercontent\.com$/u.test(location.hostname)), 'Unreviewed artifact storage origin');
  // The second fetch deliberately has no Authorization header and no follow.
  let blob;
  try { blob = await fetchImpl(location.href, {redirect: 'error', signal}); }
  catch { throw new Error('Artifact blob download is unavailable'); }
  assert(blob.ok && blob.body, 'Artifact blob download is unavailable');
  const owned = await mkdtemp(join(directory, 'session-origin-')), filename = join(owned, 'artifact.zip');
  const file = await open(filename, 'wx', 0o600);
  let size = 0, complete = false;
  try {
    for await (const bytes of blob.body) {
      size += bytes.length;
      assert(size <= 64 * 1024 * 1024, 'Artifact download exceeds bounded size');
      await file.writeFile(bytes);
    }
    assert(size > 0, 'Empty artifact download');
    complete = true;
    return filename;
  } catch {
    throw new Error('Artifact blob transfer failed');
  } finally {
    await file.close();
    if (!complete) await unlink(filename); // Only this call's exclusive file.
  }
}
