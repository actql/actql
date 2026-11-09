///|
fn native_project_mock_model_in_original_read(
  partial : Bool,
  environment : Bool,
) -> Unit raise {
  let original = native_project_mock_model_fixture(
    if partial {
      "deal-review-wrong-answer"
    } else {
      "deal-review"
    },
  )
  defer original.retire()
  let result = original.prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  assert_eq(original.models.length(), 1)
  if partial {
    assert_true(
      result is Err(Answers(@model.ModelMockAnswerIssue::OutputValue)),
    )
    assert_true(original.model_profile is Some(_))
    assert_true(original.models[0].installation is None)
  } else {
    result.unwrap()
    assert_true(original.models[0].installation is Some(_))
    if environment {
      let base = explain_fixture_environment()
      let prepared = original.prepare_model_environment(base).unwrap()
      assert_true(
        physical_equal(
          prepared,
          original.prepare_model_environment(base).unwrap(),
        ),
      )
      let entry = original.models[0]
      let execution = entry.execution.unwrap()
      assert_true(entry.admitted is Some(_))
      let provider = original.model_provider(execution).unwrap()
      assert_true(
        physical_equal(provider, original.model_provider(execution).unwrap()),
      )
      assert_true(
        physical_equal(
          provider,
          @model.original_model_mock_provider(entry.installation.unwrap()).unwrap(),
        ),
      )
      // Merely reading immutable selection must neither consult the clock nor
      // turn this implementation capability into a synchronous call bypass.
      assert_true(@model.model_provider_synchronous_invoke(provider) is None)
      let tasks = @checked.checking_environment_model_tasks(prepared).unwrap()
      let task = @compiler_environment.resolve_model_task(
        tasks, "model-task:deal-review.v1",
      ).unwrap()
      assert_true(
        @compiler_environment.normalized_public_mock_model_task_matches_task(
          original.models[0].normalized.unwrap(),
          original.models[0].declaration,
          original.model_profile.unwrap(),
          task,
        ),
      )
      let materials = @compiler_environment.model_mock_execution_materials(
        original.model_profile.unwrap(),
        entry.normalized.unwrap(),
        local_project_mock_task_limits(),
      ).unwrap()
      let equal_execution = @compiler_environment.read_model_execution_contract(
        task,
        @utf8.encode(materials.0),
        materials.1,
        local_project_mock_task_limits().bodies,
        local_project_mock_task_limits().max_work,
      ).unwrap()
      assert_false(physical_equal(execution, equal_execution))
      assert_true(
        original.model_provider(equal_execution) is Err(ForeignOriginal),
      )
      assert_true(
        physical_equal(provider, original.model_provider(execution).unwrap()),
      )
      // Equal separately admitted DATA cannot replace this caller's base.
      assert_true(
        original.prepare_model_environment(explain_fixture_environment())
        is Err(ForeignOriginal),
      )
      assert_eq(
        @compiler_environment.member_count(
          @checked.checking_environment_wire(base),
          ModelTaskContracts,
        ),
        0,
      )
      assert_eq(
        @compiler_environment.member_count(
          @checked.checking_environment_wire(prepared),
          ModelTaskContracts,
        ),
        1,
      )
    }
  }
}

