///|
// A synchronous callback can reenter cancellation. Its stack roots still
// belong to this execution until the callback returns.
fn[A] with_managed_scratch_use(
  uses : Ref[Int],
  release : () -> Unit,
  action : () -> A,
) -> A {
  uses.val += 1
  let result = action()
  uses.val -= 1
  release()
  result
}

///|
// Every input copy contributes to the same Task import extent. Keep its
// computation, current callback, debit and append in one synchronous mutation
// scope. Cancellation and cleanup remain independently callable.
fn[A] with_local_managed_import_mutation(
  active : Ref[Bool],
  action : () -> Result[A, LocalDispatchIssue],
) -> Result[A, LocalDispatchIssue] {
  if active.val {
    return Err(Configuration(InputUnavailable))
  }
  active.val = true
  let result = action()
  active.val = false
  result
}

///|
// Readiness is private import bookkeeping, not an availability or authority
// witness. Call only after the existing exact bridge/import validation.
fn[T] install_local_managed_input_read(
  reads : Array[T?],
  pending : Ref[Int],
  index : Int,
  value : T,
) -> Bool {
  if index < 0 ||
    index >= reads.length() ||
    pending.val <= 0 ||
    reads[index] is Some(_) {
    return false
  }
  reads[index] = Some(value)
  pending.val -= 1
  true
}

///|
/// Pure prepared Local managed task. Physical representation access starts
/// only after common selection, reservation and task registration.
struct LocalManagedDispatchConfiguration[T] {
  run : @strategy.CapturedDAG
  task : Int
  choice : @connector.ManagedFixedComputeChoice[T]
  prepared : @connector.PreparedManagedCompute[T, @execution.GeneratedSequence]
  sequence : @execution.GeneratedSequence
  provider : @local.ManagedProvider?
  relation_inputs : Array[LocalManagedRelationInput[T]]
  provider_inputs : Array[LocalManagedPreparedInput]
  completion_inputs : Array[@execution.ManagedInputBinding]
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  imports : @local.LocalImportLimits
  installation : LocalDispatchModule
  metadata : LocalManagedMetadataLimits
  capacity : @connector.ExecutionCapacity
  metered_output_retention : Bool
  metered_retention : Bool
  join_output_ceilings : Array[(Int, Int64)]
  interval_search_ceilings : Array[(Int, Int64)]
  asof_search_ceilings : Array[(Int, Int64)]
  sequence_match_ceilings : Array[(Int, Int64, Int64)]
  aggregate_output_ceilings : Array[@connector.AggregateOutputCeiling]
  analytic_envelopes : Array[@connector.AnalyticEnvelope]
}

///|
pub enum LocalManagedAvailableOutput[T] {
  CapturedRelationInput
  SuppliedRelationInput
  RelationOutput(@execution.ManagedCompletedOutput[T])
  CarrierOutput(
    @execution.CarrierManagedCompletedOutput,
    @carrier_runtime.Material
  )
}

///|
pub fn[T] local_managed_supplied_relation_input() -> LocalManagedAvailableOutput[
  T,
] {
  SuppliedRelationInput
}

///|
pub fn[T] local_managed_captured_relation_input() -> LocalManagedAvailableOutput[
  T,
] {
  CapturedRelationInput
}

///|
pub fn[T] local_managed_relation_output(
  output : @execution.ManagedCompletedOutput[T],
) -> LocalManagedAvailableOutput[T] {
  RelationOutput(output)
}

///|
pub fn[T] local_managed_carrier_output(
  output : @execution.CarrierManagedCompletedOutput,
  material : @carrier_runtime.Material,
) -> LocalManagedAvailableOutput[T] {
  CarrierOutput(output, material)
}

///|
priv enum LocalManagedPreparedInput {
  PreparedRelation(Int)
  PreparedSupplied(@execution.SuppliedRelationRead)
  PreparedCarrier(@carrier_runtime.ProducerView)
}

///|
priv enum LocalManagedRelationInput[T] {
  OrdinaryRelationInput(@execution.ProducerRead)
  SuppliedRelationInput(@execution.SuppliedRelationRead)
  ManagedRelationInput(@execution.ManagedProducerRead[T])
}

///|
fn bind_physical_operation_input(
  run : @strategy.CapturedDAG,
  index : Int,
  binding : @execution.ManagedInputBinding,
) -> @execution.ManagedInputBinding? {
  match @strategy.captured_next_managed_operation_input(run, index) {
    Some((step, operation_input)) =>
      @strategy.graph_task_owner(
        @strategy.captured_dag_graph(run),
        @strategy.next_captured_task(run).unwrap(),
      ).bind(owner => {
        @execution.managed_input_binding_for_operation(
          binding, owner, step, operation_input,
        )
      })
    None => Some(binding)
  }
}

