///|
/// Retains the re-admitted Local output until its exact checked Named Result
/// export and any replay are finished. The physical Store remains a caller
/// responsibility; this owner neither publishes nor grants Result access.
pub struct LocalValuesResultExport {
  stream : @publication_host.PublicationOutputExport
  bridge : @execution.ManagedPublicationBridge[Int]?
  mut closed : Bool
}

///|
pub(all) enum LocalValuesResultExportIssue {
  MissingOutput
  UnknownResult
  Bridge(@execution.ManagedProducerBridgeIssue)
  Export(@publication_host.PublicationOutputExportIssue)
  Transformation(@publication_host.CapturedClientResultTransformationIssue)
  Selection(@publication_host.ClientResultTransformationIssue)
  Preparation(ClientClosedValuesPreparationIssue)
}

///|
/// Re-admit physical rows against the completed managed output and derive
/// the Result definition and projection from the same captured graph. The
/// caller must have accepted the Run before executing this occurrence.
pub fn LocalValuesExecution::prepare_result_export(
  self : LocalValuesExecution,
  result_index : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  publication? : ClientProgramPublication? = None,
  fund_additional_bridge? : Bool = false,
) -> Result[LocalValuesResultExport, LocalValuesResultExportIssue] {
  if !self.available.val {
    return Err(MissingOutput)
  }
  if publication is Some(original) &&
    !publication_export_original_matches(original, self.run) {
    return Err(Transformation(@publication_host.ForeignSelection))
  }
  let graph = @strategy.captured_dag_graph(self.run)
  guard @strategy.graph_result_task(graph, result_index) is Some(task) &&
    @strategy.graph_result_occurrence(graph, result_index) is Some(occurrence) &&
    @strategy.graph_result_name(graph, result_index) is Some(result_name) else {
    return Err(UnknownResult)
  }
  guard self.publication_original_for_task(task) is Some((operations, managed)) else {
    return Err(MissingOutput)
  }
  let copy_quote : (
    ClientProgramPublication,
    Ref[ClientClosedValuesPreparationIssue?],
  )? = if fund_additional_bridge {
    guard publication is Some(original) else {
      return Err(Preparation(ForeignOriginal))
    }
    Some((original, Ref(None)))
  } else {
    None
  }
  // This bridge can overlap an earlier completed Result bridge. Charge its
  // actual copied prefix to the existing publication borrower before decoding;
  // only the decoder workspace is a serial peak.
  let reserve_row_copy = match copy_quote {
    None => None
    Some((owner, failure)) =>
      Some((retained, decoder) => {
        match reserve_publication_constructor(owner, retained, decoder) {
          Ok(_) => true
          Err(issue) => {
            failure.val = Some(issue)
            false
          }
        }
      })
  }
  let (bridge, output) = match
    prepare_publication_bridge_for_original(
      self.available,
      operations,
      managed,
      row_limits,
      bridge_max_entries,
      bridge_max_name_bytes,
      limits,
      reserve_row_copy~,
    ) {
    Ok(value) => value
    Err(MissingOutput) => {
      if copy_quote is Some((_, failure)) && failure.val is Some(issue) {
        return Err(Preparation(issue))
      }
      return Err(MissingOutput)
    }
    Err(Bridge(issue)) => return Err(Bridge(issue))
  }
  let stream = match publication {
    None => {
      let definition = match
        @publication.prepare_result_definition(
          @strategy.graph_program_definition_cid(graph),
          result_name,
        ) {
        Ok(value) => @publication.result_definition_contract(value)
        Err(_) => {
          @execution.close_managed_publication_bridge(bridge)
          return Err(UnknownResult)
        }
      }
      let stream = match
        @publication_host.prepare_result_publication_export(
          output, occurrence, definition, limits,
        ) {
        Ok(value) => value
        Err(issue) => {
          @execution.close_managed_publication_bridge(bridge)
          return Err(Export(issue))
        }
      }
      stream
    }
    Some(original) => {
      // Only the same adopted publication continuation asks for an original
      // captured pin. Ordinary DATA exports keep their existing standalone
      // route, including completed Local rows in an unfinished Effect Run.
      if !publication_export_original_matches(original, self.run) {
        @execution.close_managed_publication_bridge(bridge)
        return Err(Transformation(@publication_host.ForeignSelection))
      }
      // Retain the original Run occurrence through the existing checked managed
      // bridge. A standalone equal-content export cannot fund a captured snapshot.
      let transformation = match
        @publication_host.start_captured_managed_result_publication_export(
          self.run,
          result_index,
          managed,
          bridge,
          output,
          limits,
        ) {
        Ok(value) => value
        Err(issue) => {
          @execution.close_managed_publication_bridge(bridge)
          return Err(local_values_transformation_issue(issue))
        }
      }
      let mut done = false
      while !done {
        match transformation.advance(256) {
          Ok((ready, _)) => done = ready
          Err(issue) => {
            transformation.cancel()
            @execution.close_managed_publication_bridge(bridge)
            return Err(local_values_transformation_issue(issue))
          }
        }
      }
      let stream = match transformation.finish() {
        Ok(value) => value
        Err(issue) => {
          transformation.cancel()
          @execution.close_managed_publication_bridge(bridge)
          return Err(local_values_transformation_issue(issue))
        }
      }
      stream
    }
  }
  Ok({ stream, bridge: Some(bridge), closed: false, })
}

