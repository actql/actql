///|
/// Location sidecars for the very same expressions emitted in the step graph.
/// Not a sealed fragment: canonical source and demand evidence remain to bind.
struct RootIndex {
  sequence : PreparedSequence
  entries : Array[ExpressionRoot]
  start_step : Int
  end_step : Int
}

///|
pub struct ExpressionRoot {
  step_index : Int
  step_id : String
  parameter_pointer : String
  expression : Expression
  typed_expression : @typing.TypedExpression
}

///|
pub(all) struct RootLimits {
  max_roots : Int
  max_pointer_bytes : Int
  max_work : Int
}

///|
pub(all) enum RootIssue {
  InvalidRootLimits
  RootLimit
  InvalidStep
  NotExpressionKernel
  NeedsOrderedEncoding
}

///|
pub fn root_count(index : RootIndex) -> Int {
  index.entries.length()
}

///|
pub fn root_at(index : RootIndex, i : Int) -> ExpressionRoot? {
  index.entries.get(i)
}

///|
pub fn root_sequence(index : RootIndex) -> PreparedSequence {
  index.sequence
}

///|
/// Half-open scope, also retained when an empty snapshot map has no roots.
pub fn root_step_range(index : RootIndex) -> (Int, Int) {
  (index.start_step, index.end_step)
}

