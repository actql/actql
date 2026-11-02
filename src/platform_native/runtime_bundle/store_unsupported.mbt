///|
type NativeRuntimeBundleStore

///|
pub fn NativeRuntimeBundleStore::current_sqlite_component_matches_heap(
  _self : NativeRuntimeBundleStore,
  _expected_heap_bytes : Int64,
) -> Bool {
  false
}

///|
pub fn NativeRuntimeBundleStore::diagnostics_bounded_by(
  _self : NativeRuntimeBundleStore,
  _ceiling : Int,
) -> Bool {
  false
}

///|
type NativeRuntimeBundleStoreOpenFailure

///|
pub fn NativeRuntimeBundleStoreOpenFailure::issue(
  _self : NativeRuntimeBundleStoreOpenFailure,
) -> NativeRuntimeBundleStoreIssue {
  UnsupportedTarget
}

///|
pub fn NativeRuntimeBundleStoreOpenFailure::retry_cleanup(
  _self : NativeRuntimeBundleStoreOpenFailure,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn open_runtime_bundle_store_with_custody(
  _sqlite_library : @sqlite.Library,
  _signature_library : @signature.Library,
  _root_path : String,
  _authorities : Array[NativeRuntimeBundleAuthority],
  _target_triple : String,
  _capacity_bytes : Int64,
  _max_bundles : Int,
  _max_owners : Int,
  _max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreOpenError] {
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
type NativeRuntimeBundleInstaller

///|
pub fn open_runtime_bundle_store(
  _sqlite_library : @sqlite.Library,
  _signature_library : @signature.Library,
  _root_path : String,
  _authorities : Array[NativeRuntimeBundleAuthority],
  _target_triple : String,
  _capacity_bytes : Int64,
  _max_bundles : Int,
  _max_owners : Int,
  _max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn open_runtime_bundle_store_with_trust(
  _sqlite_library : @sqlite.Library,
  _signature_library : @signature.Library,
  _root_path : String,
  _trust : Array[NativeRuntimeBundleTrust],
  _target_triple : String,
  _capacity_bytes : Int64,
  _max_bundles : Int,
  _max_owners : Int,
  _max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn open_runtime_bundle_store_with_trust_and_custody(
  _sqlite_library : @sqlite.Library,
  _signature_library : @signature.Library,
  _root_path : String,
  _trust : Array[NativeRuntimeBundleTrust],
  _target_triple : String,
  _capacity_bytes : Int64,
  _max_bundles : Int,
  _max_owners : Int,
  _max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreOpenError] {
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn NativeRuntimeBundleStore::begin_install(
  _self : NativeRuntimeBundleStore,
  _install_id : String,
  _version : String,
  _key_id : String,
  _runtime_bundle_cid : String,
  _body : String,
  _signature : String,
) -> Result[NativeRuntimeBundleInstaller, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleInstaller::append(
  _self : NativeRuntimeBundleInstaller,
  _chunk : Bytes,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleInstaller::seal(
  _self : NativeRuntimeBundleInstaller,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleInstaller::cancel(
  _self : NativeRuntimeBundleInstaller,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::inspect_install(
  _self : NativeRuntimeBundleStore,
  _install_id : String,
) -> Result[NativeRuntimeBundleInstallSnapshot?, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::recover_install(
  _self : NativeRuntimeBundleStore,
  _install_id : String,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::adopt(
  _self : NativeRuntimeBundleStore,
  _version : String,
  _key_id : String,
  _runtime_bundle_cid : String,
  _body : String,
  _signature : String,
  _artifact_name : String,
  _generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::activate(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::rollback(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  self.activate(runtime_bundle_cid)
}

///|
pub fn NativeRuntimeBundleStore::drain(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::retain(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
  _hold_id : String,
  _kind : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::release(
  _self : NativeRuntimeBundleStore,
  _hold_id : String,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::reclaim(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::verify(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::inspect(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot?, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::active(
  _self : NativeRuntimeBundleStore,
) -> Result[NativeRuntimeBundleSnapshot?, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::acquire_active_component(
  _self : NativeRuntimeBundleStore,
  _observed_component_cid : String,
  _observed_target_triple : String,
  _process_hold_id : String,
) -> Result[NativeActiveRuntimeBinding, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::verify_active_component_binding(
  _self : NativeRuntimeBundleStore,
  _binding : NativeActiveRuntimeBinding,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::verify_active_component_binding_with_body_limit(
  _self : NativeRuntimeBundleStore,
  _binding : NativeActiveRuntimeBinding,
  _max_body_bytes : Int64,
  json_limits? : @decode.Limits? = None,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  ignore(json_limits)
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::active_component_source(
  _self : NativeRuntimeBundleStore,
  _binding : NativeActiveRuntimeBinding,
  _role : String,
) -> Result[NativeRuntimeBundleComponentSource, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::materialize_active_component(
  _self : NativeRuntimeBundleStore,
  _binding : NativeActiveRuntimeBinding,
  _role : String,
) -> Result[NativeRuntimeBundleComponentSource, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::list(
  _self : NativeRuntimeBundleStore,
) -> Result[Array[NativeRuntimeBundleSnapshot], NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::recover(
  _self : NativeRuntimeBundleStore,
) -> Result[Array[NativeRuntimeBundleSnapshot], NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::capacity_usage(
  _self : NativeRuntimeBundleStore,
) -> Result[@sqlite.NativeCapacityUsage, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::close(
  _self : NativeRuntimeBundleStore,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::close_checked(
  _self : NativeRuntimeBundleStore,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
#warnings("-unused_value")
fn retain_native_store_imports() -> Unit {
  ignore(runtime_bundle_trust_sets([]))
  ignore(@sha.hasher())
  ignore(@utf8.encode(""))
  let writer = @encode.writer(16, 16, 1) catch { _ => return }
  ignore(writer)
  match
    @source.parse_json_bytes(b"null", {
      max_input_bytes: 4,
      max_nodes: 1,
      max_depth: 1,
    }) {
    Ok(value) =>
      ignore(
        @decode.admit(value, {
          max_nodes: 1,
          max_depth: 1,
          max_string_bytes: 1,
          max_total_string_bytes: 1,
        }),
      )
    Err(_) => ()
  }
}

///|
pub fn NativeRuntimeBundleStore::initialize_retention(
  _self : NativeRuntimeBundleStore,
) -> Result[String, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::retention_context(
  _self : NativeRuntimeBundleStore,
  _runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleRetentionContext, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::retain_member(
  _self : NativeRuntimeBundleStore,
  _binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::inspect_member_hold(
  _self : NativeRuntimeBundleStore,
  _binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::release_member(
  _self : NativeRuntimeBundleStore,
  _binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeRuntimeBundleStore::acquire_active_component_with_custody(
  _self : NativeRuntimeBundleStore,
  _observed_component_cid : String,
  _observed_target_triple : String,
  _process_hold_id : String,
) -> Result[NativeActiveRuntimeBinding, NativeRuntimeBundleProcessAcquireError] {
  Err(RefusedBeforeHolding(UnsupportedTarget))
}
