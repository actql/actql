///|
pub(all) enum LatePolicy {
  DropLate
  MarkLate
} derive(Eq, Debug)

///|
pub enum WatermarkSource {
  FixedThreshold(Double)
  ThresholdParameter(String)
  PrefixSkew(CountValue, duration~ : Bool)
}

///|
fn watermark_source(
  b : Budget,
  source : @decode.Cursor,
  object : @decode.ObjectView,
  parameters : @parameter.Declarations?,
  types : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> WatermarkSource raise Stop {
  match
    (@decode.lookup(object, "watermark_ms"), @decode.lookup(object, "max_skew")) {
    (Some(value), None) =>
      match @decode.view(value) {
        NumberValue(n) => {
          if @scalar.read_finite_number(n) is None ||
            (n == 0.0 && 1.0 / n < 0.0) {
            fail(value, InvalidCount)
          }
          FixedThreshold(n)
        }
        _ => {
          let o = decoded(@decode.closed_object(value, ["$param"]), value)
          let s = decoded(@decode.required(o, "$param"), value)
          let name = decoded(@decode.text(s), s)
          let ty = match types.get(name) {
            Some(t) => t
            None => fail(s, UnknownParameter(name))
          }
          if !(ty.shape is @contract.Number) || ty.nullable {
            fail(s, InvalidCount)
          }
          pending.push({ kind: BoundFinite(name), source: s, })
          ThresholdParameter(name)
        }
      }
    (None, Some(value)) => {
      pending.push({ kind: WatermarkPrefixOrder, source: value, })
      match @decode.view(value) {
        TextValue(s) =>
          match @scalar.read_duration_ms(s) {
            Some(n) => PrefixSkew(Literal(n), duration=false)
            None => fail(value, InvalidCount)
          }
        ObjectValue(_) => {
          let o = decoded(@decode.closed_object(value, ["$param"]), value)
          let s = decoded(@decode.required(o, "$param"), value)
          let name = decoded(@decode.text(s), s)
          let ty = match types.get(name) {
            Some(t) => t
            None => fail(s, UnknownParameter(name))
          }
          if ty.nullable {
            fail(s, InvalidCount)
          }
          if ty.shape is @contract.Number {
            PrefixSkew(row_count(b, value, 1L, types, pending), duration=false)
          } else {
            let mut duration = false
            if parameters is Some(ds) {
              let n = @parameter.declaration_count(ds)
              spend(b, s, count=n)
              for i in 0..<n {
                let d = @parameter.declaration_at(ds, i).unwrap()
                if d.name == name {
                  duration = d.parameter_type.rule is @contract.Duration
                }
              }
            }
            if !duration {
              fail(s, InvalidCount)
            }
            pending.push({ kind: BoundDuration(name), source: s, })
            PrefixSkew(Parameter(name), duration=true)
          }
        }
        _ => PrefixSkew(row_count(b, value, 1L, types, pending), duration=false)
      }
    }
    _ => fail(source, InvalidBody)
  }
}
