///|
// Actual checked listing schema and finite implemented protocol. The fixed
// scope/version identities below are explicit component declaration DATA,
// never an Account decision, ReferenceIssuer or normal installation proof.
fn managed_listing_fixture_declaration() -> @rows.RowDeclaration raise {
  let schema : Json = {
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
  let canonical = @identity.from_json(schema, 4096, 32, 65536)
  let spec : @rows.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: @identity.stringify_value(canonical, 65536, 4096, 32),
    schema_cid: @identity.cid_value(canonical, 65536, 4096, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let limits : @rows.RowDeclarationLimits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_views: 1,
    max_fields: 7,
  }
  let original = @rows.generate_relation_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [spec],
    limits,
  ).managed_capture_stage("listing schema original")
  let profile : Json = {
    "version": "actql-file-list/0.1",
    "kind": "file_listing",
    "selectable": ["paths", "glob"],
    "allow_unfiltered_listing": true,
    "admitted_scope_contract_cid": "sha256:" + "a".repeat(64),
    "listing_schema_contract_cid": original.views[0].carrier_schema_cid,
    "version_capability": {
      "contract_cid": "sha256:" + "b".repeat(64),
      "required_nonnull": true,
    },
    "max_listing_items": 2,
    "max_examined_items": 2,
    "max_listing_pages": 1,
    "max_request_attempts": 1,
    "max_listing_bytes": 8192,
    "max_listing_duration_ms": 30000,
    "maximum_path_length": 4096,
  }
  @rows.generate_relation_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..spec,
        facts_wire: Some(({ "file_listing": profile } : Json).stringify()),
      },
    ],
    limits,
  ).managed_capture_stage("listing bounded original declaration")
}

///|
fn managed_listing_fixture_case(
  clock_mode : Int,
  query? : Bool = false,
) -> Unit raise {
  let (prototype, temporary, fields) = file_listing_page_fixture()
  assert_true(@rows.discard_relation_document_original(temporary))
  let selection = {
    ..prototype.selection,
    directory: @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap(),
    name: "row-source-files",
  }
  let physical_provider = prepare_native_relation_file_provider(
    prototype.declaration,
    selection,
    prototype.limits,
  ).managed_capture_stage("actual original physical file projection")
  let declaration = managed_listing_fixture_declaration()
  let live = Ref(true)
  let first = file_listing_test_resource("first", live)
  let second = file_listing_test_resource("second", live)
  guard first.value is @admitted.Reference(a) &&
    second.value is @admitted.Reference(b) else {
    fail("component Source references")
  }
  let issuer = @admitted.bind_reference_reissuer((contract, wire) => {
    if @admitted.reference_wire(a) == wire &&
      @admitted.reference_compatible(a, contract) {
      Some(a)
    } else if @admitted.reference_wire(b) == wire &&
      @admitted.reference_compatible(b, contract) {
      Some(b)
    } else {
      None
    }
  })
  let clock_calls = Ref(0)
  let now_ms : (() -> Int64)? = if clock_mode == 0 {
    None
  } else {
    Some(() => {
      clock_calls.val += 1
      if clock_calls.val > 1 && clock_mode == 2 {
        -1L
      } else if clock_calls.val > 1 && clock_mode == 3 {
        999L
      } else {
        1000L + clock_calls.val.to_int64()
      }
    })
  }
  let listing = prepare_native_relation_file_listing_provider(
    declaration,
    "files",
    physical_provider,
    fields,
    issuer,
    identity => {
      if identity == "first" {
        Ok(first)
      } else if identity == "second" {
        Ok(second)
      } else {
        Err(ForeignOriginal)
      }
    },
    now_ms~,
  ).managed_capture_stage("same Source listing provider original")
  let (wire, cid) = capture_fixture_environment(declaration)
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).managed_capture_stage("listing environment original")
  let contracts = @local.prepare_installed_sequence_contracts(
    capture_fixture_registry,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
  ).managed_capture_stage("listing sequence originals")
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).managed_capture_stage("listing compiler manifests")
  let program =
    #|{"version":"actql/0.1","id":"native-file-listing-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"files","request":{"paths":null,"glob":null}}},"steps":[{"select":["resource","name"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["resource","name"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"name <> ''"},{"select":["resource","name"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["resource","name"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let input = [1]
  let (arena, domain, execution, initial) = managed_capture_fixture_facility(
    input,
  )
  arena
  .enter_domain_retained_execution(execution)
  .managed_capture_stage("listing actual payload")
  let owner = managed_capture_fixture_work(
    arena,
    execution,
    initial,
    input,
    selection,
    declaration,
    listing.capacity(),
    environment,
    contracts,
    manifests,
    physical_provider.limits,
    // Exact authored body extent is supplied by the external namespace owner.
    242L,
    Some(physical_provider),
    listing=Some(listing),
    program=Some(program),
    clock_refusal=if clock_mode >= 2 { clock_mode } else { 0 },
    query~,
  )
  arena
  .close_domain_retained_execution(execution)
  .managed_capture_stage("listing physical child retirement")
  @local.retire_installed_managed_run(owner).managed_capture_stage(
    "listing original Run retirement",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .managed_capture_stage("listing physical domain ACK")
  arena.try_close().managed_capture_stage("listing arena close")
  live.val = false
  if clock_mode == 1 {
    assert_true(clock_calls.val > 1)
  } else if clock_mode == 2 || clock_mode == 3 {
    assert_eq(clock_calls.val, 2)
  } else if clock_mode == 4 {
    assert_eq(clock_calls.val, 1)
  }
}

///|
test "Native listing uses the SAME managed Plan ticket issuer and physical Ledger" {
  managed_listing_fixture_case(0)
}

///|
test "Native listing bound Host clock drives the SAME managed read without elapsed injection" {
  managed_listing_fixture_case(1)
}

///|
test "Native listing clock failure regression and replacement fence the original read without resampling" {
  for mode in [2, 3, 4] {
    managed_listing_fixture_case(mode)
  }
}

///|
test "Native managed Query listing preserves its original Plan issuer and physical Ledger" {
  managed_listing_fixture_case(1, query=true)
}
