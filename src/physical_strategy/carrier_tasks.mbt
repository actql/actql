///|
priv suberror CarrierWorkStop {
  CarrierWorkStop
}

///|
/// Spend the existing preparation balance before visiting an entry. Exhaustion
/// unwinds classification or remapping without publishing a partial graph.
fn carrier_work(
  work : Ref[Int],
  amount? : Int = 1,
) -> Unit raise CarrierWorkStop {
  if amount > work.val {
    raise CarrierWorkStop
  }
  work.val -= amount
}

///|
fn carrier_node_supports_selected_execution(
  node : @lower.PreparedNode,
  work : Ref[Int],
  analytic? : Bool = false,
) -> Bool raise CarrierWorkStop {
  // Relation DAGs with independent Values roots may hand an analytic occurrence to the already
  // registered bounded group provider. That provider retains the exact
  // order, frame, expression-context and numeric admission checks. Other
  // analytic shapes keep their existing fused ownership decision.
  if analytic && @lower.payload(node) is @lower.Analytic(_) {
    return true
  }
  // The lowering capability query scans aggregate descriptors. Reserve its
  // bounded scan before entering it, including unsupported count profiles.
  if @lower.payload(node) is @lower.CountGroup(checked) &&
    @relation.group(checked) is Some(group) {
    carrier_work(work, amount=@relation.aggregate_count(group))
  }
  @lower.node_supports_selected_managed_execution(node)
}

///|
/// Follow checked source edges to a bounded zero-input source or a typed
/// Carrier boundary. Ordinary remote Relation chains keep their native
/// whole-Stage realization until that realization supports selected Steps.
fn segmentable_relation_source(
  graph : CheckedDAG,
  start : Int,
  work : Ref[Int],
) -> Bool raise CarrierWorkStop {
  let mut stage = start
  let mut visited = 0
  while stage >= 0 &&
        stage < graph.owners.length() &&
        visited < graph.owners.length() {
    carrier_work(work)
    visited += 1
    let prepared = @lower.bound_preparation(graph.owners[stage])
    let count = @pipeline.step_count(@lower.pipeline(prepared))
    for step in 0..<count {
      carrier_work(work)
      guard @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
        is Some(carrier) else {
        return false
      }
      if @carrier.kind(carrier) != @carrier.RelationKind {
        return true
      }
    }
    guard count > 0 && @lower.node_at(prepared, 0) is Some(first) else {
      return false
    }
    if @lower.preparation_input_count(prepared) == 0 &&
      @lower.node_input_count(first) == 0 {
      return carrier_node_supports_selected_execution(first, work)
    }
    guard @lower.node_input_count(first) == 1 &&
      @lower.node_input_target(first, 0) is Some(@pipeline.Input(source)) else {
      return false
    }
    let mut predecessor = -1
    for edge in graph.data {
      carrier_work(work)
      if edge.consumer == stage && edge.input == source {
        predecessor = edge.producer
        break
      }
    }
    stage = predecessor
  }
  false
}

///|
/// Keep a Relation family child and its linear bounded suffix under one owner.
/// This is a shape decision, not provider registration or execution authority.
fn bounded_family_relation_chain(
  graph : CheckedDAG,
  stage : Int,
  work : Ref[Int],
) -> Bool raise CarrierWorkStop {
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let count = @pipeline.step_count(@lower.pipeline(prepared))
  guard count > 1 && @lower.node_at(prepared, 0) is Some(first) else {
    return false
  }
  match @lower.payload(first) {
    @lower.NestRows(_)
    | @lower.TimeSeriesValue(_)
    | @lower.IntervalJoinRows(_)
    | @lower.AsOfJoinRows(_)
    | @lower.SequenceRows(_) => ()
    @lower.CalendarValue(_) if @lower.operation(first) == "TEA.calendar.series" =>
      ()
    @lower.EventValue(_) if @lower.operation(first) ==
      "TEA.window.session_assign" => ()
    _ => return false
  }
  for step in 0..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) &&
      @carrier.kind(@lower.node_output_carrier(node)) == @carrier.RelationKind else {
      return false
    }
    if step > 0 &&
      (
        !carrier_node_supports_selected_execution(node, work) ||
        @lower.node_input_count(node) != 1 ||
        @lower.node_input_target(node, 0) != Some(@pipeline.Step(step - 1))
      ) {
      return false
    }
    for port in 0..<@lower.node_input_count(node) {
      carrier_work(work)
      guard @lower.node_accepts_managed_relation_view(node, port) &&
        @lower.node_input_target(node, port) is Some(target) &&
        @lower.preparation_carrier_at(prepared, target) is Some(input) &&
        @carrier.kind(input) == @carrier.RelationKind else {
        return false
      }
    }
  }
  // Intermediate Result roots need independently owned task outputs.
  for result in graph.results {
    carrier_work(work)
    if result.task == stage &&
      @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      ) !=
      @pipeline.Step(count - 1) {
      return false
    }
  }
  true
}

