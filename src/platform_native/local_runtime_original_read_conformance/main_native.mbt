///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, phase : String) -> Unit {
  if !condition {
    abort("runtime original-read conformance failed: " + phase)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + phase)
}

///|
// The outer cells are created outside the read scope. The Runtime and its
// returned assets must retain their real original context until the last alias
// retires. This helper boundary prevents a temporary receiver from surviving
// into the outer final-ACK assertions.
fn capture_and_close_roots(
  host : @control.InstalledArenaHost,
  original : @control.InstalledArenaOriginalRead,
  runtime_slot : Ref[@local.NativeLocalPackagedRuntime?],
  assets_slot : Ref[@host.ClientLocalProductAssets?],
  path : String,
  manifest_hash : String,
  count : Ref[Int],
) -> Unit {
  let runtime = @local.open_native_local_packaged_runtime_in_original_read(
    Some((host, original)),
    path,
    "a".repeat(40),
    "darwin-arm64",
    manifest_hash,
    128,
  ).unwrap()
  require(
    count,
    runtime.check_current() is Ok(_),
    "same carrier captures original files",
  )
  require(
    count,
    runtime.manifest() is Ok(_),
    "original manifest remains current",
  )
  require(
    count,
    runtime.library_paths().unwrap() ==
    (path + "/lib/sqlite.bin", path + "/lib/crypto.bin"),
    "exact original library paths without library load",
  )
  assets_slot.val = Some(runtime.assets().unwrap())
  runtime.close().unwrap()
  runtime.close().unwrap()
  require(
    count,
    runtime.check_current() is Err(_),
    "Root ACK retires runtime reads",
  )
  runtime_slot.val = Some(runtime)
}

///|
fn assets_unchanged(slot : Ref[@host.ClientLocalProductAssets?]) -> Bool {
  match slot.val {
    Some(assets) =>
      assets.environment == "abc" &&
      assets.registry == "abc" &&
      assets.values == "abc" &&
      assets.fragment == "abc" &&
      assets.result_policy == "abc" &&
      assets.ordered is None
    None => false
  }
}

///|
/// Fresh disposable FD and synthetic package only. These explicit finite
/// diagnostic declarations neither derive nor install a numerical profile.
/// The outer bootstrap/control allocation is not claimed as funded here.
fn main {
  let count = Ref(0)
  let path = @env.get_env_var("ACTQL_D_ORIGINAL_READ_PACKAGE").unwrap()
  let manifest_hash = @env.get_env_var("ACTQL_D_ORIGINAL_READ_MANIFEST").unwrap()
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
  let assets_slot : Ref[@host.ClientLocalProductAssets?] = Ref(None)
  capture_and_close_roots(
    host, original, runtime_slot, assets_slot, path, manifest_hash, count,
  )
  require(
    count,
    assets_unchanged(assets_slot),
    "escaped original assets survive Root ACK",
  )
  require(
    count,
    host.close_domain_original_read(original)
    is Err(Domain(@bootstrap.Bootstrap(Physical(_)))),
    "runtime and asset aliases keep same carrier pending",
  )
  runtime_slot.val = None
  require(
    count,
    host.close_domain_original_read(original)
    is Err(Domain(@bootstrap.Bootstrap(Physical(_)))),
    "asset alias alone prevents final ACK",
  )
  assets_slot.val = None
  host.close_domain_original_read(original).unwrap()
  host.close_domain_original_read(original).unwrap()
  require(
    count,
    host.borrow_domain_original_read(original) is Err(_),
    "last original alias retires without replacement or reissuance",
  )
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  println(
    "{\"success\":true,\"discovered\":8,\"executed\":8,\"passed\":8,\"failed\":0,\"all_originals_closed\":true,\"normal_profile\":null,\"public_e2e\":0}",
  )
}