///|
fn native_project_mock_model_backed_read(
  partial : Bool,
  environment? : Bool = false,
  sources? : Bool = false,
  private_source_field? : Bool = false,
  source_environment? : Bool = false,
  file_bindings? : Bool = false,
  file_facts? : Bool = false,
  write_mapping? : Bool = false,
  file_references? : Bool = false,
  readme_request? : Bool = false,
  lookup_policy? : Bool = false,
  effect_compilation? : Bool = false,
  effect_source_inputs? : Bool = false,
  content_join? : Bool = false,
  account_initialization? : Bool = false,
  static_policy? : Bool = false,
  authored_predicate? : Bool = false,
  effect_result_source? : Bool = false,
  effect_recipe? : Bool = false,
) -> Unit raise {
  // Reuse the existing real Native facility entry, as in Request/Effect's
  // physical component. This supplies no Command platform/Journal/Account.
  // Both physical facilities are created in the outer control lifetime.
  // Project metadata stays retained while its SAME immutable originals are
  // borrowed by the separate Request payload, as in the ordinary command.
  let request_facility = if readme_request {
    Some(native_mock_readme_request_facility())
  } else {
    None
  }
  let profile = local_command_installed_profile(
    "0000000000000000000000000000000000000001", "0000000000000000000000000000000000000000000000000000000000000001",
  )
  let budget = local_command_initial_read_budget(profile)
  let pool = native_storage_sum([
    budget.bootstrap_retained,
    budget.bootstrap_execution,
    budget.workspace_execution,
    budget.read_retained,
    budget.read_execution,
  ]).unwrap()
  let host = @initial_arena.prepare_installed_arena_host(
    profile.source,
    profile.recipe,
    1L,
    profile.arena_bytes,
    profile.host_limits,
    profile.control_bytes,
  ).unwrap()
  host.acquire().unwrap()
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    host
    .prepare_domain_in_process(
      backing,
      profile.read_domain_bytes,
      profile.read_domain_limits,
      initial_window=Some(pool),
    )
    .unwrap() {
    @initial_arena.PreparedDomain(value) => value
    @initial_arena.PendingDomain(_, _) => fail("actual metadata domain pending")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host
  .prepare_domain_read(
    domain,
    execution_ceiling=match profile.native_storage.read_selection {
      CommandReadFiniteFacility(value) => value
    },
  )
  .unwrap()
  let read = match host.prepare_domain_original_read(domain, budget).unwrap() {
    @initial_arena.ReadyOriginalRead(value) => value
    @initial_arena.PendingOriginalRead(_, _) =>
      fail("actual metadata Read pending")
  }
  host.enter_domain_original_read(read).unwrap()
  let mut request_issue : String? = None
  if request_facility is Some(facility) {
    request_issue = native_mock_readme_request_in_metadata_read(
      host,
      read,
      facility,
      effect_compilation~,
      effect_source_inputs~,
      content_join~,
      static_policy~,
      authored_predicate~,
      effect_result_source~,
      effect_recipe~,
    )
  } else if account_initialization {
    native_project_mock_account_in_original_read()
  } else if lookup_policy {
    native_mock_lookup_policy_in_original_read()
  } else if file_references {
    native_project_mock_file_references_in_original_read()
  } else if write_mapping {
    native_project_mock_write_mapping_in_original_read()
  } else if file_facts {
    native_project_mock_file_facts_in_original_read()
  } else if file_bindings {
    native_project_mock_file_bindings_in_original_read()
  } else if source_environment {
    native_project_mock_source_environment_in_original_read()
  } else if private_source_field {
    native_project_mock_source_private_field_in_original_read()
  } else if sources {
    native_project_mock_source_in_original_read()
  } else {
    native_project_mock_model_in_original_read(partial, environment)
  }
  host.leave_domain_original_read(read).unwrap()
  match host.close_domain_original_read(read) {
    Ok(_) => ()
    Err(_) => {
      let value = host.observe_domain_original_read_cleanup(read).unwrap()
      fail(
        "metadata Read pending: users=" +
        value.users.to_string() +
        ",active=" +
        value.active.to_string() +
        ",blocks=" +
        value.managed_live_blocks.to_string() +
        ",bytes=" +
        value.managed_requested_bytes.to_string(),
      )
    }
  }
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  if request_issue is Some(issue) {
    fail("whole original README Native Request: " + issue)
  }
}

///|
test "Native Project Mock actual backed Read retires Model metadata without a fabricated command platform" {
  native_project_mock_model_backed_read(false)
}

///|
test "Native Project Mock actual backed Read closes a partial Model constructor without suppressing its refusal" {
  native_project_mock_model_backed_read(true)
}

///|
test "Native Project Mock actual backed Read projects original Model environment once before Request checking" {
  native_project_mock_model_backed_read(false, environment=true)
}

///|
fn native_project_mock_source_in_original_read() -> Unit raise {
  // No data.json exists here. Declaration construction must not open it or
  // fabricate a Source capture, ResourceRef, ContentRef or permission.
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  original.prepare_source_declarations().unwrap()
  assert_eq(original.sources.length(), 2)
  let salesforce = original.sources[0]
  let drive = original.sources[1]
  assert_eq(salesforce._retained_connection, "salesforce")
  assert_eq(drive._retained_connection, "drive")
  assert_eq(salesforce._retained_declaration.views.length(), 1)
  assert_eq(drive._retained_declaration.views.length(), 2)
  assert_true(
    drive._retained_declaration.view_bodies.any(wire => {
      wire.contains("\"cardinality\":\"one\"")
    }),
  )
  assert_eq(salesforce._retained_files.length(), 0)
  assert_eq(drive._retained_files.length(), 1)
  let file = drive._retained_files[0]
  assert_eq(file.listing.resource, "files")
  assert_eq(file.content.resource, "contents")
  assert_eq(file._retained_selection.resource, "files")
  assert_eq(file._retained_selection.items_path, ["drive", "files", "rows"])
  assert_eq(file._retained_selection.key_path, Some(["drive", "files", "key"]))
  assert_eq(file._retained_selection.primary_identity, "id")
  assert_eq(file._retained_identity, "id")
  assert_eq(file._retained_name, "name")
  assert_eq(file._retained_version, "version")
  assert_eq(file._retained_media_type, "media_type")
  assert_eq(file._retained_content_utf8, "content_utf8")
  assert_eq(file._retained_path, None)
  assert_eq(file._retained_limits.page.max_bytes, 1048576)
  assert_true(file._retained_selection.directory.has_suffix("/mock"))
  assert_eq(file._retained_selection.name, "data.json")
  assert_true(
    @execution.execution_capacity_retained_bytes(
      file._retained_provider.capacity(),
    ) >
    0L,
  )
  assert_eq(file._retained_physical.views[0].resource, "files")
  assert_true(original.prepare_source_declarations() is Err(AlreadyPreparing))
  assert_eq(original.sources.length(), 2)
  assert_true(original.model_profile is None)
}

///|
test "Native Project Mock actual backed Read retains original Source declarations without reading payload" {
  native_project_mock_model_backed_read(false, sources=true)
}

///|
fn native_project_mock_source_private_field_in_original_read() -> Unit raise {
  let entry : Json = {
    "views": [
      {
        "resource": "records",
        "resource_kind": "record",
        "schema": { "id": { "type": "string", "nullable": false } },
        // This name belongs to the internal restore adapter, not the public
        // Project view. It cannot overwrite the original schema projection.
        "schema_wire": "{}",
      },
    ],
  }
  let wire = local_project_mock_relation_input(entry).unwrap()
  assert_true(
    @row_host.restore_relation_row_declaration(
      "declared",
      "declared_file",
      "declared_file/0.1",
      wire,
      None,
    )
    is Err(@row_host.RowHostIssue::InvalidSpecification),
  )
}

///|
test "Native Project Mock actual backed Read refuses public injection of private Source restore fields" {
  native_project_mock_model_backed_read(false, private_source_field=true)
}

///|
fn native_project_mock_source_environment_in_original_read() -> Unit raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  original.prepare_source_declarations().unwrap()
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .unwrap()
  let base = explain_fixture_environment()
  let source = original.prepare_source_environment(base).unwrap()
  assert_true(
    physical_equal(source, original.prepare_source_environment(base).unwrap()),
  )
  let environment = original.prepare_model_environment(source).unwrap()
  let (publication, wire) = original
    .prepare_source_publication(environment)
    .unwrap()
  let (same_publication, same_wire) = original
    .prepare_source_publication(environment)
    .unwrap()
  assert_true(physical_equal(publication, same_publication))
  assert_eq(wire, same_wire)
  assert_true(
    @source_publication.prepared_published_query_environment_matches(
      publication, environment,
    ),
  )
  assert_eq(
    @compiler_environment.member_count(
      @checked.checking_environment_wire(environment),
      SourceViews,
    ),
    3,
  )
  assert_eq(
    @compiler_environment.member_count(
      @checked.checking_environment_wire(environment),
      ModelTaskContracts,
    ),
    1,
  )
  assert_true(
    original.prepare_source_environment(explain_fixture_environment())
    is Err(ForeignOriginal),
  )
}