///|
/// A checked binary Relation task may reuse a private intermediate in two
/// later steps and join those branches. Keep only this bounded, single-root
/// shape together, including checked group, window, or expansion children;
/// other nonlinear or Carrier paths retain per-edge tasks.
fn bounded_branched_relation_chain(
  graph : CheckedDAG,
  stage : Int,
  work : Ref[Int],
) -> Bool raise CarrierWorkStop {
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let count = @pipeline.step_count(@lower.pipeline(prepared))
  guard count >= 3 && @lower.node_at(prepared, 0) is Some(first) else {
    return false
  }
  match @lower.payload(first) {
    @lower.InnerJoin(_)
    | @lower.AppendRows(_)
    | @lower.SetRows(_)
    | @lower.CrossJoinRows(_) => ()
    _ => return false
  }
  for result in graph.results {
    carrier_work(work)
    if result.task == stage &&
      @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      ) !=
      @pipeline.Step(count - 1) {
      return false
    }
  }
  // Reserve every bitmap slot before allocating the private reachability array.
  carrier_work(work, amount=count)
  let used_by_later = Array::make(count, false)
  let mut branched = false
  for step in 0..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) &&
      @carrier.kind(@lower.node_output_carrier(node)) == @carrier.RelationKind else {
      return false
    }
    // A checked analytic may stay inside this bounded fork, but its exact
    // aggregate and frame support is decided by the selected group provider.
    // Do not advertise every analytic as an independently splittable task.
    if !(@lower.payload(node) is @lower.Analytic(_)) &&
      !carrier_node_supports_selected_execution(node, work) {
      return false
    }
    match @lower.payload(node) {
      @lower.InnerJoin(_)
      | @lower.AppendRows(_)
      | @lower.SetRows(_)
      | @lower.CrossJoinRows(_)
      | @lower.Where(_)
      | @lower.Derive(_)
      | @lower.Select(_)
      | @lower.Sort(_)
      | @lower.Limit(_)
      | @lower.TopK(_)
      | @lower.TopKBy(_)
      | @lower.Distinct(_)
      | @lower.Dedupe(_)
      | @lower.Lag(_)
      | @lower.JsonPick(_)
      | @lower.Watermark(_)
      | @lower.RowWindow(_)
      | @lower.Pivot(_)
      | @lower.Unpivot(_)
      | @lower.Unnest(_)
      | @lower.Analytic(_)
      | @lower.AssertRows(_)
      | @lower.CountGroup(_) => ()
      _ => return false
    }
    for port in 0..<@lower.node_input_count(node) {
      carrier_work(work)
      guard @lower.node_accepts_managed_relation_view(node, port) &&
        @lower.node_input_target(node, port) is Some(target) &&
        @lower.preparation_carrier_at(prepared, target) is Some(carrier) &&
        @carrier.kind(carrier) == @carrier.RelationKind else {
        return false
      }
      match target {
        @pipeline.Step(producer) => {
          if producer < 0 || producer >= step {
            return false
          }
          used_by_later[producer] = true
          if producer != step - 1 || port > 0 {
            branched = true
          }
        }
        @pipeline.Input(source) =>
          if source < 0 || source >= @lower.preparation_input_count(prepared) {
            return false
          }
      }
    }
    // A later child may read a Stage input directly. Its output must still
    // feed a later child, as checked by used_by_later below; the selected
    // chain owner binds that input to this exact operation port.
  }
  for step in 0..<(count - 1) {
    carrier_work(work)
    if !used_by_later[step] {
      return false
    }
  }
  branched
}

///|
priv struct CarrierSegmentShape {
  values_source : Bool
  carrier_construction : Bool
  carrier_relation_consumer : Bool
  relation_dag : Bool
}

///|
/// Inspect the whole checked sequence before admitting analytic selection.
/// Both the root eligibility check and a later analytic capability query use
/// this same charged scan, including nodes and ports after that analytic.
fn carrier_segment_shape(
  prepared : @lower.Prepared,
  work : Ref[Int],
) -> CarrierSegmentShape? raise CarrierWorkStop {
  let count = @pipeline.step_count(@lower.pipeline(prepared))
  let mut values_source = false
  let mut carrier_construction = false
  let mut carrier_relation_consumer = false
  let mut relation_only = true
  let mut values_roots = 0
  let mut binary_relation_consumer = false
  for step in 0..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    match @lower.operation(node) {
      "REL.values" => {
        values_source = true
        if @lower.node_input_count(node) == 0 {
          values_roots += 1
        }
      }
      _ => ()
    }
    if @carrier.kind(@lower.node_output_carrier(node)) != @carrier.RelationKind {
      relation_only = false
      for input in 0..<@lower.node_input_count(node) {
        carrier_work(work)
        if @lower.node_input_target(node, input)
          is Some(@pipeline.Step(producer)) &&
          @lower.preparation_carrier_at(prepared, @pipeline.Step(producer))
          is Some(source) &&
          @carrier.kind(source) == @carrier.RelationKind {
          carrier_construction = true
        }
      }
    }
    if @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
      is Some(output) &&
      @carrier.kind(output) == @carrier.RelationKind {
      if @lower.node_input_count(node) == 2 {
        binary_relation_consumer = true
      }
      for input in 0..<@lower.node_input_count(node) {
        carrier_work(work)
        match @lower.node_input_target(node, input) {
          Some(@pipeline.Step(producer)) =>
            if @lower.preparation_carrier_at(prepared, @pipeline.Step(producer))
              is Some(source) &&
              @carrier.kind(source) != @carrier.RelationKind {
              carrier_relation_consumer = true
            }
          _ => ()
        }
      }
    }
  }
  // Independent Values roots and branches joined from one shared Values
  // root need exact operation ports. Let these Relation-only DAGs reach the
  // selected-provider and per-edge checks below; shape alone cannot split.
  // A unary nonlinear Values suffix still retains its existing refusal.
  let relation_dag = relation_only &&
    (values_roots > 1 || (values_roots > 0 && binary_relation_consumer))
  Some({
    values_source,
    carrier_construction,
    carrier_relation_consumer,
    relation_dag,
  })
}

