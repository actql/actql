///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, phase : String) -> Unit {
  if !condition {
    abort("installed product observation conformance failed: " + phase)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + phase)
}

///|
fn expected_refusal(
  result : Result[Unit, @local.NativeLocalPackagedRuntimeIssue],
  expected : String,
) -> Bool {
  match expected {
    "namespace" => result is Err(Physical(@filesystem.GenerationMismatch))
    "changed" => result is Err(Changed)
    "metadata" => result is Err(InvalidManifest)
    _ => false
  }
}

///|
// The returned Runtime alias is held in an outer cell so that physical file
// cleanup cannot accidentally be treated as the receiver's final carrier ACK.
fn observe_and_close(
  host : @control.InstalledArenaHost,
  original : @control.InstalledArenaOriginalRead,
  slot : Ref[@local.NativeLocalPackagedRuntime?],
  identity_slot : Ref[@local.NativeLocalVerifiedProductIdentity?],
  count : Ref[Int],
) -> Unit {
  let runtime = @local.open_native_local_packaged_runtime_in_original_read(
    Some((host, original)),
    @env.get_env_var("ACTQL_D_PRODUCT_PLATFORM_ROOT").unwrap(),
    "a".repeat(40),
    "darwin-arm64",
    @env.get_env_var("ACTQL_D_PRODUCT_RUNTIME_HASH").unwrap(),
    128,
  ).unwrap()
  require(
    count,
    runtime.check_product_current() is Err(Changed),
    "runtime-only is not whole-product capture",
  )
  let result = runtime.observe_product_members(
    @env.get_env_var("ACTQL_D_PRODUCT_LAUNCHER_ROOT").unwrap(),
    @env.get_env_var("ACTQL_D_PRODUCT_LAUNCHER_HASH").unwrap(),
    @env.get_env_var("ACTQL_D_PRODUCT_PLATFORM_HASH").unwrap(),
    128,
  )
  let expected = @env.get_env_var("ACTQL_D_PRODUCT_EXPECTED").unwrap()
  if expected == "valid" || expected == "identity" {
    require(count, result is Ok(_), "closed two-package capture")
    require(
      count,
      runtime.check_product_current() is Ok(_),
      "same original census and members current",
    )
    if expected == "valid" {
      let assets = runtime.assets().unwrap()
      require(
        count,
        assets.environment == "abc" && assets.result_policy == "abc",
        "original runtime material remains unchanged",
      )
      let identity = runtime.verified_product_identity().unwrap()
      require(
        count,
        identity.wire().unwrap() ==
        @env.get_env_var("ACTQL_D_PRODUCT_IDENTITY_WIRE").unwrap(),
        "identity wire equals independent original file digests",
      )
      identity_slot.val = Some(identity)
    } else {
      require(
        count,
        runtime.verified_product_identity() is Err(InvalidManifest),
        "generic census without formal executable images issues no identity",
      )
    }
  } else {
    require(
      count,
      expected_refusal(result, expected),
      "typed physical or metadata refusal",
    )
    require(
      count,
      runtime.check_current() is Err(_),
      "partial capture cannot fall back to runtime-only",
    )
    require(
      count,
      runtime.verified_product_identity() is Err(_),
      "partial capture issues no verified identity",
    )
  }
  runtime.close().unwrap()
  runtime.close().unwrap()
  require(
    count,
    runtime.check_product_current() is Err(_),
    "inner close retires product current",
  )
  if identity_slot.val is Some(identity) {
    require(
      count,
      identity.wire() is Err(_),
      "retained identity metadata is not retired Runtime permission",
    )
  }
  slot.val = Some(runtime)
}

///|
/// Same-provider fresh finite diagnostic only, not a normal installed profile.
/// Synthetic files are never loaded, adopted or used to issue compatibility.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let bytes = 8192L * page
  let host_limits : @resources.LedgerLimits = {
    planning_work: 20,
    attempts: 8,
    holdings: 4,
    transfer_bytes: 30L,
    retained_bytes: 0L,
    execution_bytes: bytes,
  }
  let host = @control.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    host_limits,
    65536L,
  ).unwrap()
  host.acquire_fd(0).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let child_limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 32L * page,
    execution_bytes: 6144L * page,
  }
  let domain = match
    host.prepare_domain(scope, 0, 7168L * page, child_limits).unwrap() {
    PreparedDomain(domain) => domain
    _ => abort("original FD domain unavailable")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.prepare_domain_read(domain).unwrap()
  let budget : @control.InstalledArenaOriginalReadBudget = {
    bootstrap_retained: 16L * page,
    bootstrap_execution: 16L * page,
    workspace_execution: 4096L * page,
    read_retained: 16L * page,
    read_execution: 1024L * page,
  }
  let original = match
    host.prepare_domain_original_read(domain, budget).unwrap() {
    ReadyOriginalRead(original) => original
    _ => abort("original read preparation unavailable")
  }
  let runtime_slot : Ref[@local.NativeLocalPackagedRuntime?] = Ref(None)
  let identity_slot : Ref[@local.NativeLocalVerifiedProductIdentity?] = Ref(
    None,
  )
  observe_and_close(host, original, runtime_slot, identity_slot, count)
  require(
    count,
    host.close_domain_original_read(original)
    is Err(Domain(@bootstrap.Bootstrap(Physical(_)))),
    "original Runtime alias retains final cleanup",
  )
  runtime_slot.val = None
  if identity_slot.val is Some(_) {
    require(
      count,
      host.close_domain_original_read(original)
      is Err(Domain(@bootstrap.Bootstrap(Physical(_)))),
      "identity alias alone retains the original carrier",
    )
  }
  identity_slot.val = None
  host.close_domain_original_read(original).unwrap()
  host.close_domain_original_read(original).unwrap()
  require(
    count,
    host.borrow_domain_original_read(original) is Err(_),
    "outer installer ACK closes the same carrier",
  )
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  println("checks:" + count.val.to_string())
  println(
    "{\"success\":true,\"all_originals_closed\":true,\"normal_profile\":null,\"public_e2e\":0}",
  )
}