///|
test "Native Project Mock actual backed Read composes original Source Model environment and publication once" {
  native_project_mock_model_backed_read(false, source_environment=true)
}

///|
// The real Command consumes its available Read before Project retention.
// No Command platform, database, Account, Project permission or Run is faked.
test "Native Project input keeps the original consuming Read current" {
  let profile = local_command_installed_profile(
    "0000000000000000000000000000000000000001", "0000000000000000000000000000000000000000000000000000000000000001",
  )
  let budget = local_command_initial_read_budget(profile)
  let pool = native_storage_sum([
    budget.bootstrap_retained,
    budget.bootstrap_execution,
    budget.workspace_execution,
    budget.read_retained,
    budget.read_execution,
  ]).unwrap()
  let host = @initial_arena.prepare_installed_arena_host(
    profile.source,
    profile.recipe,
    1L,
    profile.arena_bytes,
    profile.host_limits,
    profile.control_bytes,
  ).unwrap()
  host.acquire().unwrap()
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    host
    .prepare_domain_in_process(
      backing,
      profile.read_domain_bytes,
      profile.read_domain_limits,
      initial_window=Some(pool),
    )
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("Project consuming Read domain pending")
  }
  host.transfer_domain(domain).unwrap()
  let sqlite_domain = match
    host
    .prepare_domain_in_process(
      backing,
      profile.sqlite_domain_bytes,
      profile.sqlite_domain_limits,
    )
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("Project consuming SQLite domain pending")
  }
  host.transfer_domain(sqlite_domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host.prepare_domain_read(domain).unwrap()
  host.prepare_domain_read(sqlite_domain).unwrap()
  let read = match host.prepare_domain_original_read(domain, budget).unwrap() {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("Project original Read pending")
  }
  let sqlite = match
    host
    .prepare_sqlite_library(
      sqlite_domain,
      @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap(),
      profile.sqlite_heap_bytes,
      profile.diagnostic_ceiling,
    )
    .unwrap() {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("Project SQLite library pending")
  }
  let pair = host.bind_local_host_resources(read, sqlite).unwrap()
  // This is the same actual handoff made by Command::acquire_runtime.
  host
  .prepare_local_host_read_consumer(
    pair,
    profile.consumer_retained_bytes,
    budget.read_execution,
  )
  .unwrap()
  |> ignore
  assert_true(
    local_project_input_read_current(host, read, Some(pair)) is Err(_),
  )
  host.enter_local_host_phase(pair, HostRead).unwrap()
  assert_true(host.require_domain_original_read_current(read) is Err(_))
  let current = local_project_input_read_current(host, read, Some(pair))
  host.leave_local_host_phase(pair).unwrap()
  assert_true(
    local_project_input_read_current(host, read, Some(pair)) is Err(_),
  )
  host.enter_local_host_phase(pair, HostSqlite).unwrap()
  assert_true(
    local_project_input_read_current(host, read, Some(pair)) is Err(_),
  )
  host.leave_local_host_phase(pair).unwrap()
  host.close_local_host_resources(pair).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.close_domain_after_owner_ack(sqlite_domain).unwrap()
  host.try_close().unwrap()
  assert_true(current is Ok(_))
}

