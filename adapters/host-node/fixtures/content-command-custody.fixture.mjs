// Reopen the trusted fixture provider's original workspace holding. This is
// physical ReferenceIssuer evidence, not another generation, Source request,
// Run journal or permission supplied by Program JSON. The generated encoder
// is deliberately absent in a recovery process.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../../store-local/publication-store.mjs';

export async function reopenContentCommandCustody(saved) {
  const control = runtimeCore(moon).publicationControl;
  const store = await openLocalPublicationStore(saved.configuration, control);
  let current = false;
  const description = saved.description;
  const alive = () => current && !store.status().closed &&
    Date.now() < Date.parse(saved.binding.expires_at);
  const issue = async () => {
    current = false;
    assert.ok(Date.now() < Date.parse(saved.binding.expires_at), 'original Content lifetime expired');
    assert.equal(store.storeAuthorityCid, saved.binding.content_store_cid);
    assert.equal(description.storeCid, store.storeAuthorityCid);
    assert.equal(description.workspaceScopeCid, saved.binding.workspace_scope_cid);
    assert.equal(description.effectiveDataPolicyCid, saved.binding.effective_data_policy_cid);
    const actual = await store.inspectPhysicalHolding(saved.holding.holding_cid);
    assert.deepEqual(actual, saved.holding, 'only the original live holding proves byte custody');
    assert.equal(actual.namespace, 'content');
    assert.equal(actual.manifest_cid, description.identity);
    assert.deepEqual(actual.objects, [{cid: description.contentCid, byte_count: description.sizeBytes}]);
    // The existing Store reconciles directory durability, without another
    // prepare, byte generation or request to the original Source.
    await store.commitPhysicalHolding(actual, []);
    const hash = createHash('sha256');
    let bytes = 0;
    await store.consumePhysicalHolding(actual.holding_cid, 0, chunk => {
      bytes += chunk.byteLength;
      hash.update(chunk);
    });
    assert.equal(bytes, description.sizeBytes);
    assert.equal(`sha256:${hash.digest('hex')}`, description.contentCid);
    current = true;
  };
  try { await issue(); }
  catch (error) { await store.close(); throw error; }
  return {store, configuration: saved.configuration, description,
    holding: saved.holding, binding: saved.binding, issue,
    admitsContent: (media, wire) => alive() && media === 'text/csv' && wire === description.wire,
    authorizesReference: wire => alive() && wire === description.wire};
}