///|
/// Keep a single original Model execution through a checked intermediate
/// Result, with an independently supported unary Relation suffix.
fn infer_result_prefix_end(
  graph : CheckedDAG,
  stage : Int,
  work : Ref[Int],
) -> Int? raise CarrierWorkStop {
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let count = @pipeline.step_count(@lower.pipeline(prepared))
  let mut boundary = None
  for step in 0..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    match @lower.payload(node) {
      @lower.Infer(_) => {
        if boundary is Some(_) {
          return None
        }
        boundary = Some(step)
      }
      @lower.Serialize(_) => return None
      _ => ()
    }
  }
  guard boundary is Some(infer) else { return None }
  let mut terminal = count - 1
  for result in graph.results {
    carrier_work(work)
    if result.task != stage {
      continue
    }
    guard @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      )
      is @pipeline.Step(step) &&
      step >= infer else {
      return None
    }
    terminal = Int::min(terminal, step)
  }
  if terminal == count - 1 {
    return None
  }
  // The one Model operation stays in its original fused prefix. Only the
  // already registered unary Relation suffix becomes independent tasks;
  // no selected Model provider, repeated call, or substitute Result is made.
  for step in (terminal + 1)..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) &&
      carrier_node_supports_selected_execution(node, work) &&
      @lower.node_input_count(node) == 1 &&
      @lower.node_accepts_managed_relation_view(node, 0) &&
      @lower.node_input_target(node, 0) == Some(@pipeline.Step(step - 1)) &&
      @carrier.kind(@lower.node_output_carrier(node)) == @carrier.RelationKind else {
      return None
    }
  }
  Some(terminal)
}

