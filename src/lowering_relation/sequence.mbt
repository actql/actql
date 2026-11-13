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
  SerializationBoundary(Int)
  CompletedProducerBoundary(Int)
  ValuesStep(PreparedValues)
  TimeSeriesStep(PreparedTimeSeries)
  CalendarStep(PreparedCalendar)
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
  GraphSubgraphStep(PreparedGraphSubgraph)
  GraphEqualityStep(PreparedGraphEquality)
  GraphNormalizeStep(Int)
  GraphDeltaStep(PreparedGraphDelta)
  GraphUnionStep(PreparedGraphUnion)
  GraphMeanStep(PreparedGraphMean)
  GraphSubtractionStep(PreparedGraphUnion)
  GraphTraverseStep(PreparedGraphTraverse)
  GraphConstructionStep(PreparedGraphConstruction)
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
  CalendarFailure(Int, CalendarIssue)
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
  GraphSubgraphFailure(Int, GraphSubgraphIssue)
  GraphEqualityFailure(Int, GraphEqualityIssue)
  GraphTraverseFailure(Int, GraphTraverseIssue)
  GraphDeltaFailure(Int, GraphDeltaIssue)
  GraphUnionFailure(Int, GraphUnionIssue)
  GraphMeanFailure(Int, GraphMeanIssue)
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
/// Identify only the compiler-prepared internal sort, never a normal Content
/// metadata output at the same logical barrier coordinate.
pub fn sequence_serialization_input_kernel(
  value : PreparedSequence,
  index : Int,
) -> PreparedKernel? {
  guard value.owner.prepared.nodes.get(index) is Some(node) &&
    node.payload is Serialize(checked) &&
    @pipeline.serialization_sort(checked) is Some(sort) &&
    value.steps.get(index) is Some(RowStep(kernel)) &&
    physical_equal(kernel.checked, sort) &&
    kernel.body is StableSort(Some(_)) else {
    return None
  }
  Some(kernel)
}

