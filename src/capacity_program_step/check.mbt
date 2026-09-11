///|
pub(all) enum Issue {
  MissingStep
  SubjectMismatch
  UnsupportedProofForm
  UnsupportedOperation
  UnresolvedCount
  LawMismatch
  ValueMismatch
  InvalidDerivation
  InputCountMismatch
  InputOwnerMismatch(Int)
  InputTargetMismatch(Int)
  InputWitnessMismatch(Int)
  InputUnitMismatch(Int)
  BoundOverflow
  InvalidInputWorkLimit
  InputWorkLimit
  MissingInputProducer(Int)
  InvalidBindingLimits
  BindingOwnerMismatch
  BindingWorkLimit
  BindingTextLimit
  InvalidBoundCount
  InvalidBoundMilliseconds(String)
  InvalidOperandWorkLimit
  OperandWorkLimit
  MissingJoinUniqueness
  InvalidSeriesCount(@series.CountIssue)
} derive(Eq, Debug)

///|
/// An owner-relative operation application, not a Program identity or Plan.
struct StepBound {
  pipeline : @pipeline.CheckedPipeline
  index : Int
  proof : @wire.ProgramProofClaim
  inputs : Array[StepBound]
  input_work : Int
  operand_work : Int
  bindings : CountBindings?
  join_evidence : @pipeline.JoinEvidence?
}