///|
/// Split a mixed sequence at checked managed read boundaries. A prefix without
/// standalone providers remains one fused task through its Relation bridge;
/// later row operations use their own selected tasks.
/// -1 means that every step can be selected independently.
fn carrier_segment_prefix_end(
  graph : CheckedDAG,
  stage : Int,
  work : Ref[Int],
) -> Int? raise CarrierWorkStop {
  if stage < 0 || stage >= graph.owners.length() {
    return None
  }
  if graph.selected_steps[stage] is Some(_) ||
    graph.prefix_ends[stage] is Some(_) {
    return None
  }
  if stage < graph.captured_prefix {
    return captured_segment_prefix_end(graph, stage, work)
  }
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let pipeline = @lower.pipeline(prepared)
  let count = @pipeline.step_count(pipeline)
  let mut intermediate_result = false
  for result in graph.results {
    carrier_work(work)
    if result.task == stage &&
      @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      )
      is @pipeline.Step(step) &&
      step < count - 1 {
      intermediate_result = true
    }
  }
  // An installed Content child already owns generation inside a fused task.
  // Split that task only when a checked intermediate Result requires its own
  // retained completion; selected capability alone is not a reason to change
  // an existing single-terminal realization or repeat its pure prefix.
  if !intermediate_result {
    for step in 0..<count {
      carrier_work(work)
      if @lower.node_at(prepared, step) is Some(node) &&
        @lower.payload(node) is @lower.Serialize(_) {
        return None
      }
    }
  }
  if stage == 0 && !graph.source_free_root {
    return None
  }
  let mut selected_relation_dag : Bool? = None
  if stage == 0 {
    guard carrier_segment_shape(prepared, work) is Some(shape) else {
      return None
    }
    selected_relation_dag = Some(shape.relation_dag)
    // A source-free Carrier prefix needs segmentation when a later typed
    // Carrier-to-Relation step or an intermediate Result needs independent
    // ownership. Carrier-only prefixes without either retain fused execution.
    if !shape.values_source ||
      (
        !shape.relation_dag &&
        (
          (!shape.carrier_construction && !intermediate_result) ||
          (!shape.carrier_relation_consumer && !intermediate_result)
        )
      ) {
      return None
    }
  }
  if count < 2 {
    return None
  }
  if intermediate_result &&
    infer_result_prefix_end(graph, stage, work) is Some(last) {
    return Some(last)
  }
  // The registered family child and bounded row suffix share one chain owner.
  // Carrier-valued inputs and intermediate Result roots still use segmentation.
  if bounded_family_relation_chain(graph, stage, work) {
    return None
  }
  if bounded_branched_relation_chain(graph, stage, work) {
    return None
  }
  let mut found_carrier = false
  let mut carrier_transform = false
  let mut found_relation = false
  let mut found_zero_input = false
  let mut zero_input_count = 0
  let mut found_binary = false
  let mut found_external_input = false
  let mut nonlinear_relation_input = false
  let mut prefer_fused_without_relation = false
  let mut all_selected = true
  for step in 0..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    // Later non-analytic stages do not need the root eligibility scan.
    // Cache the complete shape once, only when an analytic asks for it;
    // a Relation prefix alone cannot prove a Relation-only DAG.
    if @lower.payload(node) is @lower.Analytic(_) &&
      selected_relation_dag is None {
      guard carrier_segment_shape(prepared, work) is Some(shape) else {
        return None
      }
      selected_relation_dag = Some(shape.relation_dag)
    }
    if !carrier_node_supports_selected_execution(
        node,
        work,
        analytic=selected_relation_dag == Some(true),
      ) {
      all_selected = false
      break
    }
    if @lower.node_input_count(node) == 0 {
      found_zero_input = true
      zero_input_count += 1
    } else if @lower.node_input_count(node) == 2 {
      found_binary = true
    }
    for input in 0..<@lower.node_input_count(node) {
      carrier_work(work)
      match @lower.node_input_target(node, input) {
        Some(@pipeline.Step(producer)) => {
          guard producer >= 0 &&
            producer < step &&
            @lower.preparation_carrier_at(prepared, @pipeline.Step(producer))
            is Some(carrier) else {
            return None
          }
          if @carrier.kind(carrier) == @carrier.RelationKind {
            if @lower.preparation_schema_at(prepared, @pipeline.Step(producer))
              is None ||
              !@lower.node_accepts_managed_relation_view(node, input) {
              return None
            }
            found_relation = true
            // The fused primary input follows the preceding Step. A later
            // primary reference, or a binary peer held by an internal Step,
            // needs exact per-operation ports. Fused JOINs with an external
            // peer remain unchanged.
            if (
                @lower.node_input_count(node) <= 2 &&
                input == 0 &&
                producer != step - 1
              ) ||
              (@lower.node_input_count(node) == 2 && input == 1) {
              nonlinear_relation_input = true
            }
          } else {
            if !@lower.node_accepts_managed_carrier_view(node, input) {
              return None
            }
            found_carrier = true
            if @lower.node_can_split_carrier_transform(node) {
              // A selected Carrier-to-Carrier step has its own output
              // generation. A later row consumer need not keep the whole
              // prefix fused merely to reuse that generation.
              carrier_transform = true
            }
            if @lower.node_prefers_fused_without_relation_consumer(node) {
              prefer_fused_without_relation = true
            }
          }
        }
        Some(@pipeline.Input(source)) => {
          found_external_input = true
          // A retained secondary Relation requires selected execution even
          // when an earlier Carrier transform or later MATCH prefers fusion.
          // Nearest already binds both Stage inputs in its fused provider;
          // its external Relation peer alone does not require a split.
          if !(@lower.payload(node) is @lower.NearestValue(_)) &&
            input > 0 &&
            @lower.node_accepts_managed_relation_view(node, input) &&
            @lower.node_accepts_managed_carrier_view(node, 0) &&
            @lower.node_input_target(node, 0) is Some(@pipeline.Step(primary)) &&
            @lower.preparation_carrier_at(prepared, @pipeline.Step(primary))
            is Some(carrier) &&
            @carrier.kind(carrier) != @carrier.RelationKind {
            let mut retained_relation = false
            for edge in graph.data {
              carrier_work(work)
              if edge.consumer == stage &&
                edge.input == source &&
                edge.producer >= 0 &&
                edge.producer < graph.owners.length() {
                let predecessor = @lower.bound_preparation(
                  graph.owners[edge.producer],
                )
                if @lower.preparation_carrier_at(predecessor, edge.target)
                  is Some(input_carrier) &&
                  @carrier.kind(input_carrier) == @carrier.RelationKind &&
                  @lower.preparation_schema_at(predecessor, edge.target)
                  is Some(_) {
                  retained_relation = true
                }
              }
            }
            if !retained_relation {
              return None
            }
            found_relation = true
          }
          // A binary JOIN may reread an external peer in a fused chain.
          // Only a later primary port restarts an independent branch.
          if step > 0 && @lower.node_input_count(node) <= 2 && input == 0 {
            nonlinear_relation_input = true
          }
        }
        None => return None
      }
    }
  }
  if all_selected &&
    found_carrier &&
    (!prefer_fused_without_relation || found_relation || carrier_transform) {
    return Some(-1)
  }
  // A non-linear Relation dependency cannot be realized by the fused provider.
  // Select checked steps only when every external port has an exact retained
  // Relation edge;
  // the captured predecessor and its acquisition remain one owned task.
  if all_selected &&
    nonlinear_relation_input &&
    found_relation &&
    !found_carrier {
    for step in 0..<count {
      carrier_work(work)
      let node = @lower.node_at(prepared, step).unwrap()
      for input in 0..<@lower.node_input_count(node) {
        carrier_work(work)
        if @lower.node_input_target(node, input)
          is Some(@pipeline.Input(source)) {
          if !@lower.node_accepts_managed_relation_view(node, input) {
            return None
          }
          let mut retained_relation = false
          for edge in graph.data {
            carrier_work(work)
            if edge.consumer == stage &&
              edge.input == source &&
              edge.producer >= 0 &&
              edge.producer < graph.owners.length() {
              let predecessor = @lower.bound_preparation(
                graph.owners[edge.producer],
              )
              if @lower.preparation_carrier_at(predecessor, edge.target)
                is Some(carrier) &&
                @carrier.kind(carrier) == @carrier.RelationKind {
                retained_relation = true
              }
            }
          }
          if !retained_relation {
            return None
          }
        }
      }
    }
    return Some(-1)
  }
  // A retained intermediate Relation Result needs its own exact output.
  // Use the same checked managed-view handoff as Carrier consumers, only
  // when every occurrence has a registered selected execution capability.
  // A captured predecessor is already an owned Result; splitting its
  // consumer does not split or repeat the physical source acquisition.
  if intermediate_result && all_selected && found_relation && !found_carrier {
    if found_zero_input && !found_external_input {
      return Some(-1)
    }
    guard @lower.node_at(prepared, 0) is Some(first) else { return None }
    // A registered unary consumer or binary JOIN can start from retained
    // Relation ports. Prove every input separately, including two references
    // to the same producer; one valid port cannot authorize the other.
    let input_count = @lower.node_input_count(first)
    if input_count == 1 || input_count == 2 {
      let mut complete_inputs = true
      for input in 0..<input_count {
        carrier_work(work)
        if !@lower.node_accepts_managed_relation_view(first, input) {
          complete_inputs = false
          break
        }
        guard @lower.node_input_target(first, input)
          is Some(@pipeline.Input(source)) else {
          complete_inputs = false
          break
        }
        let mut retained_relation = false
        for edge in graph.data {
          carrier_work(work)
          if edge.consumer == stage &&
            edge.input == source &&
            edge.producer >= 0 &&
            edge.producer < graph.owners.length() {
            let predecessor = @lower.bound_preparation(
              graph.owners[edge.producer],
            )
            if @lower.preparation_carrier_at(predecessor, edge.target)
              is Some(carrier) &&
              @carrier.kind(carrier) == @carrier.RelationKind {
              retained_relation = true
            }
          }
        }
        if !retained_relation {
          complete_inputs = false
          break
        }
      }
      if complete_inputs {
        return Some(-1)
      }
    }
  }
  // A checked multi-source Relation DAG can use the same per-edge handoff
  // when every zero-input producer and binary consumer has a bounded provider.
  if all_selected && found_zero_input && found_binary && found_relation {
    return Some(-1)
  }
  // Independent zero-input branches need no external representation plan.
  // Split their exact internal Relation edges even without a binary join.
  if all_selected &&
    zero_input_count > 1 &&
    found_relation &&
    !found_external_input {
    return Some(-1)
  }
  // Exact supplied input and completed Relation edges can each select
  // independently owned Relation steps.
  if all_selected && found_relation && !found_carrier {
    guard @lower.node_at(prepared, 0) is Some(first) else { return None }
    if @lower.node_accepts_managed_relation_view(first, 0) &&
      @lower.node_input_count(first) == 1 &&
      @lower.node_input_target(first, 0) is Some(@pipeline.Input(source)) {
      if original_supplied_slot(graph, stage, source, work) is Some(_) {
        return Some(-1)
      }
      for edge in graph.data {
        carrier_work(work)
        if edge.consumer != stage ||
          edge.input != source ||
          edge.producer < 0 ||
          edge.producer >= graph.owners.length() {
          continue
        }
        if segmentable_relation_source(graph, edge.producer, work) {
          return Some(-1)
        }
      }
    }
  }
  // Find the maximal selected Relation suffix in one pass. Its predecessor
  // is the exact output retained by the fused prefix.
  let mut suffix_start = count
  while suffix_start > 1 {
    carrier_work(work)
    let step = suffix_start - 1
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    if !carrier_node_supports_selected_execution(node, work) ||
      @lower.node_input_count(node) != 1 ||
      !@lower.node_accepts_managed_relation_view(node, 0) ||
      @lower.node_input_target(node, 0) != Some(@pipeline.Step(step - 1)) {
      break
    }
    suffix_start = step
  }
  if suffix_start == count || suffix_start < 1 {
    return None
  }
  let terminal = suffix_start - 1
  guard @lower.preparation_carrier_at(prepared, @pipeline.Step(terminal))
    is Some(carrier) &&
    @carrier.kind(carrier) == @carrier.RelationKind else {
    return None
  }
  if terminal == 0 {
    // The prefix is independently bounded; its later Relation consumers can
    // be split without executing the whole authored sequence synchronously.
    guard @lower.node_at(prepared, 0) is Some(prefix) &&
      @lower.node_at(prepared, 1) is Some(consumer) &&
      @lower.node_supports_bounded_managed_prefix(prefix, consumer) else {
      return None
    }
    // A linear Cross Join followed by supported row projections has a
    // bounded whole-task owner. Keep its checked operation occurrences in
    // that task so the retained output uses the same chain completion.
    if @lower.payload(prefix) is @lower.CrossJoinRows(_) {
      let mut row_suffix = true
      for step in 1..<count {
        carrier_work(work)
        guard @lower.node_at(prepared, step) is Some(node) else { return None }
        match @lower.payload(node) {
          @lower.Where(_) | @lower.Derive(_) | @lower.Select(_) => ()
          _ => row_suffix = false
        }
      }
      if row_suffix {
        return None
      }
    }
  } else {
    let mut carrier_prefix = false
    for step in 0..<terminal {
      carrier_work(work)
      guard @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
        is Some(input_carrier) else {
        return None
      }
      if @carrier.kind(input_carrier) != @carrier.RelationKind {
        carrier_prefix = true
      }
    }
    if !carrier_prefix {
      return None
    }
  }
  for result in graph.results {
    carrier_work(work)
    if result.task == stage {
      match
        @ports.port_target(
          @execution.managed_result_occurrence_port(result.occurrence),
        ) {
        @pipeline.Step(step) => if step < terminal { return None }
        _ => return None
      }
    }
  }
  Some(terminal)
}

