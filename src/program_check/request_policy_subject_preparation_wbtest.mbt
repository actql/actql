///|
fn prepare_request_policy_subjects(
  original : CheckedProgram,
  limits : CompileLimits,
) -> RequestPolicySubjectPreparation raise UnitBuildFailure {
  let prepared = begin_request_policy_subjects(original, limits)
  measure_request_policy_subjects(prepared)
  prepared
}

///|
test "measured request policy subjects keep exact wire and original binding facts" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
    request_parameter=true,
  )
  let prepared = prepare_request_policy_subjects(
    original,
    policy_continuation_limits(),
  )
  assert_true(prepared.phase == Measured)
  assert_eq(prepared.subjects.length(), 1)
  let subject = prepared.subjects[0]
  assert_eq(
    subject.request_cid,
    "sha256:7df0345ab601b8de75cad0bc51a7c1eac7aebc9641c54ce11e4b965b5adb221e",
  )
  let geometry = request_policy_subject_output_extent(prepared)
  assert_eq(
    geometry,
    (subject.bytes.to_int64(), subject.nodes.to_int64(), subject.depth),
  )
  let measured_work = prepared.initial_work - prepared.budget.work
  assert_true(measured_work > 0)
  construct_request_policy_subjects(prepared)
  let wire = request_policy_subject_wire(prepared, 0)
  // Compatibility of the one shared descriptor emitter, not an independently
  // regenerated semantic oracle or physical/ordinary Host qualification.
  assert_eq(
    wire,
    request_value_policy_subject_wire(
      original.units[0].source_execution[0],
      1000000,
      1000000,
      100000,
      100,
    ),
  )
  assert_true(wire.contains("\"origin\":\"default\",\"parameter\":\"key\""))
  assert_eq(request_policy_subject_output_extent(prepared), geometry)
  let before_bind = request_policy_subjects_spent_work(prepared)
  let proof = bind_prepared_request_policy_subject(
    prepared,
    0,
    Some(
      "sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808",
    ),
  ).unwrap()
  assert_true(request_policy_subjects_spent_work(prepared) > before_bind)
  assert_true(physical_equal(proof.origins, subject.origins))
  assert_true(physical_equal(prepared.original.unwrap(), original))
  let selected = observe_supplement_checked_request_value_policies_owned(
    original,
    [proof],
    policy_continuation_limits(),
  ).0.unwrap()
  assert_true(physical_equal(selected.identity, original.identity))
  assert_eq(
    publication_policy_classification(
      selected.units[0].publications[0].source_policy.unwrap(),
    ),
    Internal,
  )
  let work = request_policy_subjects_spent_work(prepared)
  try bind_prepared_request_policy_subject(prepared, 0, None) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("same descriptor bound twice")
  }
  assert_eq(request_policy_subjects_spent_work(prepared), work)
  retire_request_policy_subjects(prepared)
  assert_true(prepared.original is None && prepared.subjects.is_empty())
}

///|
test "request policy subjects preserve decline and poison a selected foreign policy" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let prepared = prepare_request_policy_subjects(
    original,
    policy_continuation_limits(),
  )
  construct_request_policy_subjects(prepared)
  assert_true(bind_prepared_request_policy_subject(prepared, 0, None) is None)
  assert_eq(prepared.next, 1)
  assert_true(
    original.units[0].source_execution[0].subject.request_value_policy is None,
  )
  retire_request_policy_subjects(prepared)
  let foreign = prepare_request_policy_subjects(
    original,
    policy_continuation_limits(),
  )
  construct_request_policy_subjects(foreign)
  try
    bind_prepared_request_policy_subject(
      foreign,
      0,
      Some("sha256:" + "0".repeat(64)),
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("unadmitted CID supplied policy evidence")
  }
  assert_true(foreign.phase == Failed && foreign.next == 1)
  try request_policy_subject_wire(foreign, 0) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("failed policy packet remained usable")
  }
  retire_request_policy_subjects(foreign)
}

