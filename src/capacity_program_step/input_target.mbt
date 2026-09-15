///|
fn rule_input_count_valid(rule : Rule, n : Int) -> Bool {
  match rule {
    One | Constant(_) => n == 0
    Preserve | Multiply(_) | GraphMeasure(_, _, _, _) => n == 1
    Clamp(_) => n <= 1
    Sum | Join(_) => n == 2
    GraphCombine(_, expected) => n == expected
    GraphQuery(query) => n == query.inputs.length()
    QueryTopK(_) => n == 1 || n == 2
    Ranking(expected, maximum) =>
      n == expected || (n == 0 && maximum is Some(_))
  }
}

///|
fn rule_input_descriptor(
  rule : Rule,
  n : Int,
  i : Int,
) -> (@arithmetic.BoundUnit, Int) {
  let unit = match rule {
    GraphMeasure(_, unit, _, _) | GraphCombine(unit, _) => unit
    GraphQuery(query) => query.inputs[i].0
    _ => @arithmetic.Rows
  }
  let edge = match rule {
    GraphMeasure(_, _, edge, _) => edge
    GraphQuery(query) => query.inputs[i].1
    QueryTopK(_) if n == 1 => 1
    _ => i
  }
  (unit, edge)
}

///|
// The preparation path and the public checker use the same exact edge test.
// Rejected candidates also return their traversal cost to the caller.
fn check_input_target_usage(
  pipeline : @pipeline.CheckedPipeline,
  step : @pipeline.CheckedStep,
  rule : Rule,
  n : Int,
  i : Int,
  input : BoundInput,
  max_input_work : Int,
) -> (Result[Unit, Issue], Int) {
  let mut input_work = 0
  let (input_owner, input_target) = source_target(input)
  let (expected_unit, edge) = rule_input_descriptor(rule, n, i)
  if @wire.unit(source_witness(input)) != expected_unit {
    return (Err(InputUnitMismatch(i)), input_work)
  }
  let mut owner = pipeline
  let mut target = @pipeline.input_occurrence_at(step, edge).unwrap().target
  while !(physical_equal(owner, input_owner) && target == input_target) {
    let next = match target {
      @pipeline.Input(input_index) => {
        if input_work >= max_input_work {
          return (Err(InputWorkLimit), input_work)
        }
        input_work = input_work + 1
        guard @pipeline.input_producer(owner, input_index) is Some(producer) else {
          return (Err(MissingInputProducer(i)), input_work)
        }
        owner = @pipeline.producer_pipeline(producer)
        target = @pipeline.producer_target(producer)
        continue
      }
      @pipeline.Step(index) => {
        let step = @pipeline.step_at(owner, index).unwrap()
        let forwarded = forwarded_input(step, expected_unit)
        guard forwarded is Some(next) else {
          if !physical_equal(input_owner, owner) {
            return (Err(InputOwnerMismatch(i)), input_work)
          }
          return (Err(InputTargetMismatch(i)), input_work)
        }
        next
      }
    }
    if input_work >= max_input_work {
      return (Err(InputWorkLimit), input_work)
    }
    input_work = input_work + 1
    target = next
  }
  (Ok(()), input_work)
}