///|
fn native_project_mock_file_bindings_in_original_read() -> Unit raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  original.prepare_source_declarations().unwrap()
  let source = original.sources[1]
  // Only authored declaration copies change in these distinct input cases.
  // The actual Source payload is absent, and no replacement original is issued.
  let wire = original._retained_catalog.at(1).unwrap().1
  for variant in 0..<3 {
    let entry = @json.parse(wire)
    guard entry is Object(root) &&
      root.get("file_bindings") is Some(Array(bindings)) &&
      bindings[0] is Object(binding) &&
      root.get("data") is Some(Array(data)) &&
      data[0] is Object(physical) &&
      physical.get("schema") is Some(Object(schema)) else {
      fail("authored file binding")
    }
    if variant == 0 {
      binding["unexpected_field"] = Json::string("never-a-role")
    } else if variant == 1 {
      schema["version"] = ({ "type": "number", "nullable": false } : Json)
    } else {
      data.push(data[0])
    }
    assert_true(
      local_project_mock_file_bindings(
        source._retained_connection,
        entry,
        source._retained_declaration,
        original._retained_data_file,
      )
      is Err(@row_host.InvalidSpecification),
    )
  }
  // The existing optional path role permits nullable String. Do not turn the
  // required identity/version/Text rules into a new path nullability law.
  let entry = @json.parse(wire)
  guard entry is Object(root) &&
    root.get("file_bindings") is Some(Array(bindings)) &&
    bindings[0] is Object(binding) &&
    root.get("data") is Some(Array(data)) &&
    data[0] is Object(physical) &&
    physical.get("schema") is Some(Object(schema)) else {
    fail("authored file binding")
  }
  binding["path_field"] = Json::string("optional_path")
  schema["optional_path"] = ({ "type": "string", "nullable": true } : Json)
  let selected = local_project_mock_file_bindings(
    source._retained_connection,
    entry,
    source._retained_declaration,
    original._retained_data_file,
  ).unwrap()
  assert_eq(selected.length(), 1)
  assert_eq(selected[0]._retained_path, Some("optional_path"))
  assert_eq(source._retained_files[0]._retained_path, None)
}

///|
test "Native Project Mock actual backed Read checks original physical file roles before payload" {
  native_project_mock_model_backed_read(false, file_bindings=true)
}

///|
fn native_project_mock_file_facts_in_original_read() -> Unit raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  match original.prepare_source_declarations() {
    Ok(_) => ()
    Err(Source(InvalidSpecification)) =>
      fail("File declaration InvalidSpecification")
    Err(Source(InvalidContracts)) => fail("File declaration InvalidContracts")
    Err(_) => fail("File declaration original unavailable")
  }
  let source = original.sources[1]
  let file = source._retained_files[0]
  let declaration = source._retained_declaration
  assert_eq(
    source._retained_scope_cid,
    @env.get_env_var("ACTQL_TEST_NATIVE_MOCK_DRIVE_SCOPE_CID").unwrap(),
  )
  assert_true(declaration.views.any(view => physical_equal(view, file.listing)))
  assert_true(declaration.views.any(view => physical_equal(view, file.content)))
  let bodies = declaration.contracts
  let listing = bodies
    .iter()
    .find_first(wire => wire.contains("file_listing"))
    .unwrap()
  let content = bodies
    .iter()
    .find_first(wire => wire.contains("file_content"))
    .unwrap()
  assert_true(listing.contains("\"max_listing_items\":100"))
  assert_true(listing.contains("\"max_examined_items\":100"))
  assert_true(listing.contains("\"max_listing_pages\":1"))
  assert_true(listing.contains("\"max_request_attempts\":1"))
  assert_true(listing.contains("\"max_listing_bytes\":1048576"))
  assert_true(listing.contains("\"max_listing_duration_ms\":30000"))
  assert_true(listing.contains("\"maximum_path_length\":4096"))
  assert_true(listing.contains(source._retained_scope_cid))
  assert_true(listing.contains(file.listing.carrier_schema_cid))
  assert_true(content.contains(source._retained_scope_cid))
  assert_true(content.contains(file.content.carrier_schema_cid))
  assert_true(content.contains("\"complete_per_requested_key\""))
  assert_true(content.contains("\"max_rows_per_key\":1"))
  assert_true(content.contains("\"max_pages_per_request\":1"))
  assert_true(content.contains("\"max_response_bytes_per_page\":1048576"))
  // The authored correlation is one, not a replacement zero-or-one fixture.
  assert_true(
    declaration.view_bodies.any(wire => wire.contains("\"cardinality\":\"one\"")),
  )
  assert_true(content.contains("\"exact_stored_bytes\""))
  // Complete facts still go through the same Environment/publication reader.
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .unwrap()
  let source_environment = original
    .prepare_source_environment(explain_fixture_environment())
    .unwrap()
  let environment = original
    .prepare_model_environment(source_environment)
    .unwrap()
  original.prepare_source_publication(environment).unwrap() |> ignore
  // Construction must not rewrite the originally admitted public catalogue.
  let (_, wire) = original._retained_catalog.at(1).unwrap()
  assert_false(wire.contains("max_listing_items"))
}

///|
test "Native Project Mock actual backed Read binds File facts to original schemas and physical limits" {
  native_project_mock_model_backed_read(false, file_facts=true)
}

