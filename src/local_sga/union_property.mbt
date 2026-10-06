///|
priv enum UnionPropertyPhase {
  StartProperty
  EqualProperty
  ReadItem
  AdmitItem
  OrderItem
  CompareItem
  SortItem
  CompareItemOrder
  EmitItems
  FinishProperty
}

///|
priv struct UnionSetItem {
  value : @value.CheckedValue
  order : String
  mut retained : Bool
}

///|
/// Private temporary work for one checked field strategy, not a Graph/Store
/// owner or a permission to publish a record. The caller owns stop and budgets.
priv struct UnionProperty {
  left : @value.CheckedValue
  right : @value.CheckedValue?
  output : @contract.Contract
  strategy : @graph_type.UnionPropertyStrategy
  limits : @value.Limits
  max_items : Int
  max_order_bytes : Int
  mut retained_order_bytes : Int
  mut candidate_order_bytes : Int
  mut phase : UnionPropertyPhase
  mut side : Int
  mut index : Int
  mut comparison_index : Int
  mut candidate : @value.CheckedValue?
  mut candidate_order : String
  items : Array[UnionSetItem]
  mut recheck : @value.RecheckCursor?
  mut equality : @value.CompleteEquality?
  mut order : @value.CompleteOrder?
  mut comparison : @value.BoundedKeyComparison?
  mut array : @value.ArrayBuilder?
  mut terminal : Bool
}

///|
pub(all) enum UnionPropertyIssue {
  InvalidUnionProperty
  UnionPropertyConflict
  UnionPropertyLimit
  UnionPropertyComparison(@value.CompleteEqualityIssue)
  UnionPropertyOrder(@value.CompleteOrderIssue)
  UnionPropertyArithmetic(@exact.Issue)
} derive(Eq, Debug)

///|
priv enum UnionPropertyPoll {
  PropertyContinue(Int)
  PropertyComplete(@value.CheckedValue, Int)
  PropertyFailed(UnionPropertyIssue, Int)
}

///|
fn start_union_property(
  left : @value.CheckedValue,
  right : @value.CheckedValue?,
  output : @contract.Contract,
  strategy : @graph_type.UnionPropertyStrategy,
  limits : @value.Limits,
  max_items : Int,
  max_order_bytes? : Int? = None,
) -> UnionProperty? {
  let max_order_bytes = max_order_bytes.unwrap_or(limits.max_text_bytes)
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    max_items < 0 ||
    max_order_bytes < 0 {
    return None
  }
  Some({
    left,
    right,
    output,
    strategy,
    limits,
    max_items,
    max_order_bytes,
    retained_order_bytes: 0,
    candidate_order_bytes: 0,
    phase: StartProperty,
    side: 0,
    index: 0,
    comparison_index: 0,
    candidate: None,
    candidate_order: "",
    items: [],
    recheck: None,
    equality: None,
    order: None,
    comparison: None,
    array: None,
    terminal: false,
  })
}

///|
fn cleanup_union_property(value : UnionProperty) -> Unit {
  if value.recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
  }
  if value.order is Some(cursor) {
    @value.cancel_complete_order(cursor)
  }
  if value.array is Some(array) {
    @value.cancel_array_value(array) |> ignore
  }
  value.recheck = None
  value.equality = None
  value.order = None
  value.comparison = None
  value.array = None
  value.candidate = None
  value.candidate_order = ""
  value.retained_order_bytes = 0
  value.candidate_order_bytes = 0
  value.items.clear()
  value.items.shrink_to_fit()
  value.terminal = true
}

///|
fn union_property_failed(
  value : UnionProperty,
  issue : UnionPropertyIssue,
  work : Int,
) -> UnionPropertyPoll {
  cleanup_union_property(value)
  PropertyFailed(issue, work)
}

///|
fn union_property_recheck(value : UnionProperty, result : @value.Value) -> Bool {
  value.recheck = @value.start_recheck_runtime_value(
    result,
    value.output,
    value.limits,
  )
  value.phase = FinishProperty
  value.recheck is Some(_)
}

