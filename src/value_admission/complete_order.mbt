///|
priv enum CompleteOrderFrame {
  OrderRead(Value)
  OrderArray(FrozenArray[Value], Int)
  OrderObject(FrozenArray[(String, Value)], Int)
  OrderVector(FrozenArray[Double], Int)
  OrderText(@encode.StringEmitCursor, Bool)
  OrderEndEntry
  OrderEndAggregate
}

///|
pub(all) enum CompleteOrderIssue {
  InvalidCompleteOrderLimits
  CompleteOrderLimit
  CompleteOrderReferenceUnavailable
} derive(Eq, Debug)

///|
fn begin_order_value(
  out : @encode.Writer,
  tag : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  @encode.string_value(out, tag)
}

///|
/// Resumable view of the same typed-value order owner. Pending frames and the
/// provisional writer remain private until the complete key is available.
struct CompleteOrder {
  mut recheck : RecheckCursor?
  pending : Array[CompleteOrderFrame]
  mut out : @encode.Writer?
  mut terminal : Bool
}

///|
pub enum CompleteOrderPoll {
  OrderContinue(work~ : Int)
  OrderComplete(String, bytes~ : Int, work~ : Int)
  OrderFailed(CompleteOrderIssue, work~ : Int)
}

///|
/// Produce the canonical typed-value order key used by structural set laws.
/// Reference capability material is excluded; only its live semantic identity
/// participates. Aggregate traversal is iterative and bounded by the supplied
/// admitted-value limits.
pub fn start_complete_order(
  checked : CheckedValue,
  limits : Limits,
  max_output_bytes? : Int? = None,
) -> Result[CompleteOrder, CompleteOrderIssue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    max_output_bytes.map(limit => limit < 0).unwrap_or(false) ||
    limits.max_nodes > (2147483647 - 4) / 4 ||
    limits.max_depth > (2147483647 - 2) / 2 {
    return Err(InvalidCompleteOrderLimits)
  }
  guard start_recheck_runtime_value(checked.value, checked.contract, limits)
    is Some(recheck) else {
    return Err(CompleteOrderLimit)
  }
  if limits.max_nodes > (2147483647 - 128) / 96 {
    return Err(InvalidCompleteOrderLimits)
  }
  let structural_bytes = limits.max_nodes * 96 + 128
  if limits.max_text_bytes > (2147483647 - structural_bytes) / 6 {
    return Err(InvalidCompleteOrderLimits)
  }
  let derived_order_bytes = structural_bytes + limits.max_text_bytes * 6
  let max_order_bytes = Int::min(
    derived_order_bytes,
    max_output_bytes.unwrap_or(derived_order_bytes),
  )
  try {
    let out = @encode.writer(
      max_order_bytes,
      limits.max_nodes * 4 + 4,
      limits.max_depth * 2 + 2,
    )
    Ok({
      recheck: Some(recheck),
      pending: [OrderRead(checked.value)],
      out: Some(out),
      terminal: false,
    })
  } catch {
    _ => Err(CompleteOrderLimit)
  }
}

///|
pub fn cancel_complete_order(value : CompleteOrder) -> Unit {
  if value.recheck is Some(cursor) {
    cancel_recheck_runtime_value(cursor)
  }
  value.recheck = None
  // A pending scalar emission is always the top frame; no other work can
  // borrow its writer until that same emission finishes.
  if value.pending.length() > 0 {
    match value.pending[value.pending.length() - 1] {
      OrderText(cursor, _) => @encode.cancel_string_value(cursor)
      _ => ()
    }
  }
  value.pending.clear()
  value.pending.shrink_to_fit()
  if value.out is Some(out) {
    @encode.cancel_writer(out)
  }
  value.out = None
  value.terminal = true
}

