///|
priv enum UnionFoldPhase {
  ScanUnionElements
  CompareUnionPrevious
  CompareUnionSelected
  CompareUnionEndpoints
  ResolveUnionDefinition
  CheckUnionEndpoints
  ReadUnionKeys
  ReadUnionProperties
  MergeUnionProperty
  CheckSubtractionEndpointClosure
  StartUnionAppend
  AppendUnionRecord
  FinishUnionFold
  UnionFoldFinished
} derive(Eq)

///|
pub(all) enum UnionIssue {
  InvalidUnionFold
  UnionInputUnavailable
  UnionEndpointConflict
  UnionFoldWorkLimit
  UnionFoldWorkspaceLimit
  UnionFoldProperty(UnionPropertyIssue)
  UnionFoldStorage(@storage.Issue)
  UnionOutput(@graph.Issue)
  UnionExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
/// One private fold on the existing Graph Store builder. The enclosing managed
/// execution owns the ordered input occurrences, common budget and retention
/// port; this cursor cannot publish a Graph or claim either input's custody.
priv struct UnionFoldPreparation {
  checked : @graph_type.CheckedUnion
  subtraction : Bool
  fold : Int
  left : GraphReadSource
  right : GraphReadSource
  builder : @storage.Builder
  profile : @carrier.PropertyGraphDefinition
  value_limits : @value.Limits
  mut remaining : Int
  mut phase : UnionFoldPhase
  mut edge : Bool
  mut scan_side : Int
  mut scan_index : Int
  mut previous : String?
  mut selected : String?
  mut candidate : String?
  mut comparison : @value.BoundedKeyComparison?
  mut left_index : Int
  mut right_index : Int
  mut definition_index : Int
  mut definition : @carrier.PropertyNodeDefinition?
  mut column : Int
  mut endpoint : Int
  mut identity : @value.CheckedValue?
  mut source : @value.CheckedValue?
  mut target : @value.CheckedValue?
  mut keys : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
  mut property : UnionProperty?
  mut append : @storage.PropertySnapshotAppend?
}

///|
priv enum UnionFoldPoll {
  UnionFoldContinue(Int)
  UnionFoldComplete(@storage.Storage, Int)
  UnionFoldFailed(UnionIssue, Int)
}

///|
fn prepare_union_fold(
  checked : @graph_type.CheckedUnion,
  fold : Int,
  left : GraphReadSource,
  right : GraphReadSource,
  builder : @storage.Builder,
  limits : @storage.Limits,
  remaining : Int,
  subtraction? : Bool = false,
) -> Result[UnionFoldPreparation, UnionIssue] {
  if subtraction && (fold != 0 || @graph_type.union_input_count(checked) != 2) {
    return Err(InvalidUnionFold)
  }
  guard @graph_type.union_fold_output(checked, fold)
    is Some(@carrier.GraphValue(graph)) &&
    @storage.builder_accepts_output(builder, graph, limits) &&
    remaining >= 0 &&
    graph_read_available(left) &&
    graph_read_available(right) else {
    return Err(InvalidUnionFold)
  }
  Ok({
    checked,
    subtraction,
    fold,
    left,
    right,
    builder,
    profile: @carrier.graph_property_definition(graph),
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    remaining,
    phase: ScanUnionElements,
    edge: false,
    scan_side: 0,
    scan_index: 0,
    previous: None,
    selected: None,
    candidate: None,
    comparison: None,
    left_index: -1,
    right_index: -1,
    definition_index: 0,
    definition: None,
    column: 0,
    endpoint: 0,
    identity: None,
    source: None,
    target: None,
    keys: [],
    properties: [],
    property: None,
    append: None,
  })
}

///|
fn union_fold_source(value : UnionFoldPreparation) -> GraphReadSource {
  if value.left_index >= 0 {
    value.left
  } else {
    value.right
  }
}

///|
fn union_fold_index(value : UnionFoldPreparation) -> Int {
  if value.left_index >= 0 {
    value.left_index
  } else {
    value.right_index
  }
}

///|
fn union_fold_definition(
  value : UnionFoldPreparation,
  index : Int,
) -> @carrier.PropertyNodeDefinition? {
  if value.edge {
    @carrier.property_graph_edge_at(value.profile, index).map(
      @carrier.property_edge_element,
    )
  } else {
    @carrier.property_graph_node_at(value.profile, index)
  }
}

///|
fn union_fold_reset_scan(value : UnionFoldPreparation) -> Unit {
  value.selected = None
  value.candidate = None
  value.comparison = None
  value.left_index = -1
  value.right_index = -1
  value.scan_side = 0
  value.scan_index = 0
  value.definition_index = 0
  value.definition = None
  value.identity = None
  value.source = None
  value.target = None
  value.column = 0
  value.endpoint = 0
  value.phase = ScanUnionElements
}

///|
fn union_fold_finish_candidate(value : UnionFoldPreparation) -> Unit {
  value.candidate = None
  value.comparison = None
  value.scan_index += 1
  value.phase = ScanUnionElements
}

///|
fn union_fold_select_candidate(
  value : UnionFoldPreparation,
  order : Int,
) -> Unit {
  if order < 0 {
    value.selected = value.candidate
    value.left_index = if value.scan_side == 0 { value.scan_index } else { -1 }
    value.right_index = if value.scan_side == 1 { value.scan_index } else { -1 }
  } else if order == 0 {
    if value.scan_side == 0 {
      value.left_index = value.scan_index
    } else {
      value.right_index = value.scan_index
    }
  }
  union_fold_finish_candidate(value)
}

///|
fn union_fold_start_selection(value : UnionFoldPreparation) -> Unit {
  if value.selected is Some(selected) {
    value.comparison = Some(
      @value.start_bounded_token_comparison(value.candidate.unwrap(), selected),
    )
    value.phase = CompareUnionSelected
  } else {
    union_fold_select_candidate(value, -1)
  }
}

///|
fn union_fold_next_endpoint(value : UnionFoldPreparation) -> Unit {
  value.comparison = None
  if value.endpoint == 0 {
    value.endpoint = 1
    value.phase = CheckUnionEndpoints
  } else {
    value.phase = ReadUnionKeys
  }
}

///|
fn union_fold_failed(
  value : UnionFoldPreparation,
  issue : UnionIssue,
  work : Int,
) -> UnionFoldPoll {
  // Do not cancel the builder or borrow sources here. The enclosing cleanup
  // owner retains reservations until it has acknowledged cleanup completion.
  value.remaining -= work
  value.phase = UnionFoldFinished
  UnionFoldFailed(issue, work)
}

///|
fn advance_union_fold(
  value : UnionFoldPreparation,
  quantum : Int,
) -> UnionFoldPoll {
  if value.phase == UnionFoldFinished || quantum < 1 {
    return UnionFoldFailed(InvalidUnionFold, 0)
  }
  let mut work = 0
  while work < quantum {
    if !graph_read_available(value.left) || !graph_read_available(value.right) {
      return union_fold_failed(value, UnionInputUnavailable, work)
    }
    if work >= value.remaining {
      return union_fold_failed(value, UnionFoldWorkLimit, work)
    }
    let budget = Int::min(quantum - work, value.remaining - work)
    match value.phase {
      ScanUnionElements => {
        work += 1
        let source = if value.scan_side == 0 { value.left } else { value.right }
        let count = if value.edge {
          graph_read_edge_count(source)
        } else {
          graph_read_node_count(source)
        }
        guard count is Some(count) else {
          return union_fold_failed(value, UnionInputUnavailable, work)
        }
        if value.scan_index < count {
          let key = if value.edge {
            graph_read_edge_identity_order_key(source, value.scan_index)
          } else {
            graph_read_node_identity_order_key(source, value.scan_index)
          }
          guard key is Some(key) else {
            return union_fold_failed(value, UnionInputUnavailable, work)
          }
          value.candidate = Some(key)
          if value.previous is Some(previous) {
            value.comparison = Some(
              @value.start_bounded_token_comparison(previous, key),
            )
            value.phase = CompareUnionPrevious
          } else {
            union_fold_start_selection(value)
          }
        } else if value.scan_side == 0 {
          value.scan_side = 1
          value.scan_index = 0
        } else if value.selected is Some(_) {
          if value.subtraction && value.left_index < 0 {
            value.previous = value.selected
            union_fold_reset_scan(value)
            continue
          }
          value.identity = if value.edge {
            graph_read_edge_identity(
              union_fold_source(value),
              union_fold_index(value),
            )
          } else {
            graph_read_node_identity(
              union_fold_source(value),
              union_fold_index(value),
            )
          }
          value.phase = ResolveUnionDefinition
        } else if !value.edge {
          value.edge = true
          value.previous = None
          union_fold_reset_scan(value)
        } else {
          value.phase = FinishUnionFold
        }
      }
      CompareUnionPrevious | CompareUnionSelected | CompareUnionEndpoints => {
        guard value.comparison is Some(comparison) else {
          return union_fold_failed(value, InvalidUnionFold, work)
        }
        match @value.advance_bounded_key_comparison(comparison, budget) {
          Err(_) => return union_fold_failed(value, InvalidUnionFold, work)
          Ok(@value.KeyComparisonContinue(work=used)) => work += used
          Ok(@value.KeyComparisonComplete(order~, work=used)) => {
            work += used
            value.comparison = None
            if value.phase == CompareUnionPrevious {
              if order < 0 {
                union_fold_start_selection(value)
              } else {
                union_fold_finish_candidate(value)
              }
            } else if value.phase == CompareUnionSelected {
              union_fold_select_candidate(value, order)
            } else if order != 0 {
              return union_fold_failed(value, UnionEndpointConflict, work)
            } else {
              union_fold_next_endpoint(value)
            }
          }
        }
      }
      ResolveUnionDefinition => {
        work += 1
        let input_definition = if value.edge {
          graph_read_edge_definition(
            union_fold_source(value),
            union_fold_index(value),
          )
        } else {
          graph_read_node_definition(
            union_fold_source(value),
            union_fold_index(value),
          )
        }
        guard input_definition is Some(input_definition) &&
          union_fold_definition(value, value.definition_index)
          is Some(definition) else {
          return union_fold_failed(value, UnionInputUnavailable, work)
        }
        let expected = if value.left_index >= 0 {
          Some(value.definition_index)
        } else {
          @graph_type.union_right_definition(
            value.checked,
            value.fold,
            value.definition_index,
            edge=value.edge,
          )
        }
        if expected != Some(input_definition) {
          value.definition_index += 1
          continue
        }
        if value.left_index >= 0 && value.right_index >= 0 {
          let actual = if value.edge {
            graph_read_edge_definition(value.right, value.right_index)
          } else {
            graph_read_node_definition(value.right, value.right_index)
          }
          if actual !=
            @graph_type.union_right_definition(
              value.checked,
              value.fold,
              value.definition_index,
              edge=value.edge,
            ) {
            return union_fold_failed(value, InvalidUnionFold, work)
          }
        }
        value.definition = Some(definition)
        value.phase = if value.edge {
          CheckUnionEndpoints
        } else {
          ReadUnionKeys
        }
      }
      CheckUnionEndpoints => {
        work += 1
        guard graph_read_edge_endpoints(
            union_fold_source(value),
            union_fold_index(value),
          )
          is Some((src, dst)) else {
          return union_fold_failed(value, UnionInputUnavailable, work)
        }
        let node = if value.endpoint == 0 { src } else { dst }
        let identity = graph_read_node_identity(union_fold_source(value), node)
        guard identity is Some(identity) &&
          graph_read_node_identity_order_key(union_fold_source(value), node)
          is Some(token) else {
          return union_fold_failed(value, UnionInputUnavailable, work)
        }
        if value.endpoint == 0 {
          value.source = Some(identity)
        } else {
          value.target = Some(identity)
        }
        if value.left_index >= 0 && value.right_index >= 0 {
          guard graph_read_edge_endpoints(value.right, value.right_index)
            is Some((other_src, other_dst)) &&
            graph_read_node_identity_order_key(
              value.right,
              if value.endpoint == 0 {
                other_src
              } else {
                other_dst
              },
            )
            is Some(other) else {
            return union_fold_failed(value, UnionInputUnavailable, work)
          }
          // Admission owns these complete canonical typed identity tokens;
          // shared bounded raw order supplies exact token equality here.
          value.comparison = Some(
            @value.start_bounded_token_comparison(token, other),
          )
          value.phase = CompareUnionEndpoints
        } else {
          union_fold_next_endpoint(value)
        }
      }
      ReadUnionKeys => {
        work += 1
        let definition = value.definition.unwrap()
        if value.column < @carrier.property_definition_key_count(definition) {
          let key = if value.edge {
            graph_read_edge_key_component(
              union_fold_source(value),
              union_fold_index(value),
              value.column,
            )
          } else {
            graph_read_node_key_component(
              union_fold_source(value),
              union_fold_index(value),
              value.column,
            )
          }
          guard key is Some(key) else {
            return union_fold_failed(value, UnionInputUnavailable, work)
          }
          value.keys.push(key)
          value.column += 1
        } else {
          value.column = 0
          value.phase = ReadUnionProperties
        }
      }
      ReadUnionProperties => {
        work += 1
        let fields = @carrier.property_definition_properties(
          value.definition.unwrap(),
        )
        if value.column < @carrier.field_count(fields) {
          guard @graph_type.union_field_at(
              value.checked,
              value.fold,
              value.definition_index,
              value.column,
              edge=value.edge,
            )
            is Some((left_column, right_column, strategy)) &&
            @carrier.field_at(fields, value.column).bind(field => field.contract)
            is Some(contract) else {
            return union_fold_failed(value, InvalidUnionFold, work)
          }
          let left = if value.left_index >= 0 {
            if value.edge {
              graph_read_edge_property(
                value.left,
                value.left_index,
                left_column,
              )
            } else {
              graph_read_node_property(
                value.left,
                value.left_index,
                left_column,
              )
            }
          } else if value.edge {
            graph_read_edge_property(
              value.right,
              value.right_index,
              right_column,
            )
          } else {
            graph_read_node_property(
              value.right,
              value.right_index,
              right_column,
            )
          }
          let right = if value.left_index >= 0 && value.right_index >= 0 {
            if value.edge {
              graph_read_edge_property(
                value.right,
                value.right_index,
                right_column,
              )
            } else {
              graph_read_node_property(
                value.right,
                value.right_index,
                right_column,
              )
            }
          } else {
            None
          }
          guard left is Some(left) &&
            (
              !(value.left_index >= 0 && value.right_index >= 0) ||
              right is Some(_)
            ) else {
            return union_fold_failed(value, UnionInputUnavailable, work)
          }
          value.property = start_union_property(
            left,
            right,
            contract,
            strategy,
            value.value_limits,
            value.value_limits.max_nodes,
          )
          if value.property is None {
            return union_fold_failed(value, InvalidUnionFold, work)
          }
          value.phase = MergeUnionProperty
        } else {
          let remove_shared = value.subtraction &&
            value.right_index >= 0 &&
            @graph_type.union_strategy_count(value.checked, edge=value.edge) ==
            0
          if value.subtraction && value.edge && !remove_shared {
            value.endpoint = 0
            value.phase = CheckSubtractionEndpointClosure
          } else {
            value.phase = StartUnionAppend
          }
        }
      }
      MergeUnionProperty => {
        guard value.property is Some(property) else {
          return union_fold_failed(value, InvalidUnionFold, work)
        }
        match advance_union_property(property, budget) {
          PropertyContinue(used) => work += used
          PropertyFailed(issue, used) =>
            return union_fold_failed(
              value,
              UnionFoldProperty(issue),
              work + used,
            )
          PropertyComplete(result, used) => {
            work += used
            cleanup_union_property(property)
            value.property = None
            value.properties.push(result)
            value.column += 1
            value.phase = ReadUnionProperties
          }
        }
      }
      CheckSubtractionEndpointClosure => {
        work += 1
        guard graph_read_edge_endpoints(value.left, value.left_index)
          is Some((src, dst)) &&
          graph_read_node_identity_order_key(
            value.left,
            if value.endpoint == 0 {
              src
            } else {
              dst
            },
          )
          is Some(token) &&
          @storage.builder_contains_node_identity_order_key(
            value.builder,
            token,
          )
          is Some(retained) else {
          return union_fold_failed(value, UnionInputUnavailable, work)
        }
        if !retained {
          value.keys.clear()
          value.properties.clear()
          value.previous = value.selected
          union_fold_reset_scan(value)
        } else if value.endpoint == 0 {
          value.endpoint = 1
        } else {
          value.phase = StartUnionAppend
        }
      }
      StartUnionAppend => {
        work += 1
        // Even a removed shared record reaches this point only after full
        // aligned payload comparison, including exact edge endpoints. A
        // nonempty map retains the transformed entity, even if unchanged.
        if value.subtraction &&
          value.right_index >= 0 &&
          @graph_type.union_strategy_count(value.checked, edge=value.edge) == 0 {
          value.keys.clear()
          value.properties.clear()
          value.previous = value.selected
          union_fold_reset_scan(value)
          continue
        }
        guard value.identity is Some(identity) else {
          return union_fold_failed(value, InvalidUnionFold, work)
        }
        value.append = match
          @storage.start_property_record_append(
            value.builder,
            value.definition_index,
            identity,
            value.keys,
            value.properties,
            edge=value.edge,
            source=value.source,
            target=value.target,
          ) {
          Ok(append) => Some(append)
          Err(issue) =>
            return union_fold_failed(value, UnionFoldStorage(issue), work)
        }
        value.keys = []
        value.properties = []
        value.phase = AppendUnionRecord
      }
      AppendUnionRecord => {
        guard value.append is Some(append) else {
          return union_fold_failed(value, InvalidUnionFold, work)
        }
        match @storage.advance_property_snapshot_append(append, budget) {
          @storage.PropertySnapshotAppendContinue(work=used) => work += used
          @storage.PropertySnapshotAppendFailed(issue, work=used) =>
            return union_fold_failed(
              value,
              UnionFoldStorage(issue),
              work + used,
            )
          @storage.PropertySnapshotAppendComplete(work=used) => {
            work += used
            @storage.cleanup_property_snapshot_append(append)
            value.append = None
            value.previous = value.selected
            union_fold_reset_scan(value)
          }
        }
      }
      FinishUnionFold => {
        work += 1
        value.phase = UnionFoldFinished
        value.remaining -= work
        return match @storage.finish(value.builder) {
          Ok(storage) => UnionFoldComplete(storage, work)
          Err(issue) => UnionFoldFailed(UnionFoldStorage(issue), work)
        }
      }
      UnionFoldFinished => return UnionFoldFailed(InvalidUnionFold, work)
    }
  }
  value.remaining -= work
  UnionFoldContinue(work)
}

///|
fn cleanup_union_fold(value : UnionFoldPreparation) -> Unit {
  if value.property is Some(property) {
    cleanup_union_property(property)
    value.property = None
  }
  if value.append is Some(append) {
    @storage.cleanup_property_snapshot_append(append)
    value.append = None
  }
  @storage.cancel(value.builder) |> ignore
  value.keys.clear()
  value.keys.shrink_to_fit()
  value.properties.clear()
  value.properties.shrink_to_fit()
  value.identity = None
  value.source = None
  value.target = None
  value.definition = None
  value.previous = None
  value.selected = None
  value.candidate = None
  value.comparison = None
  value.phase = UnionFoldFinished
}