///|
/// Internal subject spelling, scoped by the retained checked pipeline owner.
/// Not an authored alias, source pointer, semantic CID or external compiler ID.
pub fn subject_ref(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> String? {
  @pipeline.step_at(pipeline, index).map(_ => {
    "checked-step:" + index.to_string()
  })
}

///|
/// Check input-independent global-group and literal selection upper bounds.
/// Ordered data inputs and their unresolved validations remain on the pipeline.
pub fn check(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
) -> Result[StepBound, Issue] {
  check_with_inputs(pipeline, index, proof, [])
}

///|
priv enum Rule {
  One
  Constant(Int64)
  Preserve
  Clamp(Int64)
  Sum
  Multiply(Int64)
  QueryTopK(Int64)
  Ranking(Int, Int64?)
  Join(@join.Kind)
  GraphMeasure(@arithmetic.BoundUnit, @arithmetic.BoundUnit, Int, Int64)
}

///|
fn operation_rule(
  step : @pipeline.CheckedStep,
  bindings : CountBindings?,
  unit : @arithmetic.BoundUnit,
) -> Result[(String, Rule), Issue] {
  match step.operation {
    @pipeline.GraphConstruction(nodes~, ..) => {
      if unit == @arithmetic.Nodes {
        return Ok(
          (
            "actql.bound.graph-nodes",
            GraphMeasure(
              unit,
              @arithmetic.Rows,
              0,
              if nodes is Some(_) {
                1L
              } else {
                2L
              },
            ),
          ),
        )
      }
      if unit == @arithmetic.Edges {
        return Ok(
          (
            "actql.bound.graph-edges",
            GraphMeasure(
              unit,
              @arithmetic.Rows,
              if nodes is Some(_) {
                1
              } else {
                0
              },
              1L,
            ),
          ),
        )
      }
      return Err(LawMismatch)
    }
    @pipeline.Projection(op) =>
      match @projection.operation(op) {
        @projection.NodeRows =>
          return Ok(
            (
              "actql.bound.graph-node-rows",
              GraphMeasure(@arithmetic.Rows, @arithmetic.Nodes, 0, 1L),
            ),
          )
        @projection.EdgeRows =>
          return Ok(
            (
              "actql.bound.graph-edge-rows",
              GraphMeasure(@arithmetic.Rows, @arithmetic.Edges, 0, 1L),
            ),
          )
        _ => ()
      }
    _ => ()
  }
  match step.operation {
    @pipeline.Values(op) =>
      return Ok(
        ("actql.bound.values", Constant(@values.row_count(op).to_int64())),
      )
    @pipeline.Calendar(op) =>
      match @calendar.cardinality(op) {
        @calendar.AtMost(n) =>
          return Ok(("actql.bound.calendar-series", Constant(n.to_int64())))
        _ => ()
      }
    @pipeline.TimeSeries(op) => {
      let a = match @series.start(op) {
        @series.Literal(_) => None
        @series.Parameter(name) => {
          guard bindings is Some(b) && b.entries.get(name) is Some(entry) else {
            return Err(UnresolvedCount)
          }
          Some(entry.value)
        }
      }
      let z = match @series.end(op) {
        @series.Literal(_) => None
        @series.Parameter(name) => {
          guard bindings is Some(b) && b.entries.get(name) is Some(entry) else {
            return Err(UnresolvedCount)
          }
          Some(entry.value)
        }
      }
      let delta = match @series.step(op) {
        @window.Literal(_) => None
        value =>
          match resolve_milliseconds(value, bindings) {
            Ok(n) => Some(n)
            Err(e) => return Err(e)
          }
      }
      return match
        @series.resolve_row_count(
          op,
          start_value=a,
          end_value=z,
          step_value=delta,
        ) {
        Ok(n) => Ok(("actql.bound.time-series", Constant(n)))
        Err(e) => Err(InvalidSeriesCount(e))
      }
    }
    _ => ()
  }
  if step.operation is @pipeline.Append(..) {
    return Ok(("actql.bound.append", Sum))
  }
  match step.operation {
    @pipeline.Join(checked~, ..) =>
      return Ok(("actql.bound.join-output", Join(@join.kind(checked))))
    @pipeline.CrossJoin(..) =>
      return Ok(("actql.bound.join-output", Join(@join.Inner)))
    @pipeline.IntervalJoin(checked~, ..) =>
      return Ok(("actql.bound.join-output", Join(@join.interval_kind(checked))))
    _ => ()
  }
  if step.operation is @pipeline.AsOfJoin(..) {
    return Ok(("actql.bound.asof-left", Preserve))
  }
  if step.operation is @pipeline.Nearest(checked~, ..) {
    return Ok(
      (
        "actql.bound.nearest",
        QueryTopK(
          @vector.nearest_k(
            @vector.nearest_pair_options(@vector.nearest_pair(checked)),
          ),
        ),
      ),
    )
  }
  if step.operation is @pipeline.Ranking(checked) {
    let options = @vector.merged_ranking_options(checked)
    let maximum = if @vector.ranking_by_count(options) == 0 {
      Some(@vector.ranking_k(options).to_int64())
    } else {
      None
    }
    return Ok(
      (
        "actql.bound.merge-rankings",
        Ranking(@vector.merged_ranking_input_count(checked), maximum),
      ),
    )
  }
  if step.operation is @pipeline.TextRank(checked~, ..) {
    return Ok(
      (
        "actql.bound.text-rank",
        QueryTopK(
          @vector.text_rank_k(@vector.text_rank_options(checked)).to_int64(),
        ),
      ),
    )
  }
  if step.operation is @pipeline.Window(window) {
    let law = match @window.input(window) {
      @carrier.Relation(_) => "actql.bound.row-window"
      @carrier.EventValue(_) => "actql.bound.window-events"
      _ => return Err(UnsupportedOperation)
    }
    return window_factor(@window.options(window), bindings).map(factor => {
      (law, Multiply(factor))
    })
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(UnsupportedOperation)
  }
  if @relation.operation(operation) == @relation.Group &&
    @relation.row_count_rule(operation) is @relation.OneRow {
    return Ok(("actql.bound.global-group", One))
  }
  match (@relation.operation(operation), @relation.row_count_rule(operation)) {
    (@relation.Unpivot, @relation.Repeat(n)) =>
      return Ok(("actql.bound.unpivot", Multiply(n)))
    (@relation.Unnest, @relation.Expand(Some(n))) =>
      return Ok(("actql.bound.unnest-array-items", Multiply(n)))
    (@relation.Unnest, _) => return Err(UnresolvedCount)
    _ => ()
  }
  let (law, value) = match @relation.row_operation(operation) {
    Some(@relation.Take(count~, ..)) => ("actql.bound.take", count)
    Some(@relation.TopK(count~, ..)) => ("actql.bound.top-k", count)
    Some(@relation.TopKBy(partition~, count~, ..)) if partition.is_empty() =>
      ("actql.bound.top-k", count)
    _ => return Err(UnsupportedOperation)
  }
  let n = match resolve_count(value, bindings) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  Ok((law, Clamp(n)))
}

///|
// Reuse an upstream upper bound only through checked non-expanding operations.
// This is not an exact-count transfer or discharge of their pending validations.
fn forwarded_input(step : @pipeline.CheckedStep) -> @pipeline.Target? {
  let preserves_upper = match step.operation {
    @pipeline.Unary(op) | @pipeline.WindowGroup(op) =>
      match @relation.row_count_rule(op) {
        @relation.Preserve
        | @relation.Reduce
        | @relation.OneExistingRow
        | @relation.Slice(..) => true
        @relation.Repeat(n) | @relation.Expand(Some(n)) => n <= 1L
        _ => false
      }
    @pipeline.Set(..)
    | @pipeline.Nest(..)
    | @pipeline.AsOfJoin(..)
    | @pipeline.Pool(_) => true
    @pipeline.Join(checked~, ..) =>
      match @join.kind(checked) {
        @join.Semi | @join.Anti => true
        _ => false
      }
    @pipeline.IntervalJoin(checked~, ..) =>
      match @join.interval_kind(checked) {
        @join.Semi | @join.Anti => true
        _ => false
      }
    @pipeline.CrossJoin(checked~, ..) =>
      @join.cross_requires_one_right_row(checked)
    @pipeline.Calendar(op) =>
      @calendar.cardinality(op) == @calendar.PreserveInput
    @pipeline.Window(op) => @window.kind(@window.options(op)) == @window.Fixed
    @pipeline.Event(op) =>
      match @event.options(op) {
        @event.ToEvents
        | @event.Session(_)
        | @event.Watermark(_, _)
        | @event.Dedupe(_) => true
      }
    @pipeline.Vector(op) =>
      match @vector.operation(op) {
        @vector.ToVectors | @vector.NormalizeVectors | @vector.ScoreVectors =>
          true
      }
    @pipeline.Projection(op) =>
      match @projection.operation(op) {
        @projection.Events | @projection.Vectors => true
        _ => false
      }
    _ => false
  }
  if preserves_upper {
    step.input
  } else {
    None
  }
}

///|
/// Inputs are verified applications in actual data-input order, not CID order.
/// Input and non-expanding step traversal requires a cumulative work allowance.
/// Imported external facts and Program identity require their separate owners.
pub fn check_with_inputs(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  inputs : Array[StepBound],
  max_input_work? : Int = 0,
  max_operand_work? : Int = 0,
  bindings? : CountBindings? = None,
) -> Result[StepBound, Issue] {
  check_application(
    pipeline, index, proof, inputs, max_input_work, max_operand_work, bindings, false,
  )
}

///|
/// Refine a join bound with the actual checked join's conditional key evidence.
/// This retains assertions and key-producer obligations; it does not discharge them.
pub fn check_join_with_uniqueness(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  inputs : Array[StepBound],
  max_input_work? : Int = 0,
) -> Result[StepBound, Issue] {
  check_application(
    pipeline,
    index,
    proof,
    inputs,
    max_input_work,
    0,
    None,
    true,
  )
}

///|
fn check_application(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  inputs : Array[StepBound],
  max_input_work : Int,
  max_operand_work : Int,
  bindings : CountBindings?,
  refine_join : Bool,
) -> Result[StepBound, Issue] {
  if max_input_work < 0 {
    return Err(InvalidInputWorkLimit)
  }
  if max_operand_work < 0 {
    return Err(InvalidOperandWorkLimit)
  }
  if bindings is Some(bound) && !physical_equal(bound.pipeline, pipeline) {
    return Err(BindingOwnerMismatch)
  }
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err(MissingStep)
  }
  let join_evidence = if refine_join {
    guard @pipeline.join_evidence(pipeline, index) is Some(evidence) &&
      evidence.cardinality is Some(_) else {
      return Err(MissingJoinUniqueness)
    }
    Some(evidence)
  } else {
    None
  }
  let witness = @wire.program_proof_witness(proof)
  guard @wire.source(witness) is @wire.Program(reference, _) &&
    reference == subject_ref(pipeline, index).unwrap() else {
    return Err(SubjectMismatch)
  }
  if @wire.program_proof_form(proof) != @wire.DerivedInputs {
    return Err(UnsupportedProofForm)
  }
  let (law, rule) = match operation_rule(step, bindings, @wire.unit(witness)) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let n = inputs.length()
  let valid_count = match rule {
    One | Constant(_) => n == 0
    Preserve => n == 1
    Clamp(_) => n <= 1
    Sum => n == 2
    Join(_) => n == 2
    Multiply(_) => n == 1
    GraphMeasure(_, _, _, _) => n == 1
    QueryTopK(_) => n == 1 || n == 2
    Ranking(expected, maximum) =>
      n == expected || (n == 0 && maximum is Some(_))
  }
  if !valid_count || @wire.program_proof_input_count(proof) != n {
    return Err(InputCountMismatch)
  }
  let operand_work = if rule is Ranking(_, _) {
    // Five bounded passes: edges, multiset construction, proof comparison,
    // arithmetic and owned input copy. Check before allocating either table.
    if n > max_operand_work / 5 {
      return Err(OperandWorkLimit)
    }
    n * 5
  } else {
    0
  }
  let ids : Array[String] = []
  let mut input_work = 0
  for i in 0..<n {
    let expected_unit = match rule {
      GraphMeasure(_, unit, _, _) => unit
      _ => @arithmetic.Rows
    }
    if @wire.unit(@wire.program_proof_witness(inputs[i].proof)) != expected_unit {
      return Err(InputUnitMismatch(i))
    }
    let mut owner = pipeline
    // Per-query top-k uses the query side for its one-operand bound.
    let edge = match rule {
      GraphMeasure(_, _, edge, _) => edge
      QueryTopK(_) if n == 1 => 1
      _ => i
    }
    let mut target = @pipeline.input_occurrence_at(step, edge).unwrap().target
    while !(physical_equal(owner, inputs[i].pipeline) &&
          target == @pipeline.Step(inputs[i].index)) {
      let next = match target {
        @pipeline.Input(input_index) => {
          if input_work >= max_input_work {
            return Err(InputWorkLimit)
          }
          input_work = input_work + 1
          guard @pipeline.input_producer(owner, input_index) is Some(producer) else {
            return Err(MissingInputProducer(i))
          }
          owner = @pipeline.producer_pipeline(producer)
          target = @pipeline.producer_target(producer)
          continue
        }
        @pipeline.Step(index) => {
          let step = @pipeline.step_at(owner, index).unwrap()
          let forwarded = if expected_unit == @arithmetic.Rows {
            forwarded_input(step)
          } else {
            None
          }
          guard forwarded is Some(next) else {
            if !physical_equal(inputs[i].pipeline, owner) {
              return Err(InputOwnerMismatch(i))
            }
            return Err(InputTargetMismatch(i))
          }
          next
        }
      }
      if input_work >= max_input_work {
        return Err(InputWorkLimit)
      }
      input_work = input_work + 1
      target = next
    }
    ids.push(@wire.cid(@wire.program_proof_witness(inputs[i].proof)))
  }
  // Proof arrays sort capacity operands but retain repetitions. Derivations
  // below must still match their actual left/right data roles.
  if rule is Ranking(_, _) {
    let remaining : Map[String, Int] = Map([])
    for id in ids {
      remaining[id] = remaining.get(id).unwrap_or(0) + 1
    }
    for i in 0..<n {
      let id = @wire.program_proof_input_at(proof, i).unwrap()
      let count = remaining.get(id).unwrap_or(0)
      if count == 0 {
        return Err(InputWitnessMismatch(i))
      }
      remaining[id] = count - 1
    }
  } else {
    for i in 0..<n {
      let expected = if n == 2 && ids[0] > ids[1] { ids[1 - i] } else { ids[i] }
      if @wire.program_proof_input_at(proof, i) != Some(expected) {
        return Err(InputWitnessMismatch(i))
      }
    }
  }
  let output_unit = match rule {
    GraphMeasure(unit, _, _, _) => unit
    _ => @arithmetic.Rows
  }
  if @law.name(@wire.law(witness)) != law ||
    @wire.role(witness) != @arithmetic.ProvenUpperBound ||
    @wire.unit(witness) != output_unit {
    return Err(LawMismatch)
  }
  let input_value = fn(i) {
    @numeric.read(@wire.value(@wire.program_proof_witness(inputs[i].proof))).unwrap()
  }
  let count = match rule {
    One => 1L
    Constant(n) => n
    GraphMeasure(_, _, _, factor) =>
      match @numeric.multiply(input_value(0), @numeric.read(factor).unwrap()) {
        Ok(v) => @numeric.value(v)
        Err(_) => return Err(BoundOverflow)
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
  if @wire.value(witness) != count {
    return Err(ValueMismatch)
  }
  match (rule, @wire.derivation(witness)) {
    (One, @wire.SourceValue) => ()
    (Constant(_), @wire.SourceValue) => ()
    (GraphMeasure(_, _, _, _), @wire.SourceValue) => ()
    (Join(_), @wire.SourceValue) => ()
    (Preserve, @wire.Preserve(input)) if input == ids[0] => ()
    (Clamp(expected), @wire.Clamp(input, maximum)) if maximum == expected &&
      input == ids.get(0) => ()
    (Sum, @wire.Add(left, right)) if left == ids[0] && right == ids[1] => ()
    (Multiply(expected), @wire.Multiply(input, factor)) if factor == expected &&
      input == ids[0] => ()
    (QueryTopK(expected), @wire.Multiply(input, factor)) if n == 1 &&
      factor == expected &&
      input == ids[0] => ()
    // A candidate-dependent factor must retain that candidate proof as well.
    // Source-law validation computes the full product from both owned inputs.
    (QueryTopK(_), @wire.SourceValue) if n == 2 => ()
    (Ranking(_, _), @wire.SourceValue) if n > 0 => ()
    (Ranking(_, None), @wire.Add(left, right)) if n == 2 &&
      left == ids[0] &&
      right == ids[1] => ()
    (Ranking(_, Some(k)), @wire.Clamp(None, maximum)) if n == 0 && maximum == k =>
      ()
    _ => return Err(InvalidDerivation)
  }
  Ok({
    pipeline,
    index,
    proof,
    inputs: inputs.copy(),
    input_work,
    operand_work,
    bindings,
    join_evidence,
  })
}

///|
// A bound on successful output, optionally conditional on retained uniqueness.
// Author output guards never supply the cardinality calculation.
// The full-join maximum is max(L*R, L+R): isolated occurrences and matching
// pairs cannot independently reach their maxima in the same bipartite graph.
fn join_bound(
  kind : @join.Kind,
  left : @numeric.Value,
  right : @numeric.Value,
  evidence : @pipeline.JoinEvidence?,
) -> Result[Int64, Issue] {
  let l = @numeric.value(left)
  let r = @numeric.value(right)
  if evidence is Some(evidence) && l != 0L && r != 0L {
    let lu = evidence.left is Some(_) ||
      evidence.assertion is Some(@join.OneToOne | @join.OneToMany)
    let ru = evidence.right is Some(_) ||
      evidence.assertion is Some(@join.OneToOne | @join.ManyToOne)
    let tightened = match kind {
      @join.Inner =>
        return Ok(
          if lu && ru {
            if l < r {
              l
            } else {
              r
            }
          } else if ru {
            l
          } else {
            r
          },
        )
      @join.Left => {
        if ru {
          return Ok(l)
        }
        @numeric.add(left, @numeric.read(r - 1L).unwrap())
      }
      @join.Full => @numeric.add(left, right)
      @join.Semi | @join.Anti => return Ok(l)
    }
    return match tightened {
      Ok(v) => Ok(@numeric.value(v))
      Err(_) => Err(BoundOverflow)
    }
  }
  let result = match kind {
    @join.Semi => return Ok(if r == 0L { 0L } else { l })
    @join.Anti => return Ok(l)
    @join.Inner => @numeric.multiply(left, right)
    @join.Left =>
      @numeric.multiply(
        left,
        @numeric.read(if r == 0L { 1L } else { r }).unwrap(),
      )
    @join.Full => {
      if l == 0L {
        return Ok(r)
      }
      if r == 0L {
        return Ok(l)
      }
      if l == 1L || r == 1L {
        @numeric.add(left, right)
      } else {
        @numeric.multiply(left, right)
      }
    }
  }
  match result {
    Ok(v) => Ok(@numeric.value(v))
    Err(_) => Err(BoundOverflow)
  }
}

///|
pub fn checked_pipeline(v : StepBound) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn checked_step(v : StepBound) -> Int {
  v.index
}

///|
pub fn checked_proof(v : StepBound) -> @wire.ProgramProofClaim {
  v.proof
}

///|
pub fn input_count(v : StepBound) -> Int {
  v.inputs.length()
}

///|
pub fn input_at(v : StepBound, index : Int) -> StepBound? {
  v.inputs.get(index)
}

///|
/// Producer-input and non-expanding step links, across repeated operands.
pub fn input_work(v : StepBound) -> Int {
  v.input_work
}

///|
/// Linear ranking operand passes, separate from producer traversal work.
pub fn operand_work(v : StepBound) -> Int {
  v.operand_work
}

///|
pub fn checked_bindings(v : StepBound) -> CountBindings? {
  v.bindings
}

///|
/// Exact checked join evidence used for refinement, including pending assertions.
pub fn checked_join_evidence(v : StepBound) -> @pipeline.JoinEvidence? {
  v.join_evidence
}