///|
/// A Direct scan/filter/select capture is not completion of a later keyed
/// JOIN or selected Relation operation in the same authored Stage. Derive that boundary
/// from the original requests, then use the existing selected-task and
/// exact-port expansion. The source capture never impersonates a later Result.
fn captured_segment_prefix_end(
  graph : CheckedDAG,
  stage : Int,
  work : Ref[Int],
) -> Int? raise CarrierWorkStop {
  if graph.captured_prefix != 1 || stage != 0 {
    return None
  }
  let identity = @checked.source_identity(graph.program)
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return None
  }
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let pipeline = @lower.pipeline(prepared)
  let count = @pipeline.step_count(pipeline)
  if count < 3 {
    return None
  }
  let mut keyed : @checked.KeyedExecution? = None
  for index in 0..<@checked.source_execution_count(graph.program) {
    carrier_work(work)
    let check = @checked.source_execution_at(graph.program, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    if subject.stage == stage &&
      @checked.source_execution_kind(check) is @checked.KeyedRequest(binding) &&
      @acquisition.keyed_join_step(binding.join) == 2 &&
      @acquisition.keyed_join_left(binding.join) == @pipeline.Step(1) {
      if keyed is Some(_) || !physical_equal(subject.owner, identity) {
        return None
      }
      keyed = Some(binding)
    }
  }
  let direct_relation_suffix = keyed is None
  guard @lower.node_at(prepared, 0) is Some(first) &&
    @lower.node_input_target(first, 0) is Some(@pipeline.Input(source)) else {
    return None
  }
  // Reserve the derivation's complete edge/Result scan before calling it.
  // Its refusal has no work getter, so charge the declared scan envelope on
  // both success and refusal rather than silently refunding a failed scan.
  carrier_work(work)
  let mut derivation_work = 1
  for step in 0..<count {
    carrier_work(work)
    derivation_work += 1
    let inputs = @pipeline.input_occurrence_count(
      @pipeline.step_at(pipeline, step).unwrap(),
    )
    carrier_work(work, amount=inputs)
    derivation_work += inputs
  }
  guard @results.stage_at(@checked.checked_stage_results(graph.program), stage)
    is Some(stage_results) else {
    return None
  }
  let results = @ports.count(stage_results)
  carrier_work(work, amount=results)
  derivation_work += results
  for index in 0..<2 {
    guard @pipeline.step_at(pipeline, index) is Some(step) &&
      step.operation is @pipeline.Unary(operation) else {
      return None
    }
    let bindings = @relation.binding_count(operation)
    carrier_work(work, amount=bindings)
    derivation_work += bindings
  }
  guard @acquisition.derive_query_acquisition_shape(
      requests, source, derivation_work,
    )
    is Ok(acquisition) &&
    physical_equal(
      @acquisition.query_acquisition_pipeline(acquisition),
      pipeline,
    ) &&
    @acquisition.query_acquisition_filter_index(acquisition) == 0 &&
    @acquisition.query_acquisition_capture(acquisition) == @pipeline.Step(1) else {
    return None
  }
  // Every later task must have an existing selected managed realization.
  // The two acquisition operations keep their original fused capture owner.
  for step in 2..<count {
    carrier_work(work)
    guard @lower.node_at(prepared, step) is Some(node) &&
      carrier_node_supports_selected_execution(node, work) else {
      return None
    }
    if direct_relation_suffix {
      match @lower.payload(node) {
        // A row assertion is a separately checked operation, not completion
        // of the acquisition prefix. Preserve its own port and selected
        // provider so the later Result cannot impersonate the capture.
        @lower.Derive(_)
        | @lower.Select(_)
        | @lower.AssertRows(_)
        | @lower.Sort(_) => ()
        _ => return None
      }
    }
    for port in 0..<@lower.node_input_count(node) {
      carrier_work(work)
      guard @lower.node_accepts_managed_relation_view(node, port) &&
        @lower.node_input_target(node, port) is Some(target) &&
        @lower.preparation_carrier_at(prepared, target) is Some(carrier) &&
        @carrier.kind(carrier) == @carrier.RelationKind else {
        return None
      }
      if target is @pipeline.Step(producer) &&
        (producer < 1 || producer >= step) {
        return None
      }
      if target is @pipeline.Input(input) &&
        original_supplied_slot(graph, stage, input, work) is None {
        return None
      }
    }
  }
  Some(1)
}