///|
/// Keep the exact captured Named Result pin through export and replay. Managed
/// tasks use this execution's original completion; Source/cell tasks retain
/// their existing exporter. Neither path creates another Result or execution.
pub fn LocalValuesExecution::prepare_captured_result_export(
  self : LocalValuesExecution,
  captured : @strategy.CapturedDAG,
  result_index : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  before_row? : ((String) -> Bool)? = None,
  reserve_row_copy? : ((Int64, Int64) -> Bool)? = None,
) -> Result[LocalValuesResultExport, LocalValuesResultExportIssue] {
  if !self.available.val || !physical_equal(captured, self.run) {
    return Err(MissingOutput)
  }
  guard @strategy.graph_result_task(
      @strategy.captured_dag_graph(captured),
      result_index,
    )
    is Some(task) else {
    return Err(UnknownResult)
  }
  guard self.publication_original_for_task(task) is Some((operations, managed)) else {
    return @publication_host.prepare_captured_result_publication_export(
        captured, result_index, limits,
      )
      .map_err(issue => LocalValuesResultExportIssue::Export(issue))
      .map(stream => { stream, bridge: None, closed: false, })
  }
  let (bridge, output) = match
    self.prepare_publication_bridge_for_original(
      operations,
      managed,
      row_limits,
      bridge_max_entries,
      bridge_max_name_bytes,
      limits,
      before_row~,
      reserve_row_copy~,
    ) {
    Ok(value) => value
    Err(MissingOutput) => return Err(MissingOutput)
    Err(Bridge(issue)) => return Err(Bridge(issue))
  }
  let transformation = match
    @publication_host.start_captured_managed_result_publication_export(
      captured, result_index, managed, bridge, output, limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(local_values_transformation_issue(issue))
    }
  }
  let mut done = false
  while !done {
    match transformation.advance(256) {
      Ok((ready, _)) => done = ready
      Err(issue) => {
        transformation.cancel()
        @execution.close_managed_publication_bridge(bridge)
        return Err(local_values_transformation_issue(issue))
      }
    }
  }
  match transformation.finish() {
    Ok(stream) => Ok({ stream, bridge: Some(bridge), closed: false, })
    Err(issue) => {
      transformation.cancel()
      @execution.close_managed_publication_bridge(bridge)
      Err(local_values_transformation_issue(issue))
    }
  }
}

