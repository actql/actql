///|
priv enum ValuesTypeFrame {
  Read(@contract.Contract, Int)
  Fields(@contract.Fields, Int, Int)
}

///|
pub(all) enum ValuesRecursiveIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner
  Measurement(ValuesMeasurementIssue)
  Encoding(@encode.EncodeFailure)
  MissingCeiling
  DepthExceeded
  BytesExceeded
} derive(Debug)

///|
/// Successful static checking of the values-specific recursive resource scope.
/// Selected ceilings retain the same policy owner as the row/wire limits.
/// Canonical limit binding and execution enforcement remain separate.
pub struct ValuesRecursiveAdmission {
  rows : ValuesRowLimit
  byte_ceiling : @policy.Ceiling
  depth_ceiling : @policy.Ceiling
  bytes : Int
  type_depth : Int
  selected_fields : Int
  work : Int
}

///|
/// Validate declared depth even without rows, then measure selected typed cells
/// without row wrappers or double-counting nested containers. Work bounds schema
/// frames, field/row/cell visits and encoded value nodes cumulatively. It does not
/// replace a wire-byte budget or bound string-encoding instructions/heap usage.
pub fn check_values_recursive_resources(
  rows : ValuesRowLimit,
  max_work : Int,
  max_bytes : Int,
  max_depth : Int,
) -> Result[ValuesRecursiveAdmission, ValuesRecursiveIssue] {
  if max_work < 0 || max_bytes < 0 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  let wire = rows.wire
  let bound = wire.bound
  let site = bound.site
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOwner)
  }
  guard step.operation is @pipeline.Values(values) else {
    return Err(ForeignOwner)
  }
  guard @policy.ceiling(wire.policy, "max_nested_value_bytes")
    is Some(byte_ceiling) else {
    return Err(MissingCeiling)
  }
  guard @policy.ceiling(wire.policy, "max_nested_value_depth")
    is Some(depth_ceiling) else {
    return Err(MissingCeiling)
  }
  let schema = @values.output_schema(values)
  let width = @schema.field_count(schema)
  let mut work = 0
  let mut type_depth = 0
  let mut selected_fields = 0
  let selected : Array[Bool] = []
  for column in 0..<width {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let field = @schema.field_at(schema, column).unwrap()
    let is_selected = match field.contract.shape {
      Array(_, ..) | Object(_) | Vector(..) => true
      _ => false
    }
    selected.push(is_selected)
    if is_selected {
      selected_fields += 1
    }
    let pending : Array[ValuesTypeFrame] = [Read(field.contract, 0)]
    while pending.pop() is Some(frame) {
      if work >= max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      match frame {
        Read(contract, depth) => {
          let container = match contract.shape {
            Array(_, ..) | Object(_) | Vector(..) => true
            _ => false
          }
          let next = if container {
            if depth >= max_depth {
              return Err(BudgetExceeded)
            }
            depth + 1
          } else {
            depth
          }
          type_depth = type_depth.max(next)
          if type_depth.to_int64() > @policy.ceiling_value(depth_ceiling) {
            return Err(DepthExceeded)
          }
          match contract.shape {
            Array(item, ..) => pending.push(Read(item, next))
            Object(fields) => pending.push(Fields(fields, 0, next))
            Text(_)
            | Number
            | Boolean
            | Timestamp
            | Date
            | Decimal(..)
            | Vector(..) => ()
            Json | ResourceRef(..) | ArtifactRef(..) => return Err(ForeignOwner)
          }
        }
        Fields(fields, index, depth) =>
          if @contract.field_at(fields, index) is Some(field) {
            pending.push(Fields(fields, index + 1, depth))
            pending.push(Read(field.contract, depth))
          }
      }
    }
  }
  let mut bytes = 0
  let mut next_binding = 1
  for row_index in 0..<@values.row_count(values) {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let row = @values.row_at(values, row_index).unwrap()
    for column in 0..<width {
      if work >= max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let (value, next) = match
        resolved_values_cell(
          bound.cells,
          site,
          values,
          bound.requirement_index,
          row,
          row_index,
          column,
          next_binding,
        ) {
        Ok(v) => v
        Err(e) => return Err(Measurement(e))
      }
      next_binding = next
      if selected[column] {
        try {
          let out = @encode.measuring_writer(
            max_bytes - bytes,
            max_work - work,
            max_depth,
          )
          @value.emit_wire_value(value.value, out)
          let (cell_bytes, nodes, _) = @encode.finish_measurement_usage(out)
          bytes += cell_bytes
          work += nodes
        } catch {
          e => return Err(Encoding(e))
        }
        if bytes.to_int64() > @policy.ceiling_value(byte_ceiling) {
          return Err(BytesExceeded)
        }
      }
    }
  }
  if next_binding != @values.pending_validation_count(values) {
    return Err(ForeignOwner)
  }
  Ok({
    rows,
    byte_ceiling,
    depth_ceiling,
    bytes,
    type_depth,
    selected_fields,
    work,
  })
}
