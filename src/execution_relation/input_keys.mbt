///|
/// Admitted, homogeneous key fields keep their type domains. Arrays used as
/// compound keys are private and never mutated after insertion into the map.
priv enum KeyAtom {
  KeyNumber(Double)
  KeyBoolean(Bool)
  KeyText(String)
  KeyDate(String)
  KeyTimestamp(String)
  KeyDecimal(String, Int)
  KeyReference(String)
} derive(Eq, Hash)

///|
pub(all) enum InputKeyIssue {
  WrongOrigin
  MissingField
  NullKey(Int)
  UnsupportedKeyDomain
  NullableWitnessPending
  DuplicateKey(Int, Int)
  InvalidLimits
  Limit
}

///|
fn validate_captured_keys(
  input : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, InputKeyIssue] {
  if control.remaining < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidLimits)
  }
  guard input.origin is SuppliedInput(index) else { return Err(WrongOrigin) }
  guard @lower.preparation_input_keys(
      @lower.bound_preparation(input.owner),
      index,
    )
    is Some(keys) else {
    return Ok(())
  }
  for k = 0; k < @evidence.key_witness_count(keys); k = k + 1 {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    let key = @evidence.key_witness_at(keys, k).unwrap()
    let baseline = workspace.live
    let columns : Array[Int] = []
    for j = 0; j < @evidence.key_field_count(key); j = j + 1 {
      if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
        return Err(Limit)
      }
      let field = @evidence.key_field_at(key, j).unwrap()
      if field.contract is Some(c) && c.nullable {
        return Err(NullableWitnessPending)
      }
      let mut ordinal : Int? = None
      for n = 0; n < @schema.field_count(input.schema); n = n + 1 {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        let f = @schema.field_at(input.schema, n).unwrap()
        if !spend_control_text(control, @schema.reference_name(f.name)) ||
          !spend_control_text(control, @schema.reference_name(field.name)) {
          return Err(Limit)
        }
        if f.name == field.name {
          if f.presence != @schema.Required {
            return Err(MissingField)
          }
          ordinal = Some(n)
          break
        }
      }
      guard ordinal is Some(n) else { return Err(MissingField) }
      columns.push(n)
    }
    let seen : Map[Array[KeyAtom], Int] = Map([])
    for row = 0; row < captured_row_count(input); row = row + 1 {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let tuple : Array[KeyAtom] = []
      for column in columns {
        if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
          return Err(Limit)
        }
        guard captured_cell(input, row, column) is Some(cell) else {
          return Err(MissingField)
        }
        let atom = match cell {
          @admitted.Null => return Err(NullKey(row))
          @admitted.Number(n) => KeyNumber(n)
          @admitted.Boolean(b) => KeyBoolean(b)
          @admitted.Text(s) => {
            if !spend_control_text(control, s) {
              return Err(Limit)
            }
            KeyText(s)
          }
          @admitted.Date(s) => {
            if !spend_control_text(control, s) {
              return Err(Limit)
            }
            KeyDate(s)
          }
          @admitted.Timestamp(s) => {
            if !spend_control_text(control, s) {
              return Err(Limit)
            }
            KeyTimestamp(s)
          }
          @admitted.Decimal(d) => {
            if !spend_control_text(control, d.coefficient) {
              return Err(Limit)
            }
            KeyDecimal(d.coefficient, d.scale)
          }
          @admitted.Reference(reference) => {
            if !@admitted.reference_available(reference) ||
              !spend_control_text(
                control,
                @admitted.reference_identity_cid(reference),
              ) {
              return Err(Limit)
            }
            KeyReference(@admitted.reference_identity_cid(reference))
          }
          @admitted.Array(_)
          | @admitted.Object(_)
          | @admitted.Vector(_)
          | @admitted.JsonData(_) => return Err(UnsupportedKeyDomain)
        }
        tuple.push(atom)
      }
      if seen.get(tuple) is Some(previous) {
        return Err(DuplicateKey(previous, row))
      }
      if !reserve_slots(workspace, 1) {
        return Err(Limit)
      }
      seen[tuple] = row
    }
    release_slots(workspace, workspace.live - baseline)
  }
  Ok(())
}