///|
fn installed_whole_publication_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  invocation : @publication.PublicationContract,
) -> (
  ClientInstalledManagedCapturePlan,
  @strategy.CapturedDAG,
  @publication.PublicationContract,
)? {
  guard owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    !plan.whole_sources.is_empty() &&
    !owner.effect_operation_closing &&
    owner.publication_definition is Some(definition) &&
    owner.publication_invocation is Some(bound) &&
    physical_equal(bound, invocation) &&
    @publication_host.client_compiled_run_has_original_definition(
      compiled, definition,
    ) &&
    plan.compilation is Some(@publication_host.Tasks(tasks)) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, tasks,
    ) &&
    owner.source_free_captured is Some(captured) &&
    physical_equal(plan.graph, @strategy.captured_dag_graph(captured)) else {
    return None
  }
  Some((plan, captured, definition))
}

///|
/// Recheck one captured File occurrence against the installed Run and return
/// its exact DAG and logical relation CID for the original publication.
pub fn installed_single_whole_publication_source(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  capture : @row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
) -> Result[(@strategy.CapturedDAG, String), ClientInstalledManagedRunIssue] {
  check_installed_managed_run(owner, prepared, request).bind(_ => {
    guard installed_whole_publication_original(
        owner, prepared, request, compiled, invocation,
      )
      is Some((plan, dag, bound_definition)) &&
      physical_equal(bound_definition, definition) &&
      plan.whole_sources.length() == 1 &&
      whole_source_publication_capture_matches(owner, plan, capture) &&
      @row_source_host.row_capture_source(capture) is Ok(input) &&
      @query.captured_source_relation_identity_matches_source(identity, input) else {
      return Err(ForeignOriginal)
    }
    // Capture liveness can call its original supplier. After it returns,
    // recheck installed bindings without entering that supplier again.
    check_installed_managed_run_binding(owner, prepared, request).bind(_ => {
      guard owner.source_free_captured is Some(still) &&
        physical_equal(still, dag) &&
        owner.publication_invocation is Some(bound) &&
        physical_equal(bound, invocation) &&
        !owner.effect_operation_closing &&
        whole_source_publication_capture_matches(owner, plan, capture) else {
        return Err(ForeignOriginal)
      }
      Ok((dag, @query.captured_source_relation_logical_cid(identity)))
    })
  })
}

///|
/// Original named Result material and one bounded preparation cursor. Its
/// bridge remains under the same managed task until Finish transfers it.
struct LocalWholeNamedResultPreparation {
  execution : LocalValuesExecution
  operations : @local_driver.LocalManagedDispatchOperations[Int]
  completed : @execution.ManagedCompletedOutput[Int]
  definition : @publication.PublicationContract
  occurrence : @execution.ManagedResultOccurrence
  result_index : Int
  row_count : Int
  row_limits : @execution.RetainedRowDecodeLimits
  limits : @publication_host.PublicationOutputExportLimits
  bridge_max_entries : Int
  bridge_max_name_bytes : Int
  reserve_row_copy : (Int64, Int64) -> Bool
  mut bridge : @execution.ManagedPublicationBridge[Int]?
  mut funding : LocalPublicationBridgeCopyFunding?
  mut metadata_retained : Int64
  mut position : Int
  mut transformation : @publication_host.CapturedClientResultTransformation?
  exported : Ref[@publication_host.PublicationOutputExport?]
  mut ready : Bool
  mut finished : Bool
  mut failed : Bool
  mut closed : Bool
}

