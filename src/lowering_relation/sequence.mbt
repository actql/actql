///|
/// Opaque, wholly prepared operation sequence. NOT an admitted executable
/// fragment: registry/params, input proofs and runtime obligations remain.
struct PreparedSequence {
  owner : BoundPrepared
  steps : Array[PreparedStep]
}

///|
pub enum PreparedStep {
  InferBoundary(Int)
  ValuesStep(PreparedValues)
  TimeSeriesStep(PreparedTimeSeries)
  WindowStep(PreparedWindow)
  RowStep(PreparedKernel)
  JoinStep(PreparedJoinKernel)
  IntervalJoinStep(PreparedIntervalJoin)
  AsOfJoinStep(PreparedAsOfJoin)
  SequenceMatchStep(PreparedSequenceMatch)
  CrossJoinStep(PreparedCrossJoinKernel)
  AppendStep(PreparedAppendKernel)
  SetStep(PreparedSetKernel)
  NestStep(PreparedNestKernel)
  GraphMatchStep(PreparedGraphMatch)
  GraphDiagnosticStep(PreparedGraphDiagnostic)
  GraphEqualityStep(PreparedGraphEquality)
  GraphTraverseStep(PreparedGraphTraverse)
  PropertyGraphConstructionStep(PreparedPropertyGraphConstruction)
  VectorStep(PreparedVector)
  EventStep(PreparedEvent)
  CarrierProjectionStep(PreparedCarrierProjection)
}

///|
pub(all) struct SequenceLimits {
  max_steps : Int
  max_rows : Int
  max_cells : Int
  max_bindings : Int
  max_name_bytes : Int
  expressions : ExpressionLimits
}

///|
pub(all) enum SequenceIssue {
  InvalidSequenceLimits
  SequenceLimit
  ValuesFailure(Int, ValuesIssue)
  TimeSeriesFailure(Int, TimeSeriesIssue)
  WindowFailure(Int, WindowIssue)
  KernelFailure(Int, KernelIssue)
  JoinFailure(Int, InnerJoinIssue)
  IntervalJoinFailure(Int, IntervalJoinIssue)
  AsOfJoinFailure(Int, AsOfJoinIssue)
  SequenceMatchFailure(Int, SequenceMatchIssue)
  CrossJoinFailure(Int, CrossJoinIssue)
  AppendFailure(Int, AppendIssue)
  SetFailure(Int, SetIssue)
  NestFailure(Int, NestIssue)
  GraphMatchFailure(Int, GraphMatchIssue)
  GraphDiagnosticFailure(Int, GraphDiagnosticIssue)
  GraphEqualityFailure(Int, GraphEqualityIssue)
  GraphTraverseFailure(Int, GraphTraverseIssue)
  GraphConstructionFailure(Int, GraphConstructionIssue)
  VectorFailure(Int, VectorIssue)
  EventFailure(Int, EventIssue)
  CarrierProjectionFailure(Int, CarrierProjectionIssue)
}

///|
pub fn sequence_owner(value : PreparedSequence) -> BoundPrepared {
  value.owner
}

///|
pub fn sequence_count(value : PreparedSequence) -> Int {
  value.steps.length()
}

///|
pub fn sequence_step(value : PreparedSequence, index : Int) -> PreparedStep? {
  value.steps.get(index)
}

///|
pub fn prepare_sequence(
  owner : BoundPrepared,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  prepare_sequence_count(owner, owner.prepared.nodes.length(), limits)
}

///|
/// Prepare only an exact checked prefix before an acquisition barrier. The
/// bound invocation is retained; neither suffix execution nor acquisition
/// success is implied. A barrier inside the prefix is still rejected.
pub fn prepare_sequence_prefix(
  owner : BoundPrepared,
  terminal : Int,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  if terminal < 0 || terminal >= owner.prepared.nodes.length() {
    return Err(SequenceLimit)
  }
  prepare_sequence_count(owner, terminal + 1, limits)
}