///|
test "request policy subject emission failure cannot expose or retry partial construction" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let prepared = prepare_request_policy_subjects(
    original,
    policy_continuation_limits(),
  )
  prepared.construction_work = Some(0)
  try construct_request_policy_subjects(prepared) catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("exhausted work constructed descriptor text")
  }
  assert_true(prepared.phase == Constructing)
  try request_policy_subject_wire(prepared, 0) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("partial descriptor was returned")
  }
  try construct_request_policy_subjects(prepared) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("failed constructor retried")
  }
  retire_request_policy_subjects(prepared)
  assert_true(prepared.original is None && prepared.phase == Retired)
}

///|
test "request policy subjects preserve the exact legacy logical bound while charging added rendering" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
    request_parameter=true,
  )
  let broad = prepare_request_policy_subjects(
    original,
    policy_continuation_limits(),
  )
  let exact = broad.initial_work - broad.budget.work
  let limits = { ..policy_continuation_limits(), work: exact, }
  let prepared = prepare_request_policy_subjects(original, limits)
  assert_eq(prepared.budget.work, 0)
  construct_request_policy_subjects(prepared)
  assert_true(request_policy_subjects_spent_work(prepared) > exact.to_int64())
  assert_eq(prepared.budget.work, 0)
  assert_eq(
    request_policy_subject_wire(prepared, 0),
    request_value_policy_subject_wire(
      original.units[0].source_execution[0],
      exact,
      limits.artifacts.bytes,
      limits.artifacts.nodes,
      limits.artifacts.depth,
    ),
  )
  retire_request_policy_subjects(prepared)
  retire_request_policy_subjects(broad)
}

///|
test "restored request policy subjects share one cumulative work bound through binding" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
    append="right",
  )
  let limits = policy_continuation_limits()
  let policy = "sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808"
  let broad = begin_request_policy_subjects(original, limits)
  measure_request_policy_subjects(broad)
  construct_request_policy_subjects(broad)
  let count = request_policy_subject_count(broad)
  assert_eq(count, 3)
  for index in 0..<count {
    assert_true(
      bind_prepared_request_policy_subject(broad, index, Some(policy))
      is Some(_),
    )
  }
  let total = request_policy_subjects_spent_work(broad)
  retire_request_policy_subjects(broad)
  let exact = begin_request_policy_subjects(
    original,
    limits,
    cumulative_work=Some(total),
  )
  measure_request_policy_subjects(exact)
  construct_request_policy_subjects(exact)
  for index in 0..<count {
    assert_true(
      bind_prepared_request_policy_subject(exact, index, Some(policy))
      is Some(_),
    )
  }
  assert_true(request_policy_subject_bindings_complete(exact))
  assert_eq(request_policy_subjects_spent_work(exact), total)
  retire_request_policy_subjects(exact)
  let short = begin_request_policy_subjects(
    original,
    limits,
    cumulative_work=Some(total - 1L),
  )
  measure_request_policy_subjects(short)
  construct_request_policy_subjects(short)
  for index in 0..<(count - 1) {
    assert_true(
      bind_prepared_request_policy_subject(short, index, Some(policy))
      is Some(_),
    )
  }
  try
    bind_prepared_request_policy_subject(short, count - 1, Some(policy))
  catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("last binding refilled the original cumulative work allowance")
  }
  assert_true(short.phase == Failed)
  assert_true(request_policy_subjects_spent_work(short) <= total - 1L)
  try
    bind_prepared_request_policy_subject(short, count - 1, Some(policy))
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("failed original binding was retried")
  }
  retire_request_policy_subjects(short)
}

///|
test "restored request policy measurement refuses an exhausted cumulative prefix without retry" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let limits = policy_continuation_limits()
  try
    begin_request_policy_subjects(original, limits, cumulative_work=Some(-1L))
  catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("negative original work allowance was admitted")
  }
  let prepared = begin_request_policy_subjects(
    original,
    limits,
    cumulative_work=Some(1L),
  )
  try measure_request_policy_subjects(prepared) catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("measurement exceeded the original cumulative prefix")
  }
  assert_true(prepared.phase == Failed)
  assert_true(request_policy_subjects_spent_work(prepared) <= 1L)
  try measure_request_policy_subjects(prepared) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("partial original measurement was retried")
  }
  try construct_request_policy_subjects(prepared) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("failed measurement exposed descriptor construction")
  }
  retire_request_policy_subjects(prepared)
  assert_true(prepared.original is None && prepared.subjects.is_empty())
}