///|
fn mapped_stage_target(
  tasks : Array[Array[Int]],
  stage : Int,
  target : @pipeline.Target,
) -> Int? {
  guard tasks.get(stage) is Some(stage_tasks) && !stage_tasks.is_empty() else {
    return None
  }
  if stage_tasks.length() == 1 {
    return stage_tasks.get(0)
  }
  match target {
    @pipeline.Step(step) => stage_tasks.get(step)
    @pipeline.Input(_) => None
  }
}

///|
fn original_data_edge(
  graph : CheckedDAG,
  stage : Int,
  input : Int,
  work : Ref[Int],
) -> DataEdge? raise CarrierWorkStop {
  for edge in graph.data {
    carrier_work(work)
    if edge.consumer == stage && edge.input == input {
      return Some(edge)
    }
  }
  None
}

///|
fn original_supplied_slot(
  graph : CheckedDAG,
  stage : Int,
  input : Int,
  work : Ref[Int],
) -> LocalInputSlot? raise CarrierWorkStop {
  for slot in graph.supplied_slots {
    carrier_work(work)
    if slot.consumer == stage && slot.input == input {
      return Some(slot)
    }
  }
  // A keyed Source response becomes a supplied Relation input only after its
  // original whole-key acquisition. This is a port requirement, not Local
  // completeness or permission to skip Source evidence/authorization. Keep
  // Direct acquisition roots out of this receiving-port inventory.
  // Only the captured root can contain this initial keyed acquisition shape.
  // Do not scan Source declarations on unrelated Compute ports: their input
  // inventory and exact existing classification work remain unchanged.
  if stage >= graph.captured_prefix ||
    @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(graph.owners[stage])),
    ) <
    3 {
    return None
  }
  for index in 0..<@checked.source_execution_count(graph.program) {
    carrier_work(work)
    let check = @checked.source_execution_at(graph.program, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    if subject.stage == stage &&
      subject.input == input &&
      @checked.source_execution_kind(check) is @checked.KeyedRequest(binding) &&
      binding.stage == stage &&
      @acquisition.keyed_join_input(binding.join) == input &&
      physical_equal(subject.owner, @checked.source_identity(graph.program)) {
      return Some({
        consumer: stage,
        input,
        source_input: input,
        operation_input: None,
      })
    }
  }
  None
}