///|
/// Retain one installed acquisition boundary while preparing its surrounding
/// Compute operations. The marker has no evaluator or AoA Compute encoding;
/// its output must come from the separate checked ModelTask owner.
pub fn prepare_sequence_with_infer_boundary(
  owner : BoundPrepared,
  step : Int,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  guard owner.prepared.nodes.get(step) is Some(node) && node.payload is Infer(_) else {
    return Err(KernelFailure(step, MissingKernelNode))
  }
  prepare_sequence_count(
    owner,
    owner.prepared.nodes.length(),
    limits,
    infer_boundary=Some(step),
  )
}

///|
fn prepare_sequence_count(
  owner : BoundPrepared,
  count : Int,
  limits : SequenceLimits,
  infer_boundary? : Int? = None,
) -> Result[PreparedSequence, SequenceIssue] {
  let e = limits.expressions
  if limits.max_steps < 0 ||
    limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_bindings < 0 ||
    limits.max_name_bytes < 0 ||
    e.max_nodes < 0 ||
    e.max_work < 0 ||
    e.max_depth < 0 ||
    e.max_literal_nodes < 0 ||
    e.max_literal_text_bytes < 0 {
    return Err(InvalidSequenceLimits)
  }
  if count > limits.max_steps {
    return Err(SequenceLimit)
  }
  let steps : Array[PreparedStep] = []
  let mut rows = limits.max_rows
  let mut cells = limits.max_cells
  let mut bindings = limits.max_bindings
  let mut names = limits.max_name_bytes
  let mut expressions = limits.expressions
  for i = 0; i < count; i = i + 1 {
    let step = match owner.prepared.nodes[i].payload {
      Infer(_) => {
        guard infer_boundary == Some(i) else {
          return Err(KernelFailure(i, MissingKernelNode))
        }
        InferBoundary(i)
      }
      InnerJoin(_) => {
        let kernel = match prepare_join_kernel(owner, i, bindings, names) {
          Ok(v) => v
          Err(e) => return Err(JoinFailure(i, e))
        }
        bindings -= kernel.profile.keys.length() +
          kernel.profile.projection.length()
        names -= kernel.profile.name_bytes
        if @join.output_guard(kernel.profile.checked) is Some(Parameter(name)) {
          names -= @utf8.encode(name).length()
        }
        JoinStep(kernel)
      }
      IntervalJoinRows(_) => {
        let prepared = match prepare_interval_join(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(IntervalJoinFailure(i, issue))
        }
        bindings -= prepared.keys.length() +
          prepared.projection.length() +
          interval_operand_field_count(prepared.left_operand) +
          interval_operand_field_count(prepared.right_operand)
        names -= prepared.name_bytes
        IntervalJoinStep(prepared)
      }
      AsOfJoinRows(_) => {
        let prepared = match prepare_asof_join(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(AsOfJoinFailure(i, issue))
        }
        bindings -= prepared.keys.length() * 2 +
          prepared.projection.length() * 2 +
          prepared.identity.length() +
          prepared.tie_break.length() +
          2
        names -= prepared.name_bytes
        AsOfJoinStep(prepared)
      }
      SequenceRows(_) => {
        let (prepared, used_bindings, used_names, remaining) = match
          prepare_sequence_match(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            expressions~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(SequenceMatchFailure(i, issue))
        }
        bindings -= used_bindings
        names -= used_names
        expressions = remaining
        SequenceMatchStep(prepared)
      }
      CrossJoinRows(_) => {
        let kernel = match
          prepare_cross_join_kernel(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(CrossJoinFailure(i, issue))
        }
        bindings -= cross_join_field_count(kernel.profile)
        names -= kernel.profile.name_bytes
        if @join.cross_output_guard(kernel.profile.checked)
          is Some(Parameter(name)) {
          names -= @utf8.encode(name).length()
        }
        CrossJoinStep(kernel)
      }
      AppendRows(_) => {
        let kernel = match prepare_append_kernel(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(AppendFailure(i, issue))
        }
        bindings -= append_kernel_field_count(kernel)
        names -= append_kernel_name_bytes(kernel)
        AppendStep(kernel)
      }
      SetRows(_) => {
        let kernel = match prepare_set_kernel(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(SetFailure(i, issue))
        }
        bindings -= set_kernel_field_count(kernel)
        names -= set_kernel_name_bytes(kernel)
        SetStep(kernel)
      }
      NestRows(_) => {
        let (kernel, used_entries, used_names, used_work) = match
          prepare_nest_kernel(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(NestFailure(i, issue))
        }
        bindings -= used_entries
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        NestStep(kernel)
      }
      GraphMatchRows(_) => {
        let (prepared, used_entries, used_names, remaining) = match
          prepare_graph_match_node(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            expressions~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(GraphMatchFailure(i, issue))
        }
        bindings -= used_entries
        names -= used_names
        expressions = remaining
        GraphMatchStep(prepared)
      }
      GraphBoundsRows(_) | GraphDegreeRows(_) => {
        let (prepared, used_bindings, used_names, used_work) = match
          prepare_graph_diagnostic_node(
            owner,
            owner.prepared.nodes[i],
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(GraphDiagnosticFailure(i, issue))
        }
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        GraphDiagnosticStep(prepared)
      }
      GraphEqualityRows(_) => {
        let prepared = match
          prepare_graph_equality_node(owner.prepared.nodes[i]) {
          Ok(value) => value
          Err(issue) => return Err(GraphEqualityFailure(i, issue))
        }
        GraphEqualityStep(prepared)
      }
      GraphTraverseRows(_) => {
        let (prepared, used_entries, used_names, remaining) = match
          prepare_graph_traverse_node(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            expressions~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(GraphTraverseFailure(i, issue))
        }
        bindings -= used_entries
        names -= used_names
        expressions = remaining
        GraphTraverseStep(prepared)
      }
      PropertyGraphConstructionValue(_) => {
        let (prepared, used_entries, used_names, used_work) = match
          prepare_property_graph_construction_node(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
            max_depth=expressions.max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(GraphConstructionFailure(i, issue))
        }
        bindings -= used_entries
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        PropertyGraphConstructionStep(prepared)
      }
      VectorValue(_) | NearestValue(_) | PoolValue(_) | RankingValue(_) => {
        let (prepared, used_bindings, used_names, used_work) = match
          prepare_vector_node(
            owner,
            i,
            owner.prepared.nodes[i],
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(VectorFailure(i, issue))
        }
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        VectorStep(prepared)
      }
      EventValue(_) => {
        let (prepared, used_bindings, used_names, used_work) = match
          prepare_event_node(
            owner,
            owner.prepared.nodes[i],
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(EventFailure(i, issue))
        }
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        EventStep(prepared)
      }
      CarrierProjection(_) => {
        let prepared = match
          prepare_carrier_projection_node(owner.prepared.nodes[i]) {
          Ok(value) => value
          Err(issue) => return Err(CarrierProjectionFailure(i, issue))
        }
        CarrierProjectionStep(prepared)
      }
      Values(values) => {
        let prepared = match
          prepare_values_node(owner, i, max_rows=rows, max_cells=cells) {
          Ok(v) => v
          Err(e) => return Err(ValuesFailure(i, e))
        }
        let count = @values.row_count(values)
        // prepare_values_node proved this product <= the remaining Int bound.
        cells -= count * @schema.field_count(@values.output_schema(values))
        rows -= count
        ValuesStep(prepared)
      }
      TimeSeriesValue(_) => {
        let (prepared, used_bindings, used_names, used_work) = match
          prepare_time_series_node(
            owner,
            owner.prepared.nodes[i],
            max_rows=rows,
            max_cells=cells,
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(TimeSeriesFailure(i, issue))
        }
        let count = time_series_row_count(prepared)
        rows -= count
        cells -= count
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        TimeSeriesStep(prepared)
      }
      RowWindow(_) => {
        let (prepared, used_names, used_bindings, used_work) = match
          prepare_window(
            owner,
            i,
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(WindowFailure(i, issue))
        }
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        WindowStep(prepared)
      }
      Derive(_)
      | Where(_)
      | Select(_)
      | Limit(_)
      | TopK(_)
      | TopKBy(_)
      | Pivot(_)
      | Unnest(_)
      | Unpivot(_)
      | Distinct(_)
      | Dedupe(_)
      | Sort(_)
      | CountGroup(_)
      | WindowGroup(_)
      | Lag(_)
      | Watermark(_)
      | Analytic(_)
      | AssertRows(_)
      | JsonPick(_) => {
        let (kernel, remaining, used_names, used_bindings) = match
          prepare_kernel_measured(
            owner,
            i,
            max_bindings=bindings,
            max_name_bytes=names,
            expressions,
          ) {
          Ok(v) => v
          Err(e) => return Err(KernelFailure(i, e))
        }
        expressions = remaining
        bindings -= used_bindings
        names -= used_names
        RowStep(kernel)
      }
    }
    steps.push(step)
  }
  Ok({ owner, steps, })
}

