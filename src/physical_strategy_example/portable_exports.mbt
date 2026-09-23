///|
/// Non-JavaScript targets expose the same MoonBit API surface without asking
/// the native or Wasm linker to create a JavaScript foreign-library ABI.
#cfg(not(target="js"))
pub fn application_compute_transfer_capacity(app : Application) -> Int64 {
  core_application_compute_transfer_capacity(app)
}

///|
#cfg(not(target="js"))
pub fn prepare_application(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  database_schema : String,
  table : String,
) -> Application raise {
  core_prepare_application(
    program_json, environment_json, environment_cid, parameter_json, registry_json,
    values_json, fragment_json, query_json, evidence_json, two_receipt_json, database_schema,
    table,
  )
}

///|
#cfg(not(target="js"))
pub fn prepare_application_with_data(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  database_schema : String,
  table : String,
  data : DataProfile,
) -> Application raise {
  core_prepare_application_with_data(
    program_json, environment_json, environment_cid, parameter_json, registry_json,
    values_json, fragment_json, query_json, evidence_json, two_receipt_json, database_schema,
    table, data,
  )
}

///|
#cfg(not(target="js"))
pub fn application_acquisition(
  app : Application,
) -> @acquisition_host.NativeHostConfiguration {
  core_application_acquisition(app)
}

///|
#cfg(not(target="js"))
pub fn application_graph(app : Application) -> @strategy.CheckedDAG {
  core_application_graph(app)
}

///|
#cfg(not(target="js"))
pub fn application_compute_count(app : Application) -> Int {
  core_application_compute_count(app)
}

///|
#cfg(not(target="js"))
pub fn application_task_reference(
  app : Application,
  task : Int,
) -> @strategy.CheckedTaskReference raise {
  core_application_task_reference(app, task)
}

///|
#cfg(not(target="js"))
pub fn application_task_identity(
  reference : @strategy.CheckedTaskReference,
) -> @strategy.CheckedTaskIdentity {
  core_application_task_identity(reference)
}

///|
#cfg(not(target="js"))
pub fn application_task_output_matches(
  reference : @strategy.CheckedTaskReference,
  output : @execution.CompletedOutput,
) -> Bool {
  core_application_task_output_matches(reference, output)
}

///|
#cfg(not(target="js"))
pub fn application_task_content_read(
  app : Application,
  task : Int,
  descriptor : @execution.RetainedCompletionDescriptor,
) -> @execution.RetainedContentRead raise {
  core_application_task_content_read(app, task, descriptor)
}

///|
#cfg(not(target="js"))
pub fn application_task_completion_preparation(
  app : Application,
  task : Int,
) -> @execution.CompletionPreparation raise {
  core_application_task_completion_preparation(app, task)
}

///|
#cfg(not(target="js"))
pub fn application_bind_readmitted_output(
  app : Application,
  producer : Int,
  consumer : Int,
  input : Int,
  output : @execution.CompletedOutput,
) -> @execution.ProducerRead raise {
  core_application_bind_readmitted_output(
    app, producer, consumer, input, output,
  )
}

///|
#cfg(not(target="js"))
pub fn application_output_cid(
  run : @strategy.CapturedDAG,
  task : Int,
) -> String? {
  core_application_output_cid(run, task)
}

///|
#cfg(not(target="js"))
pub fn application_profile_output_cid(
  app : Application,
  run : @strategy.CapturedDAG,
  task : Int,
) -> String? {
  core_application_profile_output_cid(app, run, task)
}

///|
#cfg(not(target="js"))
pub fn application_ledger() -> @resources.Ledger {
  core_application_ledger()
}

///|
#cfg(not(target="js"))
pub fn application_bounded_ledger(
  limits : @resources.LedgerLimits,
) -> @resources.Ledger raise {
  core_application_bounded_ledger(limits)
}

///|
#cfg(not(target="js"))
pub fn application_ledger_limits(
  ledger : @resources.Ledger,
) -> @resources.LedgerLimits {
  core_application_ledger_limits(ledger)
}

///|
#cfg(not(target="js"))
pub fn application_ledger_usage(
  ledger : @resources.Ledger,
) -> @resources.LedgerUsage {
  core_application_ledger_usage(ledger)
}

///|
#cfg(not(target="js"))
pub fn application_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_dispatch(app, run, native_fixed_ms, resident)
}

///|
#cfg(not(target="js"))
pub fn application_retained_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_retained_dispatch(
    app, run, native_fixed_ms, file_bytes, file_work_ms, resident,
  )
}

///|
#cfg(not(target="js"))
pub fn application_managed_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_managed_dispatch(
    app, run, native_fixed_ms, file_bytes, file_work_ms, resident,
  )
}

///|
#cfg(not(target="js"))
pub fn application_materializing_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_materializing_dispatch(
    app, run, native_fixed_ms, file_bytes, file_work_ms, local_import_ms, resident,
  )
}

///|
#cfg(not(target="js"))
pub fn application_retained_local_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  local_export_ms : Int64,
  native_task_ms : Array[Int64],
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_retained_local_dispatch(
    app, run, native_fixed_ms, file_bytes, file_work_ms, local_import_ms, local_export_ms,
    native_task_ms, resident,
  )
}

///|
#cfg(not(target="js"))
pub fn application_retained_task_estimate_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  local_export_ms : Int64,
  local_task_ms : Array[Int64],
  native_task_ms : Array[Int64],
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  core_application_retained_task_estimate_dispatch(
    app, run, native_fixed_ms, file_bytes, file_work_ms, local_import_ms, local_export_ms,
    local_task_ms, native_task_ms, resident,
  )
}
