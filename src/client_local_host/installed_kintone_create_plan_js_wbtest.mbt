///|
// Actual portable Kintone declaration/Mapping and checked CREATE preparation.
// Metadata and authored values are fixture DATA, not a Site/current grant or
// physical observation. The normal constructor/backing connection is separate.
fn installed_kintone_create_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  @kintone_host.RecordDeclaration,
  @kintone_host.RecordCreateMapping,
) raise {
  let bounds : @row_source_host.RowDeclarationLimits = {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 32,
    max_views: 1,
    max_fields: 16,
  }
  let catalog = @kintone_catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true,\"defaultValue\":\"server\"}}}",
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  let original = @kintone_host.declare_records(
    catalog,
    None,
    ["Subject"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    {
      max_columns: 8,
      max_name_bytes: 128,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
    },
    bounds,
  ).unwrap()
  let selected = @kintone_host.prepare_record_create_mapping(
    original,
    "inquiries",
    [{ target: "Subject", field: "originalSubject", null_behavior: "reject", }],
    "required",
    bounds,
  ).unwrap()
  let mapping = @kintone_host.record_create_mapping(selected)
  let declaration = @kintone_host.record_declaration(original)
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(base) else { fail("fixture Environment object") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  for
    (field, additions) in [
      ("connector_catalogs", [declaration.catalog]),
      ("contract_registry", declaration.contracts),
      ("source_views", declaration.view_bodies),
      ("schema_snapshots", schemas),
      ("connector_capabilities", capabilities),
      ("mapping_contracts", [mapping.body]),
    ] {
    base[field] = effect_plan_fixture_members(base[field], additions)
  }
  guard base["connector_manifest"] is Object(manifest) else {
    fail("fixture connector manifest")
  }
  manifest["connectors"] = effect_plan_fixture_members(manifest["connectors"], [
    declaration.manifest_entry,
  ])
  let canonical = () => {
    @identity.stringify_value(
      @identity.from_json(parsed, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
  }
  let evidence = "sha256:" + @sha.hex(@utf8.encode(canonical()))
  base["evidence_bundle_cid"] = @json.parse("\"" + evidence + "\"")
  let environment = @publication_host.admit_client_check_environment(
    canonical(),
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"installed-kintone-create","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"originalSubject":{"type":"string","nullable":false}},"rows":[{"originalSubject":"requested 東京"}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["originalSubject"]}},"effects":{"createOne":{"create":{"target":"connector://kintone/inquiries","mapping":"mapping:fixture/create","from":{"result":"rows"}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = @publication_host.prepare_client_effect_computation(
    document.replace(old="mapping:fixture/create", new=mapping.mapping_ref),
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "installed-kintone-create",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (prepared, request, contracts, original, selected)
}

///|
test "actual Kintone Mapping and original declaration reach checked CREATE preparation" {
  let (prepared, _, _, original, selected) = installed_kintone_create_fixture()
  let mapping = @kintone_host.record_create_mapping(selected)
  assert_true(
    @kintone_host.record_create_mapping_matches_declaration(selected, original),
  )
  let descriptor = @publication_host.client_effect_member_descriptor(
    prepared, 0, "createOne", 1000,
  ).unwrap()
  assert_eq(descriptor.0, 0)
  assert_eq(descriptor.2, "create")
  assert_eq(descriptor.3, "connector://kintone/inquiries")
  assert_eq(descriptor.4, mapping.mapping_ref)
  assert_eq(descriptor.5, mapping.mapping_cid)
}
