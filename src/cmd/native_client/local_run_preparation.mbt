///|
// The exact existing submitted-intent preparation, without Journal admission,
// physical start or a replacement intent. The trusted command may use it to
// declare its business candidate before the first covered acquisition.
fn local_prepare_submitted_run_program(
  intent : @run_host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> @local_host.NativeClientSubmittedPreparation raise ClientStop {
  let catalog = @checked.prepare_source_catalog(environment, {
    max_work: @run_host.client_standard_program_preparation_limits().checking.compilation.work,
    max_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap_or_else(() => stop("LocalSourceCatalogNotAdmitted"))
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    source_catalog=Some(@checked.source_catalog_contracts(catalog)),
    model_tasks=@checked.checking_environment_model_tasks(environment),
  ).unwrap_or_else(() => stop("InvalidLocalQueryContext"))
  @local_host.prepare_native_client_submitted_program(
    intent,
    environment,
    Some(context),
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap_or_else(() => stop("LocalPreparationNotReady"))
}