///|
pub struct LocalManagedInputTransfer[T] {
  input : @execution.ManagedProducerRead[T]
  append : (String) -> Result[Unit, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
pub(all) struct LocalManagedAdvance {
  complete : Bool
  waiting : Bool
  settlement : Int?
  progress : Int64
  work : Int64
}

///|
/// Primitive Host-facing operations on the same family-owned snapshot handle.
/// File custody remains with the installed Store; no Graph payload is exposed.
pub struct LocalManagedSnapshot {
  key : String
  maximum_bytes : Int
  maximum_frame_bytes : Int
  advance_save : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  take_output : () -> Result[String, LocalDispatchIssue]
  content : () -> Result[@carrier_runtime.SnapshotContent, LocalDispatchIssue]
  release_source : (String) -> Result[Unit, LocalDispatchIssue]
  begin_reload : (String, () -> Bool) -> Result[Unit, LocalDispatchIssue]
  advance_reload : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
/// Representation conversion under the existing Relation completion and task
/// owner. The installed Store owns bytes; the common exporter/importer owns
/// presence, order, exact receipts and admission. No Compute is resumed here.
pub struct LocalManagedRelationSnapshot {
  key : String
  frames : LocalInputFrames
  advance_save : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  take_output : () -> Result[String, LocalDispatchIssue]
  content : () -> Result[@carrier_runtime.SnapshotContent, LocalDispatchIssue]
  release_source : (String, () -> Bool) -> Result[Unit, LocalDispatchIssue]
  source_available : () -> Bool
  begin_reload : () -> Result[Unit, LocalDispatchIssue]
  append_reload : (String) -> Result[Unit, LocalDispatchIssue]
  finish_reload : () -> Result[Unit, LocalDispatchIssue]
  cleanup_references : (Int) -> Bool
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
priv enum SnapshotPhase {
  Saving
  Saved
  Released
  Reloading
  Restored
  Finished
  Failed
} derive(Eq)

///|
pub struct LocalManagedDispatchOperations[T] {
  inputs : Array[LocalManagedInputTransfer[T]]
  retained_inputs : Array[LocalInputTransfer]
  execute : () -> Result[Unit, LocalDispatchIssue]
  advance : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  request_cancel : () -> Bool
  execution_stopped : () -> Bool
  cumulative_provider_work : () -> Result[
    Int64,
    @local.ManagedProviderWorkIssue,
  ]
  prepare_finalization : (T, Int64, () -> Bool) -> Result[
    Unit,
    LocalDispatchIssue,
  ]
  advance_finalization : (Int) -> Result[
    LocalManagedAdvance,
    LocalDispatchIssue,
  ]
  settle : () -> Result[Unit, LocalDispatchIssue]
  complete : (T, Int64, () -> Bool) -> Result[
    @execution.ManagedCompletedOutput[T],
    LocalDispatchIssue,
  ]
  complete_carrier : () -> Result[
    @execution.CarrierManagedCompletedOutput,
    LocalDispatchIssue,
  ]
  output_rows : () -> Int
  output_row : (Int) -> Result[String, LocalDispatchIssue]
  material : () -> @execution.ManagedRetainedOutput[T]?
  carrier_material : () -> @carrier_runtime.Material?
  prepare_carrier_snapshot : (() -> Bool) -> Result[
    LocalManagedSnapshot?,
    LocalDispatchIssue,
  ]
  prepare_relation_snapshot : (() -> Bool) -> Result[
    LocalManagedRelationSnapshot?,
    LocalDispatchIssue,
  ]
  // Original startup-storage quote passed back to this same operation. An
  // actual-retention task issues its final holding from checked final usage.
  storage_bytes : Int64
  close : () -> Unit
  cleanup_refresh : () -> Bool
  cleanup_progress : () -> Int64
  cleanup_local_continuation : () -> Int64
}

///|
/// Exact physical transfer unit used by the managed row wire. MoonBit String
/// length is UTF-16 code units and cannot be charged as transported bytes.
fn managed_row_transfer_bytes(
  row : String,
  max_bytes : Int,
) -> Result[Int64, LocalDispatchIssue] {
  @scalar.admit_utf8_length64(row, max_bytes.to_int64()).map_err(_ => {
    Configuration(InputUnavailable)
  })
}

///|
// Import preparation retains empty buffers and schema/cursor bindings. Row
// wire/parser scratch is constructed only by append; the original before-decode
// growth owner funds that scratch and copied DATA from the same incoming wire.
fn local_managed_import_start_bytes(
  limits : @local.LocalImportLimits,
) -> Int64? {
  @local.local_import_start_retention_capacity(limits)
}

///|
fn local_managed_import_next_extent(
  limits : @local.LocalImportLimits,
  rows : Int64,
  nodes : Int64,
  text : Int64,
  wire_bytes : Int64,
) -> (Int64, Int64, Int64, Int64)? {
  @local.local_import_next_retention_extent(
    limits, rows, nodes, text, wire_bytes,
  )
}

///|
// Same import prefix and pre-snapshot transport remain coheld. This arithmetic
// supplies no ACK or grant; only the closed acknowledged snapshot calls it.
fn local_managed_snapshot_reload_extent(
  imported : Int64,
  transport : Int64,
  transport_prefix : Int64,
  next : Int64,
) -> (Int64, Int64)? {
  if imported < 0L ||
    transport_prefix < 0L ||
    transport_prefix > transport ||
    next < imported {
    return None
  }
  guard @execution.checked_preparation_add_product(
      imported,
      transport - transport_prefix,
      1L,
    )
    is Some(previous) else {
    return None
  }
  Some((transport_prefix, Int64::max(previous, next)))
}

///|
// Reclassify only the closed original reload's duplicate scalar parser text.
// Import DATA and every external wire/frame/batch prefix remain coheld. The
// combined reservation never shrinks, and a later grow cannot spend it twice.
fn local_managed_import_working_overlap(
  imported : Int64,
  reusable : Int64,
  previous_working : Int64,
  next_working : Int64,
) -> (Int64, Int64, Int64)? {
  if imported < 0L ||
    reusable < 0L ||
    reusable > imported ||
    previous_working < 0L ||
    next_working < previous_working {
    return None
  }
  let delta = next_working - previous_working
  let reused = Int64::min(reusable, delta)
  Some((imported - reused, reusable - reused, delta - reused))
}

///|
// Fixed constructor inventory, independent of row/wire limits and backend
// nullable optimizations. Standing 2H/7R/1W: two Ref cells (scalar/optional),
// plus six closure slots (reserve/outer snapshot/finish, save/reload/finish).
// The optional cell's None tag and Some reference each use one eight-byte
// slot. Reload peak 5H/1R/7W covers old/getter/new Some values plus bind/map
// closures; each Some has its own header, tag and payload. Growth's remaining
// Some plus Some(tuple3) is only 3H/1R/6W; each post-current map/Some fence is
// at most 3H/1R/4W. These phases do not overlap. Prepay standing + reload
// (7H/8R/8W) before construction on this SAME task, independently of parser
// Text. One further standing word retains the installed Relation snapshot
// mode in the existing snapshot closure. This is the logical representation
// tariff, not a backend heap claim.
let local_managed_scalar_overlap_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 7L,
  reference_slots: 8L,
  scalar_words: 9L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// The existing Node finalization async frame additionally retains one original
// module reference and one selected task ordinal. Prepay both slots alongside
// the original task controls before the adapter can enter any finalization
// callback. No closure, holder, owner or new error record is introduced.
let local_managed_finalization_diagnostic_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 0L,
  reference_slots: 1L,
  scalar_words: 1L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn local_managed_finalization_diagnostic_control_capacity() -> Int64? {
  @execution.preparation_representation_cost(
    local_managed_finalization_diagnostic_controls,
  )
}

///|
// The new original issue (1H/4W: tag, step, limit, origin), Node DATA
// (1H/5R/2W) and <=19-digit
// policy String (1H/19 UTF16) remain live through the existing failure owner.
// The bridge tuple+Some is 2H/2R/3W, including Some's tag even when a backend
// unboxes it. Three fixed local references/two words and the defineProperty
// argument's 1H/1R coexist with the new DATA: total 174R/310E bytes.
// A conservative earlier mapping-phase sum includes refinement/step/context
// Options, the selected holder and returned Int64 Option (5H/4R/5W), then
// the new issue and the same locals (6H/7R/11W = 240 bytes). It cannot overlap
// the Node projection, and is below 310. No old error/Some replacement credit
// or metadata ceiling spare is used; these are the SAME task's complete new
// controls, not another reservation or cleanup acknowledgement.
fn local_managed_logical_work_diagnostic_capacity() -> (Int64, Int64)? {
  guard @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 5L,
      scalar_words: 6L,
      owned_utf16_units: 19L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 6L,
      scalar_words: 5L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(temporary) &&
    @execution.checked_preparation_add_product(retained, temporary, 1L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
/// Pure projection of the managed route's complete existing diagnostic frame.
/// It neither changes the materializer quote nor admits another allocation.
fn local_managed_task_capacity(
  capacity : @strategy.PhysicalEnvelope,
) -> @strategy.PhysicalEnvelope? {
  guard local_managed_logical_work_diagnostic_capacity()
    is Some((diagnostic_retained, diagnostic_execution)) &&
    @execution.checked_preparation_add_product(
      capacity.retained_bytes,
      diagnostic_retained,
      1L,
    )
    is Some(retained_bytes) &&
    @execution.checked_preparation_add_product(
      capacity.execution_bytes,
      diagnostic_execution,
      1L,
    )
    is Some(execution_bytes) else {
    return None
  }
  Some({
    transfer_bytes: capacity.transfer_bytes,
    retained_bytes,
    execution_bytes,
  })
}

///|
fn local_managed_scalar_overlap_control_capacity() -> Int64? {
  @execution.preparation_representation_cost(
    local_managed_scalar_overlap_controls,
  )
}

///|
// Only the exact finished export supplies these copy extents. They fund the
// existing importer; all original admission and identity limits still apply.
fn local_relation_snapshot_reload_capacity(
  limits : @local.LocalImportLimits,
  content : @execution.AdmittedOutputStreamReceipt,
) -> Int64? {
  let (_, bytes, nodes, rows) = @execution.output_stream_identity(content)
  let values = @execution.output_stream_value_usage(content)
  if bytes < 1 ||
    rows < 0 ||
    nodes < 1 ||
    bytes > limits.wire.max_bytes ||
    rows > limits.max_rows ||
    values.nodes < 0 ||
    values.nodes > limits.values.max_nodes ||
    values.text_bytes < 0 ||
    values.text_bytes > limits.values.max_text_bytes {
    return None
  }
  @local.local_import_retention_capacity({
    max_rows: rows,
    values: {
      ..limits.values,
      max_nodes: values.nodes,
      max_text_bytes: values.text_bytes,
    },
    wire: { ..limits.wire, max_bytes: bytes, max_nodes: nodes, },
    row: {
      ..limits.row,
      max_bytes: Int::max(1, Int::min(limits.row.max_bytes, bytes)),
      max_nodes: Int::min(limits.row.max_nodes, values.nodes),
      max_text_bytes: Int::min(limits.row.max_text_bytes, values.text_bytes),
    },
    max_batch_bytes: Int::max(1, Int::min(limits.max_batch_bytes, bytes)),
  })
}

///|
pub fn[T] prepare_local_managed_dispatch(
  installed : LocalDispatchModule,
  outputs : Array[@execution.ManagedCompletedOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[LocalManagedDispatchConfiguration[T]?, LocalDispatchIssue] {
  let available = []
  let mut completed = 0
  for producer in @strategy.captured_next_managed_producers(installed.run) {
    if producer == -1 {
      available.push(local_managed_supplied_relation_input())
    } else if completed < outputs.length() {
      available.push(local_managed_relation_output(outputs[completed]))
      completed += 1
    } else {
      return Err(Configuration(InputUnavailable))
    }
  }
  if completed != outputs.length() {
    return Err(Configuration(InputUnavailable))
  }
  prepare_local_managed_dispatch_with_outputs(
    installed, available, obligations, _output_file_bytes,
  )
}

///|
/// Prepare Local execution from the exact ordered Relation/Carrier output set.
pub fn[T] prepare_local_managed_dispatch_with_outputs(
  installed : LocalDispatchModule,
  outputs : Array[LocalManagedAvailableOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[LocalManagedDispatchConfiguration[T]?, LocalDispatchIssue] {
  guard @strategy.next_captured_task(installed.run) is Some(task) &&
    installed.import_policy is Some((imports, _)) &&
    installed.import_metadata is Some(metadata) else {
    return Ok(None)
  }
  if installed.estimate_configuration is Some(configuration) &&
    configuration.eligible.get(task - 1) is Some(false) {
    return Ok(None)
  }
  let relation_inputs = []
  let provider_inputs = []
  let completion_inputs = []
  let producers = @strategy.captured_next_managed_producers(installed.run)
  if producers.length() != outputs.length() {
    return Err(Configuration(InputUnavailable))
  }
  for index, output in outputs {
    match output {
      CapturedRelationInput => {
        let value = match
          @strategy.captured_task_input(
            installed.run,
            task,
            @local.local_module_execution_limits(installed.implementation).rows.metadata_entries,
            metadata.name_bytes,
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        if @execution.producer_read_row_count(value) >
          @local.local_module_managed_capacity(installed.implementation).max_rows {
          return Err(Configuration(CommonInputRows))
        }
        let relation_index = relation_inputs.length()
        relation_inputs.push(OrdinaryRelationInput(value))
        provider_inputs.push(PreparedRelation(relation_index))
        guard bind_physical_operation_input(
            installed.run,
            index,
            @execution.ordinary_relation_input_binding(value),
          )
          is Some(binding) else {
          return Err(Configuration(InputUnavailable))
        }
        completion_inputs.push(binding)
      }
      SuppliedRelationInput => {
        let value = match
          @strategy.captured_supplied_task_input(
            installed.run,
            task,
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        if @execution.supplied_relation_read_row_count(value) >
          @local.local_module_managed_capacity(installed.implementation).max_rows {
          return Err(Configuration(CommonInputRows))
        }
        relation_inputs.push(SuppliedRelationInput(value))
        provider_inputs.push(PreparedSupplied(value))
        guard bind_physical_operation_input(
            installed.run,
            index,
            @execution.supplied_relation_input_binding(value),
          )
          is Some(binding) else {
          return Err(Configuration(InputUnavailable))
        }
        completion_inputs.push(binding)
      }
      RelationOutput(output) =>
        match
          @strategy.captured_managed_task_input(
            installed.run,
            task,
            output,
            @local.local_module_execution_limits(installed.implementation).rows.metadata_entries,
            metadata.name_bytes,
            input_index=index,
          ) {
          Ok(value) => {
            let relation_index = relation_inputs.length()
            relation_inputs.push(ManagedRelationInput(value))
            provider_inputs.push(PreparedRelation(relation_index))
            guard bind_physical_operation_input(
                installed.run,
                index,
                @execution.managed_relation_input_binding(value),
              )
              is Some(binding) else {
              return Err(Configuration(InputUnavailable))
            }
            completion_inputs.push(binding)
          }
          Err(issue) => return Err(Execution(issue))
        }
      CarrierOutput(output, material) => {
        guard @strategy.graph_task_owner(
            @strategy.captured_dag_graph(installed.run),
            task,
          )
          is Some(receiver) &&
          @strategy.graph_task_owner(
            @strategy.captured_dag_graph(installed.run),
            producers[index],
          )
          is Some(producer) else {
          return Err(Execution(ForeignCandidate))
        }
        let operation = @strategy.captured_next_managed_operation_input(
          installed.run,
          index,
        )
        let view_result = match operation {
          Some((consumer_step, operation_input)) =>
            @carrier_runtime.material_prepare_operation_view(
              material, receiver, consumer_step, operation_input, producer,
            )
          None =>
            @carrier_runtime.material_prepare_view(
              material, receiver, index, producer,
            )
        }
        let view = match view_result {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        let read = match
          @strategy.captured_carrier_managed_task_input(
            installed.run,
            task,
            output,
            @carrier_runtime.producer_view_read_reference(view),
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        provider_inputs.push(PreparedCarrier(view))
        completion_inputs.push(@execution.managed_carrier_input_binding(read))
      }
    }
  }

  guard @strategy.graph_task_owner(
      @strategy.captured_dag_graph(installed.run),
      task,
    )
    is Some(owner) else {
    return Err(Execution(ForeignCandidate))
  }
  guard local_task_interval_search_ceilings(installed.run, task)
    is Some(interval_search_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_asof_search_ceilings(installed.run, task)
    is Some(asof_search_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_sequence_match_ceilings(installed.run, task)
    is Some(sequence_match_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  let graph = @strategy.captured_dag_graph(installed.run)
  let selected_operation = @strategy.graph_task_selected_step(graph, task)
    is Some(_) ||
    @strategy.graph_task_prefix_end(graph, task) is Some(_)
  let request_result = if selected_operation ||
    provider_inputs.any(input => input is PreparedCarrier(_)) ||
    relation_inputs.any(input => {
      input is OrdinaryRelationInput(_) || input is SuppliedRelationInput(_)
    }) {
    @connector.prepare_managed_fixed_compute_request_for_bindings(
      owner,
      completion_inputs,
      @local.local_module_managed_capacity(installed.implementation),
      obligations,
    )
  } else {
    @connector.prepare_managed_fixed_compute_request_for_owner(
      owner,
      relation_inputs.filter_map(input => {
        match input {
          ManagedRelationInput(value) => Some(value)
          OrdinaryRelationInput(_) | SuppliedRelationInput(_) => None
        }
      }),
      @local.local_module_managed_capacity(installed.implementation),
      obligations,
    )
  }
  let request = match request_result {
    Ok(value) => value
    Err(
      LogicalIdentityUnsupported
      | CommonFragmentUnsupported
      | UnsupportedInputShape
    ) => return Ok(None)
    Err(issue) => return Err(Configuration(issue))
  }
  let estimates = match
    local_managed_estimate_lines(
      installed,
      task,
      relation_inputs.map(input => {
        match input {
          OrdinaryRelationInput(value) =>
            @execution.producer_read_row_count(value)
          SuppliedRelationInput(value) =>
            @execution.supplied_relation_read_row_count(value)
          ManagedRelationInput(value) =>
            @execution.managed_producer_read_row_count(value)
        }
      }),
    ) {
    Ok(value) => value
    Err(_) => return Err(Configuration(InvalidLimits))
  }
  let (prepared, choice) = match
    @local.prepare_local_module_managed_compute_with_estimates(
      installed.implementation,
      local_task_slot(installed, task),
      request,
      estimates,
      interval_search_ceilings~,
      asof_search_ceilings~,
      sequence_match_ceilings~,
    ) {
    Ok(value) => value
    Err(
      Candidate(
        LogicalIdentityUnsupported
        | CommonFragmentUnsupported
        | UnsupportedInputShape
        | ComputeUnsupported
      )
    ) => return Ok(None)
    Err(issue) => return Err(Preparation(issue))
  }
  guard @connector.managed_fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(Configuration(InvalidLimits))
  }
  let provider = @local.local_module_managed_provider(
    installed.implementation,
    local_task_slot(installed, task),
    sequence,
  )
  // Managed Local work runs only through a bounded provider. A sequence no
  // provider accepts is not a managed candidate; there is no synchronous
  // whole-sequence fallback.
  if provider is None {
    return Ok(None)
  }
  let metered_start = @local.local_module_metered_output_start_capacity(
    installed.implementation,
    local_task_slot(installed, task),
    sequence,
  )
  let base = match metered_start {
    Some(value) => Some(value)
    None =>
      match provider {
        Some(_) =>
          @local.local_module_capacity_for_sequence(
            installed.implementation,
            local_task_slot(installed, task),
            sequence,
          )
        None =>
          @execution.generated_sequence_capacity(
            sequence,
            @local.local_module_execution_limits(installed.implementation),
            @local.local_module_measurement_limits(installed.implementation),
          )
      }
  }
  guard base is Some(base) &&
    @local.local_import_retention_capacity(imports) is Some(per_input) else {
    return Err(Configuration(InvalidLimits))
  }
  // Match the actual binding pass below. Supplied reads and already accessible
  // ordinary captures borrow their original storage; only missing copies and
  // managed producer bridges allocate an importer on this same task.
  let mut count = 0L
  let mut imported = 0L
  guard local_managed_import_start_bytes(imports) is Some(import_start) &&
    @local.local_materializing_import_start_capacity(imports)
    is Some(retained_import_start) else {
    return Err(Configuration(InvalidLimits))
  }
  for input in relation_inputs {
    let required = match input {
      OrdinaryRelationInput(read) =>
        if !@execution.producer_read_has_cell_access(read) {
          count += 1L
          // The original Local retained importer below funds every actual row
          // before decode. Unknown non-cell representations keep the full quote.
          if @execution.producer_read_retained_material(read) is Some(_) {
            retained_import_start
          } else {
            per_input
          }
        } else {
          0L
        }
      ManagedRelationInput(_) => {
        count += 1L
        // This bridge's append owns its input construction growth even when
        // the selected provider keeps its full prepaid output/workspace quote.
        import_start
      }
      SuppliedRelationInput(_) => 0L
    }
    if imported > 9223372036854775807L - required {
      return Err(Configuration(InvalidLimits))
    }
    imported += required
  }
  if per_input > 0L && count > 9223372036854775807L / per_input {
    return Err(Configuration(InvalidLimits))
  }
  guard local_managed_scalar_overlap_control_capacity() is Some(controls) &&
    local_managed_logical_work_diagnostic_capacity()
    is Some((diagnostic_retained, diagnostic_execution)) &&
    local_managed_finalization_diagnostic_control_capacity()
    is Some(finalization_controls) &&
    @execution.checked_preparation_add_product(
      controls, finalization_controls, 1L,
    )
    is Some(controls) &&
    @execution.checked_preparation_add_product(imported, controls, 1L)
    is Some(imported) &&
    @execution.checked_preparation_add_product(
      imported, diagnostic_execution, 1L,
    )
    is Some(imported) else {
    return Err(Configuration(InvalidLimits))
  }
  // Host metadata is a separately funded holding. It survives scratch release
  // and follows the existing completed-output/borrower cleanup acknowledgement.
  guard local_retained_with_metadata(
      base.retained_bytes,
      metadata.retained_bytes,
    )
    is Some(retained_with_metadata) &&
    @execution.checked_preparation_add_product(
      retained_with_metadata, diagnostic_retained, 1L,
    )
    is Some(retained_with_metadata) else {
    return Err(Configuration(InvalidLimits))
  }
  if base.retained_bytes > 9223372036854775807L - base.execution_bytes ||
    imported > 9223372036854775807L - base.execution_bytes - base.retained_bytes ||
    (
      count > 0L &&
      imports.wire.max_bytes.to_int64() > 9223372036854775807L / count
    ) {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_join_output_ceilings(installed.run, task)
    is Some(join_output_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  let aggregate_output_ceilings = []
  guard @strategy.captured_task_aggregate_output_count(installed.run, task)
    is Some(aggregate_count) else {
    return Err(Configuration(InvalidLimits))
  }
  for index in 0..<aggregate_count {
    guard @strategy.captured_task_aggregate_output_at(
        installed.run,
        task,
        index,
      )
      is Some(ceiling) else {
      return Err(Configuration(InvalidLimits))
    }
    aggregate_output_ceilings.push(ceiling)
  }
  let analytic_envelopes = []
  guard @strategy.captured_task_analytic_envelope_count(installed.run, task)
    is Some(analytic_count) else {
    return Err(Configuration(InvalidLimits))
  }
  for index in 0..<analytic_count {
    guard @strategy.captured_task_analytic_envelope_at(
        installed.run,
        task,
        index,
      )
      is Some(envelope) else {
      return Err(Configuration(InvalidLimits))
    }
    analytic_envelopes.push(envelope)
  }
  Ok(
    Some({
      run: installed.run,
      task,
      choice,
      prepared,
      sequence,
      provider,
      relation_inputs,
      provider_inputs,
      completion_inputs,
      execution: @local.local_module_execution_limits(installed.implementation),
      measurement: @local.local_module_measurement_limits(
        installed.implementation,
      ),
      imports,
      installation: installed,
      metadata,
      metered_output_retention: metered_start is Some(_),
      metered_retention: metered_start is Some(start) &&
      @local.local_module_capacity_for_sequence(
        installed.implementation,
        local_task_slot(installed, task),
        sequence,
      )
      .map(full => start.retained_bytes < full.retained_bytes)
      .unwrap_or(false),
      capacity: {
        transfer_bytes: count * imports.wire.max_bytes.to_int64(),
        retained_bytes: retained_with_metadata,
        // The checked output view, independent copy and imported input may
        // overlap until the copy commits and every bridge is closed.
        scratch_bytes: base.execution_bytes + base.retained_bytes + imported,
        execution_bytes: base.execution_bytes + base.retained_bytes + imported,
      },
      join_output_ceilings,
      interval_search_ceilings,
      asof_search_ceilings,
      sequence_match_ceilings,
      aggregate_output_ceilings,
      analytic_envelopes,
    }),
  )
}

///|
/// Exact duration selected by the installed Local cost policy. None means the
/// candidate remains unknown and must not enter automatic multi-Site ranking.
pub fn[T] local_managed_dispatch_duration(
  setup : LocalManagedDispatchConfiguration[T],
) -> Int64? {
  match
    @connector.managed_fixed_compute_candidate_duration(
      @connector.prepared_managed_compute_candidate(setup.prepared),
    ) {
    @cost.Complete(value) => Some(value)
    @cost.Unknown => None
  }
}

///|
/// True only when a registered family provider owns this execution. Ordinary
/// Relation-only work may remain on the established Local dispatcher.
pub fn[T] local_managed_dispatch_uses_provider(
  setup : LocalManagedDispatchConfiguration[T],
) -> Bool {
  setup.provider is Some(_)
}

///|
/// Safe Site sub-scope bounds for the selected managed execution. The Run
/// ledger remains the aggregate authority; these bounds prevent one Site from
/// consuming capacity assigned to another Site.
pub fn[T] local_managed_dispatch_site_capacity(
  setup : LocalManagedDispatchConfiguration[T],
) -> (Int64, Int64)? {
  Some((setup.capacity.retained_bytes, setup.capacity.execution_bytes))
}

///|
pub fn[T] start_local_managed_dispatch(
  setup : LocalManagedDispatchConfiguration[T],
  retained_relation? : Bool = false,
) -> Result[LocalManagedDispatchOperations[T], LocalDispatchIssue] {
  let live = Ref(true)
  let settled = Ref(false)
  let disposed = Ref(false)
  let scratch_uses = Ref(0)
  let bridges : Array[Ref[@execution.ManagedProducerBridge[T]?]] = []
  let retained_imports : Array[Ref[@execution.CompletedOutputImport?]] = []
  let reads : Array[@execution.ProducerRead?] = []
  let scratch_retirement = local_managed_scratch_retirement()
  let input_stop = local_managed_input_stop()
  // Supplied inputs use their own admitted representation, so their empty
  // read slots do not need an import. Count only required missing reads during
  // the existing binding pass; never rescan all inputs on provider resume.
  let pending_reads = Ref(0)
  let ordinary : Ref[@execution.CompletedOutput?] = Ref(None)
  let output_row_reader : Ref[
    (
      @execution.CompletedOutput,
      (Int, Int) -> Result[String, @execution.CompletedExportIssue],
    )?,
  ] = Ref(None)
  let retained : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let carrier : Ref[@carrier_runtime.Material?] = Ref(None)
  let carrier_completed : Ref[@execution.CarrierManagedCompletedOutput?] = Ref(
    None,
  )
  let provider_execution : Ref[@local.ManagedProviderExecution?] = Ref(None)
  let working_sequence : Ref[@execution.GeneratedSequence?] = Ref(None)
  let final_provider_work : Ref[Result[Int64, @local.ManagedProviderWorkIssue]] = Ref(
    Ok(0L),
  )
  // Stop confirmation permits cleanup; it is not cleanup confirmation. Keep
  // the task's scratch reservation until the installed provider actually
  // releases its owned state. Cache the existing owner's cumulative work
  // before dropping its last driver reference, without inventing cleanup work.
  let provider_completion_retained = Ref(false)
  let provider_reclamation_steps = Ref(0L)
  let release_provider_scratch = fn() {
    let observe = fn() {
      if provider_execution.val is Some(active) {
        let cursor = @local.managed_provider_cleanup_continuation(active)
        if cursor > provider_reclamation_steps.val {
          provider_reclamation_steps.val = cursor
        }
      }
    }
    observe()
    let released = release_local_managed_provider_scratch(
      provider_execution,
      provider_completion_retained,
      live.val &&
      settled.val &&
      (ordinary.val is Some(_) || carrier.val is Some(_)),
      final_provider_work,
    )
    observe()
    released
  }
  let retired_carriers : Array[@carrier_runtime.Material] = []
  let snapshot_attempted = Ref(false)
  let snapshot_ready = Ref(true)
  let snapshot_storage_released : Ref[(() -> Bool)?] = Ref(None)
  let relation_snapshot_cancel : Ref[(() -> Bool)?] = Ref(None)
  let execution_finished = Ref(false)
  let execution_failure : Ref[LocalDispatchIssue?] = Ref(None)
  let request = @connector.managed_fixed_compute_candidate_request(
    @connector.prepared_managed_compute_candidate(setup.prepared),
  )
  let relation_inputs = setup.relation_inputs
  let obligations = @connector.managed_fixed_compute_request_obligations(
    request,
  )
  let identity_requirements = @execution.managed_obligations_identities(
    obligations,
  ).filter(requirement => requirement.need is @execution.EstablishedBy(_))
  let finalization_started = Ref(false)
  let finalization_ready = Ref(false)
  let finalization_metadata_grown = Ref(false)
  let finalization_cancelled = Ref(false)
  let finalization_row = Ref(0)
  let finalization_receipt_steps = Ref(0L)
  let finalization_identity = Ref(0)
  let finalization_issuer = Ref(0)
  let finalization_established = Ref(0)
  let finalization_deadline = Ref(0)
  let finalization_work_remaining = Ref(setup.execution.max_work)
  let finalization_payload : Ref[T?] = Ref(None)
  let finalization_available : Ref[(() -> Bool)?] = Ref(None)
  let finalization_values : Ref[@execution.ManagedOutputValues?] = Ref(None)
  let finalization_reclamation_steps = Ref(0L)
  let finalization_receipt : Ref[@execution.ManagedOutputValueReceipt?] = Ref(
    None,
  )
  let finalization_storage : Ref[Int64?] = Ref(None)
  let finalization_retention : Ref[
    @execution.ManagedOutputRetentionPort[
      (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
      T,
    ]?,
  ] = Ref(None)
  let finalization_material : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(
    None,
  )
  let finalization_stream : Ref[@execution.CompletedOutputExport?] = Ref(None)
  let finalization_result_preparation : Ref[
    @execution.CompletedResultRelationExportPreparation?,
  ] = Ref(None)
  let finalization_cids : Array[String?] = Array::make(
    identity_requirements.length(),
    None,
  )
  let finalization_issuers : Array[@execution.ManagedIdentityIssuer[T]] = []
  let finalization_completed : Ref[@execution.ManagedCompletedOutput[T]?] = Ref(
    None,
  )
  let finalization_completion_preparation = @execution.generated_completion_preparation(
    setup.sequence,
  )
  let finalization_progress = fn() -> Int64 {
    (finalization_row.val +
    (if finalization_material.val is Some(_) { 1 } else { 0 }) +
    finalization_identity.val +
    finalization_issuer.val +
    (if finalization_completed.val is Some(_) { 1 } else { 0 }) +
    finalization_established.val +
    finalization_deadline.val).to_int64() +
    finalization_receipt_steps.val +
    finalization_reclamation_steps.val
  }
  let cancel_finalization = fn() {
    finalization_cancelled.val = true
    if relation_snapshot_cancel.val is Some(cancel) {
      if cancel() {
        relation_snapshot_cancel.val = None
      }
    }
    if finalization_completed.val is Some(completed) && !finalization_ready.val {
      @execution.revoke_unpublished_managed_completed_output(completed)
      |> ignore
    }
    if finalization_values.val is Some(values) {
      @execution.cancel_managed_output_values(values) |> ignore
    }
    if finalization_retention.val is Some(port) {
      @execution.cancel_managed_output_retention_port(port) |> ignore
    }
    if finalization_stream.val is Some(stream) {
      @execution.cancel_completed_output_export(stream)
    }
    if finalization_result_preparation.val is Some(preparation) {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
    }
  }
  let release_output_aliases = fn() {
    output_row_reader.val = None
    ordinary.val = None
    finalization_payload.val = None
    finalization_available.val = None
    finalization_receipt.val = None
    finalization_material.val = None
    finalization_completed.val = None
  }
  let stop_owned_inputs = fn() {
    if live.val {
      return true
    }
    // Successful scratch retirement already detached every input owner.
    if scratch_retirement.phase == Retired {
      input_stop.phase = Stopped
      return true
    }
    advance_local_managed_input_stop(
      input_stop,
      bridges,
      retained_imports,
      bridge => @execution.advance_close_managed_producer_bridge(bridge, 1),
      importer => @execution.advance_cancel_completed_output_import(importer, 1),
    )
  }
  // These are the driver's charged scratch roots. Returned transfer handles
  // capture optional owners, so even a finished importer can be detached.
  // Do not clear shared result storage: successful material owns its receipt.
  let release_owned_scratch = fn() {
    if !(disposed.val ||
      (settled.val && (finalization_ready.val || carrier.val is Some(_)))) ||
      scratch_uses.val != 0 ||
      (provider_execution.val is Some(_) && !provider_completion_retained.val) ||
      relation_snapshot_cancel.val is Some(_) ||
      (!live.val && input_stop.phase != Stopped) {
      return
    }
    if !advance_local_managed_scratch_retirement(
        scratch_retirement, bridges, retained_imports, reads, finalization_cids,
        finalization_issuers,
      ) {
      return
    }
    // The checked-value copy is scratch. Its immutable receipt/index was
    // transferred to material; disposing this buffer does not revoke it.
    if finalization_values.val is Some(values) {
      @execution.dispose_managed_output_values_scratch(values)
      finalization_reclamation_steps.val = @execution.managed_output_values_reclamation_steps(
        values,
      )
      if !@execution.managed_output_values_scratch_released(values) {
        return
      }
    }
    finalization_values.val = None
    finalization_retention.val = None
    finalization_stream.val = None
    finalization_result_preparation.val = None
    // Execution disposal may precede the published output's final reader.
    // Only unpublished output can be dropped here; the existing released
    // notification retires published aliases after retention is confirmed.
    if disposed.val && retained.val is None {
      release_output_aliases()
    }
  }
  let bound = match
    @connector.bind_prepared_managed_execution(
      setup.choice,
      setup.prepared,
      setup.capacity,
      setup.join_output_ceilings,
      fn(_sequence) {
        for input in relation_inputs {
          match input {
            OrdinaryRelationInput(read) =>
              if @execution.producer_read_has_cell_access(read) {
                reads.push(Some(read))
              } else {
                reads.push(None)
                pending_reads.val += 1
              }
            ManagedRelationInput(input) => {
              let bridge = match
                @execution.prepare_managed_producer_bridge(
                  input,
                  setup.imports.max_rows,
                  setup.imports.values,
                  setup.metadata.bridge_entries,
                  setup.metadata.name_bytes,
                  deferred_reclamation=true,
                ) {
                Ok(value) => value
                Err(_) =>
                  return Err(@strategy.RunIssue::Compute(InputUnavailable))
              }
              bridges.push(Ref(Some(bridge)))
              reads.push(None)
              pending_reads.val += 1
            }
            SuppliedRelationInput(_) => reads.push(None)
          }
        }
        let operations : @connector.ExecutionLifecycleOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() {
            live.val = false
            cancel_finalization()
            if provider_execution.val is Some(active) {
              @local.cancel_managed_provider(active) |> ignore
            }
            stop_owned_inputs() |> ignore
          },
          dispose: fn() {
            live.val = false
            cancel_finalization()
            if provider_execution.val is Some(active) {
              @local.cancel_managed_provider(active) |> ignore
            }
            disposed.val = true
            stop_owned_inputs() |> ignore
            release_owned_scratch()
          },
          settled: fn() {
            settled.val = true
            // Preserve the existing one stopped-provider cleanup attempt.
            // Pending/error keeps both its owner and all scratch responsibility.
            if live.val && (ordinary.val is Some(_) || carrier.val is Some(_)) {
              release_provider_scratch() |> ignore
            }
            release_owned_scratch()
          },
          // Observation only: cleanup never runs from this witness.
          scratch_released: fn() {
            (
              disposed.val ||
              (settled.val && finalization_ready.val) ||
              (settled.val && carrier.val is Some(_))
            ) &&
            scratch_uses.val == 0 &&
            (provider_execution.val is None || provider_completion_retained.val) &&
            (live.val || input_stop.phase == Stopped) &&
            scratch_retirement.phase == Retired &&
            (
              !disposed.val ||
              retained.val is Some(_) ||
              (
                ordinary.val is None &&
                finalization_payload.val is None &&
                finalization_available.val is None &&
                finalization_receipt.val is None &&
                finalization_material.val is None &&
                finalization_completed.val is None
              )
            ) &&
            finalization_values.val is None &&
            finalization_retention.val is None &&
            finalization_stream.val is None &&
            finalization_result_preparation.val is None &&
            relation_snapshot_cancel.val is None
          },
          retention_released: fn() {
            let relation_released = retained.val is None ||
              retained.val
              .map(value => {
                @execution.managed_retained_output_payload(value) is None
              })
              .unwrap()
            let carrier_released = carrier.val is None ||
              carrier.val
              .map(value => !@carrier_runtime.material_cleanup_pending(value))
              .unwrap()
            let mut old_carriers_released = true
            for material in retired_carriers {
              if @carrier_runtime.material_cleanup_pending(material) {
                old_carriers_released = false
              }
            }
            provider_execution.val is None &&
            relation_released &&
            carrier_released &&
            old_carriers_released &&
            snapshot_storage_released.val.map(check => check()).unwrap_or(true)
          },
          released: release_output_aliases,
          ready: fn() {
            if live.val && settled.val && !disposed.val {
              Ok(())
            } else {
              Err(@strategy.RunIssue::NotReady)
            }
          },
        }
        Ok(((), operations))
      },
      aggregate_output_ceilings=setup.aggregate_output_ceilings,
      analytic_envelopes=setup.analytic_envelopes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let execution = match
    @strategy.start_captured_managed_execution(setup.run, setup.task, bound) {
    Ok((_, value)) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard @strategy.task_execution_managed_attempt(setup.run, execution)
    is Some(execution_attempt) else {
    return Err(Execution(ForeignCandidate))
  }
  guard @strategy.task_execution_numeric_reduction_count(setup.run, execution)
    is Some(numeric_count) else {
    return Err(Execution(ForeignCandidate))
  }
  // Configuration may select output after managed setup. Start has now
  // recorded history, so the existing owner rejects further policy changes.
  let exports = setup.installation.output_policy.map(value => value.0)
  // Output framing belongs to the independently selected output policy.
  // An input batch or its column ceiling does not constrain a checked output.
  // Keep the established fallback for callers without an output profile.
  let output_wire = match exports {
    Some(limits) => limits.wire
    None => setup.imports.wire
  }
  let output_values = match exports {
    Some(limits) => limits.values
    None => setup.imports.values
  }
  let output_max_rows = match exports {
    Some(limits) => limits.max_rows
    None => setup.imports.max_rows
  }
  // Both evaluator growth and later Result metadata extend the same original
  // scratch extent. Keep their independent actual additions; neither may
  // replace the other's reservation with the smaller initial quote.
  let working_extra = Ref(0L)
  let retained_extra = Ref(0L)
  let metadata_extra = Ref(0L)
  let transport_extra = Ref(0L)
  let import_extra = Ref(0L)
  let import_scalar_reusable = Ref(0L)
  let import_mutating = Ref(false)
  let output_row_extent : Ref[Int?] = Ref(None)
  let working_failure : Ref[LocalDispatchIssue?] = Ref(None)
  let reserve_capacity = fn(
    extra : Int64,
    retained_data : Int64,
  ) -> Result[Unit, @execution.WorkspaceGrowthIssue] {
    if !live.val ||
      disposed.val ||
      extra < working_extra.val ||
      retained_data < retained_extra.val ||
      retained_data > 9223372036854775807L - setup.capacity.retained_bytes ||
      extra > 9223372036854775807L - setup.capacity.scratch_bytes ||
      metadata_extra.val >
      9223372036854775807L - setup.capacity.scratch_bytes - extra ||
      transport_extra.val >
      9223372036854775807L -
      setup.capacity.scratch_bytes -
      extra -
      metadata_extra.val ||
      import_extra.val >
      9223372036854775807L -
      setup.capacity.scratch_bytes -
      extra -
      metadata_extra.val -
      transport_extra.val {
      working_failure.val = Some(Execution(Stopped))
      return Err(WorkspaceUnavailable)
    }
    guard local_managed_import_working_overlap(
        import_extra.val,
        import_scalar_reusable.val,
        working_extra.val,
        extra,
      )
      is Some((imported, reusable, requested_execution)) else {
      working_failure.val = Some(Execution(Stopped))
      return Err(WorkspaceUnavailable)
    }
    let scratch = setup.capacity.scratch_bytes +
      extra +
      metadata_extra.val +
      transport_extra.val +
      imported
    // This pure balance refusal precedes every grow/current/imported-window
    // call and changes no reservation. It permits the common attachment to
    // ask for its exact minimum instead of spare page backing. The subsequent
    // grow still owns all original/current/stop checks; this is not authority.
    let ledger = @strategy.captured_dag_ledger(setup.run)
    let limits = @resources.ledger_admission_limits(ledger)
    let usage = @resources.ledger_usage(ledger)
    let requested_retention = retained_data - retained_extra.val
    let available_retention = limits.retained_bytes -
      usage.held_bytes -
      usage.reserved_retention_bytes
    let available_execution = limits.execution_bytes -
      usage.reserved_execution_bytes
    let r_refused = requested_retention > available_retention
    if r_refused || requested_execution > available_execution {
      working_failure.val = Some(
        if r_refused {
          ExecutionCapacityRefusal(
            RetentionLimit,
            requested_retention,
            available_retention,
            limits.retained_bytes,
          )
        } else {
          ExecutionCapacityRefusal(
            ExecutionLimit,
            requested_execution,
            available_execution,
            limits.execution_bytes,
          )
        },
      )
      return Err(WorkspaceBudgetUnavailable)
    }
    match
      @strategy.grow_task_execution_workspace(
        setup.run,
        execution,
        scratch,
        retained=if setup.metered_retention {
          Some(setup.capacity.retained_bytes + retained_data)
        } else {
          None
        },
      ) {
      Err(issue) => {
        working_failure.val = Some(Execution(Physical(issue)))
        return Err(WorkspaceUnavailable)
      }
      Ok(_) => ()
    }
    if !live.val || disposed.val {
      working_failure.val = Some(Execution(Stopped))
      return Err(WorkspaceUnavailable)
    }
    working_extra.val = extra
    retained_extra.val = retained_data
    import_extra.val = imported
    import_scalar_reusable.val = reusable
    working_failure.val = None
    Ok(())
  }
  let reserve_working = fn(extra) {
    reserve_capacity(extra, retained_extra.val)
  }
  // Import DATA, evaluator scratch, framing and Result metadata coexist under
  // this original Task reservation. No live parent or other copy is credited.
  let reserve_import = fn(
    next : Int64,
    retired_transport_prefix : Int64?,
  ) -> Result[Unit, LocalDispatchIssue] {
    if !live.val || disposed.val || next < import_extra.val {
      return Err(Execution(Stopped))
    }
    let (transport, imported) = match retired_transport_prefix {
      None => (transport_extra.val, next)
      Some(prefix) => {
        // Only the closed snapshot's acknowledged Released -> Reloading
        // transition selects this branch. Earlier transport and import DATA
        // stay coheld. The completed export delta is now spare backing on
        // this SAME reservation, never a physical release or a second grant.
        guard local_managed_snapshot_reload_extent(
            import_extra.val,
            transport_extra.val,
            prefix,
            next,
          )
          is Some(extent) else {
          return Err(Configuration(InvalidLimits))
        }
        extent
      }
    }
    let mut total = setup.capacity.scratch_bytes
    for extra in [working_extra.val, metadata_extra.val, transport, imported] {
      guard @execution.checked_preparation_add_product(total, extra, 1L)
        is Some(value) else {
        return Err(Configuration(InvalidLimits))
      }
      total = value
    }
    guard @execution.checked_preparation_add_product(
        setup.capacity.scratch_bytes,
        working_extra.val,
        1L,
      )
      is Some(base) &&
      @execution.checked_preparation_add_product(base, metadata_extra.val, 1L)
      is Some(metadata) &&
      @execution.checked_preparation_add_product(
        metadata,
        transport_extra.val,
        1L,
      )
      is Some(transport_before) &&
      @execution.checked_preparation_add_product(
        transport_before,
        import_extra.val,
        1L,
      )
      is Some(previous) else {
      return Err(Configuration(InvalidLimits))
    }
    if total < previous {
      return Err(Configuration(InvalidLimits))
    }
    let ledger = @strategy.captured_dag_ledger(setup.run)
    let limits = @resources.ledger_admission_limits(ledger)
    let usage = @resources.ledger_usage(ledger)
    let needed = total - previous
    let available = limits.execution_bytes - usage.reserved_execution_bytes
    if needed > available {
      return Err(
        ExecutionCapacityRefusal(
          ExecutionLimit,
          needed,
          available,
          limits.execution_bytes,
        ),
      )
    }
    match @strategy.grow_task_execution_workspace(setup.run, execution, total) {
      Err(issue) => return Err(Execution(Physical(issue)))
      Ok(_) => ()
    }
    if !live.val || disposed.val {
      return Err(Execution(Stopped))
    }
    import_extra.val = imported
    transport_extra.val = transport
    Ok(())
  }
  let reserve_transport = fn(
    extra : Int64,
  ) -> Result[Unit, LocalDispatchIssue] {
    if !live.val || disposed.val || extra < 0L {
      return Err(Execution(Stopped))
    }
    if extra > transport_extra.val {
      guard @execution.execution_capacity_inventory_add(
          setup.capacity.scratch_bytes +
          working_extra.val +
          metadata_extra.val +
          import_extra.val,
          QuotedBytes,
          extra,
          1,
        )
        is Some(scratch) else {
        return Err(Configuration(InvalidLimits))
      }
      match
        @strategy.grow_task_execution_workspace(setup.run, execution, scratch) {
        Ok(_) => ()
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      transport_extra.val = extra
      if !live.val || disposed.val {
        return Err(Execution(Stopped))
      }
    }
    Ok(())
  }
  let export_frame_extent = fn(
    receipt : @execution.ManagedOutputValueReceipt,
    result : @execution.ManagedResultOccurrence?,
  ) -> Result[Int, LocalDispatchIssue] {
    guard @execution.managed_output_value_row_wire_bound(
        receipt,
        result,
        output_wire.max_columns,
        output_wire.max_bytes,
      )
      is Some(bytes) else {
      return Err(Configuration(InvalidLimits))
    }
    let frame = Int::max(setup.imports.max_batch_bytes, bytes)
    guard @execution.execution_capacity_inventory_add(
        0L,
        CanonicalWireBytes,
        (frame - setup.imports.max_batch_bytes).to_int64(),
        1,
      )
      is Some(extra) else {
      return Err(Configuration(InvalidLimits))
    }
    match reserve_transport(extra) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    Ok(frame)
  }
  let numeric = local_task_numeric_execution(
    setup.run,
    execution,
    numeric_count,
  )
  let transfers = []
  let mut bridge_index = 0
  for read_index, input in relation_inputs {
    guard input is ManagedRelationInput(managed) else { continue }
    let handle = bridges[bridge_index]
    bridge_index += 1
    let copied_rows = Ref(0L)
    let copied_nodes = Ref(0L)
    let copied_text = Ref(0L)
    let copied_extent = Ref(0L)
    transfers.push(LocalManagedInputTransfer::{
      input: managed,
      append: row => {
        with_local_managed_import_mutation(import_mutating, fn() {
          guard handle.val is Some(bridge) &&
            local_managed_input_writes_open(live.val, settled.val, disposed.val) else {
            return Err(Configuration(InputUnavailable))
          }
          let bytes = match
            managed_row_transfer_bytes(row, setup.imports.wire.max_bytes) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          match
            @strategy.charge_task_execution_transfer(
              setup.run,
              execution,
              bytes,
            ) {
            Err(issue) => return Err(Execution(Physical(issue)))
            Ok(_) => ()
          }
          guard local_managed_import_next_extent(
              setup.imports,
              copied_rows.val,
              copied_nodes.val,
              copied_text.val,
              bytes,
            )
            is Some((rows, nodes, text, quoted)) else {
            return Err(Configuration(InvalidLimits))
          }
          // Shorter later rows need less transient parsing scratch. Keep
          // this same copy's reservation monotone, without refunding it.
          let extent = Int64::max(copied_extent.val, quoted)
          guard @execution.checked_preparation_add_product(
              import_extra.val,
              extent - copied_extent.val,
              1L,
            )
            is Some(next) else {
            return Err(Configuration(InvalidLimits))
          }
          match reserve_import(next, None) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          // A current callback may synchronously cancel and retire this exact
          // bridge. A successful grow cannot revive it or permit parsing.
          guard local_managed_input_writes_open(
              live.val,
              settled.val,
              disposed.val,
            ) &&
            handle.val is Some(current) &&
            physical_equal(current, bridge) else {
            return Err(Configuration(InputUnavailable))
          }
          copied_rows.val = rows
          copied_nodes.val = nodes
          copied_text.val = text
          copied_extent.val = extent
          match
            @execution.append_managed_producer_bridge_wire(
              bridge,
              row,
              setup.imports.row,
            ) {
            Err(_) => Err(Configuration(InputUnavailable))
            Ok(_) => {
              // The row's parser and worst-case copied DATA were funded before
              // decode. Completed admission already measured this same buffer;
              // a field-name byte must not remain a retained value node bound
              // on every later row. Keep the paid extent monotone above, and
              // preserve the conservative counters on any failed observation.
              guard @execution.managed_producer_bridge_import_usage(bridge)
                is Some(usage) &&
                usage.nodes >= 0 &&
                usage.nodes.to_int64() <= nodes &&
                usage.text_bytes >= 0 &&
                usage.text_bytes.to_int64() <= text else {
                return Err(Configuration(InputUnavailable))
              }
              copied_nodes.val = usage.nodes.to_int64()
              copied_text.val = usage.text_bytes.to_int64()
              Ok(())
            }
          }
        })
      },
      finish: fn() {
        guard handle.val is Some(bridge) &&
          local_managed_input_writes_open(live.val, settled.val, disposed.val) else {
          return Err(Configuration(InputUnavailable))
        }
        match
          @execution.finish_managed_producer_bridge(
            bridge,
            setup.metadata.bridge_entries,
            setup.metadata.name_bytes,
          ) {
          Ok(value) => {
            guard install_local_managed_input_read(
              reads, pending_reads, read_index, value,
            ) else {
              return Err(Configuration(InputUnavailable))
            }
            Ok(())
          }
          Err(_) => Err(Configuration(InputUnavailable))
        }
      },
    })
  }
  let retained_transfers : Array[LocalInputTransfer] = []
  for read_index, input in relation_inputs {
    guard input is OrdinaryRelationInput(read) &&
      !@execution.producer_read_has_cell_access(read) &&
      @execution.producer_read_retained_material(read) is Some(material) else {
      continue
    }
    let position = read_index
    let importer : Ref[@execution.CompletedOutputImport?] = Ref(None)
    // The existing per-port startup packet prepays these four monotone
    // counters and all refusal/current carriers before this closure escapes.
    let copied_rows = Ref(0L)
    let copied_nodes = Ref(0L)
    let copied_text = Ref(0L)
    let copied_extent = Ref(0L)
    retained_imports.push(importer)
    retained_transfers.push({
      material,
      input: read,
      frames: {
        maxBytes: setup.imports.wire.max_bytes,
        maxRows: setup.imports.max_rows,
        maxRowBytes: setup.imports.row.max_bytes,
        maxDepth: setup.imports.row.max_depth,
        maxFrameBytes: setup.imports.max_batch_bytes,
      },
      begin: fn() {
        guard local_managed_input_writes_open(
            live.val,
            settled.val,
            disposed.val,
          ) &&
          importer.val is None &&
          !import_mutating.val else {
          return Err(Configuration(InputUnavailable))
        }
        let prepared = match
          @execution.prepare_producer_output_import(
            read,
            setup.imports.max_rows,
            setup.imports.values,
            setup.imports.wire,
            setup.imports.max_batch_bytes,
            deferred_reclamation=true,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        importer.val = Some(prepared)
        Ok(())
      },
      charge: bytes => {
        @strategy.charge_task_execution_transfer(setup.run, execution, bytes).map_err(issue => {
            Execution(Physical(issue))
          },
        )
      },
      append: row => {
        with_local_managed_import_mutation(import_mutating, fn() {
          guard importer.val is Some(active) &&
            local_managed_input_writes_open(live.val, settled.val, disposed.val) else {
            return Err(Configuration(InputUnavailable))
          }
          let bytes = match
            managed_row_transfer_bytes(row, setup.imports.wire.max_bytes) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          guard local_managed_import_next_extent(
              setup.imports,
              copied_rows.val,
              copied_nodes.val,
              copied_text.val,
              bytes,
            )
            is Some((rows, nodes, text, quoted)) else {
            return Err(Configuration(InvalidLimits))
          }
          let extent = Int64::max(copied_extent.val, quoted)
          guard @execution.checked_preparation_add_product(
              import_extra.val,
              extent - copied_extent.val,
              1L,
            )
            is Some(next) else {
            return Err(Configuration(InvalidLimits))
          }
          match reserve_import(next, None) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          // Growth can synchronously cancel this SAME original importer.
          // Keep its paid prefix, but never parse after that current fence.
          guard local_managed_input_writes_open(
              live.val,
              settled.val,
              disposed.val,
            ) &&
            importer.val is Some(current) &&
            physical_equal(current, active) else {
            return Err(Configuration(InputUnavailable))
          }
          copied_rows.val = rows
          copied_nodes.val = nodes
          copied_text.val = text
          copied_extent.val = extent
          @execution.append_completed_output_import_wire(
            active,
            row,
            setup.imports.row,
          ).map_err(_ => Configuration(InputUnavailable))
        })
      },
      finish: fn() {
        guard !import_mutating.val &&
          importer.val is Some(active) &&
          local_managed_input_writes_open(live.val, settled.val, disposed.val) else {
          return Err(Configuration(InputUnavailable))
        }
        let output = match @execution.finish_completed_output_import(active) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        let rebound = match
          @execution.rebind_producer_representation(read, output) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        guard @execution.producer_read_has_cell_access(rebound) else {
          return Err(Configuration(InputUnavailable))
        }
        guard install_local_managed_input_read(
          reads, pending_reads, position, rebound,
        ) else {
          return Err(Configuration(InputUnavailable))
        }
        Ok(())
      },
    })
  }
  let output_target = @strategy.captured_task_target(setup.run, setup.task)
  let advance_once = fn(
    quantum : Int,
  ) -> Result[LocalManagedAdvance, LocalDispatchIssue] {
    if quantum <= 0 {
      return Err(Configuration(InvalidLimits))
    }
    if execution_finished.val {
      return Ok({
        complete: true,
        waiting: false,
        settlement: None,
        progress: 0L,
        work: 0L,
      })
    }
    if pending_reads.val != 0 {
      return Err(Configuration(InputUnavailable))
    }
    // Disposal prevents starting work, but an already-started bounded
    // provider must still receive one final advance after cancellation so it
    // can report an actual stop. Cleanup cannot substitute for that report.
    if (!live.val || disposed.val) && provider_execution.val is None {
      return Err(Configuration(InputUnavailable))
    }
    match setup.provider {
      Some(provider) => {
        let active = match provider_execution.val {
          Some(value) => value
          None => {
            let constrained = match
              @local.constrain_local_managed_sequence(
                setup.sequence,
                join_output_ceilings=setup.join_output_ceilings,
                interval_search_ceilings=setup.interval_search_ceilings,
                asof_search_ceilings=setup.asof_search_ceilings,
                sequence_match_ceilings=setup.sequence_match_ceilings,
                aggregate_output_ceilings=setup.aggregate_output_ceilings,
                analytic_envelopes=setup.analytic_envelopes,
                numeric~,
              ) {
              Ok(value) => value
              Err(issue) => {
                execution_finished.val = true
                return Err(Configuration(issue))
              }
            }
            guard local_task_constrain_expansion(
                setup.run,
                setup.task,
                constrained,
              )
              is Some(constrained) else {
              execution_finished.val = true
              return Err(Configuration(InvalidLimits))
            }
            guard local_task_constrain_traversal(
                setup.run,
                setup.task,
                constrained,
              )
              is Some(constrained) else {
              execution_finished.val = true
              return Err(Configuration(InputUnavailable))
            }
            guard local_task_constrain_calendar(
                setup.run,
                setup.task,
                constrained,
              )
              is Some(constrained) else {
              execution_finished.val = true
              return Err(Configuration(InputUnavailable))
            }
            match @strategy.begin_task_execution_use(setup.run, execution) {
              Err(issue) => return Err(Execution(Physical(issue)))
              Ok(_) => ()
            }
            // The original current callback can synchronously cancel. Its
            // return does not restore the prepared provider's live state.
            if !live.val || disposed.val {
              return Err(Configuration(InputUnavailable))
            }
            let constrained = match
              @execution.bind_generated_workspace_growth(
                constrained,
                setup.execution,
                @resources.ledger_admission_limits(
                  @strategy.captured_dag_ledger(setup.run),
                ).execution_bytes,
                reserve_working,
                meter_retained_outputs=setup.metered_output_retention,
                reserve_retained=if setup.metered_retention {
                  Some(reserve_capacity)
                } else {
                  None
                },
              ) {
              Ok(value) => {
                working_sequence.val = Some(value)
                value
              }
              Err(issue) => return Err(Configuration(Execution(issue)))
            }
            let started = match
              @local.start_managed_provider_with_inputs_and_execution(
                provider,
                constrained,
                setup.provider_inputs.map(input => {
                  match input {
                    PreparedRelation(index) =>
                      @local.managed_provider_relation_input(
                        reads[index].unwrap(),
                      )
                    PreparedSupplied(read) =>
                      @local.managed_provider_supplied_relation_input(read)
                    PreparedCarrier(view) =>
                      @local.managed_provider_carrier_input(view)
                  }
                }),
                @connector.managed_fixed_compute_request_capacity(request).max_rows,
                @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
                setup.execution,
                numeric~,
              ) {
              Ok(value) => value
              Err(issue) => {
                if working_failure.val is Some(original) {
                  return Err(original)
                }
                return Err(Configuration(issue))
              }
            }
            provider_execution.val = Some(started)
            started
          }
        }
        let poll = @local.advance_managed_provider(active, quantum)
        if working_failure.val is Some(original) {
          return Err(original)
        }
        if @local.managed_provider_cumulative_work(active) is Err(_) {
          live.val = false
          return Err(Configuration(InvalidLimits))
        }
        match poll {
          Err(issue) =>
            Err(
              local_managed_provider_failure_for_sequence(
                issue,
                setup.execution.max_work,
                setup.installation,
                setup.task,
                setup.sequence,
              ),
            )
          Ok(@local.Continue(progress~, work~)) =>
            if progress < 0L || work <= 0L || work > quantum.to_int64() {
              Err(Configuration(InvalidLimits))
            } else {
              Ok({
                complete: false,
                waiting: false,
                settlement: None,
                progress,
                work,
              })
            }
          Ok(@local.Waiting(progress~, work~)) =>
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              Err(Configuration(InvalidLimits))
            } else {
              Ok({
                complete: false,
                waiting: true,
                settlement: None,
                progress,
                work,
              })
            }
          Ok(@local.Settling(slot, progress~, work~)) =>
            if slot < 0 ||
              progress < 0L ||
              work < 0L ||
              work > quantum.to_int64() {
              Err(Configuration(InvalidLimits))
            } else {
              Ok({
                complete: false,
                waiting: false,
                settlement: Some(slot),
                progress,
                work,
              })
            }
          Ok(@local.Complete(output, progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            // As after synchronous computation, every selected numeric
            // reduction slot of the task must be sealed before publication.
            if numeric_count > 0 &&
              !@strategy.seal_task_numeric_reductions(setup.run, execution) {
              execution_finished.val = true
              return Err(Execution(ForeignCandidate))
            }
            ordinary.val = Some(output)
            execution_finished.val = true
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            Ok({
              complete: true,
              waiting: false,
              settlement: None,
              progress,
              work,
            })
          }
          Ok(@local.CarrierComplete(material, progress~, work~)) => {
            if progress < 0L ||
              work < 0L ||
              work > quantum.to_int64() ||
              !@carrier_runtime.material_available(material) {
              return Err(Configuration(InvalidLimits))
            }
            carrier.val = Some(material)
            execution_finished.val = true
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            Ok({
              complete: true,
              waiting: false,
              settlement: None,
              progress,
              work,
            })
          }
          Ok(@local.Failed(issue, progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            // Preserve the original running task's primary computation failure,
            // as in the materializing lane. Stop and cleanup remain separate.
            @strategy.fail_task_execution(setup.run, execution, Compute(issue))
            |> ignore
            execution_finished.val = true
            Err(
              local_managed_provider_failure_for_sequence(
                issue,
                setup.execution.max_work,
                setup.installation,
                setup.task,
                setup.sequence,
              ),
            )
          }
          Ok(@local.Stopped(progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            execution_finished.val = true
            Err(Execution(Stopped))
          }
        }
      }
      // Unreachable: preparation declines providerless sequences.
      None => {
        execution_finished.val = true
        Err(Configuration(ComputeUnsupported))
      }
    }
  }
  let advance = fn(
    quantum : Int,
  ) -> Result[LocalManagedAdvance, LocalDispatchIssue] {
    if execution_failure.val is Some(issue) {
      return Err(issue)
    }
    if execution_finished.val && ordinary.val is None && carrier.val is None {
      return Err(Configuration(InputUnavailable))
    }
    let result = advance_once(quantum)
    if result is Err(issue) && execution_finished.val {
      execution_failure.val = Some(issue)
    }
    result
  }
  let operations : LocalManagedDispatchOperations[T] = {
    inputs: transfers,
    retained_inputs: retained_transfers,
    execute: fn() {
      if execution_failure.val is Some(issue) {
        return Err(issue)
      }
      while !execution_finished.val {
        match advance(1024) {
          Ok(observation) =>
            if observation.waiting || observation.settlement is Some(_) {
              // A synchronous caller cannot supply asynchronous custody.
              // Leave the owner available to a bounded Host or explicit stop.
              return Err(Configuration(InputUnavailable))
            }
          Err(issue) => return Err(issue)
        }
      }
      if ordinary.val is None && carrier.val is None {
        return Err(Configuration(InputUnavailable))
      }
      Ok(())
    },
    advance,
    cumulative_provider_work: fn() {
      match provider_execution.val {
        Some(active) => @local.managed_provider_cumulative_work(active)
        None => final_provider_work.val
      }
    },
    request_cancel: fn() {
      let changed = live.val
      live.val = false
      cancel_finalization()
      @strategy.close_task_execution(setup.run, execution)
      changed
    },
    execution_stopped: fn() {
      let compute_stopped = match provider_execution.val {
        Some(active) => @local.managed_provider_stopped(active)
        None => execution_finished.val || !live.val
      }
      compute_stopped &&
      (
        !finalization_started.val ||
        finalization_ready.val ||
        finalization_cancelled.val
      )
    },
    prepare_finalization: fn(payload, storage_bytes, available) {
      if finalization_started.val ||
        !execution_finished.val ||
        !snapshot_ready.val ||
        finalization_cancelled.val {
        return Err(Configuration(InvalidLimits))
      }
      guard ordinary.val is Some(_) &&
        output_target is Some(target) &&
        storage_bytes == setup.capacity.retained_bytes &&
        available() else {
        return Err(Configuration(InvalidLimits))
      }

      let values = match
        @execution.prepare_managed_output_values(
          @connector.managed_fixed_compute_request_owner(request),
          target,
          @connector.managed_fixed_compute_request_capacity(request).max_rows,
          setup.execution.rows.output_values,
          @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
          setup.measurement,
          working=if setup.metered_retention {
            working_sequence.val
          } else {
            None
          },
          completed_projection=ordinary.val,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedValues(issue))
      }
      let retention = match
        @execution.prepare_managed_output_retention_port(values, fn(
          proof : (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
        ) {
          let (receipt, proof_payload, bytes, proof_available) = proof
          if finalization_receipt.val is Some(expected) &&
            physical_equal(receipt, expected) &&
            finalization_storage.val == Some(bytes) &&
            proof_available() &&
            available() {
            Some((receipt, proof_payload, bytes, proof_available))
          } else {
            None
          }
        }) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InvalidLimits))
      }
      finalization_payload.val = Some(payload)
      finalization_available.val = Some(available)
      finalization_values.val = Some(values)
      finalization_retention.val = Some(retention)
      finalization_started.val = true
      Ok(())
    },
    advance_finalization: fn(quantum) {
      if quantum <= 0 ||
        !finalization_started.val ||
        finalization_ready.val ||
        finalization_cancelled.val {
        return Err(Configuration(InvalidLimits))
      }
      guard ordinary.val is Some(output) &&
        output_target is Some(target) &&
        finalization_values.val is Some(values) &&
        finalization_available.val is Some(available) else {
        return Err(Configuration(InvalidLimits))
      }
      let mut work = 0
      let rows = @execution.completed_row_count(output)
      while work < quantum && finalization_row.val < rows {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let row = finalization_row.val
        match
          @execution.append_completed_projection_managed_values(
            values, output, row,
          ) {
          Ok(_) => ()
          Err(@execution.Admission(@execution.InvalidCheckedRow)) =>
            match
              @execution.append_completed_projection_managed_wire(
                values,
                output,
                row,
                setup.imports.wire,
                setup.imports.row,
              ) {
              Ok(_) => ()
              Err(issue) => return Err(ManagedValues(issue))
            }
          Err(issue) => return Err(ManagedValues(issue))
        }
        finalization_row.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      if finalization_receipt.val is None {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let poll = match
          @execution.advance_managed_output_values_finish(
            values,
            Int::min(quantum - work, finalization_work_remaining.val),
          ) {
          Ok(value) => value
          // The finished output exceeds its value limits: keep the cause.
          Err(issue) => return Err(ManagedValues(issue))
        }
        finalization_work_remaining.val -= poll.steps
        finalization_receipt_steps.val += poll.steps.to_int64()
        work += poll.steps
        finalization_receipt.val = poll.receipt
        if poll.receipt is None || work == quantum {
          return Ok({
            complete: false,
            waiting: false,
            settlement: None,
            progress: finalization_progress(),
            work: work.to_int64(),
          })
        }
      }
      if output_row_extent.val is None {
        guard finalization_receipt.val is Some(receipt) else {
          return Err(Configuration(InvalidLimits))
        }
        let extent = match export_frame_extent(receipt, None) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        output_row_extent.val = Some(
          Int::max(setup.imports.row.max_bytes, extent),
        )
      }
      if finalization_storage.val is None {
        guard finalization_receipt.val is Some(receipt) else {
          return Err(Configuration(InvalidLimits))
        }
        let data = if setup.metered_retention {
          let usage = @execution.managed_output_value_usage(receipt)
          guard @execution.execution_capacity_inventory_bytes([
              {
                unit: ValueNodeSlots,
                count: usage.nodes.to_int64(),
                copies: 1,
              },
              {
                unit: DecodedTextBytes,
                count: usage.text_bytes.to_int64(),
                copies: 1,
              },
            ])
            is Some(data) &&
            data <= retained_extra.val else {
            return Err(Configuration(InvalidLimits))
          }
          data
        } else {
          0L
        }
        guard data <= 9223372036854775807L - setup.capacity.retained_bytes else {
          return Err(Configuration(InvalidLimits))
        }
        finalization_storage.val = Some(setup.capacity.retained_bytes + data)
      }
      if finalization_material.val is None {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        guard finalization_receipt.val is Some(receipt) else {
          return Err(Configuration(InvalidLimits))
        }
        guard finalization_payload.val is Some(payload) else {
          return Err(Configuration(InvalidLimits))
        }
        guard finalization_retention.val is Some(retention) else {
          return Err(Configuration(InvalidLimits))
        }
        let material = match
          @execution.retain_managed_output(
            retention,
            (receipt, payload, finalization_storage.val.unwrap(), available),
          ) {
          Ok(value) => value
          Err(issue) => return Err(ManagedRetention(issue))
        }
        finalization_material.val = Some(material)
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      while work < quantum &&
            finalization_identity.val < identity_requirements.length() {
        let index = finalization_identity.val
        let requirement = identity_requirements[index]
        if finalization_stream.val is None {
          match
            (requirement.domain, requirement.subject, requirement.occurrence) {
            (@execution.OrderedRows, @execution.TaskOutput, None) => {
              guard finalization_receipt.val is Some(receipt) else {
                return Err(Configuration(InvalidLimits))
              }
              let frame = match export_frame_extent(receipt, None) {
                Ok(value) => value
                Err(issue) => return Err(issue)
              }
              let stream = match
                @execution.prepare_completed_output_export(
                  output, output_max_rows, output_values, output_wire, frame,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_stream.val = Some(stream)
            }
            (@execution.LogicalRelation, @execution.NamedResult, Some(result)) => {
              if finalization_result_preparation.val is None {
                // Only a Named Result constructs these row indices. Other
                // task identities do not reserve an unused Result workspace.
                if !finalization_metadata_grown.val {
                  if setup.metadata.result_rows_reserved is Some(initial) {
                    let rows = @execution.completed_row_count(output)
                    if rows < 0 || rows > output_max_rows {
                      return Err(Configuration(InvalidLimits))
                    }
                    let extra_rows = Int::max(0, rows - initial)
                    // Result projection and stable ordering own two index arrays. This is
                    // their existing logical cursor-root allowance, not measured heap/RSS.
                    guard @execution.execution_capacity_inventory_add(
                        0L,
                        CursorRootSlots,
                        extra_rows.to_int64(),
                        2,
                      )
                      is Some(scratch) else {
                      return Err(Configuration(InvalidLimits))
                    }
                    if extra_rows > 0 {
                      guard @execution.execution_capacity_inventory_add(
                          setup.capacity.scratch_bytes +
                          working_extra.val +
                          transport_extra.val +
                          import_extra.val,
                          QuotedBytes,
                          scratch,
                          1,
                        )
                        is Some(total_scratch) else {
                        return Err(Configuration(InvalidLimits))
                      }
                      match
                        @strategy.grow_task_execution_workspace(
                          setup.run,
                          execution,
                          total_scratch,
                        ) {
                        Ok(_) => ()
                        Err(issue) => return Err(Execution(Physical(issue)))
                      }
                      metadata_extra.val = scratch
                      if !live.val || disposed.val || !available() {
                        return Err(Execution(Stopped))
                      }
                    }
                  }
                  finalization_metadata_grown.val = true
                }
                guard finalization_receipt.val is Some(receipt) else {
                  return Err(Configuration(InvalidLimits))
                }
                let frame = match export_frame_extent(receipt, Some(result)) {
                  Ok(value) => value
                  Err(issue) => return Err(issue)
                }
                let preparation = match
                  @execution.start_completed_result_relation_export(
                    output,
                    result,
                    {
                      max_fields: output_wire.max_columns,
                      max_mapping_work: output_wire.max_order_work,
                      max_order_work: setup.execution.max_work,
                      max_workspace_entries: setup.metadata.result_workspace_entries,
                    },
                    output_max_rows,
                    output_values,
                    output_wire,
                    output_wire,
                    setup.metadata.schema,
                    frame,
                  ) {
                  Ok(value) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                finalization_result_preparation.val = Some(preparation)
              }
              let preparation = finalization_result_preparation.val.unwrap()
              let remaining = Int::min(
                quantum - work,
                finalization_work_remaining.val,
              )
              if remaining < 1 {
                return Err(Configuration(InvalidLimits))
              }
              let (ready, used) = match
                @execution.advance_completed_result_relation_export(
                  preparation, remaining,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_work_remaining.val -= used
              work += used
              if !ready {
                return Ok({
                  complete: false,
                  waiting: false,
                  settlement: None,
                  progress: finalization_progress(),
                  work: work.to_int64(),
                })
              }
              let stream = match
                @execution.finish_completed_result_relation_export_preparation(
                  preparation,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_result_preparation.val = None
              finalization_stream.val = Some(stream)
            }
            _ => return Err(Configuration(LogicalIdentityUnsupported))
          }
        }
        guard finalization_stream.val is Some(stream) else {
          return Err(Configuration(LogicalIdentityUnsupported))
        }
        if work == quantum {
          break
        }
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        match @execution.next_completed_output_export(stream) {
          Ok(Some(_)) => {
            finalization_work_remaining.val -= 1
            work += 1
          }
          Ok(None) => {
            let cid = match requirement.domain {
              @execution.OrderedRows => {
                let receipt = match
                  @execution.finish_completed_output_export(stream) {
                  Ok((value, _)) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                let identity = @execution.output_stream_identity(
                    @execution.completed_export_content(receipt),
                  ).0
                @execution.cancel_completed_export_receipt(receipt)
                identity
              }
              @execution.LogicalRelation => {
                let receipt = match
                  @execution.finish_completed_relation_export(stream) {
                  Ok((value, _)) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                let identity = @execution.logical_relation_cid(
                  @execution.completed_relation_export_identity(receipt),
                )
                @execution.cancel_completed_relation_export_receipt(receipt)
                identity
              }
              _ => return Err(Configuration(LogicalIdentityUnsupported))
            }
            finalization_cids[index] = Some(cid)
            finalization_stream.val = None
            finalization_identity.val += 1
            finalization_work_remaining.val -= 1
            work += 1
          }
          Err(issue) => return Err(IdentityExport(issue))
        }
      }
      if finalization_identity.val < identity_requirements.length() {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      guard finalization_material.val is Some(material) else {
        return Err(Configuration(InvalidLimits))
      }
      while work < quantum &&
            finalization_issuer.val < identity_requirements.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let index = finalization_issuer.val
        let requirement = identity_requirements[index]
        let canonical_contract_cid = match requirement.domain {
          @execution.OrderedRows =>
            @execution.ordered_rows_canonical_contract_cid()
          @execution.LogicalRelation =>
            @execution.logical_relation_canonical_contract_cid()
          _ => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let capability = match
          @execution.register_managed_identity_issuance_capability(
            requirement.domain,
            requirement.subject,
            requirement.occurrence,
            canonical_contract_cid,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let permit = match
          @execution.authorize_managed_identity_execution_attempt(
            capability, execution_attempt, finalization_completion_preparation, requirement,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let cid = finalization_cids[index]
        let issuer = match
          @execution.try_bind_managed_identity_issuer(permit, material, fn(
            source,
          ) {
            if physical_equal(source, material) && available() {
              cid
            } else {
              None
            }
          }) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_issuers.push(issuer)
        finalization_issuer.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_issuer.val < identity_requirements.length() ||
        work == quantum {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      if finalization_completed.val is None {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let completion = match
          @execution.prepare_managed_completion_port(
            @execution.selected_managed_execution_profile(),
            finalization_completion_preparation,
            target,
            setup.metadata.completion_entries,
            setup.metadata.name_bytes,
            fn(candidate : @execution.ManagedRetainedOutput[T]) {
              if physical_equal(candidate, material) {
                Some(material)
              } else {
                None
              }
            },
            common_inputs=setup.completion_inputs,
            obligations~,
            identity_issuers=finalization_issuers,
            attempt=execution_attempt,
          ) {
          Ok(value) => value
          Err(issue) => return Err(ManagedCompletion(issue))
        }
        let completed = match
          @execution.complete_managed_output(completion, material) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InvalidLimits))
        }
        finalization_completed.val = Some(completed)
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      guard finalization_completed.val is Some(completed) else {
        return Err(Configuration(InvalidLimits))
      }
      while work < quantum &&
            finalization_established.val < identity_requirements.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let requirement = identity_requirements[finalization_established.val]
        match
          @execution.establish_managed_completed_identity_requirement(
            completed, requirement,
          ) {
          Ok(_) => ()
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_established.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_established.val < identity_requirements.length() ||
        work == quantum {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      let deadlines = [
        @execution.BeforeCidOperation,
        @execution.BeforePublication,
        @execution.BeforeDiscard,
      ]
      while work < quantum && finalization_deadline.val < deadlines.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let deadline = deadlines[finalization_deadline.val]
        if !@execution.managed_completed_deadline_satisfied(completed, deadline) {
          return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_deadline.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_deadline.val < deadlines.length() {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      // The receipt/material now own their immutable copies and transferred
      // index. Retire only the admission buffer before reporting ready; the
      // driver/provider/input roots still wait for the existing settled hook.
      // This shares the original bounded finalization continuation and never
      // releases reservation capacity before the ordinary scratch witness.
      // Cleanup is mandatory original-owner retirement, not semantic work:
      // it remains legal after semantic max_work exhaustion. Actual finite
      // owned entries bound total retirement; this poll reports its steps
      // within quantum without debiting finalization_work_remaining.
      @execution.request_managed_output_values_disposal(values)
      let before = @execution.managed_output_values_reclamation_steps(values)
      let reclaimed = @execution.advance_managed_output_values_reclamation(
        values,
        quantum - work,
      )
      let after = @execution.managed_output_values_reclamation_steps(values)
      finalization_reclamation_steps.val = after
      work += (after - before).to_int()
      if !reclaimed ||
        !@execution.managed_output_values_scratch_released(values) {
        return Ok({
          complete: false,
          waiting: false,
          settlement: None,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      finalization_ready.val = true
      Ok({
        complete: true,
        waiting: false,
        settlement: None,
        progress: finalization_progress(),
        work: work.to_int64(),
      })
    },
    settle: fn() {
      let failed_or_stopped = !live.val ||
        (execution_finished.val && ordinary.val is None && carrier.val is None)
      let relation_pending = ordinary.val is Some(_) &&
        !finalization_ready.val &&
        !finalization_cancelled.val &&
        !failed_or_stopped
      if relation_pending ||
        (!failed_or_stopped && carrier.val is Some(_) && !snapshot_ready.val) {
        return Err(Configuration(InvalidLimits))
      }
      @strategy.settle_task_execution(setup.run, execution, true).map_err(issue => {
        Execution(Physical(issue))
      })
    },
    complete: fn(payload, storage_bytes, available) {
      guard finalization_ready.val &&
        finalization_payload.val is Some(expected_payload) &&
        physical_equal(payload, expected_payload) &&
        storage_bytes == setup.capacity.retained_bytes &&
        finalization_available.val is Some(expected_available) &&
        expected_available() &&
        available() &&
        finalization_material.val is Some(material) &&
        finalization_completed.val is Some(completed) else {
        return Err(Configuration(InvalidLimits))
      }
      let allocation = match
        @strategy.retain_task_execution_allocation(
          setup.run,
          execution,
          finalization_storage.val.unwrap(),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      match
        @strategy.complete_managed_task_execution_with_inputs(
          setup.run,
          execution,
          completed,
          allocation~,
          managed_inputs=setup.completion_inputs,
        ) {
        Err(issue) => {
          @strategy.release_task_execution_allocation(allocation) |> ignore
          Err(Execution(issue))
        }
        Ok(_) => {
          retained.val = Some(material)
          Ok(completed)
        }
      }
    },
    complete_carrier: fn() {
      guard execution_finished.val &&
        ordinary.val is None &&
        carrier.val is Some(material) &&
        carrier_completed.val is None &&
        snapshot_ready.val &&
        output_target is Some(target) &&
        @carrier_runtime.material_available(material) &&
        @carrier_runtime.material_storage_bytes(material) is Some(storage_bytes) &&
        storage_bytes >= 0L &&
        storage_bytes <= setup.capacity.retained_bytes &&
        !@execution.managed_obligations_require_logical_identity(obligations) else {
        return Err(Configuration(InvalidLimits))
      }
      let common_inputs = setup.completion_inputs
      let reference = @carrier_runtime.material_reference(material)
      let completion = match
        @execution.prepare_carrier_managed_completion_port_with_inputs(
          @execution.selected_managed_execution_profile(),
          @execution.generated_completion_preparation(setup.sequence),
          target,
          setup.metadata.completion_entries,
          setup.metadata.name_bytes,
          (_ : Unit) => {
            if @carrier_runtime.material_available(material) {
              Some(reference)
            } else {
              None
            }
          },
          inputs=common_inputs,
          obligations~,
          attempt=execution_attempt,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCompletion(issue))
      }
      let completed = match
        @execution.complete_carrier_managed_output(completion, ()) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCompletion(issue))
      }
      let allocation = match
        @strategy.retain_task_execution_allocation(
          setup.run,
          execution,
          storage_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      match
        @strategy.complete_carrier_managed_task_execution_with_inputs(
          setup.run,
          execution,
          completed,
          allocation~,
          managed_inputs=common_inputs,
        ) {
        Err(issue) => {
          @strategy.release_task_execution_allocation(allocation) |> ignore
          Err(Execution(issue))
        }
        Ok(_) => {
          carrier_completed.val = Some(completed)
          Ok(completed)
        }
      }
    },
    output_rows: fn() {
      ordinary.val.map(@execution.completed_row_count).unwrap_or(0)
    },
    output_row: fn(row) {
      guard ordinary.val is Some(output) else {
        return Err(Configuration(InputUnavailable))
      }
      // Before finalization, preserve the original funded small transport.
      // A larger read needs the measured extent funded before settlement.
      let extent = output_row_extent.val.unwrap_or(setup.imports.row.max_bytes)
      let read = match output_row_reader.val {
        Some((original, read)) => {
          if !physical_equal(original, output) {
            return Err(Configuration(InputUnavailable))
          }
          read
        }
        None => {
          // Reuse only the separately held export-metadata envelope, not the
          // producer scratch that may already be retired. Its existing quote
          // keeps 24 column roots and 64 controls per reader; the prepared
          // order/positions borrow names and fit alongside snapshot metadata.
          // Legacy/custom policies without that retained extent keep the
          // original per-call transport and retain no additional column state.
          let width = @execution.completed_column_count(output)
          let reader_metadata = @execution.execution_capacity_inventory_bytes([
            { unit: CursorRootSlots, count: 64L, copies: 1, },
            { unit: CursorRootSlots, count: width.to_int64(), copies: 24, },
          ])
          if width < 0 ||
            width > setup.metadata.schema.max_fields ||
            reader_metadata is None ||
            reader_metadata.unwrap() > setup.metadata.retained_bytes {
            return @execution.completed_output_row_wire(
              output,
              row,
              extent,
              setup.imports.row.max_nodes,
              setup.imports.row.max_depth,
            ).map_err(_ => Configuration(InputUnavailable))
          }
          let read = match
            @execution.prepare_completed_output_row_wire_reader(
              output,
              setup.imports.row.max_nodes,
              setup.imports.row.max_depth,
            ) {
            Ok(read) => read
            Err(_) => return Err(Configuration(InputUnavailable))
          }
          // Availability callbacks may have retired the original aliases.
          // Never install a prepared reader after that retirement completed.
          guard ordinary.val is Some(current) && physical_equal(current, output) else {
            return Err(Configuration(InputUnavailable))
          }
          output_row_reader.val = Some((output, read))
          read
        }
      }
      read(row, extent).map_err(_ => Configuration(InputUnavailable))
    },
    material: fn() { retained.val },
    carrier_material: fn() { carrier.val },
    prepare_relation_snapshot: fn(storage_released) {
      // Retain checked Graph row bridges, sparse selections, derived and
      // grouped rows, Delta rows, and node traversals. Operation keys come from the
      // checked owner, not caller-supplied names.
      let prepared = @lower.bound_preparation(
        @execution.generated_sequence_owner(setup.sequence),
      )
      let mut graph_rows = false
      for
        position in 0..<@execution.generated_sequence_step_count(setup.sequence) {
        if @execution.generated_sequence_step_index_at(setup.sequence, position).bind(index => {
              @lower.node_at(prepared, index)
            },
          )
          is Some(node) {
          let key = @lower.operation(node)
          if key == "BRIDGE.graph.to_node_rows" ||
            key == "BRIDGE.graph.to_edge_rows" {
            graph_rows = true
          } else if key == "REL.derive" ||
            key == "REL.distinct" ||
            key == "REL.groupBy" ||
            key == "SGA.diff" {
            graph_rows = true
          } else if (
              key == "REL.where" ||
              key == "REL.orderByStable" ||
              key == "REL.limit"
            ) &&
            @lower.preparation_schema_at(
              prepared,
              @pipeline.Step(
                @execution.generated_sequence_step_index_at(
                  setup.sequence,
                  position,
                ).unwrap(),
              ),
            )
            is Some(schema) &&
            !@schema.all_fields_required(schema) {
            graph_rows = true
          } else if @lower.sequence_step(
              @execution.generated_prepared_sequence(setup.sequence),
              @execution.generated_sequence_step_index_at(
                setup.sequence,
                position,
              ).unwrap(),
            )
            is Some(@lower.GraphTraverseStep(traverse)) &&
            (
              !@lower.graph_traverse_emits_paths(traverse) ||
              @lower.graph_traverse_shortest(traverse) is Some(_)
            ) {
            // Shortest's typed path columns are completed Relation values;
            // persist/reload them through the existing snapshot owner too.
            graph_rows = true
          }
        }
      }
      if !retained_relation && !graph_rows {
        return Ok(None)
      }
      guard live.val &&
        execution_finished.val &&
        execution_failure.val is None &&
        !snapshot_attempted.val &&
        !finalization_started.val &&
        ordinary.val is Some(output) &&
        carrier.val is None &&
        provider_execution.val is Some(active) else {
        return Err(Configuration(InvalidLimits))
      }
      // An actual-output task's startup quote is not a whole-snapshot wire
      // ceiling. The original finite wire policy remains authoritative; each
      // emitted body/frame is funded below on this same Task before transfer.
      let maximum_bytes = if setup.metered_retention {
        setup.imports.wire.max_bytes
      } else {
        Int::min(
          setup.imports.wire.max_bytes,
          if setup.capacity.retained_bytes > 2147483647L {
            2147483647
          } else {
            setup.capacity.retained_bytes.to_int()
          },
        )
      }
      if maximum_bytes < 2 {
        return Err(Configuration(InvalidLimits))
      }
      let wire = { ..setup.imports.wire, max_bytes: maximum_bytes, }
      let frames : LocalInputFrames = {
        maxBytes: maximum_bytes,
        maxRows: setup.imports.max_rows,
        maxRowBytes: setup.imports.row.max_bytes,
        maxDepth: setup.imports.row.max_depth,
        maxFrameBytes: Int::min(maximum_bytes, setup.imports.max_batch_bytes),
      }
      let exporting = match
        @execution.prepare_completed_output_export(
          output,
          setup.imports.max_rows,
          setup.imports.values,
          wire,
          frames.maxFrameBytes,
        ) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InputUnavailable))
      }
      let stream = Ref(Some(exporting))
      let receipt : Ref[@execution.CompletedOutputExportReceipt?] = Ref(None)
      let stored : Ref[@execution.CompletedOutput?] = Ref(None)
      let importing : Ref[@execution.CompletedOutputImport?] = Ref(None)
      // Reuse the input-stop cursor for a cancelled snapshot reload. The
      // private importer must survive its closure's cancellation callback.
      retained_imports.push(importing)
      let restored : Ref[@execution.CompletedOutput?] = Ref(None)
      let phase = Ref(SnapshotPhase::Saving)
      // Preserve any earlier transport prefix through this snapshot. Only
      // its later, completed exporter delta can be reused after physical ACK.
      let snapshot_transport_prefix = transport_extra.val
      let emitted_bytes = Ref(0L)
      let reload_capacity : Ref[Int64?] = Ref(None)
      let reload_scalar_text : Ref[Int64?] = Ref(None)
      let fund_part = fn(part : String) -> Result[Unit, LocalDispatchIssue] {
        let bytes = match
          managed_row_transfer_bytes(part, frames.maxFrameBytes) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if bytes > maximum_bytes.to_int64() - emitted_bytes.val {
          return Err(Configuration(InputUnavailable))
        }
        let total = emitted_bytes.val + bytes
        if setup.metered_retention {
          // Construction was already funded at the measured-row boundary.
          // Validate that actual outgoing aliases fit that retained quote;
          // never grow after constructing, nor retain an old peak frame as
          // a new demand for a later tiny frame/tail.
          guard @execution.execution_capacity_inventory_add(
              0L,
              CanonicalWireBytes,
              emitted_bytes.val + 3L * bytes,
              1,
            )
            is Some(quoted) &&
            quoted <= transport_extra.val else {
            return Err(Configuration(InvalidLimits))
          }
        }
        if !live.val || phase.val != Saving {
          return Err(Execution(Stopped))
        }
        emitted_bytes.val = total
        Ok(())
      }
      let remaining = Ref(0L)
      match @local.managed_provider_cumulative_work(active) {
        Ok(work) if work >= 0L && work <= setup.execution.max_work.to_int64() =>
          remaining.val = setup.execution.max_work.to_int64() - work
        _ => return Err(Configuration(InvalidLimits))
      }
      let save_output : Ref[String?] = Ref(None)
      let save_work = Ref(0L)
      let save_issue : Ref[LocalDispatchIssue?] = Ref(None)
      let fund_batch_growth = fn(
        pending : Int,
      ) -> Result[Bool, @execution.CompletedExportIssue] {
        if !live.val || phase.val != Saving || pending < 0 {
          save_issue.val = Some(Execution(Stopped))
          return Err(Closed)
        }
        if !setup.metered_retention {
          return Ok(true)
        }
        // Actual saved bytes and this measured row/batch may overlap with its
        // builder, drained String and Store Buffer. No future frame prequote.
        guard @execution.execution_capacity_inventory_add(
            0L,
            CanonicalWireBytes,
            emitted_bytes.val + 3L * pending.to_int64(),
            1,
          )
          is Some(quoted) else {
          save_issue.val = Some(Configuration(InvalidLimits))
          return Err(Admission(InvalidCaptureLimits))
        }
        if quoted > transport_extra.val {
          let ledger = @strategy.captured_dag_ledger(setup.run)
          let limits = @resources.ledger_admission_limits(ledger)
          let usage = @resources.ledger_usage(ledger)
          if quoted - transport_extra.val >
            limits.execution_bytes - usage.reserved_execution_bytes {
            save_issue.val = Some(Execution(Physical(ExecutionLimit)))
            return Ok(false)
          }
        }
        match reserve_transport(quoted) {
          Err(issue) => {
            // Growth may already have acquired partial physical backing.
            // Never reinterpret this failure as permission to flush/retry.
            save_issue.val = Some(issue)
            Err(Admission(CaptureLimit))
          }
          Ok(_) =>
            if !live.val || phase.val != Saving {
              save_issue.val = Some(Execution(Stopped))
              Err(Unavailable)
            } else {
              Ok(true)
            }
        }
      }
      // The same existing final receipt and exact tail still require the
      // physical Store's later write/seal acknowledgement.
      let finish_save = fn(
        value : @execution.CompletedOutputExport,
      ) -> Result[String, LocalDispatchIssue] {
        // Empty output has not drained its initial '['; finish emits '[]'.
        // A nonempty traversal already drained its rows and emits only ']'.
        // Fund the exact pending tail before the writer constructs it.
        let tail_bytes = if emitted_bytes.val == 0L { 2 } else { 1 }
        match fund_batch_growth(tail_bytes) {
          Ok(true) => ()
          _ =>
            return Err(save_issue.val.unwrap_or(Configuration(InvalidLimits)))
        }
        let (finished, tail) = match
          @execution.finish_completed_output_export(value) {
          Ok(result) => result
          Err(issue) => return Err(IdentityExport(issue))
        }
        receipt.val = Some(finished)
        stream.val = None
        match fund_part(tail) {
          Ok(_) => ()
          Err(issue) => {
            phase.val = Failed
            if execution_failure.val is None {
              execution_failure.val = Some(issue)
            }
            return Err(issue)
          }
        }
        let content = @execution.completed_export_content(finished)
        reload_capacity.val = local_relation_snapshot_reload_capacity(
          setup.imports,
          content,
        )
        let imported_values = @execution.output_stream_value_usage(content)
        reload_scalar_text.val = @execution.checked_preparation_add_product(
          0L,
          Int::min(setup.imports.row.max_text_bytes, imported_values.text_bytes).to_int64(),
          8L,
        )
        if !live.val ||
          phase.val != Saving ||
          !(receipt.val is Some(actual) && physical_equal(actual, finished)) {
          return Err(Execution(Stopped))
        }
        phase.val = Saved
        Ok(tail)
      }
      let workspace_slots = match
        @execution.completed_output_export_workspace_slots(
          setup.imports.values,
          wire,
        ) {
        Some(value) => value
        None => return Err(Configuration(InvalidLimits))
      }
      let advance_save = fn(
        quantum : Int,
      ) -> Result[LocalManagedAdvance, LocalDispatchIssue] {
        with_local_managed_import_mutation(import_mutating, fn() {
          if !live.val ||
            execution_failure.val is Some(_) ||
            quantum <= 0 ||
            quantum > 32 ||
            save_output.val is Some(_) {
            return Err(Configuration(InvalidLimits))
          }
          if phase.val == Saved {
            return Ok({
              complete: true,
              waiting: false,
              settlement: None,
              progress: emitted_bytes.val,
              work: 0L,
            })
          }
          guard phase.val == Saving && stream.val is Some(value) else {
            return Err(Configuration(InvalidLimits))
          }
          save_issue.val = None
          if remaining.val < 1L {
            match @execution.completed_output_export_rows_complete(value) {
              Ok(true) => ()
              result => {
                let issue = match result {
                  Err(cause) => IdentityExport(cause)
                  _ => ControlWorkLimit(setup.execution.max_work)
                }
                execution_failure.val = Some(issue)
                phase.val = Failed
                return Err(issue)
              }
            }
          }
          // The same mutation scope excludes another save/reload/finalization
          // debit. Authorize only this finite allowance before entering poll.
          let allowed = Int::max(
            1,
            Int64::min(remaining.val, quantum.to_int64()).to_int(),
          )
          let polled = @execution.advance_completed_output_export(
            value,
            allowed,
            workspace_slots,
            batch=true,
            before_batch_growth=Some(fund_batch_growth),
          )
          // LAST-poll observation survives cancellation and encoder failure.
          // The existing provider accounting owner remains writable after
          // cleanup; unused authorized allowance is neither spent nor refunded.
          let spent = @execution.completed_output_export_poll_steps(value)
          if spent < 0 || spent > allowed || spent.to_int64() > remaining.val {
            @local.managed_provider_record_handoff_work(active, -1L) |> ignore
            let issue = Configuration(InvalidLimits)
            execution_failure.val = Some(issue)
            phase.val = Failed
            return Err(issue)
          }
          match
            @local.managed_provider_record_handoff_work(
              active,
              spent.to_int64(),
            ) {
            Err(_) => {
              let issue = Configuration(InvalidLimits)
              execution_failure.val = Some(issue)
              phase.val = Failed
              return Err(issue)
            }
            Ok(_) => ()
          }
          remaining.val -= spent.to_int64()
          save_work.val += spent.to_int64()
          let observation = match polled {
            Ok(value) => value
            Err(issue) => {
              let failure = save_issue.val.unwrap_or(IdentityExport(issue))
              execution_failure.val = Some(failure)
              phase.val = Failed
              return Err(failure)
            }
          }
          if observation.batch is Some(part) {
            match fund_part(part) {
              Err(issue) => {
                execution_failure.val = Some(issue)
                phase.val = Failed
                return Err(issue)
              }
              Ok(_) => save_output.val = Some(part)
            }
          }
          if observation.complete {
            let tail = match finish_save(value) {
              Ok(value) => value
              Err(issue) => {
                execution_failure.val = Some(issue)
                phase.val = Failed
                return Err(issue)
              }
            }
            save_output.val = Some(tail)
          }
          Ok({
            complete: observation.complete,
            waiting: false,
            settlement: None,
            progress: emitted_bytes.val,
            work: spent.to_int64(),
          })
        })
      }
      let debit_reload = fn() -> Result[Unit, LocalDispatchIssue] {
        if !live.val ||
          phase.val != Reloading ||
          execution_failure.val is Some(_) {
          return Err(Execution(Stopped))
        }
        if remaining.val < 1L {
          let issue = ControlWorkLimit(setup.execution.max_work)
          execution_failure.val = Some(issue)
          return Err(issue)
        }
        match @local.managed_provider_record_handoff_work(active, 1L) {
          Err(_) => return Err(Configuration(InvalidLimits))
          Ok(_) => ()
        }
        remaining.val -= 1L
        Ok(())
      }
      snapshot_attempted.val = true
      snapshot_ready.val = false
      snapshot_storage_released.val = Some(storage_released)
      // The same snapshot owner retains exact export authority until its
      // physical file is gone. Reloading copies does not transfer cleanup of
      // the old material to a hidden queue or discard its retained allowance.
      let cleanup_references = fn(quantum : Int) -> Bool {
        if quantum <= 0 {
          return false
        }
        if stream.val is Some(value) {
          if !@execution.advance_cancel_completed_output_export(value, quantum) {
            return false
          }
          stream.val = None
        }
        if receipt.val is Some(value) {
          if !@execution.advance_cancel_completed_export_receipt(value, quantum) {
            return false
          }
          receipt.val = None
        }
        if stored.val is Some(value) {
          if !storage_released() {
            return false
          }
          if @execution.completed_output_retained_material(value)
            is Some(material) &&
            !@execution.advance_retained_output_reference_reclamation(
              material, quantum,
            ) {
            return false
          }
          stored.val = None
        }
        true
      }
      relation_snapshot_cancel.val = Some(fn() {
        save_output.val = None
        if stream.val is Some(value) {
          @execution.cancel_completed_output_export(value)
        }
        if receipt.val is Some(value) {
          @execution.cancel_completed_export_receipt(value)
        }
        if importing.val is Some(value) {
          @execution.cancel_completed_output_import(value) |> ignore
        }
        restored.val = None
        phase.val = Failed
        cleanup_references(64)
      })
      Ok(
        Some({
          key: "relation-task-" + setup.task.to_string(),
          frames,
          advance_save,
          take_output: () => {
            if !live.val || (phase.val != Saving && phase.val != Saved) {
              return Err(Execution(Stopped))
            }
            let part = save_output.val.unwrap_or("")
            save_output.val = None
            Ok(part)
          },
          content: () => {
            guard phase.val == Saved && receipt.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            let (cid, bytes, _, _) = @execution.output_stream_identity(
              @execution.completed_export_content(value),
            )
            Ok({ cid, bytes, })
          },
          release_source: (cid, available) => {
            guard live.val && phase.val == Saved && receipt.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            let content = @execution.completed_export_content(value)
            let (expected, _, _, _) = @execution.output_stream_identity(content)
            if cid != expected || !available() {
              return Err(Configuration(InputUnavailable))
            }
            let handle = @execution.retain_admitted_output_stream(
              content,
              (),
              available,
            )
            let retained = match
              @execution.bind_completed_output_export(
                value,
                @execution.retained_output_material(handle),
              ) {
              Ok(result) => result
              Err(_) => return Err(Configuration(InputUnavailable))
            }
            // The exporter consumed its exact receipt. Retire the driver's
            // only cell output before the first reload byte can be admitted.
            receipt.val = None
            output_row_reader.val = None
            ordinary.val = None
            stored.val = Some(retained)
            phase.val = Released
            Ok(())
          },
          source_available: () => ordinary.val is Some(_),
          begin_reload: () => {
            with_local_managed_import_mutation(import_mutating, fn() {
              guard live.val &&
                phase.val == Released &&
                stored.val is Some(value) else {
                return Err(Configuration(InvalidLimits))
              }
              if setup.metered_retention {
                guard reload_capacity.val is Some(quoted) &&
                  @execution.checked_preparation_add_product(
                    import_extra.val,
                    quoted,
                    1L,
                  )
                  is Some(next) else {
                  return Err(Configuration(InvalidLimits))
                }
                match reserve_import(next, Some(snapshot_transport_prefix)) {
                  Ok(_) => ()
                  Err(issue) => {
                    phase.val = Failed
                    if execution_failure.val is None {
                      execution_failure.val = Some(issue)
                    }
                    return Err(issue)
                  }
                }
                if !live.val ||
                  phase.val != Released ||
                  !(stored.val is Some(actual) && physical_equal(actual, value)) {
                  return Err(Execution(Stopped))
                }
              }
              let value = match
                @execution.prepare_completed_output_import(
                  value,
                  setup.imports.max_rows,
                  setup.imports.values,
                  wire,
                  frames.maxFrameBytes,
                  deferred_reclamation=true,
                ) {
                Ok(result) => result
                Err(_) => return Err(Configuration(InputUnavailable))
              }
              importing.val = Some(value)
              phase.val = Reloading
              Ok(())
            })
          },
          append_reload: row => {
            guard phase.val == Reloading && importing.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            if debit_reload() is Err(issue) {
              return Err(issue)
            }
            @execution.append_completed_output_import_wire(
              value,
              row,
              setup.imports.row,
            ).map_err(_ => Configuration(InputUnavailable))
          },
          finish_reload: () => {
            guard phase.val == Reloading && importing.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            if debit_reload() is Err(issue) {
              return Err(issue)
            }
            let original_import = value
            let value = match
              @execution.finish_completed_output_import(original_import) {
              Ok(result) => result
              Err(_) => return Err(Configuration(InputUnavailable))
            }
            let scalar_text = if setup.metered_retention {
              @execution.completed_output_import_shared_scalar_text_bytes(
                original_import, value,
              ).bind(bytes => {
                reload_scalar_text.val.map(capacity => {
                  Int64::min(bytes, capacity)
                })
              })
            } else {
              None
            }
            guard live.val &&
              !disposed.val &&
              phase.val == Reloading &&
              importing.val
              .map(original => physical_equal(original, original_import))
              .unwrap_or(false) else {
              return Err(Execution(Stopped))
            }
            reload_scalar_text.val = scalar_text
            restored.val = Some(value)
            importing.val = None
            phase.val = Restored
            Ok(())
          },
          cleanup_references: quantum => {
            (phase.val == Restored || phase.val == Failed) &&
            cleanup_references(quantum)
          },
          finish: () => {
            guard live.val &&
              phase.val == Restored &&
              storage_released() &&
              stored.val is None &&
              stream.val is None &&
              receipt.val is None &&
              restored.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            // The actual Host has returned every append frame, cancelled the
            // framer and confirmed body/reference cleanup before this call.
            // Recheck after the imported storage-release callback; a reentrant
            // stop cannot publish this scalar overlap on a failed snapshot.
            guard live.val &&
              !disposed.val &&
              !import_mutating.val &&
              phase.val == Restored &&
              importing.val is None &&
              restored.val
              .map(original => physical_equal(original, value))
              .unwrap_or(false) &&
              import_scalar_reusable.val == 0L else {
              return Err(Execution(Stopped))
            }
            if setup.metered_retention && reload_scalar_text.val is Some(bytes) {
              guard reload_capacity.val is Some(quoted) &&
                bytes >= 0L &&
                bytes <= quoted &&
                bytes <= import_extra.val else {
                return Err(Configuration(InvalidLimits))
              }
              import_scalar_reusable.val = bytes
            }
            ordinary.val = Some(value)
            restored.val = None
            relation_snapshot_cancel.val = None
            phase.val = Finished
            snapshot_ready.val = true
            Ok(())
          },
        }),
      )
    },
    prepare_carrier_snapshot: fn(storage_released) {
      guard live.val &&
        execution_finished.val &&
        execution_failure.val is None &&
        !snapshot_attempted.val &&
        carrier.val is Some(source) &&
        carrier_completed.val is None &&
        output_target is Some(target) &&
        provider_execution.val is Some(active) else {
        return Err(Configuration(InvalidLimits))
      }
      snapshot_attempted.val = true
      let operation = match @carrier_runtime.material_prepare_snapshot(source) {
        Err(issue) => return Err(CarrierSnapshot(issue))
        Ok(None) => return Ok(None)
        Ok(Some(operation)) => operation
      }
      snapshot_ready.val = false
      snapshot_storage_released.val = Some(storage_released)
      if operation.workspace_bytes > setup.capacity.execution_bytes ||
        operation.maximum_bytes < 1 ||
        operation.maximum_frame_bytes < 1 {
        return Err(Configuration(InvalidLimits))
      }
      let owner = @execution.generated_sequence_owner(setup.sequence)
      let remaining = Ref(0L)
      match @local.managed_provider_cumulative_work(active) {
        Ok(work) if work >= 0L && work <= setup.execution.max_work.to_int64() =>
          remaining.val = setup.execution.max_work.to_int64() - work
        _ => return Err(Configuration(InvalidLimits))
      }
      let phase = Ref(SnapshotPhase::Saving)
      let save_work = Ref(0L)
      let reload_work = Ref(0L)
      let save_progress = Ref(0L)
      let reload_progress = Ref(0L)
      let advance_stage = fn(quantum, reloading) {
        if !live.val ||
          execution_failure.val is Some(_) ||
          quantum <= 0 ||
          phase.val != (if reloading { Reloading } else { Saving }) {
          return Err(Configuration(InvalidLimits))
        }
        if remaining.val <= 0L {
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        let allowed = if remaining.val < quantum.to_int64() {
          remaining.val.to_int()
        } else {
          quantum
        }
        let observation = match
          (if reloading {
            operation.advance_reload
          } else {
            operation.advance_save
          })(allowed) {
          Ok(value) => value
          Err(issue) => {
            phase.val = Failed
            execution_failure.val = Some(CarrierSnapshot(issue))
            return Err(CarrierSnapshot(issue))
          }
        }
        let work_cursor = if reloading { reload_work } else { save_work }
        let progress_cursor = if reloading {
          reload_progress
        } else {
          save_progress
        }
        if observation.work < work_cursor.val ||
          observation.progress < progress_cursor.val {
          @local.managed_provider_record_handoff_work(active, -1L) |> ignore
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        let delta = observation.work - work_cursor.val
        if delta < 0L ||
          delta > allowed.to_int64() ||
          (!observation.complete && observation.issue is None && delta == 0L) {
          @local.managed_provider_record_handoff_work(active, -1L) |> ignore
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        match @local.managed_provider_record_handoff_work(active, delta) {
          Ok(_) => ()
          Err(_) => {
            phase.val = Failed
            execution_failure.val = Some(Configuration(InvalidLimits))
            return Err(Configuration(InvalidLimits))
          }
        }
        work_cursor.val = observation.work
        progress_cursor.val = observation.progress
        remaining.val -= delta
        if observation.issue is Some(issue) {
          phase.val = Failed
          execution_failure.val = Some(CarrierSnapshot(issue))
          return Err(CarrierSnapshot(issue))
        }
        if observation.complete {
          phase.val = if reloading { Restored } else { Saved }
        }
        Ok({
          complete: observation.complete,
          waiting: false,
          settlement: None,
          progress: observation.progress,
          work: delta,
        })
      }
      Ok(
        Some({
          key: "task-" + setup.task.to_string(),
          maximum_bytes: operation.maximum_bytes,
          maximum_frame_bytes: operation.maximum_frame_bytes,
          advance_save: quantum => advance_stage(quantum, false),
          take_output: () => {
            if phase.val != Saving && phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            (operation.take_output)().map_err(issue => CarrierSnapshot(issue))
          },
          content: () => {
            if phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            (operation.content)().map_err(issue => CarrierSnapshot(issue))
          },
          release_source: cid => {
            if !live.val || phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            match (operation.release_source)(cid) {
              Ok(_) => ()
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            phase.val = Released
            Ok(())
          },
          begin_reload: (text, available) => {
            if !live.val || phase.val != Released {
              return Err(Configuration(InvalidLimits))
            }
            match (operation.begin_reload)(text, available) {
              Ok(_) => ()
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            phase.val = Reloading
            Ok(())
          },
          advance_reload: quantum => advance_stage(quantum, true),
          finish: () => {
            if !live.val || phase.val != Restored || !storage_released() {
              return Err(Configuration(InvalidLimits))
            }
            let restored = match (operation.take_material)() {
              Ok(value) => value
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            // Keep the old operation handle through its cleanup confirmation;
            // revoking its source alone does not end snapshot custody.
            retired_carriers.push(source)
            carrier.val = Some(restored)
            if !@carrier_runtime.completion_reference_matches_port(
                @carrier_runtime.material_reference(restored),
                owner,
                target,
              ) ||
              !@carrier_runtime.material_available(restored) {
              phase.val = Failed
              return Err(Configuration(InputUnavailable))
            }
            @carrier_runtime.reclaim_material(source) |> ignore
            if @carrier_runtime.material_cleanup_pending(source) {
              return Err(Configuration(InputUnavailable))
            }
            phase.val = Finished
            snapshot_ready.val = true
            Ok(())
          },
        }),
      )
    },
    storage_bytes: setup.capacity.retained_bytes,
    close: fn() {
      live.val = false
      cancel_finalization()
      if carrier.val is Some(material) {
        @carrier_runtime.reclaim_material(material) |> ignore
      }
      for material in retired_carriers {
        @carrier_runtime.reclaim_material(material) |> ignore
      }
      @strategy.close_task_execution(setup.run, execution)
    },
    cleanup_refresh: fn() {
      if scratch_uses.val != 0 {
        return false
      }
      if !stop_owned_inputs() {
        return false
      }
      if !release_provider_scratch() {
        return false
      }
      if relation_snapshot_cancel.val is Some(cancel) {
        if !cancel() {
          return false
        }
        relation_snapshot_cancel.val = None
      }
      release_owned_scratch()
      let carrier_reclaimed = match carrier.val {
        None => true
        Some(material) =>
          if !@carrier_runtime.material_cleanup_pending(material) {
            true
          } else {
            @carrier_runtime.reclaim_material(material) |> ignore
            !@carrier_runtime.material_cleanup_pending(material)
          }
      }
      if !carrier_reclaimed {
        return false
      }
      for material in retired_carriers {
        @carrier_runtime.reclaim_material(material) |> ignore
        if @carrier_runtime.material_cleanup_pending(material) {
          return false
        }
      }
      if !snapshot_storage_released.val.map(check => check()).unwrap_or(true) {
        return false
      }
      @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(
        false,
      )
    },
    cleanup_progress: fn() { finalization_reclamation_steps.val },
    // -1 means no authorized local continuation, not a stop/release witness.
    // External provider, borrowed input, snapshot and reader waits retain custody.
    cleanup_local_continuation: fn() {
      // Completed Relation material owns its independent receipt/index. Its
      // stopped provider can retire temporary roots before that live output
      // closes; this cursor is not an output or physical cleanup ACK.
      let completed_relation = live.val &&
        settled.val &&
        finalization_ready.val &&
        finalization_completed.val is Some(_) &&
        retained.val is Some(_) &&
        ordinary.val is Some(_)
      if ((!disposed.val || live.val) && !completed_relation) ||
        scratch_uses.val != 0 ||
        relation_snapshot_cancel.val is Some(_) ||
        (!completed_relation && input_stop.phase != Stopped) ||
        carrier.val is Some(_) ||
        !retired_carriers.is_empty() ||
        (retained.val is Some(_) && !completed_relation) ||
        snapshot_storage_released.val is Some(_) {
        return -1L
      }
      let provider_pending = match provider_execution.val {
        Some(active) if !provider_completion_retained.val => {
          let cursor = @local.managed_provider_cleanup_continuation(active)
          if cursor < 0L {
            return -1L
          }
          true
        }
        _ => false
      }
      if finalization_values.val is Some(values) &&
        !@execution.managed_output_values_scratch_released(values) &&
        !@execution.managed_output_values_reclamation_runnable(values) {
        return -1L
      }
      if provider_pending ||
        scratch_retirement.phase != Retired ||
        finalization_values.val is Some(_) {
        let scratch = scratch_retirement.steps
        let provider = provider_reclamation_steps.val
        let values = finalization_reclamation_steps.val
        if scratch > 9223372036854775807L - provider ||
          values > 9223372036854775807L - provider - scratch {
          -1L
        } else {
          provider + scratch + values
        }
      } else {
        -1L
      }
    },
  }
  Ok({
    ..operations,
    inputs: operations.inputs.map(transfer => {
      ..transfer,
      append: row => {
        with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
          (transfer.append)(row)
        })
      },
      finish: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.finish,
        )
      },
    }),
    execute: () => {
      with_managed_scratch_use(
        scratch_uses,
        release_owned_scratch,
        operations.execute,
      )
    },
    retained_inputs: operations.retained_inputs.map(transfer => {
      ..transfer,
      begin: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.begin,
        )
      },
      append: row => {
        with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
          (transfer.append)(row)
        })
      },
      finish: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.finish,
        )
      },
    }),
    advance: quantum => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.advance)(quantum)
      })
    },
    prepare_finalization: (payload, bytes, available) => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.prepare_finalization)(payload, bytes, available)
      })
    },
    advance_finalization: quantum => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.advance_finalization)(quantum)
      })
    },
  })
}

///|
pub fn start_local_managed_dispatch_node(
  setup : LocalManagedDispatchConfiguration[Int],
  retained_relation? : Bool = false,
) -> Result[LocalManagedDispatchOperations[Int], LocalDispatchIssue] {
  start_local_managed_dispatch(setup, retained_relation~)
}
