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
  inputs : Array[BoundInput]
  input_work : Int
  operand_work : Int
  bindings : CountBindings?
  join_evidence : @pipeline.JoinEvidence?
  enforcement : OutputEnforcement?
}

///|
/// Ordered capacity dependencies with their validated source owners intact.
pub(all) enum BoundInput {
  StepInput(StepBound)
  GraphInput(@graph_input.InputBound)
}

///|
fn source_witness(v : BoundInput) -> @wire.WireWitness {
  match v {
    StepInput(step) => @wire.program_proof_witness(step.proof)
    GraphInput(input) => @graph_input.bound_witness(input)
  }
}

///|
fn source_target(
  v : BoundInput,
) -> (@pipeline.CheckedPipeline, @pipeline.Target) {
  match v {
    StepInput(step) => (step.pipeline, @pipeline.Step(step.index))
    GraphInput(input) =>
      (
        @graph_input.checked_pipeline(@graph_input.bound_owner(input)),
        @pipeline.Input(@graph_input.bound_input(input)),
      )
  }
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
  PropertyGraphMeasure(@arithmetic.BoundUnit, Int, Int)
  GraphQuery(QueryBound)
}

///|
fn operation_rule(
  step : @pipeline.CheckedStep,
  bindings : CountBindings?,
  unit : @arithmetic.BoundUnit,
) -> Result[(String, Rule), Issue] {
  match step.operation {
    @pipeline.PropertyGraphConstruction(checked~, ..) => {
      let nodes = @graph.property_construction_node_count(checked)
      let edges = @graph.property_construction_edge_count(checked)
      return match unit {
        @arithmetic.Nodes =>
          Ok(
            (
              "actql.bound.property-graph-nodes",
              PropertyGraphMeasure(unit, 0, nodes),
            ),
          )
        @arithmetic.Edges =>
          Ok(
            (
              "actql.bound.property-graph-edges",
              PropertyGraphMeasure(unit, nodes, edges),
            ),
          )
        _ => Err(LawMismatch)
      }
    }
    @pipeline.Traverse(checked~, ..) => {
      if @graph.traverse_emission(checked) != @graph.TraversedNodes {
        return Err(UnsupportedOperation)
      }
      return Ok(
        ("actql.bound.traverse-nodes", GraphQuery(traversal_bound(checked))),
      )
    }
    @pipeline.Shortest(source_selector~, checked~, ..) =>
      return Ok(
        (
          "actql.bound.shortest-path",
          GraphQuery(shortest_bound(checked, source_selector is Some(_))),
        ),
      )
    @pipeline.Graph(op) =>
      match @graph.operation(op) {
        @graph.Degree =>
          return Ok(
            (
              "actql.bound.graph-degree",
              GraphMeasure(@arithmetic.Rows, @arithmetic.Nodes, 0, 1L),
            ),
          )
        @graph.Components => {
          if unit == @arithmetic.Nodes {
            return Ok(
              (
                "actql.bound.components-input-nodes",
                GraphMeasure(unit, unit, 0, 1L),
              ),
            )
          }
          return Ok(
            (
              "actql.bound.components-nodes",
              GraphMeasure(@arithmetic.Rows, @arithmetic.Nodes, 0, 1L),
            ),
          )
        }
        _ => ()
      }
    @pipeline.GraphMatch(op) => {
      let (law, input_unit) = if @graph.match_entity(op) == @graph.Nodes {
        ("actql.bound.match-nodes", @arithmetic.Nodes)
      } else {
        ("actql.bound.match-edges", @arithmetic.Edges)
      }
      // A successful selection cannot exceed the original entity count.
      // Do not mistake repeated authored selectors for extra output entities.
      return Ok((law, GraphMeasure(@arithmetic.Rows, input_unit, 0, 1L)))
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
          guard bindings is Some(b) &&
            b.parameters.entries.get(name) is Some(entry) else {
            return Err(UnresolvedCount)
          }
          Some(entry.value)
        }
      }
      let z = match @series.end(op) {
        @series.Literal(_) => None
        @series.Parameter(name) => {
          guard bindings is Some(b) &&
            b.parameters.entries.get(name) is Some(entry) else {
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
  // Inspect the operation discriminator before a row view. Ranking readers
  // retain count/partition size without copying potentially large key arrays.
  let (law, value) = match @relation.operation(operation) {
    @relation.Take => {
      guard @relation.row_operation(operation)
        is Some(@relation.Take(count~, ..)) else {
        return Err(UnsupportedOperation)
      }
      ("actql.bound.take", count)
    }
    @relation.TopK =>
      ("actql.bound.top-k", @relation.top_k_count(operation).unwrap())
    @relation.TopKBy if @relation.top_k_partition_count(operation) == 0 =>
      ("actql.bound.top-k", @relation.top_k_count(operation).unwrap())
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
fn forwarded_input(
  step : @pipeline.CheckedStep,
  unit : @arithmetic.BoundUnit,
) -> @pipeline.Target? {
  if unit == @arithmetic.Nodes || unit == @arithmetic.Edges {
    return match step.operation {
      @pipeline.Graph(op) if @graph.operation(op) == @graph.NormalizeGraph =>
        step.input
      @pipeline.Subgraph(..) => step.input
      _ => None
    }
  }
  if unit != @arithmetic.Rows {
    return None
  }
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
    pipeline,
    index,
    proof,
    inputs.length(),
    i => StepInput(inputs[i]),
    max_input_work,
    max_operand_work,
    bindings,
    false,
  )
}

///|
/// Accepts operation proofs and validated external Graph preflight bounds.
/// Matching input coordinates do not replace exact pipeline/source ownership.
pub fn check_with_sources(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  proof : @wire.ProgramProofClaim,
  inputs : Array[BoundInput],
  max_input_work? : Int = 0,
  max_operand_work? : Int = 0,
  bindings? : CountBindings? = None,
) -> Result[StepBound, Issue] {
  check_application(
    pipeline,
    index,
    proof,
    inputs.length(),
    i => inputs[i],
    max_input_work,
    max_operand_work,
    bindings,
    false,
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
    inputs.length(),
    i => StepInput(inputs[i]),
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
  n : Int,
  get_input : (Int) -> BoundInput,
  max_input_work : Int,
  max_operand_work : Int,
  bindings : CountBindings?,
  refine_join : Bool,
  usage? : Array[Int]? = None,
  aggregate_work? : Int? = None,
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
  if !rule_input_count_valid(rule, n) ||
    @wire.program_proof_input_count(proof) != n {
    return Err(InputCountMismatch)
  }
  let prepared = match
    prepare_bound_inputs(
      pipeline,
      step,
      rule,
      n,
      get_input,
      max_input_work,
      max_operand_work,
      usage,
      aggregate_work~,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let ids = prepared.ids
  let inputs = prepared.inputs
  let input_work = prepared.input_work
  let operand_work = prepared.operand_work
  // Proof arrays sort capacity operands but retain repetitions. Derivations
  // below must still match their actual left/right data roles.
  if rule is Ranking(_, _) || rule is PropertyGraphMeasure(_, _, _) {
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
  let output_unit = rule_output_unit(rule)
  if @law.name(@wire.law(witness)) != law ||
    @wire.role(witness) != @arithmetic.ProvenUpperBound ||
    @wire.unit(witness) != output_unit {
    return Err(LawMismatch)
  }
  let count = match
    calculate_bound_value(
      rule,
      n,
      i => @numeric.read(@wire.value(source_witness(inputs[i]))).unwrap(),
      join_evidence,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @wire.value(witness) != count {
    return Err(ValueMismatch)
  }
  match (rule, @wire.derivation(witness)) {
    (One, @wire.SourceValue) => ()
    (Constant(_), @wire.SourceValue) => ()
    (GraphQuery(_), @wire.SourceValue) => ()
    (GraphMeasure(_, _, _, _), @wire.SourceValue) => ()
    (PropertyGraphMeasure(_, _, _), @wire.SourceValue) => ()
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
    inputs,
    input_work,
    operand_work,
    bindings,
    join_evidence,
    enforcement: None,
  })
}

///|
fn rule_output_unit(rule : Rule) -> @arithmetic.BoundUnit {
  match rule {
    GraphMeasure(unit, _, _, _) | PropertyGraphMeasure(unit, _, _) => unit
    _ => @arithmetic.Rows
  }
}

///|
priv struct PreparedBoundInputs {
  ids : Array[String]
  inputs : Array[BoundInput]
  input_work : Int
  operand_work : Int
}

///|
// Both supplied-proof admission and compiler construction validate actual
// operand edges here. CID equality never substitutes for an input owner.
fn prepare_bound_inputs(
  pipeline : @pipeline.CheckedPipeline,
  step : @pipeline.CheckedStep,
  rule : Rule,
  n : Int,
  get_input : (Int) -> BoundInput,
  max_input_work : Int,
  max_operand_work : Int,
  usage : Array[Int]?,
  aggregate_work? : Int? = None,
) -> Result[PreparedBoundInputs, Issue] {
  let operand_work = if rule is Ranking(_, _) ||
    rule is PropertyGraphMeasure(_, _, _) {
    // Five bounded passes: edges, multiset construction, proof comparison,
    // arithmetic and owned input copy. Check before allocating either table.
    if n > max_operand_work / 5 {
      return Err(OperandWorkLimit)
    }
    n * 5
  } else {
    0
  }
  let max_input_work = match aggregate_work {
    Some(total) => {
      if operand_work > total {
        return Err(OperandWorkLimit)
      }
      max_input_work.min(total - operand_work)
    }
    None => max_input_work
  }
  let ids : Array[String] = []
  if usage is Some(v) {
    v[1] = operand_work
  }
  let inputs : Array[BoundInput] = []
  let mut input_work = 0
  for i in 0..<n {
    let input = get_input(i)
    let (matched, used) = check_input_target_usage(
      pipeline,
      step,
      rule,
      n,
      i,
      input,
      max_input_work - input_work,
    )
    input_work += used
    if usage is Some(v) {
      v[0] = input_work
    }
    match matched {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    ids.push(@wire.cid(source_witness(input)))
    inputs.push(input)
  }
  Ok({ ids, inputs, input_work, operand_work, })
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
  match v.inputs.get(index) {
    Some(StepInput(step)) => Some(step)
    _ => None
  }
}

///|
/// All dependency kinds; input_at exposes only operation dependencies.
pub fn source_at(v : StepBound, index : Int) -> BoundInput? {
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