///|
/// Expand structurally safe mixed Carrier/Relation sequences into common
/// physical tasks. The author-visible owner, global step coordinates and
/// Result occurrences remain unchanged.
pub fn expand_internal_carrier_tasks(
  graph : CheckedDAG,
  max_tasks : Int,
  max_work : Int,
) -> Result[CheckedDAG, GraphIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let work = Ref(max_work)
  expand_internal_carrier_tasks_with_work(graph, max_tasks, work) catch {
    CarrierWorkStop => Err(WorkLimit)
  }
}

///|
fn expand_internal_carrier_tasks_with_work(
  graph : CheckedDAG,
  max_tasks : Int,
  work : Ref[Int],
) -> Result[CheckedDAG, GraphIssue] raise CarrierWorkStop {
  let stages = graph.owners.length()
  let mut any_segmentable = false
  let split_boundaries : Array[Int?] = []
  for stage in 0..<stages {
    carrier_work(work)
    let boundary = carrier_segment_prefix_end(graph, stage, work)
    split_boundaries.push(boundary)
    if boundary is Some(_) {
      any_segmentable = true
    }
  }
  if !any_segmentable {
    return Ok(graph)
  }
  let stage_tasks : Array[Array[Int]] = Array::makei(stages, _ => [])
  let expanded = Array::make(stages, false)
  let owners = []
  let targets = []
  let input_counts = []
  let selected_steps = []
  let prefix_ends = []
  let operations : Array[Array[TaskOperationRequirement]] = []
  let numeric : Array[Array[TaskNumericObservation]] = []

  for stage in 0..<stages {
    carrier_work(work)
    let split_boundary = split_boundaries[stage]
    let split = split_boundary is Some(_)
    expanded[stage] = split
    let step_count = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(graph.owners[stage])),
    )
    let prefix_end = split_boundary.unwrap_or(-1)
    let task_count = if !split {
      1
    } else if prefix_end < 0 {
      step_count
    } else {
      step_count - prefix_end
    }
    if task_count > max_tasks - owners.length() {
      return Err(TaskLimit)
    }
    for position in 0..<task_count {
      carrier_work(work)
      let task = owners.length()
      if split && position == 0 && prefix_end >= 0 {
        for _ in 0..<(prefix_end + 1) {
          carrier_work(work)
          stage_tasks[stage].push(task)
        }
      } else {
        stage_tasks[stage].push(task)
      }
      owners.push(graph.owners[stage])
      operations.push([])
      numeric.push([])
      if split {
        let step = if prefix_end >= 0 {
          prefix_end + position
        } else {
          position
        }
        let node = @lower.node_at(
          @lower.bound_preparation(graph.owners[stage]),
          step,
        ).unwrap()
        targets.push(Some(@pipeline.Step(step)))
        if prefix_end >= 0 && position == 0 {
          input_counts.push(graph.input_counts[stage])
          selected_steps.push(None)
          prefix_ends.push(Some(prefix_end))
        } else {
          input_counts.push(@lower.node_input_count(node))
          selected_steps.push(Some(step))
          prefix_ends.push(None)
        }
      } else {
        targets.push(graph.targets[stage])
        input_counts.push(graph.input_counts[stage])
        selected_steps.push(None)
        prefix_ends.push(None)
      }
    }
  }

  let data : Array[DataEdge] = []
  let supplied_slots : Array[LocalInputSlot] = []
  for stage in 0..<stages {
    carrier_work(work)
    if !expanded[stage] {
      let consumer = stage_tasks[stage][0]
      for edge in graph.data {
        carrier_work(work)
        if edge.consumer == stage {
          guard mapped_stage_target(stage_tasks, edge.producer, edge.target)
            is Some(producer) else {
            return Err(ForeignPort(stage, edge.input))
          }
          data.push({ ..edge, producer, consumer, })
        }
      }
      for slot in graph.supplied_slots {
        carrier_work(work)
        if slot.consumer == stage {
          supplied_slots.push({ ..slot, consumer, })
        }
      }
      continue
    }
    let prepared = @lower.bound_preparation(graph.owners[stage])
    let prefix_end = split_boundaries[stage].unwrap_or(-1)
    if prefix_end >= 0 {
      let prefix_task = stage_tasks[stage][0]
      for edge in graph.data {
        carrier_work(work)
        if edge.consumer == stage {
          guard mapped_stage_target(stage_tasks, edge.producer, edge.target)
            is Some(producer) else {
            return Err(ForeignPort(stage, edge.input))
          }
          data.push({ ..edge, producer, consumer: prefix_task, })
        }
      }
      for slot in graph.supplied_slots {
        carrier_work(work)
        if slot.consumer == stage {
          if stage < graph.captured_prefix {
            // The checked keyed slot belongs to its later operation, never
            // to the Direct capture that completes the prefix.
            continue
          }
          supplied_slots.push({ ..slot, consumer: prefix_task, })
        }
      }
    }
    for step, consumer in stage_tasks[stage] {
      carrier_work(work)
      if step <= prefix_end {
        continue
      }
      let node = @lower.node_at(prepared, step).unwrap()
      for operation_input in 0..<@lower.node_input_count(node) {
        carrier_work(work)
        match @lower.node_input_target(node, operation_input) {
          Some(@pipeline.Step(producer_step)) =>
            data.push({
              producer: stage_tasks[stage][producer_step],
              target: @pipeline.Step(producer_step),
              consumer,
              input: operation_input,
              source_input: None,
              operation_input: Some((step, operation_input)),
            })
          Some(@pipeline.Input(source_input)) =>
            match original_data_edge(graph, stage, source_input, work) {
              Some(edge) => {
                guard mapped_stage_target(
                    stage_tasks,
                    edge.producer,
                    edge.target,
                  )
                  is Some(producer) else {
                  return Err(ForeignPort(stage, source_input))
                }
                data.push({
                  producer,
                  target: edge.target,
                  consumer,
                  input: operation_input,
                  source_input: Some(source_input),
                  operation_input: Some((step, operation_input)),
                })
              }
              None =>
                match original_supplied_slot(graph, stage, source_input, work) {
                  Some(slot) =>
                    supplied_slots.push({
                      consumer,
                      input: operation_input,
                      source_input: slot.source_input,
                      operation_input: Some((step, operation_input)),
                    })
                  None => return Err(MissingProducer(stage, source_input))
                }
            }
          None => return Err(ForeignPort(stage, operation_input))
        }
      }
    }
  }

  let control = []
  for edge in graph.control {
    carrier_work(work)
    let predecessor_tasks = stage_tasks[edge.predecessor]
    let consumer_tasks = stage_tasks[edge.consumer]
    control.push({
      predecessor: predecessor_tasks[predecessor_tasks.length() - 1],
      consumer: consumer_tasks[0],
      gate: edge.gate,
    })
  }
  for stage in 0..<stages {
    carrier_work(work)
    for requirement in graph.operations[stage] {
      carrier_work(work)
      let task = if expanded[stage] {
        stage_tasks[stage][requirement.site.step]
      } else {
        stage_tasks[stage][0]
      }
      operations[task].push(requirement)
    }
    for observation in graph.numeric[stage] {
      carrier_work(work)
      let task = if expanded[stage] {
        stage_tasks[stage][observation.step]
      } else {
        stage_tasks[stage][0]
      }
      numeric[task].push(observation)
    }
  }
  let results = []
  for result in graph.results {
    carrier_work(work)
    let target = @ports.port_target(
      @execution.managed_result_occurrence_port(result.occurrence),
    )
    guard mapped_stage_target(stage_tasks, result.task, target) is Some(task) else {
      return Err(ForeignPort(result.task, 0))
    }
    results.push({ task, occurrence: result.occurrence, })
  }
  Ok({
    program: graph.program,
    source_free_root: graph.source_free_root,
    captured_prefix: graph.captured_prefix,
    original_tasks: Array::makei(owners.length(), task => task),
    original_task_count: owners.length(),
    owners,
    stage_tasks,
    targets,
    input_counts,
    selected_steps,
    prefix_ends,
    data,
    supplied_slots,
    control,
    operations,
    numeric,
    results,
  })
}
