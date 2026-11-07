///|
// Exact independently sealed snapshot-checkpoint-explicit public vector. No
// product output supplies this input or expected constructor quantities.
fn construction_catalog() -> @environment.SourceRequestContracts {
  fixture_catalog(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:3786b9b50a35e7cfa0ba19eadf1ff97fb2a248450e87be6ba1d209e2cc9ecefa\",\"commands\":[],\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contracts\":[{\"body\":{},\"cid\":\"sha256:10b1ca923970aa50ac04a5755deb02d8c22a2899d93b2bef6dad48af93af1ff6\",\"id\":\"fixture-4\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:67344bddee3781cb87c183208b2e932ef5972d6172809adb1fb592d3a1ce3383\",\"id\":\"fixture-5\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"nullable\":false,\"type\":\"string\"},\"cid\":\"sha256:9b9ba852bb677ac0db4b057735b94b21e1cb191a5efffe551d4afe2daba904f3\",\"id\":\"fixture-3\",\"kind\":\"checkpoint\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"checkpoint\":{\"expires\":false,\"kind\":\"opaque\",\"value_schema\":{\"cid\":\"sha256:9b9ba852bb677ac0db4b057735b94b21e1cb191a5efffe551d4afe2daba904f3\",\"id\":\"fixture-3\",\"version\":\"fixture\"}},\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:6f18934fff3fe00ff10f513bb5a7cc79e699a252df06b14ab49f33af700d2b5a\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:10b1ca923970aa50ac04a5755deb02d8c22a2899d93b2bef6dad48af93af1ff6\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:67344bddee3781cb87c183208b2e932ef5972d6172809adb1fb592d3a1ce3383\",\"id\":\"fixture-5\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}]}],\"contract_registry\":[{\"body\":{\"nullable\":false,\"type\":\"string\"},\"cid\":\"sha256:9b9ba852bb677ac0db4b057735b94b21e1cb191a5efffe551d4afe2daba904f3\",\"id\":\"fixture-3\",\"kind\":\"checkpoint\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:10b1ca923970aa50ac04a5755deb02d8c22a2899d93b2bef6dad48af93af1ff6\",\"id\":\"fixture-4\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:67344bddee3781cb87c183208b2e932ef5972d6172809adb1fb592d3a1ce3383\",\"id\":\"fixture-5\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"evidence_bundle_cid\":\"sha256:d5b5a909cfc9ad73bae97118007a610defd6c4d93e1d92ac5262cfb60292f271\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"checkpoint\":{\"expires\":false,\"kind\":\"opaque\",\"value_schema\":{\"cid\":\"sha256:9b9ba852bb677ac0db4b057735b94b21e1cb191a5efffe551d4afe2daba904f3\",\"id\":\"fixture-3\",\"version\":\"fixture\"}},\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:6f18934fff3fe00ff10f513bb5a7cc79e699a252df06b14ab49f33af700d2b5a\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:10b1ca923970aa50ac04a5755deb02d8c22a2899d93b2bef6dad48af93af1ff6\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:67344bddee3781cb87c183208b2e932ef5972d6172809adb1fb592d3a1ce3383\",\"id\":\"fixture-5\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:d5b5a909cfc9ad73bae97118007a610defd6c4d93e1d92ac5262cfb60292f271",
  )
}

