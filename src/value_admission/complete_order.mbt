///|
priv enum CompleteOrderFrame {
  OrderRead(Value)
  OrderArray(FrozenArray[Value], Int)
  OrderObject(FrozenArray[(String, Value)], Int)
  OrderVector(FrozenArray[Double], Int)
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
/// Produce the canonical typed-value order key used by structural set laws.
/// Reference capability material is excluded; only its live semantic identity
/// participates. Aggregate traversal is iterative and bounded by the supplied
/// admitted-value limits.
pub fn complete_order_key(
  checked : CheckedValue,
  limits : Limits,
) -> Result[String, CompleteOrderIssue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes > (2147483647 - 4) / 4 ||
    limits.max_depth > (2147483647 - 2) / 2 {
    return Err(InvalidCompleteOrderLimits)
  }
  try {
    let out = @encode.writer(
      limits.max_text_bytes,
      limits.max_nodes * 4 + 4,
      limits.max_depth * 2 + 2,
    )
    let pending : Array[CompleteOrderFrame] = [OrderRead(checked.value)]
    while pending.pop() is Some(frame) {
      match frame {
        OrderRead(value) =>
          match value {
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
              @encode.string_value(out, value)
              @encode.end_array(out)
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
            Reference(value) => {
              if !reference_available(value) {
                return Err(CompleteOrderReferenceUnavailable)
              }
              begin_order_value(out, "reference")
              @encode.string_value(out, reference_identity_cid(value))
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
            @encode.string_value(out, name)
          }
        OrderVector(values, index) =>
          if element_at(values, index) is Some(value) {
            @encode.number_value(out, value)
            pending.push(OrderVector(values, index + 1))
          }
        OrderEndEntry => @encode.end_array(out)
        OrderEndAggregate => {
          @encode.end_array(out)
          @encode.end_array(out)
        }
      }
    }
    Ok(@encode.finish(out))
  } catch {
    _ => Err(CompleteOrderLimit)
  }
}
