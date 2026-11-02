///|
// Membership/currentness DATA from the SAME trusted Store/Instance/Memory.
// This is not an execution-child admit/limit/capacity or public packet field.
fn platform_vm_observation(nonce : Int64, ordinal : Int) -> Int64 = "actql_host" "platform_vm_observation"

///|
fn platform_vm_port() -> Result[(Int64, Int) -> Int64, ImportedChildLedgerIssue] {
  Ok(platform_vm_observation)
}