///|
// RFC6901 escaping changes sort order: '/' precedes 'a', but '~1' follows it.
// Budget UTF-8 bytes before constructing the escaped pointer.
fn root_pointer(name : String, available : Int) -> String? {
  if available < 7 || name.length() > available - 7 {
    return None
  }
  let mut bytes = 7
  for c in name {
    let n = c.to_int()
    let size = if c == '~' || c == '/' {
      2
    } else if n <= 0x7f {
      1
    } else if n <= 0x7ff {
      2
    } else if n <= 0xffff {
      3
    } else {
      4
    }
    if size > available - bytes {
      return None
    }
    bytes += size
  }
  let out = StringBuilder()
  out.write_string("/exprs/")
  for c in name {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  Some(out.to_string())
}

///|
fn group_root_pointer(name : String, leaf : String, available : Int) -> String? {
  let fixed = 7 + leaf.length()
  if available < fixed || name.length() > available - fixed {
    return None
  }
  let out = StringBuilder()
  out.write_string("/aggs/")
  for c in name {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  out.write_char('/')
  out.write_string(leaf)
  let pointer = out.to_string()
  if @utf8.encode(pointer).length() > available {
    None
  } else {
    Some(pointer)
  }
}

///|
fn analytic_root_pointer(
  name : String,
  leaf : String,
  available : Int,
) -> String? {
  let fixed = 12 + leaf.length()
  if available < fixed || name.length() > available - fixed {
    return None
  }
  let out = StringBuilder()
  out.write_string("/functions/")
  for c in name {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  out.write_char('/')
  out.write_string(leaf)
  let pointer = out.to_string()
  if @utf8.encode(pointer).length() > available {
    None
  } else {
    Some(pointer)
  }
}

///|
pub fn prepare_roots(
  sequence : PreparedSequence,
  limits : RootLimits,
) -> Result[RootIndex, RootIssue] {
  prepare_root_range(sequence, 0, sequence.steps.length(), limits)
}

///|
/// Roots for a single expression kernel's fragment, retaining the original
/// sequence and step identity. This does not construct a shortened sequence or
/// imply that values/select belong inside the expression-fragment contract.
pub fn prepare_kernel_roots(
  sequence : PreparedSequence,
  step_index : Int,
  limits : RootLimits,
) -> Result[RootIndex, RootIssue] {
  let step = match sequence.steps.get(step_index) {
    Some(step) => step
    None => return Err(InvalidStep)
  }
  match step {
    ValuesStep(_)
    | TimeSeriesStep(_)
    | WindowStep(_)
    | JoinStep(_)
    | IntervalJoinStep(_)
    | AsOfJoinStep(_)
    | SequenceMatchStep(_)
    | CrossJoinStep(_)
    | AppendStep(_)
    | SetStep(_)
    | NestStep(_)
    | GraphMatchStep(_)
    | GraphDiagnosticStep(_)
    | GraphSubgraphStep(_)
    | GraphEqualityStep(_)
    | GraphNormalizeStep(_)
    | GraphDeltaStep(_)
    | GraphUnionStep(_)
    | GraphSubtractionStep(_)
    | GraphTraverseStep(_)
    | PropertyGraphConstructionStep(_)
    | VectorStep(_)
    | EventStep(_)
    | CarrierProjectionStep(_)
    | InferBoundary(_) => return Err(NotExpressionKernel)
    RowStep(kernel) =>
      match kernel.body {
        Select(_)
        | AssertUnique(_)
        | JsonPick(_, _, _)
        | Limit(_, _, _)
        | TopK(_, _)
        | PartitionedTopK(_, _)
        | Pivot(_)
        | Unnest(_, _, _, _, _)
        | Unpivot(_, _, _, _)
        | DistinctRows
        | DedupeRows
        | StableSort(_)
        | Lag(_, _)
        | Watermark(_, _, _, _)
        | CountGroups(_) => return Err(NotExpressionKernel)
        Filter(_)
        | AssertAll(_)
        | SnapshotMap(_)
        | OrderedBindings(_)
        | Groups(_)
        | AnalyticRows(_) => ()
      }
  }
  prepare_root_range(sequence, step_index, step_index + 1, limits)
}

///|
fn prepare_root_range(
  sequence : PreparedSequence,
  start_step : Int,
  end_step : Int,
  limits : RootLimits,
) -> Result[RootIndex, RootIssue] {
  if limits.max_roots < 0 || limits.max_pointer_bytes < 0 || limits.max_work < 0 {
    return Err(InvalidRootLimits)
  }
  let mut work = limits.max_work
  let mut bytes = limits.max_pointer_bytes
  let mut sorted : Array[ExpressionRoot] = []
  for step_index = start_step
      step_index < end_step
      step_index = step_index + 1 {
    if work == 0 {
      return Err(RootLimit)
    }
    work -= 1
    let bindings = match sequence.steps[step_index] {
      ValuesStep(_)
      | TimeSeriesStep(_)
      | WindowStep(_)
      | JoinStep(_)
      | IntervalJoinStep(_)
      | AsOfJoinStep(_)
      | CrossJoinStep(_)
      | AppendStep(_)
      | SetStep(_)
      | NestStep(_)
      | GraphMatchStep(_)
      | GraphDiagnosticStep(_)
      | GraphSubgraphStep(_)
      | GraphEqualityStep(_)
      | GraphNormalizeStep(_)
      | GraphDeltaStep(_)
      | GraphUnionStep(_)
      | GraphSubtractionStep(_)
      | GraphTraverseStep(_)
      | PropertyGraphConstructionStep(_)
      | VectorStep(_)
      | EventStep(_)
      | CarrierProjectionStep(_)
      | InferBoundary(_) => continue
      SequenceMatchStep(sequence_match) => {
        for index in 0..<sequence_match.predicates.length() {
          let pointer = "/pattern/" + index.to_string() + "/where"
          if sorted.length() == limits.max_roots ||
            pointer.length() > bytes ||
            pointer.length() >= work {
            return Err(RootLimit)
          }
          bytes -= pointer.length()
          work -= 1 + pointer.length()
          let expression = sequence_match.predicates[index]
          sorted.push({
            step_index,
            step_id: sequence.owner.prepared.nodes[step_index].id,
            parameter_pointer: pointer,
            expression,
            typed_expression: expression.typed_owner,
          })
        }
        continue
      }
      RowStep(kernel) =>
        match kernel.body {
          Select(_)
          | AssertUnique(_)
          | JsonPick(_, _, _)
          | Limit(_, _, _)
          | TopK(_, _)
          | PartitionedTopK(_, _)
          | Pivot(_)
          | Unnest(_, _, _, _, _)
          | Unpivot(_, _, _, _)
          | DistinctRows
          | DedupeRows
          | StableSort(_)
          | Lag(_, _)
          | Watermark(_, _, _, _)
          | CountGroups(_) => continue
          AnalyticRows(analytic) => {
            for call in analytic.calls {
              let add = fn(leaf : String, expr : Expression) -> Bool {
                if sorted.length() == limits.max_roots || work == 0 {
                  return false
                }
                guard analytic_root_pointer(call.name, leaf, bytes)
                  is Some(pointer) else {
                  return false
                }
                let size = @utf8.encode(pointer).length()
                if size >= work {
                  return false
                }
                bytes -= size
                work -= 1 + size
                sorted.push({
                  step_index,
                  step_id: sequence.owner.prepared.nodes[step_index].id,
                  parameter_pointer: pointer,
                  expression: expr,
                  typed_expression: expr.typed_owner,
                })
                true
              }
              match call.function {
                PreparedLag(expression, _)
                | PreparedLead(expression, _)
                | PreparedFirstValue(expression)
                | PreparedLastValue(expression) =>
                  if !add("expr", expression) {
                    return Err(RootLimit)
                  }
                PreparedFrameAggregate(aggregate) => {
                  if aggregate.filter is Some(filter) && !add("filter", filter) {
                    return Err(RootLimit)
                  }
                  if aggregate.argument is AggregateExpression(expression) &&
                    !add("expr", expression) {
                    return Err(RootLimit)
                  }
                }
                PreparedRowNumber | PreparedRank | PreparedDenseRank => ()
              }
            }
            continue
          }
          Groups(group) => {
            for i in 0..<group.aggregates.length() {
              let aggregate = group.aggregates[i]
              let add = fn(leaf : String, expr : Expression) -> Bool {
                if sorted.length() == limits.max_roots || work == 0 {
                  return false
                }
                guard group_root_pointer(aggregate.name, leaf, bytes)
                  is Some(pointer) else {
                  return false
                }
                let size = @utf8.encode(pointer).length()
                if size >= work {
                  return false
                }
                bytes -= size
                work -= 1 + size
                sorted.push({
                  step_index,
                  step_id: sequence.owner.prepared.nodes[step_index].id,
                  parameter_pointer: pointer,
                  expression: expr,
                  typed_expression: expr.typed_owner,
                })
                true
              }
              if aggregate.filter is Some(filter) && !add("filter", filter) {
                return Err(RootLimit)
              }
              if aggregate.argument is AggregateExpression(expression) &&
                !add("expr", expression) {
                return Err(RootLimit)
              }
            }
            continue
          }
          Filter(expr) | AssertAll(expr) => {
            if sorted.length() == limits.max_roots || bytes < 5 || work < 6 {
              return Err(RootLimit)
            }
            bytes -= 5
            work -= 6
            sorted.push({
              step_index,
              step_id: sequence.owner.prepared.nodes[step_index].id,
              parameter_pointer: "/expr",
              expression: expr,
              typed_expression: expr.typed_owner,
            })
            continue
          }
          OrderedBindings(bindings) => {
            for i = 0; i < bindings.length(); i = i + 1 {
              let pointer = "/bindings/" + i.to_string() + "/expr"
              if sorted.length() == limits.max_roots ||
                pointer.length() > bytes ||
                pointer.length() >= work {
                return Err(RootLimit)
              }
              bytes -= pointer.length()
              work -= 1 + pointer.length()
              let expr = bindings[i].1
              sorted.push({
                step_index,
                step_id: sequence.owner.prepared.nodes[step_index].id,
                parameter_pointer: pointer,
                expression: expr,
                typed_expression: expr.typed_owner,
              })
            }
            continue
          }
          SnapshotMap(bindings) => bindings
        }
    }
    if bindings.length() > limits.max_roots - sorted.length() {
      return Err(RootLimit)
    }
    for (name, expr) in bindings {
      // A scan is charged even if the subsequent pointer byte ceiling fails.
      if work == 0 || name.length() > work - 1 {
        return Err(RootLimit)
      }
      work -= 1 + name.length()
      guard root_pointer(name, bytes) is Some(pointer) else {
        return Err(RootLimit)
      }
      let size = @utf8.encode(pointer).length()
      if size > work {
        return Err(RootLimit)
      }
      work -= size
      bytes -= size
      sorted.push({
        step_index,
        step_id: sequence.owner.prepared.nodes[step_index].id,
        parameter_pointer: pointer,
        expression: expr,
        typed_expression: expr.typed_owner,
      })
    }
  }
  // Bounded bottom-up merge: sorting never changes the row evaluation order.
  // At most two root-reference arrays coexist; each is bounded by max_roots.
  let mut width = 1
  while width < sorted.length() {
    let next : Array[ExpressionRoot] = []
    let mut start = 0
    while start < sorted.length() {
      let middle = start + Int::min(width, sorted.length() - start)
      let end = middle + Int::min(width, sorted.length() - middle)
      let mut left = start
      let mut right = middle
      while left < middle || right < end {
        if work == 0 {
          return Err(RootLimit)
        }
        work -= 1
        let take_left = if left == middle {
          false
        } else if right == end {
          true
        } else if sorted[left].step_index != sorted[right].step_index {
          sorted[left].step_index < sorted[right].step_index
        } else {
          for
            pointer in [
              sorted[left].parameter_pointer,
              sorted[right].parameter_pointer,
            ] {
            if pointer.length() > work {
              return Err(RootLimit)
            }
            work -= pointer.length()
          }
          @canonical.compare_utf16(
            sorted[left].parameter_pointer,
            sorted[right].parameter_pointer,
          ) <=
          0
        }
        if take_left {
          next.push(sorted[left])
          left += 1
        } else {
          next.push(sorted[right])
          right += 1
        }
      }
      start = end
    }
    sorted = next
    if width >= sorted.length() - width {
      break
    }
    width += width
  }
  Ok({ sequence, entries: sorted, start_step, end_step, })
}
