///|
#external
priv type PublicationTestLoader

///|
#module("node:module")
extern "js" fn publication_test_loader(url : String) -> PublicationTestLoader = "createRequire"

///|
extern "js" fn publication_test_url() -> String =
  #|() => import.meta.url

///|
// Preserve the original Array FFI/input boundary under this declaration only.
#warnings("-deprecated")
extern "js" fn publication_test_original(
  loader : PublicationTestLoader,
  input : () -> Array[Int],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input(),{planningWork:0,attempts:0,holdings:0,transferBytes:0n,retainedBytes:536870912n,executionBytes:536870912n},current,()=>false,'local-preparation')

///|
fn publication_custody_fixture_originals(
  current : () -> Unit,
) -> (
  ClientProgramPublication,
  @resources.Ledger,
  @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ],
  @resources.NodePreparationAdmission[Array[Int]],
) {
  let input = [1]
  let original = publication_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    current,
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let prepared = result_envelope_fixture()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    1000000L,
    1000000L,
    max_borrowers=6,
  ).unwrap()
  @resources.complete_preparation_capacity(
    capacity, input, prepared, 1000000L, 0L,
  ).unwrap()
  @resources.transfer_preparation_capacity_to_run(
    capacity, input, prepared, ledger,
  ).unwrap()
  let holder = @resources.borrow_preparation_body(capacity).unwrap()
  @resources.reserve_preparation_publication_phase(
    holder, prepared, 1000000L, publication_projection_execution,
  ).unwrap()
  let value : ClientProgramPublication = {
    original: None,
    retiring: false,
    publication_definition: None,
    publication_invocation: None,
    row_bound: None,
    retained_quote: 1000000L,
    execution_quote: publication_projection_execution,
    holder,
    capture_started: false,
    capture: None,
    run: None,
    snapshot: None,
    snapshot_starting: false,
    next_snapshot_index: 0,
    completed_snapshots: [],
  }
  value.original = Some(value)
  (value, ledger, capacity, initial)
}

///|
test "publication handle rejects manager returned by currentness while sibling still borrows" {
  let armed = Ref(false)
  let selected : Ref[
    @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram]?,
  ] = Ref(None)
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      if armed.val {
        armed.val = false
        if selected.val is Some(holder) {
          ignore(@resources.return_preparation_body_borrow(holder))
        }
      }
    },
  )
  selected.val = Some(value.holder)
  let sibling = @resources.borrow_preparation_body(capacity).unwrap()
  armed.val = true
  assert_true(refresh_publication_original(value) is Err(ForeignOriginal))
  assert_true(@resources.preparation_body_borrow_value(sibling) is Some(_))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 1000000L)
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  assert_true(@resources.return_preparation_body_borrow(sibling).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(publication_original_body(value) is None)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication escaped handle and one-shot continuation reject retired owner" {
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let prepared = publication_original_body(value).unwrap()
  let used = managed_publication_duplicate_fixture(prepared)
  assert_true(reserve_program_publication(used, prepared) is Err(WrongPhase))
  retire_installed_managed_run(used).unwrap()
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_true(refresh_publication_original(value) is Err(ForeignOriginal))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
fn publication_custody_contract() -> @publication.PublicationContract {
  @publication.result_definition_contract(
    @publication.prepare_result_definition("sha256:" + "8".repeat(64), "answer").unwrap(),
  )
}

///|
/// Deliberately unadvanced semantic issuer: this fixture tests cancellation of
/// private constructor ownership, not validity of an assembled publication.
fn publication_custody_issuer(
  contract : @publication.PublicationContract,
) -> @publication.CapturedRunIssuancePreparation {
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"annotations\":[]}",
    10000,
    1000,
    32,
  ).unwrap()
  @publication.start_effect_free_captured_run(
    contract,
    contract,
    [],
    [],
    contract,
    contract,
    [],
    [],
    authoring,
    [],
    10000,
    1000,
    32,
    10000,
  )
}