///|
/// Select one checked named occurrence and its physical output before any
/// row is copied. Narrowing the quantum never reselects its managed Task.
pub fn start_installed_whole_named_result_export(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  invocation : @publication.PublicationContract,
  execution : LocalValuesExecution,
  result_index : Int,
  definition : @publication.PublicationContract,
  max_payload_bytes : Int,
  reserve_row_copy : (Int64, Int64) -> Bool,
) -> Result[LocalWholeNamedResultPreparation, LocalValuesResultExportIssue] {
  guard installed_whole_publication_original(
      owner, prepared, request, compiled, invocation,
    )
    is Some((plan, captured, _)) &&
    physical_equal(captured, execution.run) else {
    return Err(Transformation(@publication_host.ForeignSelection))
  }
  guard installed_managed_publication_limits(owner, prepared, max_payload_bytes)
    is Some(limits) else {
    return Err(MissingOutput)
  }
  // installed_whole_publication_original checks the same compiled material
  // and the exact installed graph. Select its Result directly.
  let graph = @strategy.captured_dag_graph(captured)
  guard @strategy.graph_result_occurrence(graph, result_index)
    is Some(occurrence) &&
    @strategy.graph_result_task(graph, result_index) is Some(task) &&
    @strategy.graph_result_name(graph, result_index) is Some(name) else {
    return Err(UnknownResult)
  }
  let original = @publication_host.prepared_client_graph(prepared)
  if @strategy.graph_result_task(original, result_index) != Some(task) ||
    !(@strategy.graph_result_occurrence(original, result_index) is Some(checked) &&
    physical_equal(checked, occurrence)) ||
    !@publication.result_definition_contract_matches(
      definition,
      @strategy.graph_program_definition_cid(graph),
      name,
    ) {
    return Err(Transformation(@publication_host.ForeignSelection))
  }
  guard execution.publication_original_for_task(task)
    is Some((operations, completed)) else {
    return Err(MissingOutput)
  }
  let row_count = @execution.managed_completed_output_row_count(completed)
  if row_count < 0 ||
    row_count > limits.max_rows ||
    (operations.output_rows)() != row_count {
    return Err(MissingOutput)
  }
  Ok({
    execution,
    operations,
    completed,
    definition,
    occurrence,
    result_index,
    row_count,
    row_limits: plan.capacity_plan.imports.row,
    limits,
    bridge_max_entries: plan.capacity_plan.metadata.bridge_entries,
    bridge_max_name_bytes: plan.capacity_plan.metadata.name_bytes,
    reserve_row_copy,
    bridge: None,
    funding: None,
    metadata_retained: 0L,
    position: 0,
    transformation: None,
    exported: Ref(None),
    ready: false,
    finished: false,
    failed: false,
    closed: false,
  })
}

///|
fn local_publication_bridge_issue(
  issue : LocalValuesPublicationBridgeIssue,
) -> LocalValuesResultExportIssue {
  match issue {
    MissingOutput => MissingOutput
    Bridge(issue) => Bridge(issue)
  }
}

///|
fn LocalWholeNamedResultPreparation::reserve_view(
  self : LocalWholeNamedResultPreparation,
) -> Bool {
  let port = @execution.managed_result_occurrence_port(self.occurrence)
  let fields = @schema.field_count(@results.port_schema(port)).to_int64()
  let terms = @results.port_order_term_count(port).to_int64()
  let rows = self.row_count.to_int64()
  let indexes = if terms > 0L && rows > 1L { 2L * rows } else { rows }
  // The projected names borrow the original Text. Include both row-index
  // arrays while sorting, the mapped columns and terms, all growth backing,
  // and the existing recursive comparison controls up to the checked depth.
  guard @execution.preparation_array_representation(
      5L,
      indexes + 2L * fields + terms,
      true,
    )
    is Some(arrays) &&
    @execution.preparation_representation_cost({
      ..arrays,
      record_headers: arrays.record_headers + terms,
      reference_slots: arrays.reference_slots + 2L * terms,
      scalar_words: arrays.scalar_words + 3L * terms,
    })
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      0L,
      CursorRootSlots,
      self.limits.values.max_depth.to_int64(),
      4,
    )
    is Some(comparison) else {
    return false
  }
  (self.reserve_row_copy)(retained, comparison)
}

///|
fn LocalWholeNamedResultPreparation::reserve_metadata(
  self : LocalWholeNamedResultPreparation,
  capacity : @execution.ExecutionCapacity,
) -> Bool {
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  let next = Int64::max(self.metadata_retained, retained)
  if !(self.reserve_row_copy)(
      next - self.metadata_retained,
      execution - retained,
    ) {
    return false
  }
  self.metadata_retained = next
  true
}

