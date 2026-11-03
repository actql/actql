///|
// Real original Node Resource admission and existing Core engine. These tests
// construct no Source, provider kernel, Host, permission or physical output.
extern "js" fn closed_module_test_original(
  loader : PublicationTestLoader,
  input : () -> Array[Int],
  limits : () -> Array[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,limits,current) => {
  #| const [p,a,h,t,r,e]=limits();
  #| return loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input(),{planningWork:Number(p),attempts:Number(a),holdings:Number(h),transferBytes:t,retainedBytes:r,executionBytes:e},current,()=>false,'local-preparation');
  #|}

///|
fn catalog_current_fixture(
  current : () -> Unit,
  entries : Array[@context.StageCapacityInput],
) -> (
  ClientProgramCheckPreparation[Array[Int], Array[Int]],
  @resources.PreparationCapacity[Array[Int], Array[Int]],
  Array[Int],
  @resources.NodePreparationAdmission[Array[Int]],
) {
  let input = [1]
  // Actual existing preparation-purpose Node original. Program and callback
  // backing are borrowed component inputs, not a physical prelude supplier.
  let original = closed_module_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    () => [7L, 2L, 0L, 0L, 10000000L, 10000000L],
    current,
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let capacity : @resources.PreparationCapacity[Array[Int], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_program_check_preparation(
    capacity,
    input,
    catalog_current_program(),
    catalog_domain_environment(),
    None,
    entries,
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  (owner, capacity, input, initial)
}

///|
test "actual original binder current boundaries reject synchronous controller reentry" {
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (owner, capacity, input, initial) = catalog_current_fixture(
    () => {
      calls.val += 1
      if action.val is Some(run) {
        run()
      }
    },
    [],
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if prepare_program_check_input(owner) is Err(WrongPhase) {
      flags.val += 1
    }
  })
  let before = calls.val
  prepare_program_check_input(owner).unwrap()
  // Observer backing then actual binder growth are distinct boundaries, with
  // no added check-current call inside either original allocation operation.
  assert_eq(calls.val - before, 2)
  assert_eq(flags.val, 4)
  let next = calls.val
  let prepared = take_program_check_input(owner).unwrap()
  assert_eq(calls.val - next, 1)
  assert_eq(flags.val, 6)
  assert_eq(prepared.program.id, "p")
  assert_true(take_program_check_input(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "actual original current callback cannot allocate changed evidence under the captured binder quote" {
  let sources = catalog_current_empty_sources()
  let entries : Array[@context.StageCapacityInput] = []
  let armed = Ref(false)
  let calls = Ref(0)
  let (owner, capacity, input, initial) = catalog_current_fixture(
    () => {
      if armed.val {
        calls.val += 1
        if calls.val == 2 {
          entries.push({ stage: "missing", sources, uses: [], })
        }
      }
    },
    entries,
  )
  armed.val = true
  assert_true(prepare_program_check_input(owner) is Err(ChangedInputs))
  assert_eq(calls.val, 2)
  assert_true(
    owner.phase == Failed && owner.check_input is None && owner.work is None,
  )
  // Recheck has consumed its original phase; the actual semantic binder has
  // not started and cannot be mislabeled as a successful prepared input.
  let unused = @resources.begin_preparation_phase_work64(
    capacity,
    input,
    @resources.CapacityInputBinding,
    1L,
  ).unwrap()
  assert_eq(@resources.finish_preparation_phase_work64(unused), Ok(0L))
  clear_program_check_preparation(owner).unwrap()
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
test "actual stopping original refuses before binder observation without replacing input or debit" {
  let calls = Ref(0)
  let stop = Ref(false)
  let (owner, capacity, input, _) = catalog_current_fixture(
    () => {
      calls.val += 1
      if stop.val {
        source_current_stop()
      }
    },
    [],
  )
  let arguments = owner.arguments.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let count = calls.val
  stop.val = true
  assert_true(
    prepare_program_check_input(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val - count, 1)
  assert_true(
    owner.binding_inventory is None &&
    owner.check_input is None &&
    owner.work is None,
  )
  assert_true(physical_equal(arguments, owner.arguments.unwrap()))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
  clear_program_check_preparation(owner).unwrap()
  // No callback reset, new original, parent retirement or physical cleanup ACK.
}