///|
// Explicit immutable installation DATA ports exercise the SAME pure projection
// used after the normal Runtime/Account observations. They are not a Host,
// Account/capture, Runtime acquisition or normal installation qualification.
fn native_project_mock_write_mapping_in_original_read() -> Unit raise {
  let original = native_project_mock_model_fixture("deal-review-missing")
  defer original.retire()
  original.prepare_source_declarations().unwrap()
  let source = original.sources[0]
  assert_eq(source._retained_writes.length(), 1)
  assert_eq(original.sources[1]._retained_writes.length(), 0)
  let write = source._retained_writes[0]
  assert_eq(write.aliases, ["salesforce.Opportunity"])
  assert_eq(write._retained_observe_permission, "salesforce:record:observe")
  guard @json.parse(write.mapping.body) is Object(mapping) &&
    mapping.get("primary_identity") == Some(Json::string("id")) &&
    mapping.get("minimum_approval") == Some(Json::string("required")) &&
    mapping.get("target_schema") is Some(Object(schema)) &&
    schema.get("fields") is Some(Object(fields)) &&
    fields.get("NextStep") is Some(Object(next_step)) else {
    fail("original complete UPDATE Mapping")
  }
  assert_eq(next_step.get("nullable"), Some(Json::boolean(true)))
  assert_true(
    fields.contains("id") &&
    fields.contains("name") &&
    fields.contains("StageName"),
  )
  assert_true(original.update_aliases().is_empty())
  let projected = local_project_mock_write_installations(
    source,
    "sha256:" + "d".repeat(64),
    "sha256:" + "8".repeat(64),
  ).unwrap()
  assert_eq(projected.length(), 1)
  assert_true(physical_equal(projected[0].write, write))
  assert_true(physical_equal(projected[0]._retained_source, source))
  original.write_installations = Some(projected)
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .unwrap()
  let source_environment = original
    .prepare_source_environment(explain_fixture_environment())
    .unwrap()
  let environment = original
    .prepare_model_environment(source_environment)
    .unwrap()
  assert_eq(
    @compiler_environment.member_count(
      @checked.checking_environment_wire(environment),
      MappingContracts,
    ),
    1,
  )
  let (publication, wire) = original
    .prepare_source_publication(environment)
    .unwrap()
  assert_true(wire.contains(projected[0].binding))
  assert_true(wire.contains(projected[0].owner.0))
  let document = local_project_required_declaration(
    original._retained_project,
    Some("deal-review.aql"),
  ).unwrap()
  let (lowered, _) = match
    @source_publication.lower_prepared_published_query(
      publication,
      environment,
      document,
      @frontend.Text,
      None,
      public_primary=true,
    ) {
    Ok(value) => value
    Err(Frontend(QueryLowering(UpdateTargetBinding(issue)))) =>
      fail("original UPDATE: " + @debug.to_string(issue))
    Err(_) => fail("original full README lowerer")
  }
  assert_true(lowered.program is Some(_))
  assert_true(lowered.update_targets is Some(_))
  assert_true(lowered.document.contains("model-task:deal-review.v1"))
  assert_true(lowered.document.contains("StageName"))
  // Strict authored-spec refusal stays before the Common Mapping constructor.
  let (_, wire) = original._retained_catalog.at(0).unwrap()
  for variant in 0..<2 {
    guard @json.parse(wire) is Object(body) &&
      body.get("writes") is Some(Array(writes)) &&
      writes[0] is Object(spec) else {
      fail("original authored write spec")
    }
    if variant == 0 {
      spec["extra"] = Json::boolean(true)
    } else {
      spec["primary_identity"] = Json::string("name")
    }
    assert_true(
      local_project_mock_write_declarations(
        Json::object(body),
        source._retained_declaration,
      )
      is Err(_),
    )
  }
  original.retire_originals().unwrap() |> ignore
  assert_true(original.write_installations is None)
  assert_true(original.update_aliases().is_empty())
}

///|
test "Native Project Mock original UPDATE Mapping and selected metadata preserve full README lowering" {
  native_project_mock_model_backed_read(false, write_mapping=true)
}

