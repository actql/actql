///|
type NativeRuntimeBundleStore

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
#warnings("-unused_value")
fn retain_native_store_imports() -> Unit {
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
