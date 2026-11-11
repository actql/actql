///|
fn[T, E] Result::business_window_value(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
// Only scalars leave the actual payload scope. In particular, the same
// Request/census controls were constructed outside this Read, as at entry.
fn business_window_payload(
  host : @initial_arena.InstalledArenaHost,
  domain : @initial_arena.InstalledArenaDomain,
  execution : @initial_arena.InstalledArenaRetainedExecution,
  parent : @local_values.ClientRequestPreparation[Ref[Int]],
  input : Ref[Int],
) -> Unit raise {
  host
  .enter_domain_retained_execution(execution)
  .business_window_value("business window: enter original execution")
  let before = host
    .observe_domain_inventory(domain)
    .business_window_value("business window: original inventory before").capacity_bytes
  @local_values.reserve_request_native_intake_wire(parent, input, 16384).business_window_value(
    "business window: canonical intake demand",
  )
  let after = host
    .observe_domain_inventory(domain)
    .business_window_value("business window: original inventory after").capacity_bytes
  assert_true(after > before)
  assert_true(after < 128L * 1048576L)
  let accounting = @local_values.request_preparation_accounting(parent)
  // Policy refusal must precede a new Native acquisition or reservation.
  assert_true(
    @local_values.reserve_request_native_intake_wire(parent, input, 2147483518)
    is Err(_),
  )
  assert_eq(@local_values.request_preparation_accounting(parent), accounting)
  assert_eq(
    host
    .observe_domain_inventory(domain)
    .business_window_value("business window: inventory after refusal").capacity_bytes,
    after,
  )
  let payload = Bytes::make(65536, 73)
  assert_eq(payload[65535], 73)
  host
  .leave_domain_retained_execution(execution)
  .business_window_value("business window: leave original execution")
}

///|
test "business Request grows the original Native window on canonical demand and retires" {
  let mib = 1048576L
  let host = @initial_arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    16L * mib,
    {
      planning_work: 64,
      attempts: 16,
      holdings: 16,
      transfer_bytes: mib,
      retained_bytes: 0L,
      execution_bytes: 256L * mib,
    },
    mib,
  ).business_window_value("business window: prepare Host")
  host.acquire().business_window_value("business window: acquire Host")
  let scope = host
    .borrow_backing()
    .business_window_value("business window: original Root borrow")
  host
  .enter_backing_borrow_scope(scope)
  .business_window_value("business window: enter Root borrow")
  let initial_window = 2L * mib
  let first_domain = local_command_domain_bytes(initial_window).unwrap()
  let maximum_domain = local_command_domain_bytes(128L * mib).unwrap()
  host
  .grow_backing_for_allocation(scope, first_domain)
  .business_window_value("business window: exact initial physical block")
  let domain = match
    host
    .prepare_domain_in_process(
      scope,
      first_domain,
      {
        planning_work: 32,
        attempts: 8,
        holdings: 8,
        transfer_bytes: mib,
        retained_bytes: 64L * mib,
        execution_bytes: 64L * mib,
      },
      initial_window=Some(initial_window),
    )
    .business_window_value("business window: initial domain") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("business window: pending initial domain")
  }
  host
  .transfer_domain(domain)
  .business_window_value("business window: transfer")
  host
  .leave_backing_borrow_scope(scope)
  .business_window_value("business window: leave Root borrow")
  host
  .return_backing_borrow(scope)
  .business_window_value("business window: return Root borrow")
  host
  .prepare_domain_read(domain, execution_ceiling=maximum_domain)
  .business_window_value("business window: original Read MAX")
  let input = Ref(17)
  let (execution, initial) = match
    host
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: mib,
      bootstrap_execution: mib,
    })
    .business_window_value("business window: original initialized execution") {
    ReadyRequestExecution(execution, initial) => (execution, initial)
    PendingRequestExecution(_, _) => fail("business window: pending execution")
  }
  let parent = @local_values.begin_backed_request_preparation(
    initial,
    input,
    @local_values.client_local_resource_policy(),
  ).business_window_value("business window: original fixed Request")
  business_window_payload(host, domain, execution, parent, input)
  // Logical abort is not the physical retirement acknowledgement. Preserve
  // the original parent until the actual retained-execution Owner closes.
  assert_true(
    @local_values.abort_request_preparation_after_cleanup(parent) is Err(_),
  )
  host
  .close_domain_retained_execution(execution)
  .business_window_value("business window: actual execution close")
  @local_values.abort_request_preparation_after_cleanup(parent).business_window_value(
    "business window: same parent retirement continuation",
  )
  host
  .close_domain_after_owner_ack(domain)
  .business_window_value("business window: actual domain close")
  host.try_close().business_window_value("business window: actual Root close")
}
