///|
// Select an existing physical constructor, never a capacity/permission fact.
// Only the scoped entry below selects CurrentOriginalReadRoots; the same
// acquired Root and its children retain the actual entered context themselves.
priv enum NativeLocalAdoptionRootOpening {
  LegacyPrivateRoots
  CurrentOriginalReadRoots(Int)
}

///|
/// Inspect an existing original through the unchanged legacy Root constructors.
/// Missing Host proof cannot initialize a replacement Host or signing material.
pub fn begin_existing_native_local_host_adoption_with_custody(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure] {
  begin_native_local_host_adoption_with_original_root_custody(
    parent_path,
    state_name,
    source_path,
    source_name,
    account_id,
    crypto,
    LegacyPrivateRoots,
    configuration_files~,
    managed_root_path~,
  )
}

///|
/// Consume the caller's already entered original read context for every source,
/// parent and optional managed Root. No legacy open substitutes a missing scope.
/// The caller retains the same Host/Domain/read/workspace and escaped aliases
/// through their actual cleanup acknowledgements. A diagnostic bound supplies
/// no allocation, permission, Host binding or normal installation profile.
///
/// The original Adoption constructor owns selection, locks, custody checks and
/// partial-acquisition cleanup. This entry cannot initialize a missing Host or
/// combine the separate filesystem and SQLite operation contexts.
pub fn begin_existing_native_local_host_adoption_in_current_read_context_with_custody(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  diagnostic_ceiling : Int,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure] {
  begin_native_local_host_adoption_with_original_root_custody(
    parent_path,
    state_name,
    source_path,
    source_name,
    account_id,
    crypto,
    CurrentOriginalReadRoots(diagnostic_ceiling),
    configuration_files~,
    managed_root_path~,
  )
}

///|
/// The existing explicit installer may initialize through its actual entered
/// Read as well as reopen retained originals. The original Account, selection,
/// marker and exclusive Session determine eligibility; a scope is not a claim.
/// Every partial Root/Reader/lock remains in the same returned failure carrier.
pub fn begin_native_local_host_adoption_in_current_read_context_with_custody(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  diagnostic_ceiling : Int,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
  existing_only? : Bool = false,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure] {
  begin_native_local_host_adoption_with_original_root_custody(
    parent_path,
    state_name,
    source_path,
    source_name,
    account_id,
    crypto,
    CurrentOriginalReadRoots(diagnostic_ceiling),
    existing_only~,
    configuration_files~,
    managed_root_path~,
  )
}
