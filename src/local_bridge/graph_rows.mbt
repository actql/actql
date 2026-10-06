///|
/// A source descriptor under the existing Carrier and Relation owners.
/// It does not retain a second Graph or create a Graph-specific Relation.
priv enum GraphRowsRead {
  StoredGraph(@graph_storage.Storage)
  ViewedGraph(@lifecycle.ProducerView)
}

///|
priv struct GraphRowsSource {
  source : GraphRowsRead
  definition : @carrier.GraphDefinition
  selected_definition : String?
  selected_label : String?
  mut selection_label_index : Int
  mut selection_name_offset : Int
  edge : Bool
  limits : @execution.ValueLimits
  mut label_builder : @value.ArrayBuilder?
  mut label_recheck : @value.RecheckCursor?
  mut label_workspace : Int
  mut label_reserved : Int
  mut label_index : Int
  mut label_bytes : Int
  order_keys : Array[Array[String]]
  mut order : @sort.Sort?
  order_slots : Int
}

///|
fn graph_rows_order_key(source : GraphRowsSource, record : Int) -> String? {
  match source.source {
    StoredGraph(storage) =>
      if source.edge {
        @graph_storage.edge_identity_order_key(storage, record)
      } else {
        @graph_storage.node_identity_order_key(storage, record)
      }
    ViewedGraph(view) =>
      (if source.edge {
        @lifecycle.producer_view_edge_identity_order_key(view, record)
      } else {
        @lifecycle.producer_view_node_identity_order_key(view, record)
      }).to_option()
  }
}

///|
priv enum GraphRowFieldRead {
  PendingField
  AbsentField
  GraphField(@schema.FieldName, @value.Value)
}

///|
fn graph_rows_count(source : GraphRowsSource) -> Int? {
  match source.source {
    StoredGraph(storage) =>
      Some(
        if source.edge {
          @graph_storage.edge_count(storage)
        } else {
          @graph_storage.node_count(storage)
        },
      )
    ViewedGraph(view) =>
      if source.edge {
        @lifecycle.producer_view_edge_count(view)
      } else {
        @lifecycle.producer_view_node_count(view)
      }
  }
}

///|
fn graph_row_definition(
  source : GraphRowsSource,
  record : Int,
) -> @carrier.GraphNodeDefinition? {
  let index = match source.source {
    StoredGraph(storage) =>
      if source.edge {
        @graph_storage.edge_definition_index(storage, record)
      } else {
        @graph_storage.node_definition_index(storage, record)
      }
    ViewedGraph(view) =>
      (if source.edge {
        @lifecycle.producer_view_edge_definition(view, record)
      } else {
        @lifecycle.producer_view_node_definition(view, record)
      }).to_option()
  }
  index.bind(index => {
    if source.edge {
      @carrier.graph_edge_at(source.definition, index).map(
        @carrier.graph_edge_element,
      )
    } else {
      @carrier.graph_node_at(source.definition, index)
    }
  })
}

///|
priv enum GraphRowSelection {
  PendingSelection
  SelectedRow
  SkipRow
}

///|
/// Each call inspects one fragment of one admitted selector candidate.
fn graph_row_selected(
  source : GraphRowsSource,
  record : Int,
) -> GraphRowSelection? {
  guard source.order.bind(sort => @sort.index_at(sort, record)) is Some(record) else {
    return None
  }
  graph_row_definition(source, record).map(definition => {
    let (result, index, offset) = graph_definition_selected(
      definition,
      source.selected_definition,
      source.selected_label,
      source.selection_label_index,
      source.selection_name_offset,
    )
    source.selection_label_index = index
    source.selection_name_offset = offset
    result
  })
}

///|
fn graph_definition_selected(
  definition : @carrier.GraphNodeDefinition,
  selected_definition : String?,
  selected_label : String?,
  index : Int,
  offset : Int,
) -> (GraphRowSelection, Int, Int) {
  let (compared, next, _) = if selected_definition is Some(name) {
    @canonical.compare_utf16_fragment(
      @carrier.graph_element_definition_name(definition),
      name,
      offset,
      64,
    )
  } else if selected_label is Some(label) {
    let count = @carrier.graph_element_definition_label_count(definition)
    if index >= count {
      return (SkipRow, 0, 0)
    }
    let (candidate, _) = @carrier.graph_element_definition_label_at(
      definition, index,
    ).unwrap()
    @carrier.compare_property_name_fragment(candidate, label, offset, 64)
  } else {
    return (SelectedRow, 0, 0)
  }
  match compared {
    None => (PendingSelection, index, next)
    Some(0) => (SelectedRow, 0, 0)
    Some(_) =>
      if selected_definition is Some(_) ||
        index + 1 == @carrier.graph_element_definition_label_count(definition) {
        (SkipRow, 0, 0)
      } else {
        (PendingSelection, index + 1, 0)
      }
  }
}