///|
fn LocalWholeNamedResultPreparation::step(
  self : LocalWholeNamedResultPreparation,
  quantum : Int,
) -> Result[(Bool, Int), LocalValuesResultExportIssue] {
  if self.transformation is Some(transform) {
    return transform
      .advance(
        quantum,
        before_metadata=Some(capacity => self.reserve_metadata(capacity)),
      )
      .map_err(local_values_transformation_issue)
  }
  if self.bridge is None {
    let (bridge, copy) = match
      self.execution.open_publication_bridge_for_original(
        self.operations,
        self.completed,
        self.row_limits,
        self.bridge_max_entries,
        self.bridge_max_name_bytes,
        self.limits,
        Some(self.reserve_row_copy),
      ) {
      Ok(value) => value
      Err(issue) => return Err(local_publication_bridge_issue(issue))
    }
    self.bridge = Some(bridge)
    self.funding = copy
    return Ok((false, 1))
  }
  guard self.bridge is Some(bridge) else { return Err(MissingOutput) }
  let rows = Int::min(quantum, self.row_count - self.position)
  if rows > 0 {
    for _ in 0..<rows {
      let row = match (self.operations.output_row)(self.position) {
        Ok(value) => value
        Err(_) => return Err(MissingOutput)
      }
      match
        append_local_publication_bridge_row(
          self.execution.available,
          bridge,
          row,
          self.row_limits,
          self.position,
          self.funding,
        ) {
        Err(issue) => return Err(local_publication_bridge_issue(issue))
        Ok(_) => self.position += 1
      }
    }
    return Ok((false, rows))
  }
  let output = match @execution.finish_managed_publication_bridge(bridge) {
    Err(issue) => return Err(Bridge(issue))
    Ok(output) => output
  }
  if !self.reserve_view() {
    return Err(MissingOutput)
  }
  match
    @publication_host.start_captured_managed_result_publication_export(
      self.execution.run,
      self.result_index,
      self.completed,
      bridge,
      output,
      self.limits,
      definition=self.definition,
    ) {
    Err(issue) => Err(local_values_transformation_issue(issue))
    Ok(transformation) => {
      self.transformation = Some(transformation)
      Ok((false, 1))
    }
  }
}

///|
/// Copy or transform only the current quantum. A refusal seals the cursor;
/// its already retained bridge and task remain reachable by close.
pub fn LocalWholeNamedResultPreparation::advance(
  self : LocalWholeNamedResultPreparation,
  quantum : Int,
) -> Result[(Bool, Int), LocalValuesResultExportIssue] {
  if quantum <= 0 ||
    self.closed ||
    self.finished ||
    self.failed ||
    !self.execution.available.val {
    return Err(Export(@publication_host.InvalidState))
  }
  if self.ready {
    return Ok((true, 0))
  }
  match self.step(quantum) {
    Err(issue) => {
      self.failed = true
      Err(issue)
    }
    Ok((done, work)) => {
      self.ready = done
      Ok((done, work))
    }
  }
}

///|
/// The same preparation keeps the bridge and finished export until close.
/// Finish exposes a borrowed stream, and cannot move its pin to a new owner.
pub fn LocalWholeNamedResultPreparation::finish(
  self : LocalWholeNamedResultPreparation,
) -> Result[
  @publication_host.PublicationOutputExport,
  LocalValuesResultExportIssue,
] {
  guard !self.closed &&
    !self.finished &&
    !self.failed &&
    self.ready &&
    self.execution.available.val &&
    self.transformation is Some(transformation) else {
    return Err(Export(@publication_host.InvalidState))
  }
  match transformation.finish(handoff=Some(self.exported)) {
    Err(issue) => {
      self.failed = true
      Err(local_values_transformation_issue(issue))
    }
    Ok(stream) => {
      self.finished = true
      Ok(stream)
    }
  }
}

///|
pub fn LocalWholeNamedResultPreparation::inputs_ready(
  self : LocalWholeNamedResultPreparation,
) -> Bool {
  !self.closed && !self.failed && self.transformation is Some(_)
}

