///|
test "Business candidate rejects parent control overlap and simultaneous allowance overflow before physical acquisition" {
  // Declaration validation only, not an adopted operational profile. These
  // cases cannot create a Host/domain or issue a business Ledger from DATA.
  let profile = native_storage_arithmetic_profile()
  let logical : @initial_resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 64L,
    execution_bytes: 64L,
  }
  let overlapping : LocalCommandBusinessProfile = {
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
