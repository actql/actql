///|
/// Exact primitive calls have a cumulative ceiling independent of control
/// ticks. The fixed coefficient ceiling also bounds each atomic BigInt call.
/// This private cursor does not establish the enclosing realization's peak
/// reservation for inputs, accumulators, output and arithmetic scratch.
priv struct MeanArithmeticBudget {
  max_bits : Int
  mut remaining : Int
}

///|
fn take_mean_arithmetic(value : MeanArithmeticBudget) -> Bool {
  if value.remaining < 1 {
    false
  } else {
    value.remaining -= 1
    true
  }
}

///|
priv enum MeanFoldPhase {
  AdmitMeanSamples
  ResetMeanPositions
  ScanMeanElements
  CompareMeanPrevious
  CompareMeanSelected
  FindMeanOccurrences
  CompareMeanOccurrence
  AddMeanSupport
  CheckMeanSupport
  ResolveMeanDefinition
  CheckMeanRecord
  CompareMeanEndpoint
  CheckMeanClosure
  CompareMeanClosure
  ReadMeanKeys
  StartMeanProperty
  SupplyMeanProperty
  ExecuteMeanProperty
  StartMeanAppend
  AppendMeanRecord
  FinishMeanFold
  MeanFoldTerminal
} derive(Eq)

///|
pub(all) enum MeanFoldIssue {
  InvalidMeanFold
  MeanInputUnavailable
  MeanFoldWorkLimit
  MeanExactWorkLimit
  MeanEndpointConflict
  MeanFoldProperty(MeanPropertyIssue)
  MeanFoldArithmetic(@exact.Issue)
  MeanFoldStorage(@storage.Issue)
} derive(Eq, Debug)

///|
priv enum MeanFoldPoll {
  MeanFoldContinue(Int)
  MeanFoldComplete(@storage.Storage, Int)
  MeanFoldFailed(MeanFoldIssue, Int)
}

///|
/// Private ordered reduction into the existing Store builder. A separate
/// bounded session owns stop, output completion and input borrow custody.
priv struct MeanFold {
  checked : @graph_type.CheckedMean
  options : @graph_type.CheckedMeanOptions
  inputs : Array[GraphReadSource]
  builder : @storage.Builder
  profile : @carrier.GraphDefinition
  limits : @value.Limits
  arithmetic : MeanArithmeticBudget
  total : @exact.WeightSum
  mut present : @exact.WeightSum?
  mut remaining : Int
  mut phase : MeanFoldPhase
  mut edge : Bool
  mut sample : Int
  mut index : Int
  positions : Array[Int]
  mut previous : String?
  mut selected : String?
  mut candidate : String?
  mut selected_sample : Int
  mut selected_index : Int
  mut comparison : @value.BoundedKeyComparison?
  mut definition_index : Int
  mut definition : @carrier.GraphNodeDefinition?
  mut identity : @value.CheckedValue?
  mut source : @value.CheckedValue?
  mut target : @value.CheckedValue?
  mut source_token : String?
  mut target_token : String?
  retained_nodes : Array[String]
  mut endpoint : Int
  mut column : Int
  mut keys : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
  mut property : MeanProperty?
  mut append : @storage.GraphSnapshotAppend?
}