///|
fn native_project_mock_file_references_in_original_read() -> Unit raise {
  let project = native_project_mock_model_fixture("deal-review-missing")
  defer project.retire()
  project.prepare_source_declarations().unwrap()
  let declaration = project.sources[1]
  let binding = declaration._retained_files[0]
  // Explicit immutable authority metadata for this component only. The
  // production caller obtains it from the original adopted Journal Read.
  let source = local_project_mock_file_source(
    declaration,
    "sha256:" + "8".repeat(64),
  ).unwrap()
  project.file_sources = Some([source])
  assert_eq(source.references.known.unwrap().length(), 0)
  let (provider, selected_binding) = source._retained_listings[0]
  assert_true(physical_equal(selected_binding, binding))
  assert_true(
    @execution.execution_capacity_retained_bytes(provider.capacity()) > 0L,
  )
  let raw = @env.get_env_var("ACTQL_TEST_NATIVE_MOCK_FILE_DATA").unwrap()
  let document = @row_host.admit_relation_document(
    @utf8.encode(raw),
    binding._retained_limits.page,
    binding._retained_limits.max_work,
  ).unwrap()
  let fields : @row_file.NativeRelationFileListingFields = {
    name: binding._retained_name,
    version: binding._retained_version,
    media_type: binding._retained_media_type,
    path: binding._retained_path,
  }
  let calls = Ref(0)
  let page = @row_file.project_native_relation_file_listing_page(
    binding._retained_provider,
    document,
    fields,
    identity => {
      calls.val += 1
      source.references.observe_identity(
        source._retained_issuer,
        source._retained_contract,
        binding,
        identity,
      )
    },
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_eq(source.references.known.unwrap().length(), 2)
  let first = source.references.known.unwrap()[0].value.unwrap()
  guard first.value is @admitted.Reference(reference) else {
    fail("original file reference")
  }
  assert_eq(
    @admitted.reference_identity_cid(reference),
    @env.get_env_var("ACTQL_TEST_NATIVE_MOCK_FIRST_RESOURCE_CID").unwrap(),
  )
  assert_eq(
    (source._retained_resolve_identity)(binding, reference),
    Some("file-acme-notes"),
  )
  assert_true(@admitted.reference_available(reference))
  let repeated = source.references
    .observe_identity(
      source._retained_issuer,
      source._retained_contract,
      binding,
      "file-acme-notes",
    )
    .unwrap()
  assert_true(physical_equal(first, repeated))
  assert_eq(source.references.known.unwrap().length(), 2)
  assert_true(@utf8.decode(page).contains(@admitted.reference_wire(reference)))
  // Equal wire and an independent issuer are not this Source's occurrence.
  let foreign = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, _) => true, _ => true),
    first.contract,
    @admitted.reference_wire(reference),
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  guard foreign.value is @admitted.Reference(foreign_ref) else {
    fail("foreign fixture reference")
  }
  assert_eq((source._retained_resolve_identity)(binding, foreign_ref), None)
  let copied = { ..binding, }
  assert_eq((source._retained_resolve_identity)(copied, reference), None)
  // This Source may not mint an unknown reference through its raw issuer.
  let unknown = @admitted.reference_wire(reference).replace(
    old=@admitted.reference_identity_cid(reference),
    new="sha256:" + "9".repeat(64),
  )
  assert_true(
    @admitted.issue_reference(
      source._retained_issuer,
      first.contract,
      unknown,
      { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
    )
    is Err(IssuerRejected),
  )
  assert_true(@row_host.discard_relation_document_original(document))
  project.retire_originals().unwrap() |> ignore
  assert_true(project.file_sources is None)
  assert_true(source.references.known is None)
  assert_true(!@admitted.reference_available(reference))
  assert_eq((source._retained_resolve_identity)(binding, reference), None)
  assert_true(
    source.references.observe_identity(
      source._retained_issuer,
      source._retained_contract,
      binding,
      "file-acme-notes",
    )
    is Err(ForeignOriginal),
  )
}

///|
test "Native Project Mock original file listing issuer resolves only its observed identities and retires escaped refs" {
  native_project_mock_model_backed_read(false, file_references=true)
}

///|
test "Native Project Mock retains its original admitted implementation before Graph compilation" {
  native_project_mock_model_backed_read(false, environment=true)
}

///|
fn native_project_mock_account_in_original_read() -> Unit raise {
  // Exercise the actual adoption declaration selection under the same physical
  // metadata Read. This does not open a Host or authenticate Account custody.
  let original = native_project_mock_model_fixture(
    "deal-review",
    operation="adopt",
  )
  defer original.retire()
  assert_true(original.account_subjects() is Err(ForeignOriginal))
  original.prepare_source_declarations().unwrap()
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .unwrap()
  let subjects = original.account_subjects().unwrap()
  assert_eq(subjects.sources.length(), 3)
  for
    subject in [
      ("salesforce", "Opportunity"),
      ("drive", "files"),
      ("drive", "contents"),
    ] {
    assert_true(subjects.sources.contains(subject))
  }
  assert_eq(subjects.model_tasks.length(), 1)
  assert_eq(
    subjects.model_tasks[0],
    @compiler_environment.normalized_public_model_task_materials(
      original.models[0].normalized.unwrap(),
    ).1,
  )
  assert_eq(subjects.update_target, Some(("salesforce", "Opportunity")))
  let account = @authorization.admit_account_configuration_json(
    @authorization.local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  for subject in subjects.sources {
    assert_true(
      @authorization.evaluate_account(account, {
        principal: "local-cli",
        connection: subject.0,
        resource: subject.1,
        operation: "read",
      })
      is @authorization.Allow(_),
    )
  }
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "mock",
      resource: subjects.model_tasks[0],
      operation: "infer",
    })
    is @authorization.Allow(_),
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "salesforce",
      resource: "Opportunity",
      operation: "effect",
    })
    is @authorization.Delegate(_),
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "drive",
      resource: "other",
      operation: "read",
    })
    is @authorization.Deny(_),
  )
  original.retire()
  assert_true(original.account_subjects() is Err(ForeignOriginal))
}

///|
test "Native Mock first adoption retains only the original Project Account subjects" {
  native_project_mock_model_backed_read(false, account_initialization=true)
}

