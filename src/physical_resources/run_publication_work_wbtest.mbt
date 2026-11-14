///|
test "adopted PublicationProof spends one original wide receipt without dispatch work or repeated current" {
  let (_, _, admission, body, ledger, frame, _, _) = backed_prepared_operation_fixture()
  let control = reserve_prepared_run_operation_controls(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
  ).unwrap()
  let before = ledger_usage(ledger)
  let receipt = begin_prepared_run_publication_work(
    admission, body, ledger, 4100L,
  ).unwrap()
  return_preparation_phase_work_continuation64(receipt).unwrap()
  let original_current = frame.origin.current
  let calls = Ref(0)
  frame.origin.current = nonce => {
    calls.val += 1
    original_current(nonce)
  }
  let escaped : Ref[((Int) -> Result[Unit, LedgerIssue])?] = Ref(None)
  let answer : Result[Int, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_publication_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => true,
    receipt,
    spend => {
      resume_preparation_phase_work_continuation64(receipt).unwrap()
      defer return_preparation_phase_work_continuation64(receipt) |> ignore
      escaped.val = Some(spend)
      for _ in 0..<4097 {
        spend(1).unwrap()
      }
      Ok(4097)
    },
  )
  assert_true(answer is Ok(4097))
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(escaped.val.unwrap()(1), Err(ForeignOwner))
  assert_eq(calls.val, 1)
  resume_preparation_phase_work_continuation64(receipt).unwrap()
  assert_eq(
    spend_preparation_phase_work_continuation64(receipt, 4L),
    Err(WorkLimit),
  )
  spend_preparation_phase_work_continuation64(receipt, 3L).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(receipt), Ok(4100L))
  assert_true(
    begin_prepared_run_publication_work(admission, body, ledger, 4100L)
    is Err(Unavailable),
  )
  assert_eq(
    spend_preparation_phase_work_continuation64(receipt, 0L),
    Err(Closed),
  )
}

///|
test "adopted PublicationProof rejects foreign body ledger receipt and escaped stopped work" {
  let (_, _, admission, body, ledger, frame, _, _) = backed_prepared_operation_fixture()
  assert_true(
    begin_prepared_run_publication_work(admission, Ref(4), ledger, 10L)
    is Err(_),
  )
  let foreign_ledger = create_ledger(ledger_limits(ledger)).unwrap()
  assert_true(
    begin_prepared_run_publication_work(admission, body, foreign_ledger, 10L)
    is Err(_),
  )
  let receipt = begin_prepared_run_publication_work(
    admission, body, ledger, 10L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(receipt, 2L).unwrap()
  return_preparation_phase_work_continuation64(receipt).unwrap()
  frame.origin.stopping = true
  assert_eq(
    resume_preparation_phase_work_continuation64(receipt),
    Err(Stopping),
  )
  assert_eq(finish_preparation_phase_work_continuation64(receipt), Ok(2L))
}

///|
test "only exact Run PublicationProof can span numeric resize without revival or work refill" {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 10000L,
    retained_bytes: 10000L,
    execution_bytes: 10000L,
  }).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    100L,
    100L,
    max_borrowers=2,
  ).unwrap()
  assert_true(
    begin_run_publication_work_continuation64(owner, body, ledger, 100L)
    is Err(_),
  )
  complete_preparation_capacity(owner, input, body, 100L, 100L).unwrap()
  let holder = borrow_preparation_body(owner).unwrap()
  assert_true(
    begin_run_publication_work_continuation64(owner, body, ledger, 100L)
    is Err(WrongPhase),
  )
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let work = begin_run_publication_work_continuation64(
    owner, body, ledger, 100L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 40L).unwrap()
  assert_eq(
    reserve_preparation_publication_phase(holder, body, 110L, 110L),
    Err(WorkActive),
  )
  return_preparation_phase_work_continuation64(work).unwrap()
  reserve_preparation_publication_phase(holder, body, 110L, 110L).unwrap()
  assert_true(physical_equal(owner.body.unwrap(), body))
  assert_true(owner.phase == Run)
  assert_eq(resume_preparation_phase_work_continuation64(work), Ok(()))
  assert_eq(
    spend_preparation_phase_work_continuation64(work, 61L),
    Err(WorkLimit),
  )
  owner.phase = Ready
  assert_eq(
    spend_preparation_phase_work_continuation64(work, 1L),
    Err(WrongPhase),
  )
  assert_eq(return_preparation_phase_work_continuation64(work), Err(WrongPhase))
  assert_eq(finish_preparation_phase_work_continuation64(work), Err(WrongPhase))
  owner.phase = Run
  spend_preparation_phase_work_continuation64(work, 60L).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(100L))
  assert_true(
    begin_run_publication_work_continuation64(owner, body, ledger, 1L)
    is Err(AlreadyClaimed),
  )
}
