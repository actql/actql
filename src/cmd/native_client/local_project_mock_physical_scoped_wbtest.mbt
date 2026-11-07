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
) -> Unit raise {
  // Reuse the existing real Native facility entry, as in Request/Effect's
  // physical component. This supplies no Command platform/Journal/Account.
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
  if file_facts {
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
