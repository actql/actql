///|
// The caller has validated operand arity, units and exact input ownership.
// This computes a bound on successful output, not an observed count or an
// execution permission. Keep it independent of proof encoding and admission.
fn calculate_bound_value(
  rule : Rule,
  n : Int,
  input_value : (Int) -> @numeric.Value,
  join_evidence : @pipeline.JoinEvidence?,
) -> Result[Int64, Issue] {
  let count = match rule {
    One => 1L
    Constant(n) => n
    GraphQuery(query) =>
      match query_bound_value(query, i => @numeric.value(input_value(i))) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
    GraphMeasure(_, _, _, factor) =>
      match @numeric.multiply(input_value(0), @numeric.read(factor).unwrap()) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
    GraphCombine(_, _) => {
      let mut total = @numeric.read(0L).unwrap()
      for i in 0..<n {
        total = match @numeric.add(total, input_value(i)) {
          Ok(v) => v
          Err(_) => return Err(BoundOverflow)
        }
      }
      @numeric.value(total)
    }
    Preserve => @numeric.value(input_value(0))
    Clamp(maximum) =>
      @numeric.value(
        @numeric.clamp(
          if n == 0 {
            None
          } else {
            Some(input_value(0))
          },
          @numeric.read(maximum).unwrap(),
        ),
      )
    Sum =>
      match @numeric.add(input_value(0), input_value(1)) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
    Join(kind) =>
      match join_bound(kind, input_value(0), input_value(1), join_evidence) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
    Multiply(factor) =>
      match @numeric.multiply(input_value(0), @numeric.read(factor).unwrap()) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
    QueryTopK(k) => {
      let query = input_value(n - 1)
      let maximum = @numeric.read(k).unwrap()
      let factor = if n == 1 {
        maximum
      } else {
        @numeric.minimum(input_value(0), maximum)
      }
      match @numeric.multiply(query, factor) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
      }
    }
    Ranking(_, maximum) =>
      if n == 0 {
        maximum.unwrap()
      } else {
        let mut total = 0L
        for i in 0..<n {
          let next = @numeric.value(input_value(i))
          total = match maximum {
            Some(k) => if next >= k - total { k } else { total + next }
            None =>
              match
                @numeric.add(@numeric.read(total).unwrap(), input_value(i)) {
                Ok(v) => @numeric.value(v)
                Err(_) => return Err(BoundOverflow)
              }
          }
        }
        total
      }
  }
  Ok(count)
}
