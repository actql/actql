///|
/// Host-private finite native conversion plan. Its installed verifier attests
/// completion of the exact verified-file import in the private attempt session;
/// neither a path nor a matching physical digest can construct that evidence.
struct NativeFileInputPlan {
  run : ComputeNodeRun
  port : Int
  input : @execution.ProducerRead
  sql : (String, String)
  mut used : Bool
}

///|
#export_name("computeHostInputFilePlan")
pub fn compute_host_input_file_plan(
  run : ComputeNodeRun,
  port : Int,
  wire : @execution.RowWireLimits,
  max_row_bytes : Int,
  max_sql_bytes : Int,
) -> NativeFileInputPlan? raise NodeHostFailure {
  guard compute_host_input_file_sql(
      run, port, wire, max_row_bytes, max_sql_bytes,
    )
    is Some(sql) else {
    return None
  }
  Some({
    run,
    port,
    input: compute_host_input_read(run, port),
    sql,
    used: false,
  })
}

///|
#export_name("computeHostInputFilePlanSql")
pub fn compute_host_input_file_plan_sql(
  plan : NativeFileInputPlan,
) -> (String, String) {
  plan.sql
}

///|
/// Trusted installed Host wiring only. Call after final physical verification
/// and successful execution of this plan's import SQL. The private table must
/// remain unchanged through the typed scan. Value admission, consumer demand,
/// measurement and row-count checks still run; only repeated content encoding
/// and hashing may be replaced. Not a new-profile CID omission.
#export_name("computeHostInputFilePlanReuse")
pub fn compute_host_input_file_plan_reuse(
  plan : NativeFileInputPlan,
  run : ComputeNodeRun,
  port : Int,
  verified_copy : () -> Bool,
) -> Bool {
  if plan.used ||
    run.closed ||
    !physical_equal(plan.run, run) ||
    plan.port != port {
    return false
  }
  plan.used = true
  guard @execution.prepare_trusted_retained_scan_reuse(plan.input, plan, fn(
      plan,
      input,
    ) {
      !plan.run.closed &&
      physical_equal(plan.input, input) &&
      verified_copy() &&
      !plan.run.closed
    })
    is Some(evidence) else {
    return false
  }
  @duckdb_compute.reuse_duckdb_compute_input_identity(
    run.attempt,
    port,
    evidence,
  )
}
