///|
/// Canonical ordering for retained analytic expression source. The cursors and
/// key Strings stay owned by the checked expression; only field-order slots
/// are retained here. This is prepared once under the cumulative lowering
/// budgets, rather than sorting unaccounted arrays during every emission.
priv struct AnalyticSource {
  root : @decode.Cursor
  objects : Map[Int, Array[(String, @decode.Cursor)]]
}

///|
priv enum AnalyticSourceFrame {
  Value(@decode.Cursor)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(Array[(String, @decode.Cursor)], Int)
}

///|
fn prepare_analytic_source(
  expression : Expression,
  limits : ExpressionLimits,
) -> Result[(AnalyticSource, ExpressionLimits), ExpressionIssue] {
  let root = @syntax.tree(@typing.expression(expression.typed_owner))
  let budget : ExpressionBudget = {
    limits,
    work: 0,
    nodes: 0,
    literal_nodes: 0,
    literal_bytes: 0,
  }
  try {
    let reserve = fn(
      cursor : @decode.Cursor,
      count : Int,
    ) -> Unit raise ExpressionStop {
      if count > limits.max_nodes - budget.nodes {
        expression_fail(cursor, ExpressionBudgetExceeded)
      }
      budget.nodes += count
    }
    let spend = fn(
      cursor : @decode.Cursor,
      count : Int,
    ) -> Unit raise ExpressionStop {
      if count > limits.max_work - budget.work {
        expression_fail(cursor, ExpressionBudgetExceeded)
      }
      budget.work += count
    }
    // Charge the source record and first temporary traversal slot before
    // allocation. Temporary slots are conservatively charged cumulatively.
    reserve(root, 2)
    let objects : Map[Int, Array[(String, @decode.Cursor)]] = Map([])
    let pending = [root]
    while pending.pop() is Some(cursor) {
      spend(cursor, 1)
      if @decode.object_length(cursor) is Some(count) {
        // One map entry plus the retained field-order slots. Strings/cursors
        // are borrowed; their payloads are not copied or reinterpreted.
        reserve(cursor, 1)
        reserve(cursor, count)
        let fields : Array[(String, @decode.Cursor)] = []
        for index in 0..<count {
          spend(cursor, 2)
          guard @decode.field_at(cursor, index) is Some(field) else {
            expression_fail(cursor, MissingCheckedBinding)
          }
          fields.push(field)
        }
        // Bounded insertion sort meters comparisons and moves before each
        // operation. UTF-16 key scans use the same conservative unit charge
        // as root ordering, including equal prefixes and non-BMP keys.
        for index in 1..<count {
          spend(cursor, 1)
          let field = fields[index]
          let mut at = index
          while at > 0 {
            let before = fields[at - 1]
            spend(cursor, 1)
            spend(cursor, before.0.length())
            spend(cursor, field.0.length())
            if @canonical.compare_utf16(before.0, field.0) <= 0 {
              break
            }
            spend(cursor, 1)
            fields[at] = before
            at -= 1
          }
          spend(cursor, 1)
          fields[at] = field
        }
        guard @decode.tree_index(root, cursor) is Some(index) else {
          expression_fail(cursor, MissingCheckedBinding)
        }
        spend(cursor, 1)
        objects[index] = fields
        for (_, child) in fields {
          reserve(cursor, 1)
          spend(cursor, 1)
          pending.push(child)
        }
      } else if @decode.array_length(cursor) is Some(count) {
        for index in 0..<count {
          reserve(cursor, 1)
          spend(cursor, 2)
          guard @decode.element_at(cursor, index) is Some(child) else {
            expression_fail(cursor, MissingCheckedBinding)
          }
          pending.push(child)
        }
      }
    }
    Ok(
      (
        { root, objects, },
        {
          ..limits,
          max_nodes: limits.max_nodes - budget.nodes,
          max_work: limits.max_work - budget.work,
        },
      ),
    )
  } catch {
    ExpressionStop(issue) => Err(issue)
  }
}

///|
fn emit_analytic_source(
  source : AnalyticSource,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[AnalyticSourceFrame] = [Value(source.root)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(cursor) =>
        if @decode.array_length(cursor) is Some(count) {
          @encode.begin_array(out)
          pending.push(ArrayRest(cursor, 0, count))
        } else if @decode.object_length(cursor) is Some(_) {
          guard @decode.tree_index(source.root, cursor) is Some(index) &&
            source.objects.get(index) is Some(fields) else {
            raise @encode.InvalidStructure
          }
          @encode.begin_object(out)
          pending.push(ObjectRest(fields, 0))
        } else {
          match @decode.view(cursor) {
            NullValue => @encode.null_value(out)
            BoolValue(value) => @encode.bool_value(out, value)
            NumberValue(value) => @encode.number_value(out, value)
            TextValue(value) => @encode.string_value(out, value)
            ArrayValue(_) | ObjectValue(_) => raise @encode.InvalidStructure
          }
        }
      ArrayRest(cursor, index, count) =>
        if index == count {
          @encode.end_array(out)
        } else {
          guard @decode.element_at(cursor, index) is Some(child) else {
            raise @encode.InvalidStructure
          }
          pending.push(ArrayRest(cursor, index + 1, count))
          pending.push(Value(child))
        }
      ObjectRest(fields, index) =>
        if index == fields.length() {
          @encode.end_object(out)
        } else {
          let (name, child) = fields[index]
          @encode.key(out, name)
          pending.push(ObjectRest(fields, index + 1))
          pending.push(Value(child))
        }
    }
  }
}