///|
pub fn LocalWholeNamedResultPreparation::close(
  self : LocalWholeNamedResultPreparation,
) -> Unit {
  if !self.closed {
    if self.transformation is Some(transformation) {
      transformation.cancel()
    }
    self.transformation = None
    if self.bridge is Some(bridge) {
      @execution.close_managed_publication_bridge(bridge)
    }
    self.bridge = None
    self.funding = None
    self.closed = true
  }
}

///|
pub fn LocalValuesResultExport::output_export(
  self : LocalValuesResultExport,
) -> @publication_host.PublicationOutputExport {
  self.stream
}

///|
/// Close after the export, replay and Store custody have finished. This does
/// not stop or rerun Compute; the Local execution has its own close operation.
pub fn LocalValuesResultExport::close(self : LocalValuesResultExport) -> Unit {
  if !self.closed {
    self.closed = true
    self.stream.cancel()
    if self.bridge is Some(bridge) {
      @execution.close_managed_publication_bridge(bridge)
    }
  }
}

///|
priv enum LocalValuesPublicationBridgeIssue {
  MissingOutput
  Bridge(@execution.ManagedProducerBridgeIssue)
}

///|
// Select once from this execution's actual generation inventory. The public
// Result task and the primary completion do not select another local Result.
fn LocalValuesExecution::publication_original_for_task(
  self : LocalValuesExecution,
  task : Int,
) -> (
  @local_driver.LocalManagedDispatchOperations[Int],
  @execution.ManagedCompletedOutput[Int],
)? {
  if !self.available.val {
    return None
  }
  if self.tasks is Some((lookup, _)) {
    lookup(task)
  } else {
    if task != 0 {
      return None
    }
    Some((self.operations, self.completed))
  }
}