///|
fn graph_rows_field_count(source : GraphRowsSource, record : Int) -> Int? {
  source.order
  .bind(sort => @sort.index_at(sort, record))
  .bind(record => graph_row_definition(source, record))
  .map(definition => {
    (if source.edge { 4 } else { 2 }) +
    @carrier.graph_element_definition_key_count(definition) +
    @carrier.field_count(
      @carrier.graph_element_definition_properties(definition),
    )
  })
}

///|
fn graph_row_identity(
  source : GraphRowsSource,
  record : Int,
  edge : Bool,
) -> @value.CheckedValue? {
  match source.source {
    StoredGraph(storage) =>
      if edge {
        @graph_storage.edge_identity(storage, record)
      } else {
        @graph_storage.node_identity(storage, record)
      }
    ViewedGraph(view) =>
      (if edge {
        @lifecycle.producer_view_edge_identity(view, record)
      } else {
        @lifecycle.producer_view_node_identity(view, record)
      }).to_option()
  }
}

///|
fn graph_rows_field(
  source : GraphRowsSource,
  record : Int,
  field : Int,
) -> Result[GraphRowFieldRead, EventsBridgeIssue] {
  guard source.order.bind(sort => @sort.index_at(sort, record)) is Some(record) else {
    return Err(InvalidRecord(record))
  }
  guard graph_row_definition(source, record) is Some(definition) else {
    return Err(InputUnavailable)
  }
  let roles = if source.edge {
    ["id", "src", "dst", "labels"]
  } else {
    ["id", "labels"]
  }
  let key_count = @carrier.graph_element_definition_key_count(definition)
  let (name, cell) = if field < roles.length() {
    guard roles.get(field) is Some(name) else {
      return Err(InvalidRecord(record))
    }
    let cell = if name == "id" {
      graph_row_identity(source, record, source.edge)
    } else if name == "src" || name == "dst" {
      let endpoints = match source.source {
        StoredGraph(storage) => @graph_storage.edge_endpoints(storage, record)
        ViewedGraph(view) =>
          @lifecycle.producer_view_edge_endpoints(view, record).to_option()
      }
      endpoints.bind(pair => {
        graph_row_identity(
          source,
          if name == "src" {
            pair.0
          } else {
            pair.1
          },
          false,
        )
      })
    } else {
      let count = @carrier.graph_element_definition_label_count(definition)
      if count >= source.limits.max_nodes {
        return Err(InvalidRecord(record))
      }
      // Reserve the complete provisional array before growing it. Borrowed
      // Text recheck frames use the existing depth/custody reservation; the
      // sealed array keeps its reservation until the row is committed. Its
      // private elements cannot overlap the row cursor's own reservation.
      if source.label_builder is None {
        if count > source.label_workspace {
          return Err(RelationOutput(@execution.CaptureLimit))
        }
        source.label_builder = @value.prepare_array_value(count)
        source.label_reserved = count
      }
      guard source.label_builder is Some(builder) else {
        return Err(InvalidRecord(record))
      }
      if source.label_index < count {
        if source.label_recheck is None {
          let (label, _) = @carrier.graph_element_definition_label_at(
            definition,
            source.label_index,
          ).unwrap()
          source.label_recheck = @value.start_recheck_runtime_text(
            label,
            @contract.primitive(@contract.StringType, nullable=false),
            { max_nodes: 1, max_depth: 0, max_text_bytes: source.label_bytes, },
          )
        }
        guard source.label_recheck is Some(recheck) else {
          return Err(InvalidRecord(record))
        }
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckFailed => return Err(InvalidRecord(record))
          @value.RecheckComplete(checked, _, bytes) => {
            guard @value.append_array_item(builder, checked.value) else {
              return Err(InvalidRecord(record))
            }
            source.label_bytes -= bytes
            source.label_index += 1
            source.label_recheck = None
          }
        }
        return Ok(PendingField)
      }
      guard @value.finish_array_value(builder) is Some(labels) else {
        return Err(InvalidRecord(record))
      }
      source.label_builder = None
      source.label_index = 0
      source.label_bytes = source.limits.max_text_bytes
      return Ok(GraphField(@schema.Unqualified(name), labels))
    }
    (name, cell)
  } else if field - roles.length() < key_count {
    let component = field - roles.length()
    guard @carrier.graph_element_definition_key_column_at(definition, component)
      is Some(name) else {
      return Ok(AbsentField)
    }
    let cell = match source.source {
      StoredGraph(storage) =>
        if source.edge {
          @graph_storage.edge_typed_key_at(storage, record, component)
        } else {
          @graph_storage.node_typed_key_at(storage, record, component)
        }
      ViewedGraph(view) =>
        (if source.edge {
          @lifecycle.producer_view_edge_key(view, record, component)
        } else {
          @lifecycle.producer_view_node_key(view, record, component)
        }).to_option()
    }
    (name, cell)
  } else {
    let index = field - roles.length() - key_count
    guard @carrier.field_at(
        @carrier.graph_element_definition_properties(definition),
        index,
      )
      is Some(property) else {
      return Err(InvalidRecord(record))
    }
    let cell = match source.source {
      StoredGraph(storage) =>
        if source.edge {
          @graph_storage.edge_property(storage, record, index)
        } else {
          @graph_storage.node_property(storage, record, index)
        }
      ViewedGraph(view) =>
        (if source.edge {
          @lifecycle.producer_view_edge_property(view, record, index)
        } else {
          @lifecycle.producer_view_node_property(view, record, index)
        }).to_option()
    }
    (@schema.reference_name(property.name), cell)
  }
  guard cell is Some(cell) else { return Err(InvalidRecord(record)) }
  Ok(GraphField(@schema.Unqualified(name), cell.value))
}

