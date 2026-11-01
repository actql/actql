///|
/// Real nominal but deliberately unadvanced issuer: lifecycle-only fixture,
/// never evidence that the publication contract chain is semantically valid.
fn validation_custody_capture(
  value : ClientProgramPublication,
) -> ClientProgramCapture {
  let capture : ClientProgramCapture = {
    publication: value,
    plan: None,
    issuer: Some(publication_custody_issuer(publication_custody_contract())),
    validation: None,
    validation_retained: 0L,
  }
  value.capture_started = true
  value.capture = Some(capture)
  capture
}

///|
fn validation_custody_retire(
  value : ClientProgramPublication,
  ledger : @resources.Ledger,
  capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ],
  initial : @resources.NodePreparationAdmission[Array[Int]],
) -> Unit raise {
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "retained validation one active slot and serial reuse share same reservation" {
  let (publication, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let capture = validation_custody_capture(publication)
  let first = new_program_validation(capture, false).unwrap()
  assert_true(new_program_validation(capture, true) is Err(Owner(WrongPhase)))
  fund_validation_inventory(first, 6L, 6).unwrap()
  let peak = @resources.ledger_usage(ledger).reserved_retention_bytes
  let component = capture.validation_retained
  assert_true(component > 0L)
  cancel_program_validation(first)
  assert_true(capture.validation is None)
  assert_true(first.plan is None && first.chain is None && first.commit is None)
  assert_true(start_program_validation(first) is Err(Owner(ForeignOriginal)))
  let next = new_program_validation(capture, true).unwrap()
  fund_validation_inventory(next, 6L, 6).unwrap()
  assert_eq(capture.validation_retained, component)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  cancel_program_validation(first)
  assert_true(
    capture.validation is Some(current) && physical_equal(current, next),
  )
  fund_validation_inventory(next, 60L, 6).unwrap()
  assert_true(capture.validation_retained > component)
  cancel_program_validation(next)
  validation_custody_retire(publication, ledger, capacity, initial)
}

///|
test "retained validation callback cancellation cannot authorize constructor" {
  let armed = Ref(false)
  let selected : Ref[ClientProgramValidation?] = Ref(None)
  let (publication, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      if armed.val {
        armed.val = false
        if selected.val is Some(value) {
          cancel_program_validation(value)
        }
      }
    },
  )
  let capture = validation_custody_capture(publication)
  let value = new_program_validation(capture, false).unwrap()
  selected.val = Some(value)
  armed.val = true
  assert_true(
    fund_validation_inventory(value, 6L, 6) is Err(Owner(ForeignOriginal)),
  )
  assert_true(value.closed && capture.validation is None)
  assert_true(capture.issuer is Some(_))
  let peak = @resources.ledger_usage(ledger).reserved_retention_bytes
  let retry = new_program_validation(capture, false).unwrap()
  fund_validation_inventory(retry, 6L, 6).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  cancel_program_validation(retry)
  validation_custody_retire(publication, ledger, capacity, initial)
}

///|
test "retained validation cancellation clears owned pending Plan before retirement" {
  let (publication, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let capture = validation_custody_capture(publication)
  let value = new_program_validation(capture, false).unwrap()
  fund_validation_inventory(value, 2L, 2).unwrap()
  let contract = publication_custody_contract()
  // A plan descriptor does not claim semantic chain validity. This exercises
  // its actual copied inventory custody, never starts the full checker.
  let plan = @publication.prepare_original_effect_free_chain_validation(
    contract,
    contract,
    [contract],
    [contract],
    contract,
    contract,
    contract,
  ).unwrap()
  value.plan = Some(plan)
  assert_true(
    @publication.publication_validation_plan_inventory(plan) is Some(_),
  )
  validation_custody_retire(publication, ledger, capacity, initial)
  assert_true(value.closed && value.plan is None && capture.validation is None)
  assert_true(@publication.publication_validation_plan_inventory(plan) is None)
  assert_true(
    advance_program_validation(value, 1) is Err(Owner(ForeignOriginal)),
  )
}

///|
test "retained validation failed growth can clear slot without releasing sibling grant" {
  let (publication, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let capture = validation_custody_capture(publication)
  let value = new_program_validation(capture, false).unwrap()
  let other = @resources.reserve_capacity(ledger, 536870912L - 1000000L, 0L).unwrap()
  let issue = match fund_validation_inventory(value, 6L, 6) {
    Err(issue) => issue
    Ok(_) => abort("Expected full original retention budget to refuse growth")
  }
  let failed : Result[Unit, ClientProgramValidationIssue] = validation_failure(
    value, issue,
  )
  assert_true(failed is Err(Owner(Capacity(_))))
  assert_true(value.closed && capture.validation is None)
  assert_eq(capture.validation_retained, 0L)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    536870912L,
  )
  @resources.settle_capacity(ledger, other).unwrap()
  validation_custody_retire(publication, ledger, capacity, initial)
}