///|
fn advance_union_property(
  value : UnionProperty,
  quantum : Int,
) -> UnionPropertyPoll {
  if value.terminal || quantum < 1 {
    return PropertyFailed(InvalidUnionProperty, 0)
  }
  let mut work = 0
  while work < quantum {
    work += 1
    match value.phase {
      StartProperty => {
        guard value.right is Some(right) else {
          if !union_property_recheck(value, value.left.value) {
            return union_property_failed(value, UnionPropertyLimit, work)
          }
          continue
        }
        match value.strategy {
          @graph_type.UnionExactEqual => {
            value.equality = match
              @value.start_complete_equality(value.left, right, value.limits) {
              Ok(cursor) => Some(cursor)
              Err(issue) =>
                return union_property_failed(
                  value,
                  UnionPropertyComparison(issue),
                  work,
                )
            }
            value.phase = EqualProperty
          }
          @graph_type.UnionSetUnion | @graph_type.UnionSetDifference => {
            guard value.left.value is @value.Array(_) &&
              right.value is @value.Array(_) &&
              value.output.shape is @contract.Array(_, ..) else {
              return union_property_failed(value, InvalidUnionProperty, work)
            }
            value.phase = ReadItem
          }
          strategy => {
            guard value.left.value is @value.Number(first) &&
              right.value is @value.Number(second) else {
              return union_property_failed(value, InvalidUnionProperty, work)
            }
            let result = match strategy {
              @graph_type.UnionNumberSum => first + second
              @graph_type.UnionNumberMean =>
                match @exact.pairwise_mean(first, second) {
                  Ok(result) => result
                  Err(issue) =>
                    return union_property_failed(
                      value,
                      UnionPropertyArithmetic(issue),
                      work,
                    )
                }
              @graph_type.UnionNumberMax =>
                if first > second {
                  first
                } else {
                  second
                }
              @graph_type.UnionNumberMin =>
                if first < second {
                  first
                } else {
                  second
                }
              _ =>
                return union_property_failed(value, InvalidUnionProperty, work)
            }
            guard @value.number_value(result) is Some(result) else {
              return union_property_failed(value, InvalidUnionProperty, work)
            }
            if !union_property_recheck(value, result) {
              return union_property_failed(value, UnionPropertyLimit, work)
            }
          }
        }
      }
      EqualProperty => {
        guard value.equality is Some(cursor) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        match @value.advance_complete_equality(cursor, 1) {
          @value.EqualityContinue(..) => ()
          @value.EqualityComplete(equal~, ..) => {
            value.equality = None
            if !equal {
              return union_property_failed(value, UnionPropertyConflict, work)
            }
            if !union_property_recheck(value, value.left.value) {
              return union_property_failed(value, UnionPropertyLimit, work)
            }
          }
          @value.EqualityFailed(issue, ..) =>
            return union_property_failed(
              value,
              UnionPropertyComparison(issue),
              work,
            )
        }
      }
      ReadItem => {
        let source = if value.side == 0 {
          value.left
        } else {
          value.right.unwrap()
        }
        guard source.value is @value.Array(items) &&
          value.output.shape is @contract.Array(contract, ..) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        if @value.element_at(items, value.index) is Some(item) {
          value.recheck = @value.start_recheck_runtime_value(
            item,
            contract,
            value.limits,
          )
          if value.recheck is None {
            return union_property_failed(value, UnionPropertyLimit, work)
          }
          value.phase = AdmitItem
        } else if value.side == 0 {
          value.side = 1
          value.index = 0
        } else {
          value.index = 0
          value.array = @value.prepare_array_value(value.items.length())
          value.phase = EmitItems
        }
      }
      AdmitItem => {
        guard value.recheck is Some(cursor) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(item, _, _) => {
            value.recheck = None
            value.candidate = Some(item)
            value.order = match
              @value.start_complete_order(
                item,
                value.limits,
                max_output_bytes=Some(value.max_order_bytes),
              ) {
              Ok(cursor) => Some(cursor)
              Err(issue) =>
                return union_property_failed(
                  value,
                  UnionPropertyOrder(issue),
                  work,
                )
            }
            value.phase = OrderItem
          }
          @value.RecheckFailed =>
            return union_property_failed(value, UnionPropertyLimit, work)
        }
      }
      OrderItem => {
        guard value.order is Some(cursor) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        match @value.advance_complete_order(cursor, 1) {
          @value.OrderContinue(..) => ()
          @value.OrderComplete(key, bytes~, ..) => {
            value.order = None
            value.candidate_order = key
            value.candidate_order_bytes = bytes
            value.comparison_index = 0
            value.phase = CompareItem
          }
          @value.OrderFailed(issue, ..) =>
            return union_property_failed(value, UnionPropertyOrder(issue), work)
        }
      }
      CompareItem => {
        guard value.candidate is Some(candidate) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        if value.comparison_index >= value.items.length() {
          if value.strategy == @graph_type.UnionSetDifference && value.side == 1 {
            value.candidate = None
            value.index += 1
            value.phase = ReadItem
          } else {
            if value.items.length() >= value.max_items ||
              value.candidate_order_bytes >
              value.max_order_bytes - value.retained_order_bytes {
              return union_property_failed(value, UnionPropertyLimit, work)
            }
            value.retained_order_bytes += value.candidate_order_bytes
            value.items.push({
              value: candidate,
              order: value.candidate_order,
              retained: true,
            })
            value.candidate = None
            value.comparison_index = value.items.length() - 1
            value.phase = SortItem
          }
          continue
        }
        if value.equality is None {
          value.equality = match
            @value.start_complete_equality(
              candidate,
              value.items[value.comparison_index].value,
              value.limits,
            ) {
            Ok(cursor) => Some(cursor)
            Err(issue) =>
              return union_property_failed(
                value,
                UnionPropertyComparison(issue),
                work,
              )
          }
        } else {
          match @value.advance_complete_equality(value.equality.unwrap(), 1) {
            @value.EqualityContinue(..) => ()
            @value.EqualityComplete(equal~, ..) => {
              value.equality = None
              if equal {
                if value.strategy == @graph_type.UnionSetDifference &&
                  value.side == 1 {
                  value.items[value.comparison_index].retained = false
                }
                value.candidate = None
                value.index += 1
                value.phase = ReadItem
              } else {
                value.comparison_index += 1
              }
            }
            @value.EqualityFailed(issue, ..) =>
              return union_property_failed(
                value,
                UnionPropertyComparison(issue),
                work,
              )
          }
        }
      }
      SortItem => {
        let index = value.comparison_index
        if index > 0 {
          value.comparison = Some(
            @value.start_bounded_token_comparison(
              value.items[index].order,
              value.items[index - 1].order,
            ),
          )
          value.phase = CompareItemOrder
        } else {
          value.index += 1
          value.phase = ReadItem
        }
      }
      CompareItemOrder => {
        guard value.comparison is Some(comparison) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        match @value.advance_bounded_key_comparison(comparison, 1) {
          Err(_) =>
            return union_property_failed(value, InvalidUnionProperty, work)
          Ok(@value.KeyComparisonContinue(..)) => ()
          Ok(@value.KeyComparisonComplete(order~, ..)) => {
            value.comparison = None
            if order < 0 {
              let index = value.comparison_index
              let previous = value.items[index - 1]
              value.items[index - 1] = value.items[index]
              value.items[index] = previous
              value.comparison_index -= 1
              value.phase = SortItem
            } else {
              value.index += 1
              value.phase = ReadItem
            }
          }
        }
      }
      EmitItems => {
        guard value.array is Some(array) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        if value.index < value.items.length() {
          let item = value.items[value.index]
          if item.retained && !@value.append_array_item(array, item.value.value) {
            return union_property_failed(value, UnionPropertyLimit, work)
          }
          value.index += 1
        } else {
          guard @value.finish_bounded_array_value(array) is Some(result) else {
            return union_property_failed(value, UnionPropertyLimit, work)
          }
          value.array = None
          if !union_property_recheck(value, result) {
            return union_property_failed(value, UnionPropertyLimit, work)
          }
        }
      }
      FinishProperty => {
        guard value.recheck is Some(cursor) else {
          return union_property_failed(value, InvalidUnionProperty, work)
        }
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(result, _, _) => {
            cleanup_union_property(value)
            return PropertyComplete(result, work)
          }
          @value.RecheckFailed =>
            return union_property_failed(value, UnionPropertyLimit, work)
        }
      }
    }
  }
  PropertyContinue(work)
}
