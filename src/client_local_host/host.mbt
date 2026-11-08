///|
/// Shared Local row transport bounds for Pure and Effect computation.
/// The checked Run still admits each exact input and charges its resources.
pub fn client_local_import_limits(
  capacity : @connector.FixedComputeCapacity,
  values : @execution.ValueLimits,
) -> @local.LocalImportLimits {
  client_local_import_limits_for_rows(capacity.max_rows, values)
}

///|
fn client_local_import_limits_for_rows(
  max_rows : Int,
  values : @execution.ValueLimits,
) -> @local.LocalImportLimits {
  {
    max_rows,
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
/// The same export envelope is used for pre-start Run capacity and dispatch.
fn client_local_export_limits(
  max_rows : Int,
  values : @execution.ValueLimits,
) -> @local.LocalExportLimits {
  {
    max_rows,
    values,
    wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
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
  installed_contracts : ClientInstalledSequenceContracts,
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
    installed_contracts,
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
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  requirements? : ClientLocalRequirements? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    None,
    installed_contracts,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    retained_output=true,
    requirements~,
  )
}

///|
/// The same installed compute Host can receive a verified physical capture.
/// The caller must retain the acquisition owner through the last consumer.
pub fn open_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
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
    installed_contracts,
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
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
  requirements? : ClientLocalRequirements? = None,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    Some(source),
    installed_contracts,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    retained_output=true,
    requirements~,
  )
}

///|
/// Keep single captured input and Compute on their original acquisition ledger.
pub fn open_captured_local_host_on_ledger(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    Some(source),
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    acquisition_ledger=Some(ledger),
  )
}

///|
/// Compose the single verified capture and retained Compute with the existing
/// Host root Ledger. This opens no replacement capture or resource Owner.
pub fn open_captured_local_retained_host_on_ledger(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  requirements? : ClientLocalRequirements? = None,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    Some(source),
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    retained_output=true,
    requirements~,
    acquisition_ledger=Some(ledger),
  )
}

///|
/// Keep source-free Compute and its retained outputs on the installed Host's
/// existing root Ledger, alongside Wasm and transfer reservations. Opening
/// this checked task owner does not admit a Run or authorize physical work.
pub fn open_source_free_local_retained_host_on_ledger(
  prepared : @publication_host.PreparedClientProgram,
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  requirements? : ClientLocalRequirements? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  open_checked_local_host(
    prepared,
    None,
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    retained_output=true,
    acquisition_ledger=Some(ledger),
    requirements~,
  )
}

