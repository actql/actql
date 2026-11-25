///|
pub fn NativeClientRelationFileWork::prepare_result_exports(
  self : NativeClientRelationFileWork,
  limits : @host.PublicationOutputExportLimits,
) -> Result[Array[@host.PublicationOutputExport], NativeClientSourceWorkIssue] {
  if !self.entry.arena.matches_business_scope(false) {
    return self.entry.unavailable_export
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let count = @strategy.graph_result_count(
    @strategy.captured_dag_graph(self.run),
  )
  if self.output_bridges is Some(_) ||
    count <= 0 ||
    (count > 1 && self.publication is None) {
    return Err(Configuration)
  }
  let (row_limits, bridge_entries) = match self.plan {
    QueryFileExecution(requirements) => {
      guard requirements.publication_limits(
          self.prepared,
          limits.payload_wire.max_bytes,
        )
        is Some((rows, _)) &&
        requirements.publication_entry_limits(self.prepared)
        is Some((entries, _)) else {
        return Err(Configuration)
      }
      (rows, entries)
    }
    WholeFileExecution(rows, entries, _)
    | ManagedSourceFileExecution(rows, entries, _) => (rows, entries)
  }
  let bridges : Array[@local.LocalValuesResultExport] = []
  let exports : Array[@host.PublicationOutputExport] = []
  self.output_bridges = Some(bridges)
  for index in 0..<count {
    let bridge = match
      self.execution.prepare_result_export(
        index,
        row_limits,
        bridge_entries,
        limits.schema.max_bytes,
        limits,
        publication=self.publication,
        fund_additional_bridge=index > 0,
      ) {
      Err(issue) => return Err(LocalExport(issue))
      Ok(value) => value
    }
    // A failed current check can suspend execution. Record the actual bridge
    // before that check so original cleanup still owns every earlier export.
    bridges.push(bridge)
    match self.require_current() {
      Err(issue) => return Err(issue)
      Ok(_) => exports.push(bridge.output_export())
    }
  }
  Ok(exports)
}

///|
fn NativeClientRelationFileWork::close_export(
  self : NativeClientRelationFileWork,
) -> Unit {
  if !self.entry.arena.matches_business_scope(true) {
    return
  }
  if !values_original_cleanup_entered(Some(self.access.base)) {
    return
  }
  if self.output_bridges is Some(bridges) {
    for bridge in bridges {
      bridge.close()
    }
    self.output_bridges = None
  }
}

///|
// The checked graph funds the caller's retained Context vector and the Work's
// two export vectors together. The Work base already covers the wrappers and
// first slot in each export vector. Per Result, charge its Context and retained
// export handoffs, including both original current checks; the Common bridge
// owns the variable row, transformation and schema geometry.
fn relation_file_result_publication_control_bytes(count : Int) -> Int64? {
  if count <= 0 {
    return None
  }
  let count = count.to_int64()
  guard @execution.preparation_array_representation(1L, 3L * count - 2L, true)
    is Some(arrays) &&
    @execution.preparation_representation_cost(arrays) is Some(vectors) &&
    @execution.preparation_representation_cost({
      record_headers: 20L,
      reference_slots: 36L,
      scalar_words: 20L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(per_result) else {
    return None
  }
  @execution.checked_preparation_add_product(vectors, count, per_result)
}
