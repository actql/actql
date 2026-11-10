///|
#cfg(target="js")
fn whole_listing_effect_declaration(
  catalog_maximum? : Int? = Some(3),
) -> @row_source_host.RowDeclaration raise {
  let fields : Json = {
    "id": { "type": "number", "nullable": false },
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "name": { "type": "string", "nullable": false },
    "version": { "type": "string", "nullable": false },
    "path": { "type": "string", "nullable": true },
    "media_type": { "type": "string", "nullable": true },
    "size_bytes": { "type": "number", "nullable": true },
    "modified_at": { "type": "timestamp", "nullable": true },
  }
  let value = @identity.from_json(fields, 1000, 32, 100000)
  let spec : @row_source_host.RowRelationViewSpec = {
    resource: "r",
    resource_kind: "file",
    schema_wire: @identity.stringify_value(value, 100000, 1000, 32),
    schema_cid: @identity.cid_value(value, 100000, 1000, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let limits : @row_source_host.RowDeclarationLimits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_views: 1,
    max_fields: 8,
  }
  let base = @row_source_host.generate_relation_row_declaration(
    "operation-source",
    "fixture",
    "fixture/0.1",
    [spec],
    limits,
  ).unwrap()
  let profile : Json = {
    "file_listing": {
      "version": "actql-file-list/0.1",
      "kind": "file_listing",
      "selectable": ["paths", "glob"],
      "allow_unfiltered_listing": true,
      "admitted_scope_contract_cid": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "listing_schema_contract_cid": base.views[0].carrier_schema_cid,
      "version_capability": {
        "contract_cid": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "required_nonnull": true,
      },
      "max_listing_items": 3,
      "max_examined_items": 1000000,
      "max_listing_pages": 4,
      "max_request_attempts": 4,
      "max_listing_bytes": 8192,
      "max_listing_duration_ms": 100,
      "maximum_path_length": 128,
    },
  }
  guard profile is Object(facts) && facts["file_listing"] is Object(listing) else {
    fail("fixture listing profile")
  }
  match catalog_maximum {
    None => listing.remove("max_listing_items") |> ignore
    Some(value) =>
      listing["max_listing_items"] = Json::number(value.to_double())
  }
  @row_source_host.generate_relation_row_declaration(
    "operation-source",
    "fixture",
    "fixture/0.1",
    [{ ..spec, facts_wire: Some(profile.stringify()), }],
    limits,
  ).unwrap()
}

///|
#cfg(target="js")
test "Whole listing without a Catalog row ceiling borrows its original checked Host policy" {
  let declaration = whole_listing_effect_declaration(catalog_maximum=None)
  let plan = effect_operation_source_plan_fixture(
    whole_inputs=true,
    source_request=Some("{\"paths\":null,\"glob\":null}"),
    source_declaration=Some(declaration),
    host_listing_items=Some(2),
  )
  let whole = plan.whole_sources[0].unwrap().1
  assert_true(
    @row_source_host.row_input_acquisition_is_listing(whole.acquisition),
  )
  // The capture allows three rows; it is not substituted for this independently
  // selected Host ceiling. The declaration supplies no count fact or maximum.
  assert_eq(
    @row_source_host.row_input_acquisition_max_rows(whole.acquisition),
    3,
  )
  let policy = installed_source_listing_policy(plan.graph)
  assert_eq(
    @capacity.ceiling_value(
      @capacity.ceiling(policy, "max_file_listing_items").unwrap(),
    ),
    2L,
  )
}

///|
// Real Core preparation/adoption/Source/RowRun originals. Physical provider,
// Authority and stop below are explicit fixture ports, not ordinary acceptance.
#cfg(target="js")
test "Effect preparation parent grows its original listing RowRun without a seeded capacity substitution" {
  let declaration = whole_listing_effect_declaration()
  let plan = effect_operation_source_plan_fixture(
    whole_inputs=true,
    source_request=Some("{\"paths\":null,\"glob\":null}"),
    source_declaration=Some(declaration),
  )
  let quote = prepared_installed_effect_managed_requirements(plan)
  // The existing original installation fixture supplies a finite parent, not
  // the future listing maximum. The actual operation reserves/grows beneath it.
  quote[4] = Int64::max(quote[4], 536870912L)
  quote[5] = Int64::max(quote[5], 536870912L)
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (read, original, acquisition, _) = begin_installed_effect_managed_whole_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  assert_true(read.ledger is Some(actual) && physical_equal(actual, ledger))
  let run = start_installed_whole_source_read_rows(
    read,
    acquisition,
    "same-effect-listing",
    _ => true,
    2048L,
    2048L,
  ).unwrap()
  let issuer = @admitted.bind_reference_issuer((_, _) => true, _ => true)
  @row_source_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 2048, max_nodes: 1000, max_depth: 20, max_rows: 3, },
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  @row_source_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  let body = @utf8.encode(
    (
      #|{"items":[{"id":3,"resource":{"$actql_ref":"resource","version":"actql-resource-ref/0.1","resource_kind":"file","provider_namespace":"fixture","provider_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","boundary_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","identity_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"},"name":"a.txt","path":"a.txt","version":"v1","media_type":null,"size_bytes":3,"modified_at":null}],"request_token":null,"next_token":null}
    ),
  )
  let charge = @row_source_host.charge_row_run_page(run, body).unwrap()
  let before = @resources.ledger_usage(ledger)
  @row_source_host.begin_charged_row_run_listing_page(run, charge, body, 1L).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_true(grown.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(grown.reserved_execution_bytes > before.reserved_execution_bytes)
  assert_eq(grown.reserved_attempts, before.reserved_attempts)
  while @row_source_host.advance_row_run_listing_page(run, 1, 1L).unwrap()
        is ListingPageContinue(_) {

  }
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let source = @row_source_host.row_capture_source(
    @row_source_host.capture_row_run(run).unwrap(),
  ).unwrap()
  assert_true(
    @query.captured_source_matches_input_acquisition(source, original),
  )
  assert_eq(@query.captured_source_row_count(source), Some(1))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
