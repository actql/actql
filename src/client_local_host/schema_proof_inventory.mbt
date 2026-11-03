///|
/// One work-bounded inventory per original prepared owner. Shared task views
/// reuse checked schema facts, never storage: repeated ports remain counted.
// `_observed_*` fields retain exact bound observations for white-box tests;
// production consumes the admitted totals, not these diagnostic projections.
priv struct ClientLocalSchemaProofInventory {
  original_count : Int
  _observed_owner_count : Int
  _observed_work_used : Int
  max_node_width : Int64
  max_name_width : Int64
  fields : Int
  names : Int
  ports : Int
  bindings : Int
  // Complete-node bound by default. The explicit original Effect-source
  // mode selects member Result endpoints ONLY for operation multiplicity;
  // that scoped value must not replace Compute/input demand.
  closed_rows : Int?
}

///|
// Constructor-local observations of simultaneously retained work arrays. The
// optional observer records extents even when a schema proof returns None;
// visits/comparisons are not storage and never become array-slot allowances.
priv struct ClientLocalSchemaProofWorkspace {
  mut owners : Int
  mut rows : Int
  mut input_rows : Int
  mut row_bounds : Int
}

///|
fn client_local_schema_proof_work() -> Int {
  // This proof phase has its own counter, like the existing graph preparation
  // phase. It is not represented as aggregate compiler/Run work consumption.
  @publication_host.client_standard_program_preparation_limits().max_graph_work
}

