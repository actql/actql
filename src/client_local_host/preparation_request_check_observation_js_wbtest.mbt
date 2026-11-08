///|
fn request_observation_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  ClientRequestTerminalIssue,
) raise {
  let program = @publication_host.client_standard_program_preparation_limits()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=request_check_wire.replace(old="\"take\":1", new="\"take\":-1"),
    computation_limits=Some(
      (program, @publication_host.client_standard_effect_computation_limits()),
    ),
  )
  let terminal = match finish_request_computation_check(parent, input) {
    Err(issue) => issue
    Ok(_) => fail("the original negative Take must reject")
  }
  (parent, child, input, terminal)
}

///|
fn request_observation_publication(
  child : ClientProgramCheckPreparation[Array[Int], Unit],
) -> String {
  "{\"environmentCid\":\"" +
  @checked.checking_environment_cid(child.arguments.unwrap().environment) +
  "\",\"aliases\":[]}"
}

///|
fn request_observation_project(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  terminal : ClientRequestTerminalIssue,
  publication : String,
) -> Result[String?, ClientRequestPreparationIssue] {
  project_request_check_outcome(
    parent,
    input,
    terminal,
    publication,
    "ctx:" + "a".repeat(64),
    "program",
    "rev:" + "b".repeat(64),
    request_check_wire.length(),
    None,
    0,
    None,
    0,
    "corr:" + "c".repeat(32),
    None,
  )
}

///|
test "live Request projection keeps the same refused checker and prevents reentrant prepare or retirement" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let calls = Ref(0)
  let (parent, child, input, terminal) = request_observation_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  let outcome = child.check_outcome.unwrap()
  let registry = child.check_registry.unwrap()
  let publication = request_observation_publication(child)
  let flags = Ref(0)
  action.val = Some(() => {
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      flags.val += 1
    }
    if finish_request_computation_check(parent, input)
      is Err(Preparation(WrongPhase)) {
      flags.val += 2
    }
    if request_observation_project(parent, input, terminal, publication)
      is Err(WrongPhase) {
      flags.val += 4
    }
    if clear_program_check_preparation(child) is Err(WrongPhase) {
      flags.val += 8
    }
  })
  let before = @resources.ledger_usage(parent.ledger)
  let previous_calls = calls.val
  let report = request_observation_project(parent, input, terminal, publication)
    .unwrap()
    .unwrap()
  action.val = None
  assert_eq(flags.val, 15)
  assert_eq(calls.val - previous_calls, 1)
  assert_true(report.contains("\"outcome\":\"completed\""))
  assert_true(report.contains("\"verdict\":\"invalid\""))
  assert_true(report.contains("\"context_ref\":\"ctx:" + "a".repeat(64)))
  assert_true(physical_equal(child.check_outcome.unwrap(), outcome))
  assert_true(
    parent.phase == ProgramCheck &&
    child.phase == SemanticCheckRejected &&
    !child.busy,
  )
  assert_true(
    @checked.parsed_check_registry_remaining_work(registry)
    is Err(AlreadyConsumed),
  )
  let after = @resources.ledger_usage(parent.ledger)
  assert_eq(after.planning_work, before.planning_work)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "live Request projection refuses foreign originals and never recreates a retired observation" {
  let (parent, child, input, terminal) = request_observation_fixture()
  let (other, _, foreign_input, foreign_terminal) = request_observation_fixture()
  let publication = request_observation_publication(child)
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    request_observation_project(parent, foreign_input, terminal, publication)
    is Err(ForeignOriginal),
  )
  assert_true(
    request_observation_project(parent, input, foreign_terminal, publication)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(other).unwrap()
  clear_program_check_preparation(child).unwrap()
  assert_true(
    request_observation_project(parent, input, terminal, publication)
    is Ok(None),
  )
  // Dropping this controller's DATA is not settlement of the original parent.
  assert_eq(
    @resources.ledger_usage(parent.ledger).live_reservations,
    before.live_reservations,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(child.check_outcome is None && child.arguments is None)
  assert_true(
    request_observation_project(parent, input, terminal, publication)
    is Ok(None),
  )
}

///|
test "live Request projection backs output before publication decoding and retains original refusal across declined admission" {
  let (parent, child, input, terminal) = request_observation_fixture()
  let arguments = child.arguments.unwrap()
  let source = arguments.source_preparation.unwrap()
  let outcome = child.check_outcome.unwrap()
  let publication = request_observation_publication(child)
  let bytes = request_check_observation_bytes(
    child,
    source,
    outcome,
    publication,
    0L,
    None,
  ).unwrap()
  let (retained, _) = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let limits = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - retained - bytes + 1L,
    0L,
  ).unwrap()
  // A same-length malformed publication would produce a context-failed report
  // if decoding ran first. Capacity refusal must precede that constructor.
  let malformed = "!".repeat(publication.length())
  assert_true(
    request_observation_project(parent, input, terminal, malformed)
    is Err(Capacity(_)),
  )
  assert_true(physical_equal(child.check_outcome.unwrap(), outcome))
  assert_true(parent.phase == ProgramCheck && !child.busy)
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  let report = request_observation_project(parent, input, terminal, publication)
    .unwrap()
    .unwrap()
  assert_true(report.contains("\"verdict\":\"invalid\""))
  assert_true(physical_equal(child.check_outcome.unwrap(), outcome))
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "completed Request check projects original success before compiler and keeps one current boundary" {
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let program = @publication_host.client_standard_program_preparation_limits()
  let (parent, child, _, input) = registration_parent_fixture(
    current=() => {
      calls.val += 1
      if action.val is Some(run) {
        run()
      }
      true
    },
    computation_limits=Some(
      (program, @publication_host.client_standard_effect_computation_limits()),
    ),
  )
  finish_request_computation_check(parent, input).unwrap()
  let original = child.check_outcome.unwrap()
  assert_true(original is @checked.Checked(_))
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  let publication = request_observation_publication(child)
  let blocked = Ref(0)
  action.val = Some(() => {
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      blocked.val += 1
    }
    if clear_program_check_preparation(child) is Err(WrongPhase) {
      blocked.val += 1
    }
  })
  let before = calls.val
  let report = project_request_completed_check_outcome(
      parent,
      input,
      publication,
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      request_check_wire.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    )
    .unwrap()
    .unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(blocked.val, 2)
  assert_true(report.contains("\"verdict\":\"verified\""))
  guard @json.parse(report) is Object(root) &&
    root.get("report") is Some(Object(facts)) &&
    facts.get("runnable") is Some(Object(runnable)) else {
    fail("Expected the original typed check report")
  }
  assert_true(runnable.get("verdict") is Some(String("yes")))
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  assert_true(physical_equal(child.check_outcome.unwrap(), original))
  assert_true(
    parent.phase == ProgramCheck && child.phase == SemanticCheckComplete,
  )
  let before_usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    project_request_completed_check_outcome(
      parent,
      [999],
      publication,
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      request_check_wire.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before_usage)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    project_request_completed_check_outcome(
      parent,
      input,
      publication,
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      request_check_wire.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    )
    is Ok(None),
  )
}
