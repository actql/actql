///|
test "publication capture start rechecks exact plan after callback cancellation" {
  let armed = Ref(false)
  let selected : Ref[ClientProgramCapture[Array[Int]]?] = Ref(None)
  let (value, ledger) = publication_custody_fixture(() => {
    if armed.val {
      armed.val = false
      if selected.val is Some(capture) {
        cancel_program_capture(capture)
      }
    }
  })
  let contract = publication_custody_contract()
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"annotations\":[]}",
    10000,
    1000,
    32,
  ).unwrap()
  let plan = @publication.prepare_original_effect_free_capture_plan(
    contract,
    contract,
    [],
    [],
    contract,
    contract,
    [],
    authoring,
    [],
  ).unwrap()
  let capture : ClientProgramCapture[Array[Int]] = {
    publication: value,
    plan: Some(plan),
    issuer: None,
    validation: None,
    validation_retained: 0L,
  }
  value.capture = Some(capture)
  selected.val = Some(capture)
  armed.val = true
  assert_true(start_program_capture(capture) is Err(ForeignOriginal))
  assert_true(capture.plan is None)
  assert_true(capture.issuer is None)
  assert_true(@publication.capture_construction_layout_facts(plan) is None)
  assert_false(
    @resources.retire_preparation_capacity(value.owner.capacity).unwrap(),
  )
  assert_true(sever_closed_values_body(value.owner, value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