///|
fn prepare_mean_fold(
  checked : @graph_type.CheckedMean,
  inputs : Array[GraphReadSource],
  builder : @storage.Builder,
  limits : @storage.Limits,
  remaining : Int,
  arithmetic : MeanArithmeticBudget,
) -> Result[MeanFold, MeanFoldIssue] {
  let options = @graph_type.checked_mean_options(checked)
  guard @graph_type.mean_output(checked) is @carrier.GraphValue(graph) &&
    inputs.length() == @graph_type.mean_sample_count(options) &&
    inputs.length() > 0 &&
    remaining >= 0 &&
    arithmetic.remaining >= 0 &&
    arithmetic.max_bits >= 1 &&
    arithmetic.max_bits <= 8192 &&
    @storage.builder_accepts_output(builder, graph, limits) else {
    return Err(InvalidMeanFold)
  }
  let total = @exact.prepare_weight_sum(arithmetic.max_bits).unwrap()
  Ok({
    checked,
    options,
    inputs,
    builder,
    arithmetic,
    total,
    profile: @carrier.graph_definition(graph),
    limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    present: None,
    remaining,
    phase: AdmitMeanSamples,
    edge: false,
    sample: 0,
    index: 0,
    positions: [],
    previous: None,
    selected: None,
    candidate: None,
    selected_sample: -1,
    selected_index: -1,
    comparison: None,
    definition_index: 0,
    definition: None,
    identity: None,
    source: None,
    target: None,
    source_token: None,
    target_token: None,
    retained_nodes: [],
    endpoint: 0,
    column: 0,
    keys: [],
    properties: [],
    property: None,
    append: None,
  })
}

///|
fn mean_fold_count(value : MeanFold, sample : Int) -> Int? {
  let input = value.inputs[sample]
  if !graph_read_available(input) {
    return None
  }
  if value.edge {
    graph_read_edge_count(input)
  } else {
    graph_read_node_count(input)
  }
}

///|
fn mean_fold_token(value : MeanFold, sample : Int, index : Int) -> String? {
  if value.edge {
    graph_read_edge_identity_order_key(value.inputs[sample], index)
  } else {
    graph_read_node_identity_order_key(value.inputs[sample], index)
  }
}

///|
fn mean_fold_definition(
  value : MeanFold,
  index : Int,
) -> @carrier.GraphNodeDefinition? {
  if value.edge {
    @carrier.graph_edge_at(value.profile, index).map(
      @carrier.graph_edge_element,
    )
  } else {
    @carrier.graph_node_at(value.profile, index)
  }
}

///|
fn mean_fold_next_identity(value : MeanFold) -> Unit {
  if value.present is Some(sum) {
    @exact.cancel_weight_sum(sum) |> ignore
  }
  value.present = None
  value.previous = value.selected
  value.selected = None
  value.candidate = None
  value.comparison = None
  value.identity = None
  value.source = None
  value.target = None
  value.source_token = None
  value.target_token = None
  value.definition = None
  value.keys.clear()
  value.properties.clear()
  value.sample = 0
  value.index = 0
  value.column = 0
  value.endpoint = 0
  value.definition_index = 0
  value.selected_sample = -1
  value.selected_index = -1
  value.phase = ResetMeanPositions
}

///|
fn mean_fold_failed(
  value : MeanFold,
  issue : MeanFoldIssue,
  used : Int,
) -> MeanFoldPoll {
  value.remaining -= used
  // Failure is not cleanup acknowledgement. The enclosing owner still has
  // the builder, arithmetic roots, private output and original input borrows.
  value.phase = MeanFoldTerminal
  MeanFoldFailed(issue, used)
}

///|
fn mean_fold_choose(value : MeanFold) -> Unit {
  if value.selected is Some(selected) {
    value.comparison = Some(
      @value.start_bounded_token_comparison(value.candidate.unwrap(), selected),
    )
    value.phase = CompareMeanSelected
  } else {
    value.selected = value.candidate
    value.selected_sample = value.sample
    value.selected_index = value.index
    value.index += 1
    value.phase = ScanMeanElements
  }
}

///|
fn mean_fold_endpoint_complete(value : MeanFold) -> Unit {
  value.comparison = None
  if value.endpoint == 0 {
    value.endpoint = 1
  } else {
    value.endpoint = 0
    value.sample += 1
  }
  value.phase = CheckMeanRecord
}