///|
test "publication capture handle retirement cancels private issuer before zero" {
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let issuer = publication_custody_issuer(publication_custody_contract())
  let capture : ClientProgramCapture = {
    publication: value,
    plan: None,
    issuer: Some(issuer),
    validation: None,
    validation_retained: 0L,
  }
  value.capture_started = true
  value.capture = Some(capture)
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(capture.issuer is None)
  assert_eq(
    @publication.captured_run_preparation_fixture_phase(issuer),
    "closed",
  )
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_true(advance_program_capture(capture, 1) is Err(ForeignOriginal))
  assert_true(start_program_capture(capture) is Err(ForeignOriginal))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication capture handle callback cancellation cannot resume escaped issuer" {
  let armed = Ref(false)
  let selected : Ref[ClientProgramCapture?] = Ref(None)
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      if armed.val {
        armed.val = false
        if selected.val is Some(capture) {
          cancel_program_capture(capture)
        }
      }
    },
  )
  let issuer = publication_custody_issuer(publication_custody_contract())
  let capture : ClientProgramCapture = {
    publication: value,
    plan: None,
    issuer: Some(issuer),
    validation: None,
    validation_retained: 0L,
  }
  value.capture_started = true
  value.capture = Some(capture)
  selected.val = Some(capture)
  armed.val = true
  assert_true(advance_program_capture(capture, 1) is Err(ForeignOriginal))
  assert_eq(
    @publication.captured_run_preparation_fixture_phase(issuer),
    "closed",
  )
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication two original handles refuse same CID foreign invocation before capture" {
  let (first, first_ledger, first_capacity, first_initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let (second, second_ledger, second_capacity, second_initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let original = publication_custody_contract()
  let foreign = @publication.admit_publication_contract(
    "result_definition",
    @publication.publication_contract_json(original),
    10000,
    1000,
    32,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(original),
    @publication.publication_contract_identity(foreign),
  )
  assert_false(physical_equal(original, foreign))
  first.publication_definition = Some(original)
  first.publication_invocation = Some(original)
  second.publication_definition = Some(original)
  second.publication_invocation = Some(foreign)
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"annotations\":[]}",
    10000,
    1000,
    32,
  ).unwrap()
  assert_true(
    prepare_program_capture(
      first,
      original,
      foreign,
      [],
      [],
      original,
      original,
      [],
      authoring,
      [],
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_program_capture(
      second,
      original,
      original,
      [],
      [],
      original,
      original,
      [],
      authoring,
      [],
    )
    is Err(ForeignOriginal),
  )
  for
    (value, capacity, initial) in [
      (first, first_capacity, first_initial),
      (second, second_capacity, second_initial),
    ] {
    assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
    clear_program_publication(value)
    assert_true(@resources.preparation_body_retirement_started(value.holder))
    assert_true(
      @resources.return_preparation_body_borrow(value.holder).unwrap(),
    )
    @resources.cleanup_node_preparation_admission(initial).unwrap()
  }
  assert_eq(@resources.ledger_usage(first_ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(second_ledger).reserved_retention_bytes, 0L)
}

///|
test "publication capture handle failed payload growth retains owned plan until cleanup" {
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      ()
    },
  )
  let contract = publication_custody_contract()
  value.publication_definition = Some(contract)
  value.publication_invocation = Some(contract)
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"annotations\":[]}",
    10000,
    1000,
    32,
  ).unwrap()
  let other = @resources.reserve_capacity(
    ledger,
    536870912L - 1000000L - 600L,
    0L,
  ).unwrap()
  // Four empty copied inventories fit (480); the later capture payload does
  // not. Semantic issuance never starts on this deliberately unassembled bag.
  reserve_publication_constructor(value, 480L, 0L).unwrap()
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
  let capture : ClientProgramCapture = {
    publication: value,
    plan: Some(plan),
    issuer: None,
    validation: None,
    validation_retained: 0L,
  }
  value.capture = Some(capture)
  let facts = @publication.capture_construction_layout_facts(plan).unwrap()
  let layout = publication_capture_constructor_layout(
    facts.0,
    facts.3,
    facts.2,
    facts.4,
    facts.5,
    facts.6,
    facts.7,
  ).unwrap()
  assert_true(
    reserve_publication_constructor(
      value,
      @execution.preparation_representation_cost(layout.retained).unwrap(),
      @execution.preparation_representation_cost(layout.temporary).unwrap(),
    )
    is Err(
      Capacity(
        @resources.PreparationCapacityIssue::Resource(
          @resources.LedgerIssue::RetentionLimit
        )
      )
    ),
  )
  assert_true(capture.plan is Some(_))
  assert_true(capture.issuer is None)
  assert_eq(value.retained_quote, 1000480L)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    publication_projection_execution,
  )
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(capture.plan is None)
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  @resources.settle_capacity(ledger, other).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication continues on the transferred body without a bootstrap preparation owner" {
  let calls = Ref(0)
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      calls.val += 1
    },
  )
  let original = capacity
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  assert_true(refresh_publication_original(value) is Ok(_))
  assert_eq(calls.val - current, 1)
  assert_true(physical_equal(capacity, original))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(@resources.retire_preparation_capacity(original).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_true(publication_original_body(value) is None)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication controller copy cannot replace its original before current" {
  let calls = Ref(0)
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      calls.val += 1
    },
  )
  let copied = { ..value, }
  let before = calls.val
  assert_true(refresh_publication_original(copied) is Err(ForeignOriginal))
  assert_eq(calls.val, before)
  assert_true(publication_original_body(value) is Some(_))
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  clear_program_publication(value)
  assert_true(@resources.preparation_body_retirement_started(value.holder))
  assert_true(@resources.return_preparation_body_borrow(value.holder).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "publication controller retirement during current retains its borrow until actual return" {
  let selected : Ref[ClientProgramPublication?] = Ref(None)
  let armed = Ref(false)
  let calls = Ref(0)
  let (value, ledger, capacity, initial) = publication_custody_fixture_originals(() => {
      calls.val += 1
      if armed.val {
        armed.val = false
        clear_program_publication(selected.val.unwrap())
      }
    },
  )
  selected.val = Some(value)
  let holder = value.holder
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  armed.val = true
  assert_true(refresh_publication_original(value) is Err(ForeignOriginal))
  assert_eq(calls.val - current, 1)
  assert_true(value.retiring && value.original is None)
  assert_true(
    value.publication_definition is None && value.publication_invocation is None,
  )
  assert_true(@resources.preparation_body_borrow_value(holder) is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  assert_true(@resources.preparation_body_retirement_started(holder))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}
