///|
/// The original Native Ledger/receipt decoders and saved-response custody
/// bounds. These are immutable codec DATA, not capacity, current authority or
/// permission to interpret a missing response as a successful operation.
pub(all) struct NativeClientEffectStorageLimits {
  ledger : @checkpoint.WireLimits
  receipt : @checkpoint.WireLimits
  response_bytes : Int
}

///|
let native_client_effect_storage_profile : NativeClientEffectStorageLimits = {
  ledger: { max_wire_bytes: 65536, max_nodes: 128, max_depth: 16, },
  receipt: { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
  response_bytes: 1048576,
}

///|
/// Read the SAME Native codec selection before constructing an implementation
/// recipe. Neither this getter nor its bounds reserve another Run or backing.
pub fn native_client_effect_storage_limits() -> NativeClientEffectStorageLimits {
  native_client_effect_storage_profile
}