///|
test "resolver constructor metadata keeps original identities separate from opaque request data" {
  let catalog = construction_catalog()
  let small = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\",\"request\":{\"opaque\":\"x\"}}",
  )
  let large = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\",\"request\":{\"opaque\":\"" +
    "x".repeat(10000) +
    "\"}}",
  )
  let g = observe_resolution_construction_geometry(small, catalog, caps())
  let larger = observe_resolution_construction_geometry(large, catalog, caps())
  assert_eq(
    (g.inputs, g.views, g.candidate_inputs, g.candidate_views),
    (1, 1, 1, 1),
  )
  assert_eq((g.max_view_fields, g.max_declaration_fields), (11, 4))
  assert_eq(
    (
      g.identity_utf16,
      g.max_identity_utf16,
      g.max_connector_utf16,
      g.max_view_utf16,
      g.reference_utf16,
      g.max_reference_utf16,
    ),
    (80L, 71, 8, 1, 24L, 24),
  )
  assert_true(
    g.inspection_work <= resolution_construction_inspection_bound(small, caps()),
  )
  assert_eq(g.identity_utf16, larger.identity_utf16)
  assert_eq(g.inspection_work, larger.inspection_work)
  let q = resolution_construction_inventory(g, caps()).unwrap()
  assert_eq(q, resolution_construction_inventory(larger, caps()).unwrap())
  // Same original binding records, normalized text and entry-array envelope;
  // borrowed Inputs/Catalog/request bodies are not copied into this quantity.
  assert_eq(q.returned, {
    record_headers: 18L,
    reference_slots: 39L,
    scalar_words: 11L,
  })
  // The pinned NFC output expansion is four per original identity UTF16 unit.
  assert_eq(q.returned_utf16_units, 320L) // 4 * 80
  let resolved = resolve(large, catalog, caps()).unwrap()
  assert_true(physical_equal(inputs(resolved), large))
  assert_true(physical_equal(@sourceview_resolution.catalog(resolved), catalog))
  assert_eq(selected_name(at(resolved, 0).unwrap()), "v")
}

///|
test "resolver constructor minimum charges bound metadata and unconstructed backing" {
  let catalog = construction_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\"}",
  )
  let prefix = @inputs.work(inputs)
  // The actual admitted root has11fields. Charge12 precedes its first Map.
  let short : Limits = { ..caps(), max_work: prefix + 11, }
  let g = observe_resolution_construction_geometry(inputs, catalog, short)
  assert_eq(
    (g.candidate_views, g.candidate_inputs, g.identity_utf16),
    (0, 0, 0L),
  )
  assert_true(
    g.inspection_work <= resolution_construction_inspection_bound(inputs, short),
  )
  let q = resolution_construction_inventory(g, short).unwrap()
  assert_eq((q.returned_utf16_units, q.temporary_utf16_units), (0L, 0L))
  let (result, spent) = observe_resolve(inputs, catalog, short)
  assert_true(result is Err({ kind: WorkLimit, .. }))
  assert_eq(spent, 0)
  let exact = { ..caps(), max_work: prefix + 12, }
  let g = observe_resolution_construction_geometry(inputs, catalog, exact)
  assert_eq((g.candidate_views, g.candidate_inputs), (1, 0))
  assert_true(
    g.inspection_work <= resolution_construction_inspection_bound(inputs, exact),
  )
  assert_true(resolution_construction_inventory(g, exact) is Some(_))
  let (result, spent) = observe_resolve(inputs, catalog, exact)
  assert_true(result is Err({ kind: WorkLimit, .. }))
  assert_eq(spent, 12)
}

///|
test "resolver constructor early refusal metadata does not traverse Catalog identities" {
  let catalog = construction_catalog()
  let inputs = fixture_inputs("{\"connector\":\"crm/main\",\"resource\":\"r\"}")
  let limits : Limits = { ..caps(), max_views: 0, }
  let g = observe_resolution_construction_geometry(inputs, catalog, limits)
  assert_eq((g.views, g.candidate_views, g.inspection_work), (1, 0, 0L))
  let q = resolution_construction_inventory(g, limits).unwrap()
  assert_eq((q.returned_utf16_units, q.temporary_utf16_units), (0L, 0L))
  assert_true(resolve(inputs, catalog, limits) is Err({ kind: ViewLimit, .. }))
  assert_true(
    resolution_construction_inventory({ ..g, inputs: -1, }, caps()) is None,
  )
  assert_true(
    resolution_construction_inventory({ ..g, reference_utf16: -1L, }, caps())
    is None,
  )
}