///|
// One preflight cursor, three copied limit records and the pending Value
// bounds at a time, plus split quote and bridge peak counters. The row is
// borrowed from the original producer transport.
let publication_bridge_row_quote_controls : Int64 = {
  let source = @source.json_source_preflight_control_extent()
  @execution.preparation_representation_cost({
    record_headers: source.record_headers + 10L,
    reference_slots: source.reference_slots + 15L,
    scalar_words: source.scalar_words + 31L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// Measure the complete emitted row, including its object wrapper and nested
// values. The same Source cursor stops before grammar and retires before the
// decoder. Keep the byte-derived bound if the original wire cannot be measured.
fn reserve_publication_bridge_row_copy(
  limits : @local.LocalImportLimits,
  schema : @schema.Schema,
  row : String,
  bytes : Int64,
  prefix_rows : Int64,
  prefix : @execution.ValueUsage,
  previous_retained : Int64,
  previous_decoder : Int64,
  reserve : (Int64, Int64) -> Bool,
) -> (Int64, Int64, Int64, Int64)? {
  guard bytes >= 0L && bytes <= limits.row.max_bytes.to_int64() else {
    return None
  }
  let (quote, row_nodes) = match
    installed_effect_dependency_wire_geometry(
      row,
      limits.row.max_bytes,
      limits.row.max_nodes,
      limits.row.max_depth,
      _ => true,
    ) {
    Some(geometry) if geometry.input_bytes.to_int64() == bytes &&
      geometry.node_upper > 0 => {
      // Even a sparse row uses the original schema's field slots.
      let nodes = Int::max(geometry.node_upper, limits.wire.max_columns)
      (
        {
          ..limits,
          wire: {
            ..limits.wire,
            max_nodes: Int::min(limits.wire.max_nodes, nodes),
          },
          row: {
            ..limits.row,
            max_nodes: Int::min(limits.row.max_nodes, nodes),
          },
        },
        geometry.node_upper.to_int64(),
      )
    }
    _ => (limits, bytes)
  }
  // The complete wire bounds the row and every present Value. Presence
  // admission also retains an entry for every omitted slot and charges its
  // name even though neither appears in the wire. The original schema bounds
  // both, independently of the transient decoder and the admitted prefix.
  let (presence_nodes, presence_text) = if @schema.all_fields_required(schema) {
    (0L, 0L)
  } else {
    (
      @schema.field_count(schema).to_int64(),
      @schema.field_reference_name_bytes(schema).to_int64(),
    )
  }
  guard @local.local_import_next_copy_extent(
      quote,
      prefix_rows,
      prefix.nodes.to_int64(),
      prefix.text_bytes.to_int64(),
      bytes,
      pending_value_nodes=Some(row_nodes + presence_nodes),
      pending_value_text=Some(bytes + presence_text),
    )
    is Some((_, nodes, text, retained, decoder)) else {
    return None
  }
  // The copied prefix stays with this bridge. Only this append needs the
  // decoder workspace, and the previous append has already returned.
  let retained_peak = Int64::max(previous_retained, retained)
  let decoder_peak = Int64::max(previous_decoder, decoder)
  if (retained_peak > previous_retained || decoder_peak > previous_decoder) &&
    !reserve(retained_peak - previous_retained, decoder) {
    return None
  }
  Some((retained_peak, decoder_peak, nodes, text))
}

///|
// Conversion keeps the selected operations and SAME managed completion
// together across material/row callbacks. No second task lookup can replace
// that generation. An optional Host funding boundary precedes row decoding.
fn LocalValuesExecution::prepare_publication_bridge_for_original(
  self : LocalValuesExecution,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  before_row? : ((String) -> Bool)? = None,
  reserve_row_copy? : ((Int64, Int64) -> Bool)? = None,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], @execution.CompletedOutput),
  LocalValuesPublicationBridgeIssue,
] {
  prepare_publication_bridge_for_original(
    self.available,
    operations,
    completed,
    row_limits,
    bridge_max_entries,
    bridge_max_name_bytes,
    limits,
    before_row~,
    reserve_row_copy~,
  )
}

///|
fn prepare_publication_bridge_for_original(
  available : Ref[Bool],
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  before_row? : ((String) -> Bool)? = None,
  reserve_row_copy? : ((Int64, Int64) -> Bool)? = None,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], @execution.CompletedOutput),
  LocalValuesPublicationBridgeIssue,
] {
  let (bridge, copy_funding) = match
    open_publication_bridge_for_original(
      available, operations, completed, row_limits, bridge_max_entries, bridge_max_name_bytes,
      limits, reserve_row_copy,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for index in 0..<(operations.output_rows)() {
    let row = match (operations.output_row)(index) {
      Ok(value) => value
      Err(_) => {
        @execution.close_managed_publication_bridge(bridge)
        return Err(MissingOutput)
      }
    }
    if before_row is Some(prepare) && !prepare(row) {
      @execution.close_managed_publication_bridge(bridge)
      return Err(MissingOutput)
    }
    match
      append_local_publication_bridge_row(
        available, bridge, row, row_limits, index, copy_funding,
      ) {
      Err(issue) => {
        @execution.close_managed_publication_bridge(bridge)
        return Err(issue)
      }
      Ok(_) => ()
    }
  }
  let output = match @execution.finish_managed_publication_bridge(bridge) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(bridge)
      return Err(Bridge(issue))
    }
  }
  Ok((bridge, output))
}

///|
fn LocalValuesExecution::open_publication_bridge_for_original(
  self : LocalValuesExecution,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  reserve_row_copy : ((Int64, Int64) -> Bool)?,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], LocalPublicationBridgeCopyFunding?),
  LocalValuesPublicationBridgeIssue,
] {
  open_publication_bridge_for_original(
    self.available,
    operations,
    completed,
    row_limits,
    bridge_max_entries,
    bridge_max_name_bytes,
    limits,
    reserve_row_copy,
  )
}