///|
fn client_local_schema_proof_inventory(
  sequences : Array[@execution.GeneratedSequence],
  max_work? : Int = client_local_schema_proof_work(),
  graph? : @strategy.CheckedDAG? = None,
  graph_offset? : Int = 0,
  scalar_only? : Bool = true,
  leaf_only? : Bool = false,
  workspace? : ClientLocalSchemaProofWorkspace? = None,
  effect_sources? : @strategy.CheckedEffectComputationDAG? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
) -> ClientLocalSchemaProofInventory? {
  if sequences.is_empty() || max_work < 1 || sequences.length() > max_work {
    return None
  }
  if graph_offset < 0 {
    return None
  }
  match graph {
    Some(original) => {
      let count = @strategy.graph_task_count(original)
      if graph_offset > count || sequences.length() != count - graph_offset {
        return None
      }
    }
    None => if graph_offset != 0 { return None }
  }
  if effect_sources is Some(effect) &&
    (
      graph_offset != 0 ||
      !(graph is Some(original) &&
      physical_equal(
        original,
        @strategy.checked_effect_computation_graph(effect),
      ))
    ) {
    return None
  }
  if content is Some(selected) &&
    !(graph is Some(original) &&
    physical_equal(
      original,
      installed_managed_owner_graph(Effect(selected.prepared)),
    )) {
    return None
  }
  let mut remaining = max_work
  // Snapshot the original compilation depth once for the optional checked
  // value proof. This does not change the Run value-depth policy.
  let value_depth = if leaf_only {
    client_local_value_node_proof_depth()
  } else {
    0
  }
  let seen : Array[@lower.BoundPrepared] = []
  let mut nodes = 1L
  let mut names_total = 0L
  let mut fields = 0
  let mut names = 0
  let mut ports = 0
  let mut bindings = 0
  let mut closed_rows : Int? = Some(0)
  let mut selected_sources = 0
  for index, sequence in sequences {
    if remaining < 1 {
      return None
    }
    remaining -= 1
    let owner = @execution.generated_sequence_owner(sequence)
    if graph is Some(original) &&
      !(@strategy.graph_task_owner(original, index + graph_offset)
      is Some(expected) &&
      physical_equal(owner, expected)) {
      return None
    }
    let mut found = false
    for previous in seen {
      if remaining < 1 {
        return None
      }
      remaining -= 1
      if physical_equal(previous, owner) {
        found = true
        break
      }
    }
    if found {
      continue
    }
    seen.push(owner)
    if workspace is Some(actual) {
      actual.owners = Int::max(actual.owners, seen.length())
    }
    let prepared = @lower.bound_preparation(owner)
    let content_nodes = match content {
      None => None
      Some(selected) =>
        match installed_content_schema_node_bound(selected, owner, remaining) {
          None => return None
          Some((contract, nodes, used)) => {
            remaining -= used
            Some((contract, nodes))
          }
        }
    }
    let inputs = @lower.preparation_input_count(prepared)
    let rows : Array[Int?] = []
    let mut row_bounds = 0
    if inputs != 0 && effect_sources is None {
      closed_rows = None
    }
    ports = Int::max(ports, inputs)
    bindings = Int::max(bindings, inputs)
    let mut input_nodes = 0L
    let mut output_nodes = 0L
    let mut input_names = 0L
    let mut output_names = 0L
    for input in 0..<inputs {
      guard @lower.preparation_input_schema(prepared, input) is Some(schema) else {
        return None
      }
      let width = @schema.field_count(schema)
      if remaining < 1 || width > remaining - 1 {
        return None
      }
      remaining -= width + 1
      if scalar_only && client_local_scalar_schema_width(schema) is None {
        return None
      }
      let node_width = if leaf_only {
        guard client_local_json_schema_nodes(schema, remaining, value_depth)
          is Some((nodes, used)) else {
          return None
        }
        remaining -= used
        nodes
      } else {
        width.to_int64() + 1L
      }
      let name_bytes = @schema.field_reference_name_bytes(schema)
      if name_bytes < 0 {
        return None
      }
      fields = Int::max(fields, width)
      names = Int::max(names, name_bytes)
      input_nodes += node_width
      output_nodes += node_width
      input_names += name_bytes.to_int64()
      output_names += name_bytes.to_int64()
    }
    for node_index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared, node_index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) else {
        return None
      }
      let row_ports = @lower.node_input_count(node)
      if row_ports > remaining {
        return None
      }
      remaining -= row_ports
      let input_rows : Array[Int] = []
      let mut known = true
      for port in 0..<row_ports {
        match @lower.node_input_target(node, port) {
          Some(@pipeline.Step(index)) =>
            match rows.get(index) {
              Some(Some(count)) => input_rows.push(count)
              _ => known = false
            }
          _ => known = false
        }
        if workspace is Some(actual) {
          actual.input_rows = Int::max(actual.input_rows, input_rows.length())
        }
      }
      let bound = if known {
        @lower.node_row_count_bound(node, input_rows)
      } else {
        @lower.node_input_independent_row_count_bound(node)
      }
      rows.push(bound)
      if bound is Some(_) {
        row_bounds += 1
      }
      if workspace is Some(actual) {
        actual.rows = Int::max(actual.rows, rows.length())
        actual.row_bounds = Int::max(actual.row_bounds, row_bounds)
      }
      if effect_sources is None {
        closed_rows = match (closed_rows, bound) {
          (Some(previous), Some(count)) => Some(Int::max(previous, count))
          _ => None
        }
      }
      let width = @schema.field_count(schema)
      if remaining < 1 || width > remaining - 1 {
        return None
      }
      remaining -= width + 1
      if scalar_only && client_local_scalar_schema_width(schema) is None {
        return None
      }
      let node_width = if leaf_only {
        guard client_local_json_schema_nodes(
            schema,
            remaining,
            value_depth,
            content=if content is Some(original) &&
              node_index >= original.component.step {
              content_nodes
            } else {
              None
            },
          )
          is Some((nodes, used)) else {
          return None
        }
        remaining -= used
        nodes
      } else {
        width.to_int64() + 1L
      }
      let name_bytes = @schema.field_reference_name_bytes(schema)
      if name_bytes < 0 {
        return None
      }
      fields = Int::max(fields, width)
      names = Int::max(names, name_bytes)
      output_nodes += node_width
      output_names += name_bytes.to_int64()
      let count = @lower.node_input_count(node)
      ports = Int::max(ports, count)
      bindings = Int::max(bindings, count)
      for port in 0..<count {
        guard @lower.node_input_target(node, port) is Some(target) &&
          @lower.preparation_schema_at(prepared, target) is Some(input_schema) else {
          return None
        }
        let width = @schema.field_count(input_schema)
        if remaining < 1 || width > remaining - 1 {
          return None
        }
        remaining -= width + 1
        if scalar_only && client_local_scalar_schema_width(input_schema) is None {
          return None
        }
        let node_width = if leaf_only {
          guard client_local_json_schema_nodes(
              input_schema,
              remaining,
              value_depth,
              content=if content is Some(original) &&
                target is @pipeline.Step(input_step) &&
                input_step >= original.component.step {
                content_nodes
              } else {
                None
              },
            )
            is Some((nodes, used)) else {
            return None
          }
          remaining -= used
          nodes
        } else {
          width.to_int64() + 1L
        }
        let name_bytes = @schema.field_reference_name_bytes(input_schema)
        if name_bytes < 0 {
          return None
        }
        input_nodes += node_width
        input_names += name_bytes.to_int64()
      }
    }
    nodes = Int64::max(nodes, Int64::max(input_nodes, output_nodes))
    names_total = Int64::max(names_total, Int64::max(input_names, output_names))
    if effect_sources is Some(effect) && graph is Some(original) {
      // This SAME owner was traversed once above. Resolve only the original
      // checked member Result endpoints, without another lowering/schema walk.
      // Different members still contribute their occurrences to the Plan fold.
      for index in 0..<@strategy.checked_effect_source_count(effect) {
        if remaining < 1 {
          return None
        }
        remaining -= 1
        match @strategy.checked_effect_source_at(effect, index) {
          None => closed_rows = None
          Some(source) => {
            let task = @strategy.checked_effect_source_task(source)
            guard @strategy.graph_task_owner(original, task) is Some(expected) else {
              return None
            }
            if physical_equal(owner, expected) {
              selected_sources += 1
              let bound = match @strategy.graph_task_target(original, task) {
                Some(@pipeline.Step(step)) =>
                  rows.get(step).bind(value => value)
                _ => None
              }
              closed_rows = match (closed_rows, bound) {
                (Some(previous), Some(count)) => Some(Int::max(previous, count))
                _ => None
              }
            }
          }
        }
      }
    }
  }
  if effect_sources is Some(effect) &&
    selected_sources != @strategy.checked_effect_source_count(effect) {
    closed_rows = None
  }
  Some({
    original_count: sequences.length(),
    _observed_owner_count: seen.length(),
    _observed_work_used: max_work - remaining,
    max_node_width: nodes,
    max_name_width: names_total,
    fields,
    names,
    ports,
    bindings,
    closed_rows,
  })
}

///|
fn client_local_inventory_nodes(
  inventory : ClientLocalSchemaProofInventory,
  max_rows : Int,
) -> Int? {
  client_local_scalar_product(inventory.max_node_width, max_rows, 3)
}
