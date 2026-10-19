///|
extern "C" fn execution_domain_minimum_ffi(
  domain_bytes : Int64,
  payload_bytes : Int64,
) -> Int64 = "actql_bootstrap_execution_domain_necessary_bytes"

///|
/// Necessary coexistence DATA from the selected provider's actual layout.
/// The payload remains the caller's complete live allocation allowance; this
/// adds its original control table and context without issuing an extent,
/// estimating spare capacity or proving all managed inputs fit the facility.
pub fn execution_domain_necessary_bytes(
  domain_bytes : Int64,
  payload_bytes : Int64,
) -> Int64 {
  execution_domain_minimum_ffi(domain_bytes, payload_bytes)
}