///|
fn open_publication_bridge_for_original(
  available : Ref[Bool],
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
  row_limits : @execution.RetainedRowDecodeLimits,
  bridge_max_entries : Int,
  bridge_max_name_bytes : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  reserve_row_copy : ((Int64, Int64) -> Bool)?,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], LocalPublicationBridgeCopyFunding?),
  LocalValuesPublicationBridgeIssue,
] {
  if !available.val {
    return Err(MissingOutput)
  }
  guard (operations.material)() is Some(material) else {
    return Err(MissingOutput)
  }
  let copy_funding = match reserve_row_copy {
    None => None
    Some(reserve) => {
      // The ingress policy comes from the original row decoder. The final
      // Result can have a narrower wire than the complete producer row.
      let imports : @local.LocalImportLimits = {
        max_rows: limits.max_rows,
        values: limits.values,
        wire: {
          ..limits.payload_wire,
          max_bytes: row_limits.max_bytes,
          max_nodes: row_limits.max_nodes,
          max_depth: row_limits.max_depth,
          max_columns: @execution.managed_publication_bridge_fixed_entries(
            completed,
          ),
        },
        row: row_limits,
        max_batch_bytes: row_limits.max_bytes,
      }
      guard @local.local_materializing_import_start_capacity(imports)
        is Some(start) &&
        @execution.checked_preparation_add_product(
          start, publication_bridge_row_quote_controls, 1L,
        )
        is Some(start) &&
        reserve(start, 0L) &&
        available.val else {
        return Err(MissingOutput)
      }
      Some({ imports, reserve, retained: 0L, decoder: 0L, })
    }
  }
  let bridge = match
    @execution.prepare_managed_publication_bridge(
      completed,
      material,
      limits.max_rows,
      limits.values,
      bridge_max_entries,
      bridge_max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Bridge(issue))
  }
  Ok((bridge, copy_funding))
}

///|
priv struct LocalPublicationBridgeCopyFunding {
  imports : @local.LocalImportLimits
  reserve : (Int64, Int64) -> Bool
  mut retained : Int64
  mut decoder : Int64
}

///|
fn append_local_publication_bridge_row(
  available : Ref[Bool],
  bridge : @execution.ManagedPublicationBridge[Int],
  row : String,
  row_limits : @execution.RetainedRowDecodeLimits,
  index : Int,
  copy_funding : LocalPublicationBridgeCopyFunding?,
) -> Result[Unit, LocalValuesPublicationBridgeIssue] {
  let funded = match copy_funding {
    None => None
    Some(state) => {
      let bytes = match
        @scalar.admit_utf8_length64(row, row_limits.max_bytes.to_int64()) {
        Ok(value) => value
        Err(_) => return Err(Bridge(Wire(InputLimit)))
      }
      guard @execution.managed_publication_bridge_import_usage(bridge)
        is Some(usage) &&
        reserve_publication_bridge_row_copy(
          state.imports,
          @execution.managed_publication_bridge_import_schema(bridge),
          row,
          bytes,
          index.to_int64(),
          usage,
          state.retained,
          state.decoder,
          state.reserve,
        )
        is Some((retained, decoder, nodes, text)) else {
        return Err(MissingOutput)
      }
      state.retained = retained
      state.decoder = decoder
      Some((nodes, text))
    }
  }
  // The Host's storage callback can reenter retirement. Keep this cheap
  // execution fence in addition to the bridge's original material checks.
  if !available.val {
    return Err(MissingOutput)
  }
  match
    @execution.append_managed_publication_bridge_wire(bridge, row, row_limits) {
    Ok(_) => ()
    Err(issue) => return Err(Bridge(issue))
  }
  if funded is Some((nodes, text)) &&
    !(@execution.managed_publication_bridge_import_usage(bridge) is Some(usage) &&
    usage.nodes >= 0 &&
    usage.nodes.to_int64() <= nodes &&
    usage.text_bytes >= 0 &&
    usage.text_bytes.to_int64() <= text) {
    return Err(MissingOutput)
  }
  Ok(())
}

///|
fn local_values_transformation_issue(
  issue : @publication_host.CapturedClientResultTransformationIssue,
) -> LocalValuesResultExportIssue {
  match issue {
    Transform(Output(original)) => Export(@publication_host.Output(original))
    Retain(original) => Export(@publication_host.Retain(original))
    _ => Transformation(issue)
  }
}

///|
fn publication_export_original_matches(
  value : ClientProgramPublication,
  run : @strategy.CapturedDAG,
) -> Bool {
  publication_original_body(value) is Some(_) &&
  value.run is Some(original) &&
  physical_equal(original, run)
}
