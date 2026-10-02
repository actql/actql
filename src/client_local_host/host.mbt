///|
/// Shared Local row transport bounds for Pure and Effect computation.
/// The checked Run still admits each exact input and charges its resources.
pub fn client_local_import_limits(
  capacity : @connector.FixedComputeCapacity,
  values : @execution.ValueLimits,
) -> @local.LocalImportLimits {
  {
    max_rows: capacity.max_rows,
    values,
    wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    },
    row: {
      max_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
      max_text_bytes: 65536,
    },
    max_batch_bytes: 65536,
  }
}

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
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
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
    provider_factory~,
  )
}

///|
/// Install retained Relation output on the same checked source-free Host.
/// This is trusted Compute configuration, not permission to start a Run.
pub fn open_source_free_local_retained_host(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
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
    provider_factory~,
    retained_output=true,
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
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
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
    provider_factory~,
  )
}

///|
/// Keep a verified acquisition bound to the checked retained Compute Host.
/// The acquisition owner must outlive every consumer of its captured source.
pub fn open_captured_local_retained_host(
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
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
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
    provider_factory~,
    retained_output=true,
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
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
  retained_output? : Bool = false,
  captured_sources? : Array[(Int, @query.CapturedInputSource)] = [],
  acquisition_ledger? : @resources.Ledger? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if registry_body.length() > 100000 ||
    values_body.length() > 100000 ||
    fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  // The checked graph admits at most 32 tasks. Reserve one physical attempt
  // and one retained output per task; a fixed ten-attempt cap would reject a
  // valid longer task graph before its final computation can start.
  let task_count = @strategy.graph_task_count(
    @publication_host.prepared_client_graph(prepared),
  )
  if task_count < 1 || task_count > 32 {
    return None
  }
  let generated = match
    prepare_client_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    ) {
    Some(value) => value
    None => return None
  }
  let first_compute = if !captured_sources.is_empty() {
    if source is Some(_) ||
      captured_sources.length() != 2 ||
      acquisition_ledger is None {
      return None
    }
    2
  } else if source is None {
    0
  } else {
    1
  }
  let compute_sequences : Array[@execution.GeneratedSequence] = []
  for task in first_compute..<generated.length() {
    compute_sequences.push(generated[task])
  }
  let (values, execution, measurement) = client_local_execution_limits()
  let mut retained_bytes = 0L
  let mut execution_bytes = 0L
  let mut total_retained_bytes = 0L
  for sequence in compute_sequences {
    guard @execution.generated_sequence_capacity(
        sequence, execution, measurement,
      )
      is Some(required) else {
      return None
    }
    let retained = @execution.execution_capacity_retained_bytes(required)
    let executing = @execution.execution_capacity_execution_bytes(required)
    if retained < 0L || retained > 536870912L - total_retained_bytes {
      return None
    }
    total_retained_bytes += retained
    if retained > retained_bytes {
      retained_bytes = retained
    }
    if executing > execution_bytes {
      execution_bytes = executing
    }
  }
  // Each attempt may import one input of at most the Local import wire below
  // (1 MB), so the transfer budget covers the checked task inventory.
  let limits : @resources.LedgerLimits = {
    planning_work: 100000,
    attempts: task_count,
    holdings: task_count,
    transfer_bytes: task_count.to_int64() * 1000000L,
    retained_bytes: if total_retained_bytes > 200000000L {
      total_retained_bytes
    } else {
      200000000L
    },
    // The admitted value and retained-output reservations can exceed
    // 256 MiB for a bounded multi-task Program. Keep the established value
    // envelope and cap concurrent execution reservations at 512 MiB.
    execution_bytes: 536870912L,
  }
  let opened = if captured_sources.length() == 2 {
    @strategy.open_multi_captured_dag(
      @publication_host.prepared_client_graph(prepared),
      captured_sources,
      acquisition_ledger.unwrap(),
    ).map_err(issue => @publication_host.ClientRunOpenIssue::Run(issue))
  } else {
    match source {
      None =>
        @publication_host.open_prepared_source_free_client_run(prepared, limits)
      Some(captured) =>
        @publication_host.open_prepared_captured_client_run(
          prepared, captured, limits,
        )
    }
  }
  let run = match opened {
    Ok(value) => value
    Err(_) => return None
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  let providers = match
    @execution.execution_capacity(retained_bytes, execution_bytes) {
    Some(base) => provider_factory(base)
    None => return reject_client_local_run(run)
  }
  let local_configuration : @local_driver.LocalComputeConfiguration = {
    sequences: compute_sequences,
    managed_providers: providers,
    managed_capacity: capacity,
    execution,
    measurement,
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
  // Local import limits follow the bounds around them: the checked
  // requirement's rows and value size (`capacity`), the Store's column,
  // depth and 64 KiB batch bounds, and a whole-input wire sized for what one
  // acquisition captures (500 KB of text, encoded). One row must fit one
  // batch, so a row is bounded by the batch size; a larger input is split
  // into batches. The worst-case retention these limits imply stays within
  // the Run's capacity.
  match
    @local_driver.configure_local_retained_inputs(
      installed,
      client_local_import_limits(capacity, values),
      Some(0L),
    ) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  let slots = @local_driver.local_dispatch_work_slots()
  if retained_output {
    match
      @local_driver.configure_local_retained_output(
        installed,
        {
          max_rows: capacity.max_rows,
          values,
          wire: {
            max_columns: 100,
            max_order_work: 1000000,
            max_bytes: 1000000,
            max_nodes: 100000,
            max_depth: 64,
          },
          max_batch_bytes: 65536,
        },
        Some(0L),
      ) {
      Ok(_) => ()
      Err(_) => return reject_client_local_run(run)
    }
  }
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
      if first_compute == 1 {
        let fractions = Array::make(
          @strategy.graph_task_count(graph) - first_compute,
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
      } else if retained_output || first_compute == 2 {
        // Source-free and bounded multiple-root Hosts use the existing
        // installed offers and common selection. Do not pretend that one
        // capture's statistics describe all independent input roots.
        let offers = []
        for task in first_compute..<task_count {
          let proposed = match
            @local_driver.estimate_local_installed_offers(installed, task, {
              rows: None,
              wire_bytes: None,
              pairs: None,
            }) {
            Ok(value) => value
            Err(_) => return reject_client_local_run(run)
          }
          guard !proposed.is_empty() else {
            return reject_client_local_run(run)
          }
          for offer in proposed {
            offers.push(offer)
          }
        }
        match
          @strategy.configure_strategy_search(run, {
            max_offers: 100,
            max_strategies: 100,
            max_work: 10000,
            max_revisions: 100,
          }) {
          Ok(_) => ()
          Err(_) => return reject_client_local_run(run)
        }
        let choices = match
          @strategy.prepare_strategy_choices(run, offers, registry, None) {
          Ok(value) => value
          Err(_) => return reject_client_local_run(run)
        }
        match @strategy.commit_strategy_choice(choices, None) {
          Ok(@strategy.Selected(_)) => ()
          _ => return reject_client_local_run(run)
        }
      }
      Some(value)
    }
    Err(_) => reject_client_local_run(run)
  }
}

///|
/// Two independent captures enter the same existing Local Compute owner.
/// Their exact NativePhysical holdings remain in the supplied Run ledger.
pub fn open_multi_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    None,
    registry_body,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    captured_sources=sources,
    acquisition_ledger=Some(ledger),
  )
}
