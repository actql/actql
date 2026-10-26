///|
/// Domain callers supply storage/slot inventories, never another tariff or
/// an already guessed budget. Workspace is simultaneous with retained state;
/// ExecutionCapacity therefore includes both components in its execution peak.
priv struct PreparationExecutionInventory {
  retained : @execution.PreparationRepresentationUnits
  workspace : @execution.PreparationRepresentationUnits
  retained_nodes : Int64
  workspace_nodes : Int64
  retained_bytes : Int64
  workspace_bytes : Int64
}

///|
fn preparation_execution_capacity(
  inventory : PreparationExecutionInventory,
) -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost(inventory.retained)
    is Some(retained) &&
    @execution.preparation_representation_cost(inventory.workspace)
    is Some(workspace) else {
    return None
  }
  @execution.execution_capacity_inventory(
    [
      { unit: QuotedBytes, count: retained, copies: 1, },
      { unit: ValueNodeSlots, count: inventory.retained_nodes, copies: 1, },
      { unit: QuotedBytes, count: inventory.retained_bytes, copies: 1, },
    ],
    [
      { unit: QuotedBytes, count: workspace, copies: 1, },
      { unit: ValueNodeSlots, count: inventory.workspace_nodes, copies: 1, },
      { unit: QuotedBytes, count: inventory.workspace_bytes, copies: 1, },
    ],
    @execution.RetainedAlongsideExecution,
  )
}

///|
/// Fixed owned control family of the ordinary Node structural scanner. Its
/// source-owned inventory is independently checked in the adapter suite; byte
/// pricing remains exclusively this Common tariff, not a Node-issued grant.
fn preparation_node_own_data_scan_cost() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 4L,
    reference_slots: 5L,
    scalar_words: 31L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Valid narrow input traversal count from the original header's F/R facts.
/// UTF16 lengths are inspected in O(1), not characters, in this Node phase.
/// JSON byte bounds and the later Common lexical scan have distinct units.
fn preparation_node_own_data_scan_work(fields : Int, rows : Int) -> Int? {
  if fields < 1 || rows < 0 {
    return None
  }
  let f = fields.to_int64()
  let r = rows.to_int64()
  let maximum = 2147483647L
  if f > (maximum - 140L) / (f + 19L) {
    return None
  }
  let base = 140L + f * f + 19L * f
  let per_row = 4L + 6L * f
  if r > (maximum - base) / per_row {
    return None
  }
  Some((base + r * per_row).to_int())
}

///|
/// A nominal input-bound header survives into the full scan: one record with
/// input identity/F/R facts and private state. It is additional to the scanner
/// owned control family, not hidden in its 344-byte component quote.
fn preparation_node_own_data_header_cost() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 3L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
