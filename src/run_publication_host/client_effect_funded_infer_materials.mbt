///|
// SAME immutable Model execution original: canonical bytes/nodes were retained
// at its original admission. Reading depth borrows its existing cursor metrics.
fn client_effect_funded_execution_wire(
  execution : @environment.ModelExecutionContract,
  fund : (String, Int, Int, Int) -> Bool,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let original = @environment.model_execution_source(execution)
  let usage = @environment.model_execution_usage(execution)
  client_effect_funded_material_input(
    "model_execution",
    (usage.0, usage.1, Int::max(1, @decode.admission_usage(original).depth)),
    writer => @syntax.emit_admitted_source_value(original, writer),
    fund,
  )
}

///|
// This already-issued Effect compiler owns the complete Model inventory. Fund
// its two metadata projection arrays and final writer BEFORE enumeration; no
// graph compiler is rerun to compare the bytes of an immutable original.
fn client_effect_funded_infer_inventory(
  compilation : ClientEffectCompilation,
  fund : (String, Int, Int, Int) -> Bool,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let components = compilation.compiled.infers
  let count = components.length().to_int64()
  // Per entry: seven fixed keys, CID/kind and three Int decimal spellings,
  // quotes, commas and object punctuation fit 304 UTF16 units. Each retained
  // execution/profile unit needs at most six UTF8 bytes when JSON-quoted.
  let mut units = 304L * count
  for graph in components {
    guard @execution.checked_preparation_add_product(
        units,
        @environment.model_execution_usage(graph.execution).0.to_int64(),
        1L,
      )
      is Some(next) else {
      return Err(Input(MaterialsConstructionRefused("model_inventory")))
    }
    units = next
    if graph.keyed is Some(keyed) {
      guard @execution.checked_preparation_add_product(
          units,
          @publication.publication_contract_json(keyed.original.profile)
          .length()
          .to_int64(),
          1L,
        )
        is Some(next) else {
        return Err(Input(MaterialsConstructionRefused("model_inventory")))
      }
      units = next
    }
  }
  guard count > 1L &&
    @execution.checked_preparation_add_product(2L, units, 6L) is Some(bytes) &&
    @execution.checked_preparation_add_product(1L, count, 8L) is Some(nodes) &&
    bytes < 2147483647L &&
    nodes < 2147483647L else {
    return Err(Input(MaterialsConstructionRefused("model_inventory")))
  }
  if !fund("model_inventory", bytes.to_int(), nodes.to_int(), 2) {
    return Err(Input(MaterialsConstructionRefused("model_inventory")))
  }
  guard client_effect_compilation_infer_originals(compilation)
    is Some(originals) else {
    return Err(Compilation(ForeignInferOwner))
  }
  try {
    let writer = @encode.writer(bytes.to_int(), nodes.to_int(), 2)
    @encode.begin_array(writer)
    for index in 0..<originals.length() {
      let (graph, occurrence) = originals[index]
      // The private issued-graph pin is stronger than reconstructing a new
      // graph from mutable copied fields and comparing its wire afterward.
      if !physical_equal(graph, components[index]) ||
        client_infer_graph_original_parts(
          graph,
          compilation.compiled.owner,
          graph.graph_wire_bytes,
          graph.graph_wire_nodes,
          graph.graph_wire_depth,
        )
        is None {
        return Err(Compilation(ForeignInferOwner))
      }
      let body = match
        client_effect_funded_execution_wire(graph.execution, fund) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let (task, stage, step) = client_infer_occurrence_coordinates(occurrence)
      @encode.begin_object(writer)
      @encode.key(writer, "execution_contract_cid")
      @encode.string_value(
        writer,
        @environment.model_execution_cid(graph.execution),
      )
      @encode.key(writer, "execution_contract_json")
      @encode.string_value(writer, body)
      if graph.keyed is Some(component) {
        let kind = @publication.publication_contract_name(
          component.original.profile,
        )
        guard kind == "native_file_content_read" ||
          kind == "declared_file_content_read" else {
          return Err(Input(MaterialsEvidence("infer_execution_contracts")))
        }
        @encode.key(writer, "native_read_profile")
        @encode.string_value(
          writer,
          @publication.publication_contract_json(component.original.profile),
        )
        @encode.key(writer, "native_read_profile_kind")
        @encode.string_value(writer, kind)
      }
      for (name, value) in [("stage", stage), ("step", step), ("task", task)] {
        @encode.key(writer, name)
        @encode.number_value(writer, value.to_double())
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Input(MaterialsEncoding("model_inventory", issue)))
  }
}