///|
/// Match the original compiler-prepared sort without exposing its checked
/// payload to an evaluator. Equal rows, schemas or another bound invocation
/// cannot substitute for the same barrier and operation occurrence.
pub fn sequence_matches_serialization_sort(
  value : PreparedSequence,
  barrier : PreparedSerialization,
) -> Bool {
  physical_equal(value.owner, barrier.owner) &&
  sequence_serialization_input_kernel(value, barrier.step) is Some(kernel) &&
  @pipeline.serialization_sort(barrier.checked) is Some(sort) &&
  physical_equal(kernel.checked, sort)
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
/// An explicitly selected original input permits its empty prefix. Ordinary
/// negative Step requests still refuse; no replacement input or observation
/// is manufactured.
pub fn prepare_sequence_prefix(
  owner : BoundPrepared,
  terminal : Int,
  limits : SequenceLimits,
  original_input? : Int? = None,
) -> Result[PreparedSequence, SequenceIssue] {
  if original_input is Some(input) {
    guard terminal == -1 &&
      @pipeline.input_at(pipeline(owner.prepared), input) is Some(_) else {
      return Err(SequenceLimit)
    }
    return prepare_sequence_count(owner, 0, limits)
  }
  if terminal < 0 || terminal >= owner.prepared.nodes.length() {
    return Err(SequenceLimit)
  }
  prepare_sequence_count(owner, terminal + 1, limits)
}

///|
/// The physical Relation prefix of an exact Content barrier, including its
/// checked internal ORDER BY when present. The byte barrier is not executed or
/// emitted as Compute; the resulting Relation still needs completion binding.
pub fn prepare_serialization_input_sequence(
  barrier : PreparedSerialization,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  if @pipeline.serialization_sort(barrier.checked) is None {
    guard @pipeline.serialization_order_input(barrier.order) is Step(terminal) else {
      return Err(KernelFailure(barrier.step, InvalidKernelWiring))
    }
    return prepare_sequence_prefix(barrier.owner, terminal, limits)
  }
  prepare_sequence_count(
    barrier.owner,
    barrier.step + 1,
    limits,
    serialization_input=Some(barrier.step),
  )
}

///|
/// Retain one installed acquisition boundary while preparing its surrounding
/// Compute operations. The marker has no evaluator or AoA Compute encoding;
/// its output must come from the separate checked ModelTask owner.
pub fn prepare_sequence_with_infer_boundary(
  owner : BoundPrepared,
  step : Int,
  limits : SequenceLimits,
  serialization? : Int? = None,
) -> Result[PreparedSequence, SequenceIssue] {
  guard owner.prepared.nodes.get(step) is Some(node) && node.payload is Infer(_) else {
    return Err(KernelFailure(step, MissingKernelNode))
  }
  if serialization is Some(content) {
    guard content < step &&
      owner.prepared.nodes.get(content) is Some(node) &&
      node.payload is Serialize(_) else {
      return Err(KernelFailure(content, MissingKernelNode))
    }
  }
  prepare_sequence_count(
    owner,
    owner.prepared.nodes.length(),
    limits,
    infer_boundary=Some(step),
    serialization_boundary=serialization,
  )
}

///|
/// Retain the exact checked Content barrier for installed provider selection.
/// This marker is neither the encoder nor a producer completion. Prefix and
/// suffix coordinates keep their ordinary kernels; pure execution and AoA
/// emission must still refuse the whole sequence.
pub fn prepare_sequence_with_serialization_boundary(
  owner : BoundPrepared,
  step : Int,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is Serialize(_) else {
    return Err(KernelFailure(step, MissingKernelNode))
  }
  prepare_sequence_count(
    owner,
    owner.prepared.nodes.length(),
    limits,
    serialization_boundary=Some(step),
  )
}

///|
/// Prepare only the pure segment following an already completed Serialize.
/// Earlier coordinates remain non-executable boundaries, not VALUES or no-op
/// kernels. The consuming driver must bind the authentic producer completion
/// and select just this range; whole-sequence execution continues to refuse.
pub fn prepare_serialization_infer_input_sequence(
  owner : BoundPrepared,
  serialization_step : Int,
  infer_step : Int,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  guard serialization_step >= 0 &&
    serialization_step + 1 < infer_step &&
    owner.prepared.nodes.get(serialization_step) is Some(producer) &&
    producer.payload is Serialize(_) &&
    owner.prepared.nodes.get(infer_step) is Some(consumer) &&
    consumer.payload is Infer(_) else {
    return Err(KernelFailure(infer_step, MissingKernelNode))
  }
  prepare_serialization_consumer_sequence(
    owner,
    serialization_step,
    infer_step - 1,
    limits,
  )
}

///|
/// Prepare a pure consumer range after an authentic completed Content barrier.
/// The earlier steps remain non-executable markers. A driver still has to
/// bind the original producer completion and select only the consumer range;
/// this preparation neither generates bytes nor proves producer completion.
pub fn prepare_serialization_consumer_sequence(
  owner : BoundPrepared,
  serialization_step : Int,
  terminal : Int,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  guard serialization_step >= 0 &&
    terminal > serialization_step &&
    terminal < owner.prepared.nodes.length() &&
    owner.prepared.nodes.get(serialization_step) is Some(producer) &&
    producer.payload is Serialize(_) else {
    return Err(KernelFailure(terminal, MissingKernelNode))
  }
  prepare_sequence_count(
    owner,
    terminal + 1,
    limits,
    completed_producer=Some(serialization_step),
  )
}

///|
fn prepare_sequence_count(
  owner : BoundPrepared,
  count : Int,
  limits : SequenceLimits,
  infer_boundary? : Int? = None,
  serialization_boundary? : Int? = None,
  serialization_input? : Int? = None,
  completed_producer? : Int? = None,
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
    if completed_producer is Some(producer) && i <= producer {
      steps.push(CompletedProducerBoundary(i))
      continue
    }
    let step = match owner.prepared.nodes[i].payload {
      Infer(_) => {
        guard infer_boundary == Some(i) else {
          return Err(KernelFailure(i, MissingKernelNode))
        }
        InferBoundary(i)
      }
      // A retained-content barrier cannot execute as a pure Relation kernel.
      // Its dedicated bounded preparation selects the exact checked node.
      Serialize(_) => {
        if serialization_boundary == Some(i) {
          steps.push(SerializationBoundary(i))
          continue
        }
        guard serialization_input == Some(i) && i == count - 1 else {
          return Err(KernelFailure(i, MissingKernelNode))
        }
        let barrier = match
          prepare_serialization(owner, i, max_work=expressions.max_work) {
          Ok(barrier) => barrier
          Err(_) => return Err(KernelFailure(i, KernelBudgetExceeded))
        }
        let preparation_work = serialization_preparation_work(barrier)
        let kernel = match
          prepare_serialization_sort_kernel(
            barrier,
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work - preparation_work,
          ) {
          Ok(kernel) => kernel
          Err(issue) => return Err(KernelFailure(i, issue))
        }
        let terms = kernel_sort_term_count(kernel)
        bindings -= terms
        for term in 0..<terms {
          let (field, _, _) = kernel_sort_term_at(kernel, term).unwrap()
          names -= @utf8.encode(@schema.reference_name(field)).length()
        }
        expressions = {
          ..expressions,
          max_work: expressions.max_work - preparation_work - terms,
        }
        RowStep(kernel)
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
      GraphBoundsRows(_) | GraphDegreeRows(_) | GraphComponentsRows(_) => {
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
      GraphSubgraphValue(_) => {
        let (prepared, used_entries, used_names, remaining) = match
          prepare_graph_subgraph_node(
            owner,
            i,
            max_entries=bindings,
            max_name_bytes=names,
            expressions~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(GraphSubgraphFailure(i, issue))
        }
        bindings -= used_entries
        names -= used_names
        expressions = remaining
        GraphSubgraphStep(prepared)
      }
      GraphEqualityRows(_) => {
        let prepared = match
          prepare_graph_equality_node(owner.prepared.nodes[i]) {
          Ok(value) => value
          Err(issue) => return Err(GraphEqualityFailure(i, issue))
        }
        GraphEqualityStep(prepared)
      }
      GraphNormalizeValue(_) => GraphNormalizeStep(i)
      GraphUnionValue(_) =>
        match prepare_graph_union_node(owner.prepared.nodes[i]) {
          Ok(prepared) => GraphUnionStep(prepared)
          Err(issue) => return Err(GraphUnionFailure(i, issue))
        }
      GraphMeanValue(_) =>
        match prepare_graph_mean_node(owner.prepared.nodes[i]) {
          Ok(prepared) => GraphMeanStep(prepared)
          Err(issue) => return Err(GraphMeanFailure(i, issue))
        }
      GraphSubtractionValue(_) =>
        match prepare_graph_union_node(owner.prepared.nodes[i]) {
          Ok(prepared) => GraphSubtractionStep(prepared)
          Err(issue) => return Err(GraphUnionFailure(i, issue))
        }
      GraphDeltaValue(_) =>
        match prepare_graph_delta_node(owner.prepared.nodes[i]) {
          Ok(prepared) => GraphDeltaStep(prepared)
          Err(issue) => return Err(GraphDeltaFailure(i, issue))
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
      GraphConstructionValue(_) => {
        let (prepared, used_entries, used_names, used_work) = match
          prepare_graph_construction_node(
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
        GraphConstructionStep(prepared)
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
      CalendarValue(_) => {
        let (prepared, used_bindings, used_names, used_work) = match
          prepare_calendar_node(
            owner,
            i,
            max_rows=rows,
            max_cells=cells,
            max_bindings=bindings,
            max_name_bytes=names,
            max_work=expressions.max_work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(CalendarFailure(i, issue))
        }
        if calendar_row_bound(prepared) is Some(count) {
          rows -= count
          cells -= count * 2
        }
        bindings -= used_bindings
        names -= used_names
        expressions = {
          ..expressions,
          max_work: expressions.max_work - used_work,
        }
        CalendarStep(prepared)
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
    emit_sequence_node(value, index, out)
  }
  @encode.end_array(out)
}

///|
/// Emit the existing canonical nodes for one checked step, without an array
/// wrapper. Ordered bindings still require their registered params owner.
pub fn emit_sequence_node(
  value : PreparedSequence,
  index : Int,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  guard value.steps.get(index) is Some(step) else {
    raise @encode.InvalidStructure
  }
  match step {
    InferBoundary(_)
    | SerializationBoundary(_)
    | CompletedProducerBoundary(_) => raise @encode.InvalidStructure
    ValuesStep(v) => emit_values_node(v, out)
    TimeSeriesStep(v) => emit_time_series_node(v, out)
    CalendarStep(v) => emit_calendar_node(v, out)
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
    GraphSubgraphStep(v) => emit_graph_subgraph_node(v, out)
    GraphEqualityStep(v) => emit_graph_equality_node(v, out)
    GraphNormalizeStep(index) =>
      emit_graph_normalize_node(value.owner, index, out)
    GraphDeltaStep(prepared) => emit_graph_delta_node(prepared, out)
    GraphUnionStep(prepared) => emit_graph_union_node(prepared, out)
    GraphMeanStep(prepared) => emit_graph_mean_node(prepared, out)
    GraphSubtractionStep(prepared) => emit_graph_union_node(prepared, out)
    GraphTraverseStep(v) => emit_graph_traverse_node(v, out)
    GraphConstructionStep(v) => emit_graph_construction_node(v, out)
    VectorStep(v) => emit_vector_node(v, out)
    EventStep(v) => emit_event_node(v, out)
    CarrierProjectionStep(v) => emit_carrier_projection_node(v, out)
    RowStep(v) => {
      emit_kernel_prefix(v, out)
      emit_kernel_node(v, out)
    }
  }
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
