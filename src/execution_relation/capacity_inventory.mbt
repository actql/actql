///|
/// Units in the existing logical backing allowances, not measured heap sizes.
/// A cursor root retains a reference, not another copy of its value tree.
/// Decoded text and canonical wire remain distinct even where their current
/// allowances happen to agree. QuotedBytes composes an existing byte quote.
pub(all) enum ExecutionCapacityUnit {
  ValueNodeSlots
  CursorRootSlots
  DecodedTextBytes
  CanonicalWireBytes
  QuotedBytes
}

///|
/// Domain code supplies the objects and simultaneous multiplicity. The common
/// capacity owner performs every conversion, multiplication and accumulation.
pub(all) struct ExecutionCapacityItem {
  unit : ExecutionCapacityUnit
  count : Int64
  copies : Int
}

///|
pub(all) enum ExecutionCapacityOverlap {
  SeparateDimensions
  RetainedAlongsideExecution
}

///|
fn execution_capacity_unit_bytes(unit : ExecutionCapacityUnit) -> Int64 {
  match unit {
    ValueNodeSlots => execution_capacity_node_bytes()
    // The existing bounded traversal-entry envelope uses a node allowance;
    // this is not the preparation representation's raw reference-slot tariff
    // and does not charge a second tree. Retain each actual root occurrence.
    CursorRootSlots => execution_capacity_node_bytes()
    DecodedTextBytes => 8L
    CanonicalWireBytes => 8L
    QuotedBytes => 1L
  }
}

///|
pub fn execution_capacity_inventory_bytes(
  items : Array[ExecutionCapacityItem],
) -> Int64? {
  let mut total = 0L
  for item in items {
    if item.count < 0L || item.copies < 0 {
      return None
    }
    // No instance exists when multiplicity is zero; still reject invalid
    // counts above before taking this branch.
    if item.count == 0L || item.copies == 0 {
      continue
    }
    let unit = execution_capacity_unit_bytes(item.unit)
    let copies = item.copies.to_int64()
    if unit <= 0L || item.count > 9223372036854775807L / unit {
      return None
    }
    let amount = item.count * unit
    if amount > (9223372036854775807L - total) / copies {
      return None
    }
    total += amount * copies
  }
  Some(total)
}

///|
/// Compose only the declared simultaneous inventory. SeparateDimensions keeps
/// already-quoted retained/execution dimensions; RetainedAlongsideExecution
/// explicitly keeps the retained inventory live alongside workspace. Neither
/// projection reserves capacity, acknowledges disposal or refunds spent work.
pub fn execution_capacity_inventory(
  retained : Array[ExecutionCapacityItem],
  execution : Array[ExecutionCapacityItem],
  overlap : ExecutionCapacityOverlap,
) -> ExecutionCapacity? {
  guard execution_capacity_inventory_bytes(retained) is Some(retained) &&
    execution_capacity_inventory_bytes(execution) is Some(execution) else {
    return None
  }
  let execution = match overlap {
    SeparateDimensions => execution
    RetainedAlongsideExecution => {
      if execution > 9223372036854775807L - retained {
        return None
      }
      retained + execution
    }
  }
  execution_capacity(retained, execution)
}

///|
/// Both existing components remain live. A caller that wants peak reuse must
/// first prove retirement through its original owner, rather than using this
/// operation as a release or inferring non-overlap from equal byte amounts.
pub fn add_execution_capacity(
  first : ExecutionCapacity,
  second : ExecutionCapacity,
) -> ExecutionCapacity? {
  execution_capacity_inventory(
    [
      { unit: QuotedBytes, count: first.retained_bytes, copies: 1, },
      { unit: QuotedBytes, count: second.retained_bytes, copies: 1, },
    ],
    [
      { unit: QuotedBytes, count: first.execution_bytes, copies: 1, },
      { unit: QuotedBytes, count: second.execution_bytes, copies: 1, },
    ],
    SeparateDimensions,
  )
}