///|
// Same ordinary finite Read/SQLite declarations, actual original components
// and original adopted Account. This component does not supply a packaged
// Runtime, Model dispatch, Preview, grant, business Run or Saved acceptance.
test "Native Mock Account opens its original consuming Journal Read before Model dispatch" {
  let profile = local_command_installed_profile(
    "0000000000000000000000000000000000000001", "0000000000000000000000000000000000000000000000000000000000000001",
  )
  let host = @initial_arena.prepare_installed_arena_host(
    profile.source,
    profile.recipe,
    1L,
    profile.arena_bytes,
    profile.host_limits,
    profile.control_bytes,
  ).native_mock_journal_required("prepare original Host")
  host.acquire().native_mock_journal_required("acquire original Host")
  let backing = host
    .borrow_backing()
    .native_mock_journal_required("borrow original backing")
  host
  .enter_backing_borrow_scope(backing)
  .native_mock_journal_required("enter backing borrow")
  let read_domain = match
    host
    .prepare_domain_in_process(
      backing,
      profile.read_domain_bytes,
      profile.read_domain_limits,
    )
    .native_mock_journal_required("prepare original Read domain") {
    @initial_arena.PreparedDomain(value) => value
    @initial_arena.PendingDomain(_, _) =>
      fail("original Journal Read domain pending")
  }
  host
  .transfer_domain(read_domain)
  .native_mock_journal_required("transfer Read domain")
  let sql_domain = match
    host
    .prepare_domain_in_process(
      backing,
      profile.sqlite_domain_bytes,
      profile.sqlite_domain_limits,
    )
    .native_mock_journal_required("prepare original SQLite domain") {
    @initial_arena.PreparedDomain(value) => value
    @initial_arena.PendingDomain(_, _) =>
      fail("original Journal SQLite domain pending")
  }
  host
  .transfer_domain(sql_domain)
  .native_mock_journal_required("transfer SQLite domain")
  host
  .leave_backing_borrow_scope(backing)
  .native_mock_journal_required("leave backing borrow")
  host
  .return_backing_borrow(backing)
  .native_mock_journal_required("return backing borrow")
  let budget = local_command_initial_read_budget(profile)
  host
  .prepare_domain_read(
    read_domain,
    execution_ceiling=match profile.native_storage.read_selection {
      CommandReadFiniteFacility(value) => value
    },
  )
  .native_mock_journal_required("select original Read ceiling")
  host
  .prepare_domain_read(
    sql_domain,
    execution_ceiling=match profile.native_storage.sqlite_domain_selection {
      CommandSqliteDomainFiniteFacility(value) => value
    },
  )
  .native_mock_journal_required("select original SQLite ceiling")
  let read = match
    host
    .prepare_domain_original_read(read_domain, budget)
    .native_mock_journal_required("prepare original consuming Read") {
    @initial_arena.ReadyOriginalRead(value) => value
    @initial_arena.PendingOriginalRead(_, _) =>
      fail("original consuming Read pending")
  }
  let sqlite = match
    host
    .prepare_sqlite_library(
      sql_domain,
      @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").native_mock_journal_required(
        "select SQLite component",
      ),
      profile.sqlite_heap_bytes,
      profile.diagnostic_ceiling,
    )
    .native_mock_journal_required("prepare SQLite Library") {
    @initial_arena.ReadySqlite(value) => value
    @initial_arena.PendingSqlite(_, issue) =>
      fail(
        "original SQLite component pending: " +
        command_preparation_cleanup_cause(CommandSqlite(issue)),
      )
  }
  let pair = host
    .bind_local_host_resources(read, sqlite)
    .native_mock_journal_required("bind original Read/SQLite pair")
  let consumer = host
    .prepare_local_host_read_consumer(
      pair,
      profile.consumer_retained_bytes,
      Int64::min(profile.consumer_execution_bytes, budget.read_execution),
    )
    .native_mock_journal_required("prepare original consumer")
  let control = host
    .prepare_local_host_read_crypto_control(pair, read)
    .native_mock_journal_required("retain original Crypto control")
  native_mock_original_journal_body(host, pair, read, control, profile)
  // All caller aliases from the body retire before its original pair. The
  // existing owners, not process exit or our booleans, supply these ACKs.
  host
  .close_local_host_resources(pair)
  .native_mock_journal_required("close original Read/SQLite pair")
  host
  .close_domain_after_owner_ack(read_domain)
  .native_mock_journal_required("close Read domain after ACK")
  host
  .close_domain_after_owner_ack(sql_domain)
  .native_mock_journal_required("close SQLite domain after ACK")
  host.try_close().native_mock_journal_required("close original Host")
  ignore(consumer)
}

