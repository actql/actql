import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {downloadArtifact} from './transport.mjs';

test('GitHub token stays on the API; original blob bytes are stored privately without extraction', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-action-download-'));
  try {
    const calls = [];
    const archive = await downloadArtifact({repository: 'actql/actql', artifactId: 1, token: 'test-only-token', directory,
      fetchImpl: async (url, options) => {
        calls.push({url, options});
        return calls.length === 1 ? new Response(null, {status: 302,
          headers: {location: 'https://productionresults.blob.core.windows.net/artifact.zip?sig=private'}}) :
          new Response(Buffer.from('original ZIP bytes'));
      }});
    assert.equal((await readFile(archive)).toString(), 'original ZIP bytes');
    assert.equal(calls[0].options.headers.authorization, 'Bearer test-only-token');
    assert.equal(calls[0].options.redirect, 'manual');
    assert.equal(calls[1].options.headers, undefined);
    assert.equal(calls[1].options.redirect, 'error');
  } finally { await rm(directory, {recursive: true, force: true}); }
});

for (const location of ['http://productionresults.blob.core.windows.net/a', 'https://unreviewed.example/a',
  'https://user:password@productionresults.blob.core.windows.net/a'])
  test('reject an unreviewed transport origin before fetching its contents', async () => {
    let calls = 0;
    await assert.rejects(downloadArtifact({repository: 'actql/actql', artifactId: 1, token: 'test-only-token', directory: tmpdir(),
      fetchImpl: async () => { calls++; return new Response(null, {status: 302, headers: {location}}); }}), /Unreviewed artifact storage/u);
    assert.equal(calls, 1);
  });

test('empty and unavailable downloads do not become successful evidence', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-action-empty-'));
  try {
    for (const status of [200, 403]) {
      let calls = 0;
      await assert.rejects(downloadArtifact({repository: 'actql/actql', artifactId: 1, token: 'test-only-token', directory,
        fetchImpl: async () => ++calls === 1 ? new Response(null, {status: 302,
          headers: {location: 'https://productionresults.blob.core.windows.net/a'}}) : new Response(null, {status})}));
    }
  } finally { await rm(directory, {recursive: true, force: true}); }
});
