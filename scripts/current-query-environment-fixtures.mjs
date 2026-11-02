// Refresh only enumerated current admission fixtures, never retained history.
// Dependency roles and authored Source/Model/permission bodies stay unchanged.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
const definitions = [
  {
    "path": "src/run_publication_host/client_effect_program_test.mbt",
    "original_cid": "sha256:7d396c299e58a85fec0efdfecd0801c94a4cded4b29215a75291428a32aee0aa"
  },
  {
    "path": "src/run_publication_host/client_composed_effect_fixture_wbtest.mbt",
    "original_cid": "sha256:7d396c299e58a85fec0efdfecd0801c94a4cded4b29215a75291428a32aee0aa"
  },
  {
    "path": "src/run_publication_host/client_effect_source_request_binding_wbtest.mbt",
    "original_cid": "sha256:7d396c299e58a85fec0efdfecd0801c94a4cded4b29215a75291428a32aee0aa"
  },
  {
    "path": "src/run_publication_host/client_effect_local_update_source_normalization_wbtest.mbt",
    "original_cid": "sha256:d7e6eed46662620a0f19f0d85e7408d1a94980fa885a0da7ed080638b57dfe14"
  },
  {
    "path": "src/run_publication_host/client_query_time_wbtest.mbt",
    "original_cid": "sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed"
  },
  {
    "path": "src/run_publication_host/client_local_normalization_wbtest.mbt",
    "original_cid": "sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed"
  },
  {
    "path": "src/run_publication_host/client_local_source_catalog_profile_wbtest.mbt",
    "original_cid": "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78"
  },
  {
    "path": "src/run_publication_host/client_multi_source_wbtest.mbt",
    "original_cid": "sha256:8dddb2a590629efb451ee5c579798da0ec64a674980601b49a97ff6a79140505"
  },
  {
    "path": "src/platform_native/remote_standard_host/retained_task_input_wbtest.mbt",
    "original_cid": "sha256:806cd2ad9e32c71ac2a5879c896385a55d9ce388e7b782cb79209d93e556c771"
  },
  {
    "path": "src/platform_native/remote_resident_host/effect_consumer_context_native_wbtest.mbt",
    "original_cid": "sha256:7d396c299e58a85fec0efdfecd0801c94a4cded4b29215a75291428a32aee0aa"
  },
  {
    "path": "src/platform_native/remote_resident_host/effect_source_fixture_wbtest.mbt",
    "original_cid": "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78"
  },
  {
    "path": "adapters/host-node/fixtures/two-source/left.environment.json",
    "original_cid": "sha256:3ecf64039ce7b3a8a2136c60d17ee43e26c144be72cffdfcbe6cf4f0da3c0033"
  },
  {
    "path": "adapters/host-node/fixtures/two-source/right.environment.json",
    "original_cid": "sha256:c89ae8aa91fba72c411ea94353fee78d840e9d312c287a08d61e1fed0eef0004"
  },
  {
    "path": "adapters/host-node/fixtures/two-source/two-source.environment.json",
    "original_cid": "sha256:8dddb2a590629efb451ee5c579798da0ec64a674980601b49a97ff6a79140505"
  }
];
const consumers = [
  "src/client_local_host/unfiltered_join_requirement_wbtest.mbt",
  "src/client_local_host/single_source_free_capacity_wbtest.mbt",
  "src/client_local_host/installed_effect_managed_run_wbtest.mbt",
  "src/run_publication_host/client_effect_program_test.mbt",
  "src/run_publication_host/client_composed_effect_fixture_wbtest.mbt",
  "src/run_publication_host/client_local_group_normalization_wbtest.mbt",
  "src/run_publication_host/client_effect_source_request_binding_wbtest.mbt",
  "src/run_publication_host/client_document_catalog_wbtest.mbt",
  "src/run_publication_host/client_effect_local_update_source_normalization_wbtest.mbt",
  "src/run_publication_host/client_local_assertion_normalization_wbtest.mbt",
  "src/run_publication_host/client_query_time_wbtest.mbt",
  "src/run_publication_host/client_local_dedupe_normalization_wbtest.mbt",
  "src/run_publication_host/client_local_normalization_wbtest.mbt",
  "src/run_publication_host/client_source_dispatch_wbtest.mbt",
  "src/run_publication_host/client_local_source_catalog_profile_wbtest.mbt",
  "src/run_publication_host/client_resident_source_wbtest.mbt",
  "src/run_publication_host/client_multi_source_wbtest.mbt",
  "src/platform_native/remote_standard_host/retained_task_input_wbtest.mbt",
  "src/platform_native/remote_resident_host/effect_consumer_context_native_wbtest.mbt",
  "src/platform_native/remote_resident_host/effect_source_fixture_wbtest.mbt",
  "adapters/host-node/fixtures/two-source/left.environment.json",
  "adapters/host-node/fixtures/two-source/right.environment.json",
  "adapters/host-node/fixtures/two-source/two-source.environment.json",
  "scripts/legacy-task-run-material-fixtures.test.mjs"
];
const oldProcess = 'sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b';
const oldReceipt = 'sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a';
const processCid = machineCid(JSON.parse(readFileSync('spec/contracts/actql-query-process-evidence.json', 'utf8')));
const receiptCid = machineCid(JSON.parse(readFileSync('spec/contracts/actql-query-two-receipt.json', 'utf8')));
const pins = new Map([[oldProcess, processCid], [processCid, processCid], [oldReceipt, receiptCid], [receiptCid, receiptCid]]);
const namedBindings = [{
  "owner": "src/run_publication_host/client_local_normalization_wbtest.mbt",
  "name": "local_normalization_environment_wire",
  "consumers": [
    "src/run_publication_host/client_composed_infer_wbtest.mbt",
    "src/run_publication_host/client_effect_normalization_wbtest.mbt",
    "src/run_publication_host/client_effect_run_materials_wbtest.mbt",
    "src/run_publication_host/client_effect_serialized_infer_wbtest.mbt",
    "src/run_publication_host/client_serialization_effect_branch_wbtest.mbt",
    "src/run_publication_host/client_serialization_retained_task_wbtest.mbt"
  ]
}, {
  owner: 'src/platform_native/remote_resident_host/effect_source_fixture_wbtest.mbt',
  name: 'resident_effect_source_environment',
  consumers: ['effect_source_wbtest.mbt', 'source_dispatch_wbtest.mbt', 'effect_source_dispatch_wbtest.mbt']
    .map(name => 'src/platform_native/remote_resident_host/' + name),
}, {
  owner: 'src/client_local_host/resident_source_query_regression_wbtest.mbt',
  name: 'source_query_original_environment',
  consumers: ['src/client_local_host/single_installed_capture_wbtest.mbt'],
  selectorConsumers: ['src/client_local_host/original_serialization_prefix_wbtest.mbt'],
}];
for (const binding of namedBindings) for (const path of [binding.owner, ...binding.consumers, ...(binding.selectorConsumers ?? [])]) {
  if (!consumers.includes(path)) consumers.push(path);
}
const texts = new Map(consumers.map(path => [path, readFileSync(path, 'utf8')]));
// Retained compatibility preimages are independent fixtures. Refreshing the
// current admission owner must not rewrite their wires or expected identities.
const retainedFixtures = [{
  path: 'src/run_publication_host/client_local_normalization_wbtest.mbt',
  name: 'Local Environment fixture preserves original identity and member-order refusals',
}];
const retainedBlocks = new Map();
for (const [index, fixture] of retainedFixtures.entries()) {
  const text = texts.get(fixture.path);
  const marker = `///|\ntest "${fixture.name}" {`;
  assert.equal(text.split(marker).length, 2, 'unique retained compatibility fixture');
  const start = text.indexOf(marker), end = text.indexOf('\n///|', start + marker.length);
  assert(end > start, 'bounded retained compatibility fixture');
  const slot = `// Retained compatibility fixture ${index}; restored verbatim below.`;
  assert(!text.includes(slot), 'retained fixture placeholder collision');
  retainedBlocks.set(fixture.path, {slot, body: text.slice(start, end)});
  texts.set(fixture.path, text.slice(0, start) + slot + text.slice(end));
}
const replacements = new Map();
function refresh(environment, original) {
  const {evidence_bundle_cid: before, ...body} = environment;
  assert.equal(machineCid(body), before, 'complete original environment preimage');
  for (const capability of body.connector_capabilities) {
    capability.capability_contract_cids = capability.capability_contract_cids.map(pin => {
      assert(pins.has(pin), 'review unrecognized query capability instead of guessing its role');
      return pins.get(pin);
    });
  }
  body.connector_capabilities.sort((a,b) => machineCid(a) < machineCid(b) ? -1 : machineCid(a) > machineCid(b) ? 1 : 0);
  const after = machineCid(body);
  for (const key of [before, original]) {
    assert(!replacements.has(key) || replacements.get(key) === after, 'one original environment cannot select different current bodies');
    replacements.set(key, after);
  }
  return {...body, evidence_bundle_cid: after};
}
for (const {path, original_cid} of definitions) {
  const text = texts.get(path);
  if (path.endsWith('.json')) {
    texts.set(path, JSON.stringify(refresh(JSON.parse(text), original_cid), null, 2) + '\n');
  } else {
    let count = 0;
    const updated = text.replace(/#\|(\{[^\n]+)/g, (line, wire) => {
      let body;
      try { body = JSON.parse(wire); } catch { return line; }
      if (body.version !== 'actql-check-environment/0.1') return line;
      count++;
      return '#|' + canonicalText(refresh(body, original_cid));
    });
    assert.equal(count, 1, path + ': exact current environment');
    texts.set(path, updated);
  }
}
// A caller's expected CID belongs to the exact named environment argument,
// even when it predates the previous capability-only fixture refresh.
for (const binding of namedBindings) {
  const owner = texts.get(binding.owner);
  const wire = owner.match(new RegExp('let ' + binding.name + ' : String =\\s*\\n\\s*#\\|([^\\n]+)'))?.[1];
  assert(wire, binding.owner + ': named environment owner');
  const cid = JSON.parse(wire).evidence_bundle_cid;
  for (const path of binding.consumers) {
    let text = texts.get(path);
    const pattern = new RegExp('(admit_client_check_environment\\(\\s*' + binding.name + ',\\s*")([^"]+)(")', 'g');
    const matches = [...text.matchAll(pattern)];
    assert(matches.length > 0, path + ': exact environment argument');
    for (const match of matches) text = text.replaceAll(match[2], cid);
    texts.set(path, text);
  }
  for (const path of binding.selectorConsumers ?? []) {
    let text = texts.get(path);
    assert(text.includes(binding.name), path + ': original source environment selector');
    const pattern = /else if source \{\s*"(sha256:[a-f0-9]{64})"/g;
    const matches = [...text.matchAll(pattern)];
    assert.equal(matches.length, 1, path + ': original source CID selector');
    text = text.replaceAll(matches[0][1], cid);
    texts.set(path, text);
  }
}
for (const [path, original] of texts) {
  let text = original;
  if (path === 'scripts/legacy-task-run-material-fixtures.test.mjs') {
    const current = JSON.parse(texts.get('adapters/host-node/fixtures/two-source/two-source.environment.json')).evidence_bundle_cid;
    text = text.replace(/const currentCid = '[^']+';/, `const currentCid = '${current}';`);
  } else for (const [before, after] of replacements) text = text.replaceAll(before, after);
  const retained = retainedBlocks.get(path);
  if (retained) {
    assert.equal(text.split(retained.slot).length, 2, 'retained fixture remains separate');
    text = text.replace(retained.slot, retained.body);
  }
  if (process.argv.includes('--write')) writeFileSync(path, text);
  else assert.equal(readFileSync(path, 'utf8'), text, path + ': stale current query admission fixture');
}
console.log(`${definitions.length} current query environments and ${consumers.length} bounded consumers verified; no execution permission issued.`);
