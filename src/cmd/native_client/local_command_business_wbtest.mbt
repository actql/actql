///|
// A checked demand below the supported facility can select a smaller actual
// acquisition. A conservative upper bound above it does not invalidate the
// existing finite facility or promise that every input will fit it.
fn local_command_selected_business_limits(
  maximum : @initial_resources.LedgerLimits,
  required : @initial_resources.LedgerLimits?,
) -> @initial_resources.LedgerLimits {
  match required {
    Some(value) if value.retained_bytes > 0L &&
      value.execution_bytes > 0L &&
      value.planning_work <= maximum.planning_work &&
      value.attempts <= maximum.attempts &&
      value.holdings <= maximum.holdings &&
      value.transfer_bytes <= maximum.transfer_bytes &&
      value.retained_bytes <= maximum.retained_bytes &&
      value.execution_bytes <= maximum.execution_bytes => value
    _ => maximum
  }
}

///|
test "Business candidate rejects parent control overlap and simultaneous allowance overflow before physical acquisition" {
  // Declaration validation only, not an adopted operational profile. These
  // cases cannot create a Host/domain or issue a business Ledger from DATA.
  let profile = native_storage_finite_arithmetic_profile()
  let logical : @initial_resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 64L,
    execution_bytes: 64L,
  }
  let overlapping : LocalCommandBusinessProfile = {
    kind: SourceFreeCompute,
    domain_bytes: profile.arena_bytes -
    profile.read_domain_bytes -
    profile.sqlite_domain_bytes,
    payload_facility_bytes: 128L,
    limits: logical,
  }
  assert_true(
    prepare_local_command_preparation_original(
      profile,
      business=Some(overlapping),
    )
    is Err(CommandInvalidProfile),
  )
  let exceeds_payload : LocalCommandBusinessProfile = {
    kind: SourceFreeCompute,
    domain_bytes: 1048576L,
    payload_facility_bytes: 127L,
    limits: logical,
  }
  assert_true(
    prepare_local_command_preparation_original(
      profile,
      business=Some(exceeds_payload),
    )
    is Err(CommandInvalidProfile),
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "checked business limits stay independent of the compiled acquisition layout" {
  let maximum : @initial_resources.LedgerLimits = {
    planning_work: 100000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 32000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }
  let required = {
    ..maximum,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 1000000L,
    retained_bytes: 1048577L,
    execution_bytes: 2097152L,
  }
  assert_eq(
    local_command_selected_business_limits(maximum, Some(required)),
    required,
  )
  assert_eq(
    local_command_selected_business_limits(
      maximum,
      Some({ ..required, execution_bytes: 536870913L, }),
    ),
    maximum,
  )
  assert_eq(local_command_selected_business_limits(maximum, None), maximum)
  assert_true(
    (required.retained_bytes + required.execution_bytes) %
    native_storage_page_bytes() !=
    0L,
  )
  if local_command_test_selected_layout() {
    // Positive geometry requires the actual linked provider. This branch
    // supplies no replacement layout to the ordinary unselected Core binary.
    let small = local_command_domain_bytes(
      required.retained_bytes + required.execution_bytes,
    ).unwrap()
    let large = local_command_domain_bytes(
      maximum.retained_bytes + maximum.execution_bytes,
    ).unwrap()
    assert_true(small > required.retained_bytes + required.execution_bytes)
    assert_eq(small % native_storage_page_bytes(), 0L)
    assert_true(small < large)
  } else {
    assert_eq(
      local_command_domain_bytes(
        required.retained_bytes + required.execution_bytes,
      ),
      None,
    )
    assert_eq(
      local_command_domain_bytes(
        maximum.retained_bytes + maximum.execution_bytes,
      ),
      None,
    )
  }
  assert_eq(local_command_domain_bytes(9223372036854775807L), None)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}

///|
test "saved Result selection preserves Read facilities without a Compute acquisition candidate" {
  let static_profile = native_storage_finite_arithmetic_profile()
  let parsed = command().parse(
    argv=["--mode", "local", "result", "original-run", "--result", "answer"],
    env=Map([]),
  )
  let (selected, retained) = local_command_profile_selection(
    static_profile, parsed,
  )
  assert_eq(selected.arena_bytes, static_profile.arena_bytes)
  assert_eq(selected.control_bytes, static_profile.control_bytes)
  assert_eq(selected.read_domain_bytes, static_profile.read_domain_bytes)
  assert_eq(selected.sqlite_domain_bytes, static_profile.sqlite_domain_bytes)
  assert_eq(
    selected.consumer_execution_bytes,
    static_profile.consumer_execution_bytes,
  )
  assert_eq(selected.host_limits, static_profile.host_limits)
  let read = retained.unwrap()
  assert_true(read.kind == SavedResultRead)
  assert_eq(read.domain_bytes, 0L)
  assert_eq(read.payload_facility_bytes, 0L)
  // The tag selects routing, never a zero-byte physical Compute issuer.
  assert_true(
    prepare_local_command_preparation_original(
      static_profile,
      business=Some({ ..read, limits: { ..read.limits, execution_bytes: 1L, }, }),
    )
    is Err(CommandInvalidProfile),
  )
  assert_true(
    prepare_local_command_preparation_original(
      static_profile,
      business=Some({ ..read, kind: SourceFreeCompute, }),
    )
    is Err(CommandInvalidProfile),
  )
  assert_true(command_preparation_invocation.val is None)
}

///|
test "fresh Run selection requires its compiled layout before Compute acquisition" {
  let static_profile = native_storage_finite_arithmetic_profile()
  let parsed = command().parse(
    argv=["--mode", "local", "run", "query.aql"],
    env=Map([]),
  )
  if local_command_test_selected_layout() {
    let (selected, retained) = local_command_profile_selection(
      static_profile, parsed,
    )
    let compute = retained.unwrap()
    assert_true(compute.kind == SourceFreeCompute)
    assert_eq(compute.limits.retained_bytes, 536870912L)
    assert_eq(compute.limits.execution_bytes, 536870912L)
    assert_true(selected.arena_bytes > static_profile.arena_bytes)
    assert_true(compute.domain_bytes > compute.payload_facility_bytes)
  } else {
    let failure = try {
      ignore(local_command_profile_selection(static_profile, parsed))
      "unexpected Compute profile"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(failure, "LocalBusinessLayoutUnavailable")
  }
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}
