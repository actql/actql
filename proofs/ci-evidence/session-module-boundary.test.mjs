// Load the actual consumer entry modules in a separate Node process. Refusing
// pipeline resolution makes an accidental eager import a real load failure.
// This tests module isolation, not execution in an image or Actions provenance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('Session collector, final consumer and image executor load without pipeline scientific modules', () => {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import {registerHooks} from 'node:module';
    const loaded = new Set();
    registerHooks({resolve(specifier, context, next) {
      const result = next(specifier, context);
      if (result.url.includes('/proofs/relation-pipeline/') || result.url.endsWith('/isolated-pipeline-results.mjs')) {
        assert(result.url.endsWith('/relation-pipeline/inventory.mjs'), 'Pipeline scientific module reached Session import graph: ' + result.url);
        loaded.add(result.url);
      }
      return result;
    }});
    const execution = await import('./proofs/ci-evidence/isolated-execution.mjs');
    await import('./proofs/ci-evidence/collect.mjs');
    await import('./proofs/ci-evidence/final.mjs');
    // Reconsume scientific observations only, keeping their original execution
    // SHA and source. This does not apply that old image to the current source.
    const {readFileSync} = await import('node:fs');
    const {gunzipSync} = await import('node:zlib');
    const {hash} = await import('./proofs/ci-evidence/inputs.mjs');
    const bytes = gunzipSync(readFileSync('./docs/reviews/evidence/2026-10-07-local-isolated-session-9a083b1d3.json.gz'), {maxOutputLength: 8 * 1024 * 1024});
    assert.equal(hash(bytes), '48db50ef669ce6ff8b92ad6d80f30b094a82619068a3791ac25e1e19448d21d7');
    const original = JSON.parse(bytes), payload = original.answer.payload;
    assert.equal(original.revision, '9a083b1d32621b73a89e223c0c6cb1a0be3d3d29');
    assert(await execution.checkIsolatedExecutionResult({payload, manifest: original.prepared.manifest, before: payload.report.source}));
    assert.equal(payload.report.results.length, 13);
    const changed = structuredClone(payload); changed.restored = false;
    await assert.rejects(execution.checkIsolatedExecutionResult({payload: changed, manifest: original.prepared.manifest, before: payload.report.source}));
    await assert.rejects(execution.checkIsolatedExecutionResult({profile: 'unregistered'}), /Unregistered scientific profile/u);
    assert.equal(loaded.size, 1, 'The remaining inventory module must actually be observed');
    assert.throws(() => execution.executeIsolatedMutation({}), /CI-only/u);
    console.log('PASS actual Session consumers; one bound inventory, no pipeline scientific module');
  `], {cwd: root, env: {...process.env, GITHUB_ACTIONS: ''}, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
  assert(!result.error && result.status === 0, result.stderr);
  assert.match(result.stdout, /^PASS actual Session consumers;/u);
});