///|
fn native_mock_original_journal_body(
  arena : @initial_arena.InstalledArenaHost,
  pair : @initial_arena.InstalledArenaLocalHostResources,
  read : @initial_arena.InstalledArenaOriginalRead,
  control : @initial_arena.InstalledArenaCryptoComponent,
  profile : LocalCommandPreparationProfile,
) -> Unit raise {
  arena
  .enter_local_host_phase(pair, @initial_arena.HostRead)
  .native_mock_journal_required("enter original Read")
  let component = match
    arena
    .prepare_local_host_read_crypto(
      pair,
      read,
      @env.get_env_var("ACTQL_TEST_CRYPTO_COMPONENT").native_mock_journal_required(
        "select Crypto component",
      ),
      profile.crypto_heap_bytes,
      profile.diagnostic_ceiling,
    )
    .native_mock_journal_required("prepare original Crypto component") {
    @initial_arena.ReadyCrypto(value) => value
    @initial_arena.PendingCrypto(_, _) =>
      fail("original Crypto component pending")
  }
  assert_true(physical_equal(component, control))
  let original_crypto = arena
    .current_crypto_component(component)
    .native_mock_journal_required("borrow original Crypto component")
  let crypto = match
    original_crypto
    .new_library()
    .native_mock_journal_required("prepare original Crypto Library") {
    @local_crypto.ReadyCryptoLibrary(value) => value
    @local_crypto.PendingCryptoLibrary(_, _) =>
      fail("original Crypto Library pending")
  }
  let original = native_project_mock_model_fixture("deal-review")
  original
  .prepare_source_declarations()
  .native_mock_journal_required("prepare original Source declarations")
  original
  .prepare_models(
    local_project_mock_task_limits(),
    local_project_mock_answer_limits(),
    local_utc_now,
  )
  .native_mock_journal_required("prepare original Model metadata")
  let subjects = original
    .account_subjects()
    .native_mock_journal_required("retain original Account subjects")
  let path = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").native_mock_journal_required(
    "select fresh process root",
  )
  let originals = @run_host.client_local_product_finite_originals(
    path + "/product",
    @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").native_mock_journal_required(
      "select original SQLite path",
    ),
    @env.get_env_var("ACTQL_TEST_CRYPTO_COMPONENT").native_mock_journal_required(
      "select original Crypto path",
    ),
    "2026-10-12T00:00:00.000Z",
    @run_host.client_local_product_assets(),
    mock=Some(subjects),
  ).native_mock_journal_required("prepare original Product files")
  let product = @local_host.prepare_native_local_product_configuration_capture_in_current_read_context(
    path,
    "product",
    crypto,
    profile.diagnostic_ceiling,
    originals=Some(originals),
  ).native_mock_journal_required("retain original Product capture")
  product.open().native_mock_journal_required("open original Product") |> ignore
  product
  .stage_configuration()
  .native_mock_journal_required("stage original Product configuration")
  let adoption = @local_host.prepare_native_local_initial_adoption_capture_in_current_read_context(
    {
      parent_path: path + "/product",
      state_name: "host",
      source_path: path + "/product",
      source_name: "account.json",
      account_id: "local-cli",
      configuration_files: [],
      managed_root_path: None,
    },
    crypto,
    profile.diagnostic_ceiling,
  ).native_mock_journal_required("retain original first adoption")
  assert_true(adoption.open(product=Some(product)).issue() is None)
  // Match the real first-use command. Only the original fresh Session may
  // consume its initializer; an existing-only Journal cannot stand in for it.
  let material = adoption
    .original_session()
    .native_mock_journal_required("retain original adoption Session")
    .create_initial_signing_material(crypto)
    .native_mock_journal_required("create original first signing material")
  let capture = adoption
    .capture_initial_command_journal_with_original_resources(
      arena,
      pair,
      read,
      material,
      @run_host.client_local_default_signing_bootstrap_policy(),
      100.0,
      profile.native_storage.max_records,
      profile.native_storage.max_snapshot_bytes,
    )
    .native_mock_journal_required("retain original initial Journal capture")
  arena
  .leave_local_host_phase(pair)
  .native_mock_journal_required("leave initial Read")
  let observed = native_mock_journal_adoption_result(
    capture.with_original_read(_ => {
      let account = match capture.configuration_in_original_read() {
        Ok(value) => value
        Err(_) => return None
      }
      let allow = @authorization.evaluate_account(account, {
          principal: "local-cli",
          connection: "mock",
          resource: subjects.model_tasks[0],
          operation: "infer",
        })
        is @authorization.Allow(_)
      let delegated = @authorization.evaluate_account(account, {
          principal: "local-cli",
          connection: "salesforce",
          resource: "Opportunity",
          operation: "effect",
        })
        is @authorization.Delegate(_)
      Some((account.configuration_cid(), allow, delegated))
    }),
    "actual original captured Journal Read",
  )
  guard observed is Some((configuration, allow, delegated)) else {
    fail("same adopted Account unavailable inside captured Read")
  }
  assert_true(allow && delegated)
  assert_true(configuration.has_prefix("sha256:"))
  assert_true(capture.close().issue() is None)
  // Journal close selects cleanup-only custody. Match the ordinary caller:
  // retire the remaining Read aliases in that SAME cleanup frame.
  arena
  .enter_local_host_cleanup(pair, @initial_arena.HostRead)
  .native_mock_journal_required("enter original cleanup Read")
  original.retire()
  assert_true(adoption.close().issue() is None)
  product.close().native_mock_journal_required("close original Product")
  crypto
  .close_checked()
  .native_mock_journal_required("close original Crypto Library")
  arena
  .close_local_host_read_crypto_component(pair, read, component)
  .native_mock_journal_required("close same-frame original Crypto component")
  original_crypto
  .close_checked()
  .native_mock_journal_required("observe original component close")
  arena
  .leave_local_host_phase(pair)
  .native_mock_journal_required("leave original cleanup Read")
}

///|
fn[T] native_mock_journal_adoption_result(
  value : Result[T, @local_host.NativeLocalAdoptionIssue],
  stage : String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(issue) =>
      fail(
        stage + ": " + command_preparation_cleanup_cause(CommandAdoption(issue)),
      )
  }
}

///|
fn[T, E] Result::native_mock_journal_required(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn[T] Option::native_mock_journal_required(
  self : T?,
  stage : String,
) -> T raise {
  match self {
    Some(value) => value
    None => fail(stage)
  }
}