///|
// Original independent utf16-candidates public vector; sort expectation is
// authored UTF16 order, never a normalized result generated by the resolver.
fn ambiguous_construction_catalog() -> @environment.SourceRequestContracts {
  fixture_catalog(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:d1cae297f37642703ebe6d5d6eb6c8647a97900390bc380b0ff7e35d41e6f502\",\"commands\":[],\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contracts\":[{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#a\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:5d959264d73f7ebc5764abee8fbe54a3df62262a7aefa02979a30a498f69a91e\",\"id\":\"fixture-6\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#𐀀\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:c9002b473d7d9a2358810ff1e2040ea4414ae844548164d8ee1d3c718301eec9\",\"id\":\"fixture-5\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:d675b517745b1af17b780bc455e320b8c786d8a5717317932e70515be42bd6e4\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:56707cfec437c6a246a108bf1470e78475e4b0d0b66e05e94fb5efba6562c712\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:5d959264d73f7ebc5764abee8fbe54a3df62262a7aefa02979a30a498f69a91e\",\"id\":\"fixture-6\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"a\",\"view_version\":\"fixture\"},{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:a6513a94d6cc5fb097b80ea5dd5eb8b20bee66aa8586615326177406a6ac0f4b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:d675b517745b1af17b780bc455e320b8c786d8a5717317932e70515be42bd6e4\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"\",\"view_version\":\"fixture\"},{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:fb64c4e8b43638bf8ef240a54b0e2a44dcc752131836211b31a13c38003ccd88\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:c9002b473d7d9a2358810ff1e2040ea4414ae844548164d8ee1d3c718301eec9\",\"id\":\"fixture-5\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"𐀀\",\"view_version\":\"fixture\"}]}],\"contract_registry\":[{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#a\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:5d959264d73f7ebc5764abee8fbe54a3df62262a7aefa02979a30a498f69a91e\",\"id\":\"fixture-6\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#𐀀\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:c9002b473d7d9a2358810ff1e2040ea4414ae844548164d8ee1d3c718301eec9\",\"id\":\"fixture-5\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/Opportunity#\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:d675b517745b1af17b780bc455e320b8c786d8a5717317932e70515be42bd6e4\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"evidence_bundle_cid\":\"sha256:c65e41f0cebbdca9ca43831e8dbc96dc8a695214cf6639416bb9af3eb069f9f7\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:fb64c4e8b43638bf8ef240a54b0e2a44dcc752131836211b31a13c38003ccd88\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:c9002b473d7d9a2358810ff1e2040ea4414ae844548164d8ee1d3c718301eec9\",\"id\":\"fixture-5\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"𐀀\",\"view_version\":\"fixture\"},{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:56707cfec437c6a246a108bf1470e78475e4b0d0b66e05e94fb5efba6562c712\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:5d959264d73f7ebc5764abee8fbe54a3df62262a7aefa02979a30a498f69a91e\",\"id\":\"fixture-6\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"a\",\"view_version\":\"fixture\"},{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:a6513a94d6cc5fb097b80ea5dd5eb8b20bee66aa8586615326177406a6ac0f4b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:d675b517745b1af17b780bc455e320b8c786d8a5717317932e70515be42bd6e4\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:3ee7c6cd829b6c838f70a76fdbaf848a5fcca4598f21edb357f5bc5ea51ff482\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"\",\"view_version\":\"fixture\"}],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:c65e41f0cebbdca9ca43831e8dbc96dc8a695214cf6639416bb9af3eb069f9f7",
  )
}

///|
test "resolver constructor retains actual ambiguous UTF16 names and both sort arrays" {
  let catalog = ambiguous_construction_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"Opportunity\"}",
  )
  let g = observe_resolution_construction_geometry(inputs, catalog, caps())
  assert_eq((g.views, g.candidate_views, g.candidate_inputs), (3, 3, 1))
  assert_eq((g.identity_utf16, g.reference_utf16), (241L, 103L))
  assert_true(
    g.inspection_work <=
    resolution_construction_inspection_bound(inputs, caps()),
  )
  let q = resolution_construction_inventory(g, caps()).unwrap()
  assert_eq(q.returned, {
    record_headers: 29L,
    reference_slots: 67L,
    scalar_words: 13L,
  })
  assert_eq(q.returned_utf16_units, 964L) // 4 * 241
  let result = resolve(inputs, catalog, caps())
  assert_true(result is Err({ kind: Ambiguous(["a", "𐀀", ""]), .. }))
}
