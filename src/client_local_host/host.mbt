///|
fn reject_client_local_run(
  run : @strategy.CapturedDAG,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  None
}

///|
/// Assemble an installed Local realization from the checked task owners.
/// The two registry bodies are independently validated against the selected
/// engine pins; caller-provided names or CIDs cannot install an extension.
/// This opens only an in-memory task owner. Client request and Run admission
/// must finish before the Host invokes it or starts physical work.
pub fn open_source_free_local_host(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    None,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
  )
}

///|
/// The same installed compute Host can receive a verified physical capture.
/// The caller must retain the acquisition owner through the last consumer.
pub fn open_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    Some(source),
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
  )
}

///|
fn open_checked_local_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource?,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if registry_body.length() > 100000 ||
    values_body.length() > 100000 ||
    fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  let limits : @resources.LedgerLimits = {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }
  let opened = match source {
    None =>
      @publication_host.open_prepared_source_free_client_run(prepared, limits)
    Some(captured) =>
      @publication_host.open_prepared_captured_client_run(
        prepared, captured, limits,
      )
  }
  let run = match opened {
    Ok(value) => value
    Err(_) => return None
  }
  let generated = match
    prepare_client_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    ) {
    Some(value) => value
    None => return reject_client_local_run(run)
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let first_compute = @strategy.captured_compute_first_task(run)
  let compute_sequences : Array[@execution.GeneratedSequence] = []
  for task in first_compute..<generated.length() {
    compute_sequences.push(generated[task])
  }
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let local_configuration : @local_driver.LocalComputeConfiguration = {
    sequences: compute_sequences,
    managed_providers: [],
    managed_capacity: capacity,
    execution: {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: values,
        output_values: values,
      },
      max_work: 100000,
      max_frames: 100,
    },
    measurement: {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    },
    max_work: 100,
  }
  let bundle : @connector.CapabilityBundle[
    Unit,
    @local_driver.LocalComputeConfiguration,
    Unit,
  ] = {
    name: "local",
    acquisition: None,
    fixed_compute: Some((_, _) => local_configuration),
    effect: None,
  }
  let installed_bundles = match @connector.install_bundles([bundle], 1, 100) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  let registry = @connector.installed_bundle_registry(installed_bundles)
  guard @connector.capability_registration_at(registry, 0)
    is Some(local_registration) else {
    return reject_client_local_run(run)
  }
  guard @connector.capability_implementation(
      @connector.installed_compute_implementations(installed_bundles),
      local_registration,
    )
    is Some(local_configuration) else {
    return reject_client_local_run(run)
  }
  let modules = match
    @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          local_registration,
          local_configuration,
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  guard @builtin.configured_local_module(modules) is Some(installed) else {
    return reject_client_local_run(run)
  }
  match
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values,
        wire: {
          max_columns: 10,
          max_order_work: 100,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        row: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
        max_batch_bytes: 64,
      },
      Some(0L),
    ) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  let slots = @local_driver.local_dispatch_work_slots()
  let schedule = match
    @cost.prepare_rate_schedule(
      slots,
      [
        {
          work_slots: Array::makei(slots, index => index),
          fixed_ms: Some(fixed_ms),
          per_row_ms: Some(per_row_ms),
          per_wire_byte_ms: Some(per_wire_byte_ms),
          per_pair_ms: Some(per_pair_ms),
        },
      ],
      100,
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  let schedules = Array::make(
    @strategy.graph_task_count(graph) - first_compute,
    schedule,
  )
  let estimate = match
    @local_driver.prepare_local_estimate_module(installed, schedules, 1000) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  match @local_driver.install_local_dispatch_estimates(installed, estimate) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  match
    @builtin.open_configured_compute_host(
      modules, registry, capacity, 100, 10000, 1,
    ) {
    Ok(value) => {
      if source is Some(_) {
        let fractions = Array::make(
          @strategy.graph_task_count(graph) - 1,
          Some(1000),
        )
        match
          @host_driver.configure_compute_host_estimates(
            @builtin.configured_host_runtime(value),
            fractions,
            {
              max_offers: 100,
              max_strategies: 100,
              max_work: 10000,
              max_revisions: 10,
            },
            1000,
          ) {
          Ok(_) => ()
          Err(_) => return reject_client_local_run(run)
        }
      }
      Some(value)
    }
    Err(_) => reject_client_local_run(run)
  }
}