///|
pub fn start_graph_view_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    (
      @lower.carrier_projection_operation(projection) == @projection.NodeRows ||
      @lower.carrier_projection_operation(projection) == @projection.EdgeRows
    ) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_graph_definition(input) is Ok(definition) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  let source : GraphRowsSource = {
    source: ViewedGraph(input),
    definition,
    selected_definition: @lower.carrier_projection_definition(projection),
    selected_label: @lower.carrier_projection_label(projection),
    selection_label_index: 0,
    selection_name_offset: 0,
    edge: @lower.carrier_projection_operation(projection) ==
    @projection.EdgeRows,
    limits,
    label_builder: None,
    label_recheck: None,
    label_workspace: 0,
    label_reserved: 0,
    label_index: 0,
    label_bytes: limits.max_text_bytes,
    order_keys: [],
    order: None,
    order_slots: max_entries,
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    GraphRows(source),
    fn() { graph_rows_count(source) is Some(_) },
    None,
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    None,
    control_work_limit,
    trusted_inputs=Some([
      @execution.trusted_output_carrier_input(
        @lifecycle.producer_view_read_reference(input),
      ),
    ]),
  )
}

///|
pub fn start_graph_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    (
      @lower.carrier_projection_operation(projection) == @projection.NodeRows ||
      @lower.carrier_projection_operation(projection) == @projection.EdgeRows
    ) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(storage) &&
    @graph_storage.carrier(storage) is @carrier.GraphValue(graph) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  let source : GraphRowsSource = {
    source: StoredGraph(storage),
    definition: @carrier.graph_definition(graph),
    selected_definition: @lower.carrier_projection_definition(projection),
    selected_label: @lower.carrier_projection_label(projection),
    selection_label_index: 0,
    selection_name_offset: 0,
    edge: @lower.carrier_projection_operation(projection) ==
    @projection.EdgeRows,
    limits,
    label_builder: None,
    label_recheck: None,
    label_workspace: 0,
    label_reserved: 0,
    label_index: 0,
    label_bytes: limits.max_text_bytes,
    order_keys: [],
    order: None,
    order_slots: max_entries,
  }
  let retained = if @lifecycle.producer_read_reference_matches_input(
      @graph.producer_read_carrier_reference(input),
      owner,
      0,
    ) {
    let bindings = [
      @execution.trusted_output_carrier_input(
        @graph.producer_read_carrier_reference(input),
      ),
    ]
    for relation in inputs {
      bindings.push(@execution.trusted_output_relation_input(relation))
    }
    Some(bindings)
  } else {
    None
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    GraphRows(source),
    fn() { @graph.producer_read_available(input) },
    None,
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    Some(inputs),
    control_work_limit,
    trusted_inputs=retained,
  )
}