///|
fn open_checked_local_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource?,
  installed_contracts : ClientInstalledSequenceContracts,
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
  opened_run? : @strategy.CapturedDAG? = None,
  requirements? : ClientLocalRequirements? = None,
  source_free_preparation? : ClientInstalledManagedSourceFreePreparation? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if installed_contracts.original.registry_body.length() > 100000 ||
    values_body.length() > 100000 ||
    fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  // The checked graph already consumed its finite preparation work. Reserve one physical attempt
  // and one retained output per task; a fixed ten-attempt cap would reject a
  // valid longer task graph before its final computation can start.
  let task_count = @strategy.graph_task_count(
    @publication_host.prepared_client_graph(prepared),
  )
  if task_count < 1 {
    return None
  }
  if opened_run is Some(run) &&
    (
      source is Some(_) ||
      !captured_sources.is_empty() ||
      acquisition_ledger is Some(_) ||
      !physical_equal(
        @strategy.captured_dag_graph(run),
        @publication_host.prepared_client_graph(prepared),
      )
    ) {
    return None
  }
  // Both closed callers retain their own checked preparation. An ambiguous
  // internal selection cannot replace either original or issue another quote.
  let generated = match (requirements, source_free_preparation) {
    (Some(original), None) => {
      if !original.matches(
          prepared, installed_contracts, values_body, fragment_body, ordered_body,
        ) ||
        (original.capacity_plan.graph_offset == 0 && source is Some(_)) ||
        (original.capacity_plan.graph_offset == 1 && source is None) ||
        !captured_sources.is_empty() ||
        opened_run is Some(_) ||
        !retained_output {
        return None
      }
      original.sequences
    }
    (None, Some(value)) => {
      if source is Some(_) ||
        !captured_sources.is_empty() ||
        opened_run is Some(_) ||
        !installed_source_free_preparation_matches(
          value,
          Pure(prepared),
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
        ) {
        return None
      }
      value.sequences
    }
    (None, None) =>
      match
        prepare_client_local_sequences(
          prepared, installed_contracts, values_body, fragment_body, ordered_body,
        ) {
        Some(value) => value
        None => return None
      }
    (Some(_), Some(_)) => return None
  }
  if generated.length() != task_count {
    return None
  }
  let first_compute = if opened_run is Some(run) {
    @strategy.graph_captured_prefix(@strategy.captured_dag_graph(run))
  } else if !captured_sources.is_empty() {
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
  let compute_sequences = match (requirements, source_free_preparation) {
    (Some(original), None) => original.capacity_plan.sequences
    (None, Some(original)) => original.capacity_plan.sequences
    (None, None) =>
      Array::makei(generated.length() - first_compute, index => {
        generated[index + first_compute]
      })
    _ => return None
  }
  let max_rows = @publication_host.prepared_client_values_max_rows(prepared)
  let graph = @publication_host.prepared_client_graph(prepared)
  let capacity_plan = match (requirements, source_free_preparation) {
    (Some(original), None) => original.capacity_plan
    (None, Some(original)) => original.capacity_plan
    (None, None) =>
      client_local_capacity_plan(
        compute_sequences,
        max_rows,
        graph=Some(graph),
        graph_offset=first_compute,
      )
    _ => return None
  }
  if !client_local_capacity_plan_matches(
      capacity_plan, compute_sequences, max_rows,
    ) {
    return None
  }
  if capacity_plan.graph is Some(original_graph) &&
    !physical_equal(original_graph, graph) {
    return None
  }
  let retained_inputs = {
    let inputs = Array::make(compute_sequences.length(), 0)
    for index in 0..<@strategy.graph_data_count(graph) {
      let edge = @strategy.graph_data_at(graph, index).unwrap()
      let consumer = @strategy.data_edge_consumer(edge) - first_compute
      if consumer >= 0 && consumer < inputs.length() {
        inputs[consumer] += 1
      }
    }
    Some(inputs)
  }
  let capacity = match (requirements, source_free_preparation) {
    (Some(original), None) =>
      Some(
        (
          original.capacity.limits,
          original.capacity.provider_retained,
          original.capacity.provider_execution,
        ),
      )
    (None, Some(value)) =>
      Some(
        (
          value.limits,
          value.provider_retained_bytes,
          value.provider_execution_bytes,
        ),
      )
    (None, None) =>
      client_local_sequence_capacity(
        compute_sequences,
        task_count,
        capacity_plan=Some(capacity_plan),
        retained_inputs~,
        max_rows~,
        retained_output~,
      )
    (Some(_), Some(_)) => None
  }
  guard capacity is Some((limits, retained_bytes, execution_bytes)) else {
    return None
  }
  let retained_configuration = source_free_preparation.bind(value => {
    value.configuration
  })
  if retained_configuration is Some(original) &&
    original.retained_output != retained_output {
    return None
  }
  let opened = if opened_run is Some(run) {
    Ok(run)
  } else if captured_sources.length() == 2 {
    @strategy.open_multi_captured_dag(
      @publication_host.prepared_client_graph(prepared),
      captured_sources,
      acquisition_ledger.unwrap(),
    ).map_err(issue => @publication_host.ClientRunOpenIssue::Run(issue))
  } else {
    match source {
      None =>
        match acquisition_ledger {
          Some(ledger) =>
            @strategy.open_source_free_dag(graph, ledger).map_err(issue => {
              @publication_host.ClientRunOpenIssue::Run(issue)
            })
          None =>
            @publication_host.open_prepared_source_free_client_run(
              prepared, limits,
            )
        }
      Some(captured) =>
        match acquisition_ledger {
          Some(ledger) =>
            @strategy.open_captured_dag(graph, captured, ledger).map_err(issue => {
              @publication_host.ClientRunOpenIssue::Run(issue)
            })
          None =>
            @publication_host.open_prepared_captured_client_run(
              prepared, captured, limits,
            )
        }
    }
  }
  let run = match opened {
    Ok(value) => value
    Err(_) => return None
  }
  if retained_configuration is Some(original) {
    return bind_client_local_configuration(
      run, original, fixed_ms, per_row_ms, per_wire_byte_ms, per_pair_ms,
    )
  }
  configure_client_local_run(
    run,
    graph,
    capacity_plan,
    first_compute,
    task_count,
    AdmittedRows,
    retained_bytes,
    execution_bytes,
    retained_output,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    provider_factory,
  )
}

