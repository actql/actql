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
  let (bridge, output) = match
    self.prepare_publication_bridge_for_original(
      operations, managed, row_limits, bridge_max_entries, bridge_max_name_bytes,
      limits,
    ) {
    Ok(value) => value
    Err(MissingOutput) => return Err(MissingOutput)
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
  reserve_row_copy? : ((Int64) -> Bool)? = None,
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
// One preflight cursor and its three copied limit records at a time. The
// source row is borrowed from the existing producer transport.
let publication_bridge_row_quote_controls : Int64 = {
  let source = @source.json_source_preflight_control_extent()
  @execution.preparation_representation_cost({
    record_headers: source.record_headers + 6L,
    reference_slots: source.reference_slots + 9L,
    scalar_words: source.scalar_words + 18L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// Measure the complete emitted row, including its object wrapper and nested
// values. The same Source cursor stops before grammar and retires before the
// decoder. Keep the old quote when the original wire cannot be measured.
fn publication_bridge_copy_row_limits(
  limits : @local.LocalImportLimits,
  row : String,
  bytes : Int64,
) -> @local.LocalImportLimits {
  match
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
      {
        ..limits,
        wire: {
          ..limits.wire,
          max_nodes: Int::min(limits.wire.max_nodes, nodes),
        },
        row: { ..limits.row, max_nodes: Int::min(limits.row.max_nodes, nodes), },
      }
    }
    _ => limits
  }
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
  reserve_row_copy? : ((Int64) -> Bool)? = None,
) -> Result[
  (@execution.ManagedPublicationBridge[Int], @execution.CompletedOutput),
  LocalValuesPublicationBridgeIssue,
] {
  if !self.available.val {
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
        reserve(start) &&
        self.available.val else {
        return Err(MissingOutput)
      }
      Some((imports, reserve))
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
  let mut copy_extent = 0L
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
    let funded = match copy_funding {
      None => None
      Some((imports, reserve)) => {
        let bytes = match
          @scalar.admit_utf8_length64(row, row_limits.max_bytes.to_int64()) {
          Ok(value) => value
          Err(_) => {
            @execution.close_managed_publication_bridge(bridge)
            return Err(Bridge(Wire(InputLimit)))
          }
        }
        guard @execution.managed_publication_bridge_import_usage(bridge)
          is Some(usage) &&
          @local.local_import_next_retention_extent(
            publication_bridge_copy_row_limits(imports, row, bytes),
            index.to_int64(),
            usage.nodes.to_int64(),
            usage.text_bytes.to_int64(),
            bytes,
          )
          is Some((_, nodes, text, quote)) else {
          @execution.close_managed_publication_bridge(bridge)
          return Err(MissingOutput)
        }
        // Each bridge retains its own copied prefix. Charge only the new
        // high-water difference, with one decoder beside that prefix.
        let extent = Int64::max(copy_extent, quote)
        if extent > copy_extent && !reserve(extent - copy_extent) {
          @execution.close_managed_publication_bridge(bridge)
          return Err(MissingOutput)
        }
        copy_extent = extent
        Some((nodes, text))
      }
    }
    // The Host's storage callback can reenter retirement. Keep this cheap
    // execution fence in addition to the bridge's original material checks.
    if !self.available.val {
      @execution.close_managed_publication_bridge(bridge)
      return Err(MissingOutput)
    }
    match
      @execution.append_managed_publication_bridge_wire(bridge, row, row_limits) {
      Ok(_) => ()
      Err(issue) => {
        @execution.close_managed_publication_bridge(bridge)
        return Err(Bridge(issue))
      }
    }
    if funded is Some((nodes, text)) &&
      !(@execution.managed_publication_bridge_import_usage(bridge)
      is Some(usage) &&
      usage.nodes >= 0 &&
      usage.nodes.to_int64() <= nodes &&
      usage.text_bytes >= 0 &&
      usage.text_bytes.to_int64() <= text) {
      @execution.close_managed_publication_bridge(bridge)
      return Err(MissingOutput)
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
