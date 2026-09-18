///|
priv enum DedupeIssue {
  Ordering(OrderingIssue)
  TopTie(Int, Int)
  IdentityCollision
}

///|
/// Canonical tuple identity for admitted scalar keys, including repeated fields.
/// This is group ordering, never a representative-row tie-break.
fn[T : IndexedRows] dedupe_key_identity(
  table : T,
  row : Int,
  by : Array[ColumnOrder],
  control : ControlBudget,
) -> Result[String, DedupeIssue] {
  try {
    let writer = @encode.hashing_writer(control.remaining, control.remaining, 4)
    @encode.begin_array(writer)
    for key in by {
      if !spend_control(control, 1) {
        return Err(Ordering(Limit))
      }
      let value = table.read_cell(row, key.column)
      match charge_comparison_operand(control, value) {
        Ok(_) => ()
        Err(ComparisonChargeLimit) => return Err(Ordering(Limit))
        Err(ComparisonChargeInvalidOperand) =>
          return Err(Ordering(Scalar(InvalidOperand)))
      }
      match value {
        Null | Number(_) | Boolean(_) | Text(_) =>
          emit_runtime_value(value, writer)
        Captured(admitted) =>
          match admitted {
            Array(_) | Object(_) | Vector(_) =>
              return Err(Ordering(Scalar(ComparisonDomainNotImplemented)))
            Null
            | Number(_)
            | Boolean(_)
            | Text(_)
            | Date(_)
            | Timestamp(_)
            | Decimal(_) => emit_runtime_value(value, writer)
            Reference(reference) => {
              if !@admitted.reference_available(reference) {
                return Err(Ordering(Scalar(InvalidOperand)))
              }
              @encode.string_value(
                writer,
                @admitted.reference_identity_cid(reference),
              )
            }
          }
      }
    }
    @encode.end_array(writer)
    let (hash, bytes, _) = @encode.finish_hash_usage(writer)
    if !spend_control(control, bytes) {
      return Err(Ordering(Limit))
    }
    Ok(hash)
  } catch {
    _ => Err(Ordering(Limit))
  }
}

///|
/// Group by scalar equality, choose only by authored order, then emit groups
/// in canonical tuple-CID order. No hash match substitutes for key equality.
/// All top ties are retained until canonical group ordering determines which
/// failure comes first. No survivor index escapes on any failure.
fn[T : IndexedRows] dedupe_indices(
  table : T,
  by : Array[ColumnOrder],
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], DedupeIssue] {
  if order.is_empty() ||
    control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(Ordering(InvalidInput))
  }
  let baseline = workspace.live
  let run = fn() -> Result[Array[Int], DedupeIssue] {
    if !reserve_slots(workspace, by.length()) ||
      !reserve_slots(workspace, order.length()) ||
      !spend_control(control, by.length()) ||
      !spend_control(control, order.length()) {
      return Err(Ordering(Limit))
    }
    let combined = by.copy()
    for key in order {
      combined.push(key)
    }
    let sorted = match
      stable_order_indices(table, combined, control, workspace) {
      Ok(v) => v
      Err(e) => return Err(Ordering(e))
    }
    let leaders : Array[Int] = []
    let ties : Array[Int?] = []
    let identities : Array[Array[Value]] = []
    let mut i = 0
    while i < sorted.length() {
      if !spend_control(control, 1) {
        return Err(Ordering(Limit))
      }
      let leader = sorted[i]
      let mut end = i + 1
      while end < sorted.length() {
        if !spend_control(control, 1) {
          return Err(Ordering(Limit))
        }
        match compare_row_indices(table, leader, sorted[end], by, control) {
          Ok(0) => end += 1
          Ok(_) => break
          Err(e) => return Err(Ordering(e))
        }
      }
      let tie = if end > i + 1 {
        match
          compare_row_indices(table, leader, sorted[i + 1], order, control) {
          Ok(0) => Some(sorted[i + 1])
          Ok(_) => None
          Err(e) => return Err(Ordering(e))
        }
      } else {
        None
      }
      // Fixed 64-byte hex key plus the retained metadata/container entries.
      if !reserve_slots(workspace, 68) {
        return Err(Ordering(Limit))
      }
      let cid = match dedupe_key_identity(table, leader, by, control) {
        Ok(cid) => cid
        Err(e) => return Err(e)
      }
      leaders.push(leader)
      ties.push(tie)
      identities.push([Text(cid)])
      i = end
    }
    if !reserve_slots(workspace, 1) {
      return Err(Ordering(Limit))
    }
    let groups : DedupeIdentities = { rows: identities, }
    let ordered = match
      stable_order_indices(
        groups,
        [{ column: 0, descending: false, nulls_first: false, }],
        control,
        workspace,
      ) {
      Ok(v) => v
      Err(e) => return Err(Ordering(e))
    }
    let result : Array[Int] = []
    for j = 0; j < ordered.length(); j = j + 1 {
      if !spend_control(control, 1) {
        return Err(Ordering(Limit))
      }
      let group = ordered[j]
      if j > 0 {
        if !spend_control(control, 129) {
          return Err(Ordering(Limit))
        }
        let previous = ordered[j - 1]
        match compare(groups.rows[previous][0], groups.rows[group][0]) {
          Ok(0) => return Err(IdentityCollision)
          Ok(_) => ()
          Err(e) => return Err(Ordering(Scalar(e)))
        }
      }
      if ties[group] is Some(other) {
        return Err(TopTie(leaders[group], other))
      }
      if !reserve_slots(workspace, 1) {
        return Err(Ordering(Limit))
      }
      result.push(leaders[group])
    }
    Ok(result)
  }
  let result = run()
  let retained = match result {
    Ok(v) => v.length()
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - baseline - retained)
  result
}

///|
// Scratch keys are not a Relation and carry no fabricated checked owner.
priv struct DedupeIdentities {
  rows : Array[Array[Value]]
}

///|
impl IndexedRows for DedupeIdentities with fn row_count(self) {
  self.rows.length()
}

///|
impl IndexedRows for DedupeIdentities with fn column_count(_self) {
  1
}

///|
impl IndexedRows for DedupeIdentities with fn row_width(self, row) {
  self.rows[row].length()
}

///|
impl IndexedRows for DedupeIdentities with fn read_cell(self, row, column) {
  self.rows[row][column]
}
