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
  native_project_mock_model_in_original_read(partial, environment)
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