///|
fn advance_mean_fold(value : MeanFold, quantum : Int) -> MeanFoldPoll {
  if quantum < 1 || value.phase == MeanFoldTerminal {
    return MeanFoldFailed(InvalidMeanFold, 0)
  }
  let mut used = 0
  while used < quantum {
    if used >= value.remaining {
      return mean_fold_failed(value, MeanFoldWorkLimit, used)
    }
    let budget = Int::min(quantum - used, value.remaining - used)
    match value.phase {
      AdmitMeanSamples => {
        used += 1
        if value.sample < value.inputs.length() {
          guard mean_fold_count(value, value.sample) is Some(_) &&
            @graph_type.mean_weight_at(value.options, value.sample)
            is Some(weight) else {
            return mean_fold_failed(value, MeanInputUnavailable, used)
          }
          if !take_mean_arithmetic(value.arithmetic) {
            return mean_fold_failed(value, MeanExactWorkLimit, used)
          }
          match @exact.add_weight(value.total, weight) {
            Ok(_) => ()
            Err(issue) =>
              return mean_fold_failed(value, MeanFoldArithmetic(issue), used)
          }
          value.positions.push(-1)
          value.sample += 1
        } else {
          value.sample = 0
          value.phase = ScanMeanElements
        }
      }
      ResetMeanPositions => {
        used += 1
        if value.sample < value.positions.length() {
          value.positions[value.sample] = -1
          value.sample += 1
        } else {
          value.sample = 0
          value.phase = ScanMeanElements
        }
      }
      ScanMeanElements | FindMeanOccurrences => {
        used += 1
        if value.sample == value.inputs.length() {
          if value.phase == FindMeanOccurrences {
            value.sample = 0
            value.present = Some(
              @exact.prepare_weight_sum(value.arithmetic.max_bits).unwrap(),
            )
            value.phase = AddMeanSupport
          } else if value.selected is Some(_) {
            value.sample = 0
            value.index = 0
            value.phase = FindMeanOccurrences
          } else if !value.edge {
            value.edge = true
            value.previous = None
            value.sample = 0
            value.index = 0
            value.phase = ResetMeanPositions
          } else {
            value.phase = FinishMeanFold
          }
          continue
        }
        guard mean_fold_count(value, value.sample) is Some(count) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        if @graph_type.mean_weight_at(value.options, value.sample) == Some(0.0) ||
          value.index == count {
          value.sample += 1
          value.index = 0
          continue
        }
        guard mean_fold_token(value, value.sample, value.index) is Some(token) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        value.candidate = Some(token)
        if value.phase == FindMeanOccurrences {
          value.comparison = Some(
            @value.start_bounded_token_comparison(
              token,
              value.selected.unwrap(),
            ),
          )
          value.phase = CompareMeanOccurrence
        } else if value.previous is Some(previous) {
          value.comparison = Some(
            @value.start_bounded_token_comparison(previous, token),
          )
          value.phase = CompareMeanPrevious
        } else {
          mean_fold_choose(value)
        }
      }
      CompareMeanPrevious
      | CompareMeanSelected
      | CompareMeanOccurrence
      | CompareMeanEndpoint
      | CompareMeanClosure =>
        match
          @value.advance_bounded_key_comparison(
            value.comparison.unwrap(),
            budget,
          ) {
          Err(_) => return mean_fold_failed(value, InvalidMeanFold, used)
          Ok(@value.KeyComparisonContinue(work~)) => used += work
          Ok(@value.KeyComparisonComplete(order~, work~)) => {
            used += work
            value.comparison = None
            match value.phase {
              CompareMeanPrevious =>
                if order < 0 {
                  mean_fold_choose(value)
                } else {
                  value.index += 1
                  value.phase = ScanMeanElements
                }
              CompareMeanSelected => {
                if order < 0 {
                  value.selected = value.candidate
                  value.selected_sample = value.sample
                  value.selected_index = value.index
                }
                value.index += 1
                value.phase = ScanMeanElements
              }
              CompareMeanOccurrence => {
                if order == 0 {
                  value.positions[value.sample] = value.index
                }
                value.index += 1
                value.phase = FindMeanOccurrences
              }
              CompareMeanEndpoint => {
                if order != 0 {
                  return mean_fold_failed(value, MeanEndpointConflict, used)
                }
                mean_fold_endpoint_complete(value)
              }
              CompareMeanClosure =>
                if order == 0 {
                  if value.endpoint == 0 {
                    value.endpoint = 1
                    value.index = 0
                    value.phase = CheckMeanClosure
                  } else {
                    value.column = 0
                    value.phase = ReadMeanKeys
                  }
                } else if order > 0 {
                  mean_fold_next_identity(value)
                } else {
                  value.index += 1
                  value.phase = CheckMeanClosure
                }
              _ => return mean_fold_failed(value, InvalidMeanFold, used)
            }
          }
        }
      AddMeanSupport => {
        used += 1
        if value.sample == value.inputs.length() {
          value.phase = CheckMeanSupport
        } else {
          if value.positions[value.sample] >= 0 {
            if !take_mean_arithmetic(value.arithmetic) {
              return mean_fold_failed(value, MeanExactWorkLimit, used)
            }
            match
              @exact.add_weight(
                value.present.unwrap(),
                @graph_type.mean_weight_at(value.options, value.sample).unwrap(),
              ) {
              Ok(_) => ()
              Err(issue) =>
                return mean_fold_failed(value, MeanFoldArithmetic(issue), used)
            }
          }
          value.sample += 1
        }
      }
      CheckMeanSupport => {
        used += 1
        if !take_mean_arithmetic(value.arithmetic) {
          return mean_fold_failed(value, MeanExactWorkLimit, used)
        }
        let entity = if value.edge {
          @graph_type.Edges
        } else {
          @graph_type.Nodes
        }
        match
          @exact.accumulated_support_at_least(
            value.present.unwrap(),
            value.total,
            @graph_type.mean_support(value.options, entity),
          ) {
          Err(issue) =>
            return mean_fold_failed(value, MeanFoldArithmetic(issue), used)
          Ok(false) => mean_fold_next_identity(value)
          Ok(true) => {
            value.phase = ResolveMeanDefinition
            value.definition_index = 0
          }
        }
      }
      ResolveMeanDefinition => {
        used += 1
        let input = value.inputs[value.selected_sample]
        let actual = if value.edge {
          graph_read_edge_definition(input, value.selected_index)
        } else {
          graph_read_node_definition(input, value.selected_index)
        }
        guard actual is Some(actual) &&
          mean_fold_definition(value, value.definition_index)
          is Some(definition) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        if @graph_type.mean_definition_at(
            value.checked,
            value.selected_sample,
            value.definition_index,
            edge=value.edge,
          ) !=
          Some(actual) {
          value.definition_index += 1
          continue
        }
        value.definition = Some(definition)
        value.identity = if value.edge {
          graph_read_edge_identity(input, value.selected_index)
        } else {
          graph_read_node_identity(input, value.selected_index)
        }
        guard value.identity is Some(_) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        value.sample = 0
        value.endpoint = 0
        value.phase = CheckMeanRecord
      }
      CheckMeanRecord => {
        used += 1
        if value.sample == value.inputs.length() {
          value.endpoint = 0
          value.index = 0
          value.column = 0
          value.phase = if value.edge { CheckMeanClosure } else { ReadMeanKeys }
          continue
        }
        let index = value.positions[value.sample]
        if index < 0 {
          value.sample += 1
          continue
        }
        let input = value.inputs[value.sample]
        let actual = if value.edge {
          graph_read_edge_definition(input, index)
        } else {
          graph_read_node_definition(input, index)
        }
        if actual !=
          @graph_type.mean_definition_at(
            value.checked,
            value.sample,
            value.definition_index,
            edge=value.edge,
          ) {
          return mean_fold_failed(value, InvalidMeanFold, used)
        }
        if !value.edge {
          value.sample += 1
          continue
        }
        guard graph_read_edge_endpoints(input, index) is Some((source, target)) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        let node = if value.endpoint == 0 { source } else { target }
        guard graph_read_node_identity(input, node) is Some(identity) &&
          graph_read_node_identity_order_key(input, node) is Some(token) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        let existing = if value.endpoint == 0 {
          value.source_token
        } else {
          value.target_token
        }
        if existing is Some(existing) {
          value.comparison = Some(
            @value.start_bounded_token_comparison(token, existing),
          )
          value.phase = CompareMeanEndpoint
        } else {
          if value.endpoint == 0 {
            value.source = Some(identity)
            value.source_token = Some(token)
          } else {
            value.target = Some(identity)
            value.target_token = Some(token)
          }
          mean_fold_endpoint_complete(value)
        }
      }
      CheckMeanClosure => {
        used += 1
        if value.index == value.retained_nodes.length() {
          mean_fold_next_identity(value)
          continue
        }
        let endpoint = if value.endpoint == 0 {
          value.source_token
        } else {
          value.target_token
        }
        guard endpoint is Some(endpoint) else {
          return mean_fold_failed(value, InvalidMeanFold, used)
        }
        value.comparison = Some(
          @value.start_bounded_token_comparison(
            value.retained_nodes[value.index],
            endpoint,
          ),
        )
        value.phase = CompareMeanClosure
      }
      ReadMeanKeys => {
        used += 1
        if value.column ==
          @carrier.graph_element_definition_key_count(value.definition.unwrap()) {
          value.column = 0
          value.phase = StartMeanProperty
          continue
        }
        let input = value.inputs[value.selected_sample]
        let key = if value.edge {
          graph_read_edge_key_component(
            input,
            value.selected_index,
            value.column,
          )
        } else {
          graph_read_node_key_component(
            input,
            value.selected_index,
            value.column,
          )
        }
        guard key is Some(key) else {
          return mean_fold_failed(value, MeanInputUnavailable, used)
        }
        value.keys.push(key)
        value.column += 1
      }
      StartMeanProperty => {
        used += 1
        let fields = @carrier.graph_element_definition_properties(
          value.definition.unwrap(),
        )
        if value.column == @carrier.field_count(fields) {
          value.phase = StartMeanAppend
          continue
        }
        guard @carrier.field_at(fields, value.column) is Some(field) &&
          field.contract is Some(_) else {
          return mean_fold_failed(value, InvalidMeanFold, used)
        }
        value.property = None
        // Policy lookup itself is stepped, even for a wide closed domain.
        value.index = 0
        value.phase = SupplyMeanProperty
      }
      SupplyMeanProperty => {
        used += 1
        if value.property is None {
          let fields = @carrier.graph_element_definition_properties(
            value.definition.unwrap(),
          )
          let field = @carrier.field_at(fields, value.column).unwrap()
          let entity = if value.edge {
            @graph_type.Edges
          } else {
            @graph_type.Nodes
          }
          guard @graph_type.mean_property_at(value.options, entity, value.index)
            is Some(policy) else {
            return mean_fold_failed(value, InvalidMeanFold, used)
          }
          value.index += 1
          // Names are already admitted normalized schema metadata, not values.
          if @carrier.graph_name_identity(policy.name) !=
            @carrier.graph_name_identity(@schema.reference_name(field.name)) {
            continue
          }
          value.property = start_mean_property(
            policy.strategy,
            field.contract.unwrap(),
            value.limits,
            value.inputs.length(),
            value.remaining - used,
            value.arithmetic.max_bits,
            arithmetic_budget=Some(value.arithmetic),
          )
          guard value.property is Some(_) else {
            return mean_fold_failed(value, InvalidMeanFold, used)
          }
          value.sample = 0
        } else {
          let input_index = value.positions[value.sample]
          let property = if input_index < 0 {
            None
          } else {
            guard @graph_type.mean_property_input_at(
                value.checked,
                value.sample,
                value.definition_index,
                value.column,
                edge=value.edge,
              )
              is Some(column) else {
              return mean_fold_failed(value, InvalidMeanFold, used)
            }
            let input = value.inputs[value.sample]
            let property = if value.edge {
              graph_read_edge_property(input, input_index, column)
            } else {
              graph_read_node_property(input, input_index, column)
            }
            guard property is Some(_) else {
              return mean_fold_failed(value, MeanInputUnavailable, used)
            }
            property
          }
          match
            supply_mean_property_sample(
              value.property.unwrap(),
              @graph_type.mean_weight_at(value.options, value.sample).unwrap(),
              property,
            ) {
            Ok(_) => value.phase = ExecuteMeanProperty
            Err(issue) =>
              return mean_fold_failed(value, MeanFoldProperty(issue), used)
          }
          value.sample += 1
        }
      }
      ExecuteMeanProperty =>
        match advance_mean_property(value.property.unwrap(), budget) {
          MeanPropertyContinue(work) => used += work
          MeanPropertyNeedsSample(work) => {
            used += work
            value.phase = SupplyMeanProperty
          }
          MeanPropertyFailed(issue, work) =>
            return mean_fold_failed(value, MeanFoldProperty(issue), used + work)
          MeanPropertyComplete(result, work) => {
            used += work
            value.property = None
            value.properties.push(result)
            value.column += 1
            value.phase = StartMeanProperty
          }
        }
      StartMeanAppend => {
        used += 1
        guard value.identity is Some(identity) else {
          return mean_fold_failed(value, InvalidMeanFold, used)
        }
        match
          @storage.start_record_append(
            value.builder,
            value.definition_index,
            identity,
            value.keys,
            value.properties,
            edge=value.edge,
            source=value.source,
            target=value.target,
          ) {
          Ok(append) => value.append = Some(append)
          Err(issue) =>
            return mean_fold_failed(value, MeanFoldStorage(issue), used)
        }
        // The append cursor owns these arrays until its bounded admission
        // finishes. Dropping our references must not clear its input.
        value.keys = []
        value.properties = []
        value.phase = AppendMeanRecord
      }
      AppendMeanRecord =>
        match
          @storage.advance_graph_snapshot_append(value.append.unwrap(), budget) {
          @storage.GraphSnapshotAppendContinue(work~) => used += work
          @storage.GraphSnapshotAppendFailed(issue, work~) =>
            return mean_fold_failed(value, MeanFoldStorage(issue), used + work)
          @storage.GraphSnapshotAppendComplete(work~) => {
            used += work
            @storage.cleanup_graph_snapshot_append(value.append.unwrap())
            value.append = None
            if !value.edge {
              value.retained_nodes.push(value.selected.unwrap())
            }
            mean_fold_next_identity(value)
          }
        }
      FinishMeanFold => {
        used += 1
        value.remaining -= used
        value.phase = MeanFoldTerminal
        return match @storage.finish(value.builder) {
          Ok(storage) => MeanFoldComplete(storage, used)
          Err(issue) => MeanFoldFailed(MeanFoldStorage(issue), used)
        }
      }
      MeanFoldTerminal => return MeanFoldFailed(InvalidMeanFold, used)
    }
  }
  value.remaining -= used
  MeanFoldContinue(used)
}

///|
fn cleanup_mean_fold(value : MeanFold) -> Unit {
  if value.property is Some(property) {
    cleanup_mean_property(property)
  }
  if value.append is Some(append) {
    @storage.cleanup_graph_snapshot_append(append)
  }
  if value.present is Some(sum) {
    @exact.cancel_weight_sum(sum) |> ignore
  }
  @exact.cancel_weight_sum(value.total) |> ignore
  @storage.cancel(value.builder) |> ignore
  value.property = None
  value.append = None
  value.present = None
  value.positions.clear()
  value.retained_nodes.clear()
  value.keys.clear()
  value.properties.clear()
  value.identity = None
  value.source = None
  value.target = None
  value.source_token = None
  value.target_token = None
  value.definition = None
  value.previous = None
  value.selected = None
  value.candidate = None
  value.comparison = None
  value.phase = MeanFoldTerminal
}
