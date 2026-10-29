///|
fn tail_work_fixture(
  later_refusal? : Bool = false,
) -> LocalEnvironmentPreparation raise {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage(
      "t",
      if later_refusal {
        "missing"
      } else {
        "b"
      },
      schema_fields(),
    ),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  for _ in 0..<4 {
    advance_local_environment_preparation(read) |> ignore
  }
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentDeclaration,
  )
  read
}

///|
test "original Local tail observations report each completed pass once and sum to original final Usage" {
  let read = tail_work_fixture()
  let bound = local_environment_tail_work_bound(read).unwrap()
  let prefix = caps().max_work - bound
  let mut spent = 0
  let expected_phases : Array[LocalEnvironmentPhase] = [
    LocalEnvironmentReconciliation,
    LocalEnvironmentDeclaration,
    LocalEnvironmentReconciliation,
    LocalEnvironmentAssembly,
    LocalEnvironmentComplete,
  ]
  for expected in expected_phases {
    let (phase, debit) = observe_advance_local_environment_tail(read)
    assert_eq(phase, expected)
    assert_true(debit is Some(amount) && amount >= 0)
    spent += debit.unwrap()
    assert_true(spent <= bound)
  }
  let result = take_local_environment_preparation_result(read).unwrap().unwrap()
  assert_eq(program_environment_usage(result).work, prefix + spent)
  assert_true(local_environment_tail_work_bound(read) is None)
  assert_eq(
    observe_advance_local_environment_tail(read),
    (LocalEnvironmentTransferred, None),
  )
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentTransferred,
  )
}

///|
test "original later Local reconciliation failure leaves nested Usage missing rather than reporting zero" {
  let read = tail_work_fixture(later_refusal=true)
  let mut known_prefix = 0
  for _ in 0..<3 {
    let (_, debit) = observe_advance_local_environment_tail(read)
    assert_true(debit is Some(amount) && amount >= 0)
    known_prefix += debit.unwrap()
  }
  let (phase, debit) = observe_advance_local_environment_tail(read)
  assert_eq(phase, LocalEnvironmentFailed)
  assert_true(debit is None)
  assert_true(known_prefix > 0)
  assert_true(local_environment_preparation_usage(read) is None)
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentReconciliation),
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Environment(1, _))),
  )
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentTransferred,
  )
}