///|
pub fn advance_complete_order(
  value : CompleteOrder,
  quantum : Int,
) -> CompleteOrderPoll {
  if quantum < 1 || value.terminal {
    return OrderFailed(InvalidCompleteOrderLimits, work=0)
  }
  let mut work = 0
  try {
    guard value.out is Some(out) else {
      return OrderFailed(CompleteOrderLimit, work=0)
    }
    while work < quantum {
      work += 1
      if value.recheck is Some(cursor) {
        match advance_recheck_runtime_value(cursor) {
          RecheckContinue => ()
          RecheckComplete(_, _, _) => {
            cancel_recheck_runtime_value(cursor)
            value.recheck = None
          }
          RecheckFailed => {
            cancel_complete_order(value)
            return OrderFailed(CompleteOrderLimit, work~)
          }
        }
        continue
      }
      guard value.pending.pop() is Some(frame) else {
        let (text, bytes, _, _) = @encode.finish_text_usage(out)
        cancel_complete_order(value)
        return OrderComplete(text, bytes~, work~)
      }
      let pending = value.pending
      match frame {
        OrderRead(child) =>
          match child {
            JsonData(payload) => {
              begin_order_value(out, "json")
              // JSON adds one typed wrapper; container payloads close themselves.
              pending.push(OrderEndEntry)
              pending.push(OrderRead(payload))
            }
            Null => {
              begin_order_value(out, "null")
              @encode.end_array(out)
            }
            Boolean(value) => {
              begin_order_value(out, "boolean")
              @encode.bool_value(out, value)
              @encode.end_array(out)
            }
            Number(value) => {
              begin_order_value(out, "number")
              @encode.number_value(out, value)
              @encode.end_array(out)
            }
            Text(value) => {
              begin_order_value(out, "text")
              pending.push(
                OrderText(@encode.start_string_value(out, value), true),
              )
            }
            Date(value) => {
              begin_order_value(out, "date")
              @encode.string_value(out, value)
              @encode.end_array(out)
            }
            Timestamp(value) => {
              begin_order_value(out, "timestamp")
              @encode.string_value(out, value)
              @encode.end_array(out)
            }
            Decimal(value) => {
              begin_order_value(out, "decimal")
              @encode.string_value(out, decimal_wire_text(value))
              @encode.end_array(out)
            }
            Array(values) => {
              begin_order_value(out, "array")
              @encode.begin_array(out)
              pending.push(OrderEndAggregate)
              pending.push(OrderArray(values, 0))
            }
            Object(values) => {
              begin_order_value(out, "object")
              @encode.begin_array(out)
              pending.push(OrderEndAggregate)
              pending.push(OrderObject(values, 0))
            }
            Vector(values) => {
              begin_order_value(out, "vector")
              @encode.begin_array(out)
              pending.push(OrderEndAggregate)
              pending.push(OrderVector(values, 0))
            }
            Reference(reference) => {
              if !reference_available(reference) {
                cancel_complete_order(value)
                return OrderFailed(CompleteOrderReferenceUnavailable, work~)
              }
              begin_order_value(out, "reference")
              @encode.string_value(out, reference_identity_cid(reference))
              @encode.end_array(out)
            }
          }
        OrderArray(values, index) =>
          if element_at(values, index) is Some(value) {
            pending.push(OrderArray(values, index + 1))
            pending.push(OrderRead(value))
          }
        OrderObject(values, index) =>
          if element_at(values, index) is Some((name, value)) {
            pending.push(OrderObject(values, index + 1))
            pending.push(OrderEndEntry)
            pending.push(OrderRead(value))
            @encode.begin_array(out)
            pending.push(
              OrderText(@encode.start_string_value(out, name), false),
            )
          }
        OrderVector(values, index) =>
          if element_at(values, index) is Some(value) {
            @encode.number_value(out, value)
            pending.push(OrderVector(values, index + 1))
          }
        OrderText(cursor, close_value) =>
          if @encode.advance_string_value(cursor) {
            if close_value {
              @encode.end_array(out)
            }
          } else {
            pending.push(OrderText(cursor, close_value))
          }
        OrderEndEntry => @encode.end_array(out)
        OrderEndAggregate => {
          @encode.end_array(out)
          @encode.end_array(out)
        }
      }
    }
    OrderContinue(work~)
  } catch {
    _ => {
      cancel_complete_order(value)
      OrderFailed(CompleteOrderLimit, work~)
    }
  }
}

///|
/// Synchronous convenience view; bounded execution uses the resumable cursor.
pub fn complete_order_key(
  checked : CheckedValue,
  limits : Limits,
) -> Result[String, CompleteOrderIssue] {
  let cursor = match start_complete_order(checked, limits) {
    Ok(cursor) => cursor
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_complete_order(cursor, 64) {
      OrderContinue(..) => ()
      OrderComplete(text, ..) => return Ok(text)
      OrderFailed(issue, ..) => return Err(issue)
    }
  } nobreak {
    Err(CompleteOrderLimit)
  }
}
