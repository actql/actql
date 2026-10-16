// Generated from the existing Client–Host Run wait correlation rule.
// Run: node scripts/generate-client-host-wire.mjs --write

///|
fn generated_run_wait_stable(status : String) -> Bool {
  status == "waiting_checkpoint" ||
  status == "needs_reconciliation" ||
  status == "succeeded" ||
  status == "failed" ||
  status == "cancelled"
}