///|
/// Emits the steps array only, not a made-up fragment/Plan envelope. Writer
/// finish is the publication boundary; unsupported sequences yield no value.
pub fn emit_sequence_steps(
  value : PreparedSequence,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_sequence_step_range(value, 0, value.steps.length(), out)
}

///|
/// Encode a checked half-open Compute segment. An acquisition boundary inside
/// the segment is rejected, never silently dropped from the logical identity.
pub fn emit_sequence_step_range(
  value : PreparedSequence,
  first : Int,
  end : Int,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if first < 0 || end < first || end > value.steps.length() {
    raise @encode.InvalidStructure
  }
  @encode.begin_array(out)
  for index in first..<end {
    let step = value.steps[index]
    match step {
      InferBoundary(_) => raise @encode.InvalidStructure
      ValuesStep(v) => emit_values_node(v, out)
      TimeSeriesStep(v) => emit_time_series_node(v, out)
      WindowStep(v) => emit_window_node(v, out)
      JoinStep(v) => emit_join_kernel(v, out)
      IntervalJoinStep(v) => emit_interval_join(v, out)
      AsOfJoinStep(v) => emit_asof_join(v, out)
      SequenceMatchStep(v) => emit_sequence_match(v, out)
      CrossJoinStep(v) => emit_cross_join_kernel(v, out)
      AppendStep(v) => emit_append_kernel(v, out)
      SetStep(v) => emit_set_kernel(v, out)
      NestStep(v) => emit_nest_kernel(v, out)
      GraphMatchStep(v) => emit_graph_match_node(v, out)
      GraphDiagnosticStep(v) => emit_graph_diagnostic_node(v, out)
      GraphEqualityStep(v) => emit_graph_equality_node(v, out)
      GraphTraverseStep(v) => emit_graph_traverse_node(v, out)
      PropertyGraphConstructionStep(v) =>
        emit_property_graph_construction_node(v, out)
      VectorStep(v) => emit_vector_node(v, out)
      EventStep(v) => emit_event_node(v, out)
      CarrierProjectionStep(v) => emit_carrier_projection_node(v, out)
      RowStep(v) => {
        emit_kernel_prefix(v, out)
        emit_kernel_node(v, out)
      }
    }
  }
  @encode.end_array(out)
}

///|
pub(all) enum SourceFreeValuesPipelineIssue {
  NotSingleValues
}

///|
/// Emit the canonical source-free AoA pipeline rooted in checked REL.values.
/// Later steps in the same task remain part of this compilation identity.
pub fn emit_source_free_values_pipeline(
  value : PreparedSequence,
  out : @encode.Writer,
) -> Result[Unit, SourceFreeValuesPipelineIssue] raise @encode.EncodeFailure {
  if value.steps.is_empty() {
    return Err(NotSingleValues)
  }
  guard value.steps[0] is ValuesStep(_) else { return Err(NotSingleValues) }
  let output = value.owner.prepared.nodes[value.steps.length() - 1].id
  @encode.begin_object(out)
  @encode.key(out, "output")
  @encode.string_value(out, output)
  @encode.key(out, "sources")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.key(out, "steps")
  emit_sequence_steps(value, out)
  @encode.key(out, "version")
  @encode.string_value(out, "aoa-pipeline/0.1")
  @encode.end_object(out)
  Ok(())
}
