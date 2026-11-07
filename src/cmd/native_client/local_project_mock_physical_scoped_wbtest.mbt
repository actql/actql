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
  if source_environment {
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