///|
// Preserve the established Pure/Node and installed Effect request boundaries.
// Both row dimensions are retained by the same checked plan.
priv enum ClientLocalManagedBoundaryProfile {
  AdmittedRows
  ExecutionRows
}

///|
let client_local_adaptive_revisions : Int = 10

///|
let client_local_estimate_work : Int = 1000

///|
/// Pure selected Local module and immutable policies retained before a Run.
/// The actual driver binds this original instead of reconstructing providers
/// or selecting another module from equal numerical limits.
priv struct ClientPreparedLocalConfiguration {
  graph : @strategy.CheckedDAG
  capacity_plan : ClientLocalCapacityPlan
  registry : @connector.CapabilityRegistry
  dispatch : @local_driver.LocalDispatchPreparation
  capacity : @connector.FixedComputeCapacity
  retained_output : Bool
}

///|
fn prepare_client_local_configuration(
  graph : @strategy.CheckedDAG,
  capacity_plan : ClientLocalCapacityPlan,
  boundary_profile : ClientLocalManagedBoundaryProfile,
  retained_bytes : Int64,
  execution_bytes : Int64,
  retained_output : Bool,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> ClientPreparedLocalConfiguration? {
  let compute_sequences = capacity_plan.sequences
  if !(capacity_plan.graph is Some(original) && physical_equal(original, graph)) ||
    !client_local_capacity_plan_matches(
      capacity_plan,
      compute_sequences,
      capacity_plan.admitted_rows,
    ) {
    return None
  }
  // These two existing boundary profiles are projections of the same plan,
  // not caller-supplied alternative execution or serialization limits.
  let max_rows = match boundary_profile {
    AdmittedRows => capacity_plan.admitted_rows
    ExecutionRows => capacity_plan.execution.rows.max_rows
  }
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows,
    max_value_bytes: capacity_plan.max_value_bytes,
    common_fragment: None,
  }
  let providers = match
    @execution.execution_capacity(retained_bytes, execution_bytes) {
    Some(base) => provider_factory(base)
    None => return None
  }
  let local_configuration : @local_driver.LocalComputeConfiguration = {
    sequences: compute_sequences,
    managed_providers: providers,
    managed_capacity: capacity,
    execution: capacity_plan.execution,
    measurement: capacity_plan.measurement,
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
    Err(_) => return None
  }
  let registry = @connector.installed_bundle_registry(installed_bundles)
  guard @connector.capability_registration_at(registry, 0)
    is Some(local_registration) else {
    return None
  }
  guard @connector.capability_implementation(
      @connector.installed_compute_implementations(installed_bundles),
      local_registration,
    )
    is Some(local_configuration) else {
    return None
  }
  let dispatch = match
    @local_driver.prepare_local_dispatch_plan(
      graph,
      registry,
      local_registration,
      compute_sequences,
      capacity_plan.execution,
      capacity_plan.measurement,
      100,
      managed_capacity=capacity,
      managed_providers=local_configuration.managed_providers,
      inputs=Some((capacity_plan.imports, Some(0L))),
      metadata=Some(capacity_plan.metadata),
      // The explicit retained-output selection keeps the original row-file
      // exporter and its full simultaneous backing. Default managed consumers
      // do not select that separate exporter.
      output=if retained_output {
        Some((capacity_plan.exports, Some(0L)))
      } else {
        None
      },
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  Some({ graph, capacity_plan, registry, dispatch, capacity, retained_output, })
}

///|
fn bind_client_local_configuration(
  run : @strategy.CapturedDAG,
  original : ClientPreparedLocalConfiguration,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  captured_effect? : @strategy.CapturedEffectRunDAG? = None,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  let graph = original.graph
  let capacity_plan = original.capacity_plan
  let first_compute = capacity_plan.graph_offset
  let task_count = @strategy.graph_task_count(graph)
  let registry = original.registry
  let capacity = original.capacity
  let retained_output = original.retained_output
  let same_graph = match captured_effect {
    None => physical_equal(@strategy.captured_dag_graph(run), graph)
    Some(value) =>
      @strategy.captured_effect_run_matches_preparation(value, run, graph)
  }
  if !same_graph || @strategy.captured_compute_first_task(run) != first_compute {
    return reject_client_local_run(run)
  }
  let driver = @host_driver.open_dispatch_driver(run)
  let binding = match captured_effect {
    None => @local_driver.bind_local_dispatch_plan(driver, original.dispatch)
    Some(value) =>
      @local_driver.bind_local_effect_dispatch_plan(
        driver,
        original.dispatch,
        value,
      )
  }
  let installed = match binding {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  let modules = match
    @builtin.assemble_configured_compute_modules(
      driver,
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          installed,
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ) {
    Ok(value) => value
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
    @local_driver.prepare_local_estimate_module(
      installed, schedules, client_local_estimate_work,
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  match @local_driver.install_local_dispatch_estimates(installed, estimate) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  match
    @builtin.open_configured_compute_host(
      modules,
      registry,
      capacity,
      capacity_plan.dispatch_entries,
      capacity_plan.dispatch_name_bytes,
      1,
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
              max_revisions: client_local_adaptive_revisions,
            },
            client_local_estimate_work,
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
          if @strategy.captured_task_completed(run, task) {
            // A borrowed completed Model task has already spent its work.
            // Offer only its actual downstream tasks, never rerun the prefix.
            continue
          }
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
        if offers.is_empty() {
          // Every remaining task is an actual typed completion. This Host
          // still owns Result/Effect consumers, but has no Compute to select.
          return Some(value)
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
// Shared installed Local configuration on the exact already-open Run. The
// Pure and Effect entrypoints retain their own original preparation/admission;
// this helper neither opens a Run/Ledger nor grants execution authority.
fn configure_client_local_run(
  run : @strategy.CapturedDAG,
  graph : @strategy.CheckedDAG,
  capacity_plan : ClientLocalCapacityPlan,
  first_compute : Int,
  task_count : Int,
  boundary_profile : ClientLocalManagedBoundaryProfile,
  retained_bytes : Int64,
  execution_bytes : Int64,
  retained_output : Bool,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  let compute_sequences = capacity_plan.sequences
  if !physical_equal(@strategy.captured_dag_graph(run), graph) ||
    @strategy.graph_task_count(graph) != task_count ||
    @strategy.captured_compute_first_task(run) != first_compute ||
    capacity_plan.graph_offset != first_compute ||
    !(capacity_plan.graph is Some(original) && physical_equal(original, graph)) ||
    !client_local_capacity_plan_matches(
      capacity_plan,
      compute_sequences,
      capacity_plan.admitted_rows,
    ) {
    return reject_client_local_run(run)
  }
  let original = match
    prepare_client_local_configuration(
      graph, capacity_plan, boundary_profile, retained_bytes, execution_bytes, retained_output,
      provider_factory,
    ) {
    Some(value) => value
    None => return reject_client_local_run(run)
  }
  bind_client_local_configuration(
    run, original, fixed_ms, per_row_ms, per_wire_byte_ms, per_pair_ms,
  )
}

///|
/// Two independent captures enter the same existing Local Compute owner.
/// Their exact NativePhysical holdings remain in the supplied Run ledger.
pub fn open_multi_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
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
    installed_contracts,
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

///|
/// Two captured inputs use their original ledger and retained Relation output.
/// No second acquisition or Compute owner is created for the output mode.
pub fn open_multi_captured_local_retained_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
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
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    retained_output=true,
    captured_sources=sources,
    acquisition_ledger=Some(ledger),
  )
}
