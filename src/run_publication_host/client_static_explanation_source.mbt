///|
/// The exact original compiler and map already used for the static Plan view.
/// The Request owner must admit the read, Plan construction and retained map
/// before borrowing it. This value supplies no disclosure or execution grant.
struct ClientStaticEffectExplanationOriginal {
  prepared : PreparedClientEffectComputation
  compiled : ClientEffectCompilation
  map : @canonical.CanonicalValue
  declarations : ClientEffectStaticDeclarationSet
}

///|
pub(all) enum ClientStaticExplanationSourceIssue {
  Plan(ClientEffectfulStaticPlanIssue)
  ForeignOriginal
  WorkLimit
  Encoding(@encode.EncodeFailure)
} derive(Debug)

///|
/// Borrow the logical map emitted by the existing static Plan issuer. The
/// companion and Plan therefore share the same compiler and map issuance.
pub fn capture_client_static_effect_explanation_original(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientStaticEffectExplanationOriginal, String),
  ClientStaticExplanationSourceIssue,
] {
  let retained = Ref(None)
  let wire = match
    issue_client_effectful_static_plan_view(
      prepared,
      compiled,
      max_bytes,
      max_nodes,
      max_depth,
      64,
      10000,
      retained_explanation=Some(retained),
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Plan(issue))
  }
  guard retained.val is Some((value, declarations)) &&
    @canonical.object_field(value, "logical_map") is Some(map) else {
    return Err(ForeignOriginal)
  }
  Ok(({ prepared, compiled, map, declarations, }, wire))
}

///|
/// Measure both Facts forms on the retained map under the Request's existing
/// measuring-writer reservation. The geometry grants no disclosure.
pub fn measure_client_static_effect_explanation_facts(
  original : ClientStaticEffectExplanationOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  if !client_static_effect_explanation_matches(original, prepared, compiled) {
    return Err(ForeignOriginal)
  }
  measure_client_explanation_facts_from_map(
    compiled.compiled.owner,
    compiled.compiled.compiled_plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Seal the existing Facts family over the same computation and map as the
/// static Effect Plan and Context. The Request must fund the writer and
/// canonical codec before this call, and authorize the entire disclosure.
pub fn seal_client_static_effect_explanation_facts(
  original : ClientStaticEffectExplanationOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientExplanationFactsIssue] {
  if !client_static_effect_explanation_matches(original, prepared, compiled) {
    return Err(ForeignOriginal)
  }
  seal_client_explanation_facts_from_map(
    compiled.compiled.owner,
    compiled.compiled.compiled_plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn client_static_effect_explanation_matches(
  original : ClientStaticEffectExplanationOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
) -> Bool {
  physical_equal(original.prepared, prepared) &&
  physical_equal(original.compiled, compiled) &&
  physical_equal(compiled.owner, prepared)
}

///|
priv suberror ClientStaticExplanationAbort {
  StaticExplanationWorkLimited
  StaticExplanationForeignSubject
}

///|
fn spend_static_explanation_work(
  remaining : Ref[Int],
  count? : Int = 1,
) -> Unit raise {
  if count < 0 || count > remaining.val {
    raise StaticExplanationWorkLimited
  }
  remaining.val -= count
}

///|
// A source is one checked stage input. Many logical input ports may consume
// that same locator. Retain every occurrence link without copying the source.
fn write_static_explanation_consumers(
  writer : @encode.Writer,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  stage : Int,
  input : Int,
  remaining : Ref[Int],
) -> Bool raise {
  let mut found = false
  @encode.begin_array(writer)
  for step_index in 0..<@canonical.array_count(steps) {
    spend_static_explanation_work(remaining)
    let step = @canonical.array_at(steps, step_index).unwrap()
    let step_id = explanation_original_text(step, "step_id")
    guard @canonical.object_field(step, "ports")
      is Some(@canonical.Array(ports)) else {
      raise @encode.InvalidStructure
    }
    for port_index in 0..<@canonical.array_count(ports) {
      spend_static_explanation_work(remaining)
      let port = @canonical.array_at(ports, port_index).unwrap()
      guard explanation_original_text(port, "role") == "input" &&
        @canonical.object_field(port, "source") is Some(source) &&
        @canonical.object_field(source, "kind")
        is Some(@canonical.String("stage_input")) &&
        explanation_original_ordinal(source, "stage_ordinal") == stage &&
        explanation_original_ordinal(source, "input_port_ordinal") == input else {
        continue
      }
      @encode.begin_object(writer)
      explanation_text(
        writer,
        "port_id",
        explanation_original_text(port, "port_id"),
      )
      explanation_text(writer, "step_id", step_id)
      @encode.end_object(writer)
      found = true
    }
  }
  @encode.end_array(writer)
  found
}

///|
/// Measure the same structural Context without producing an output string.
/// Use the measured geometry for the Request's separate output/codec quote.
/// The Request must already cover this measuring writer and traversal.
pub fn measure_client_static_effect_explanation_context(
  original : ClientStaticEffectExplanationOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[
  @encode.EncodingConstructionGeometry,
  ClientStaticExplanationSourceIssue,
] {
  if !client_static_effect_explanation_matches(original, prepared, compiled) {
    return Err(ForeignOriginal)
  }
  if max_work <= 0 {
    return Err(WorkLimit)
  }
  try {
    let writer = @encode.construction_measuring_writer(
      max_bytes, max_nodes, max_depth,
    )
    match
      write_client_static_effect_explanation_context(
        original, prepared, compiled, writer, max_work,
      ) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(@encode.finish_construction_measurement(writer))
    }
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Write the structural Context from the same opaque static Plan original.
/// The original Request read and egress admission must cover every item,
/// full writer and simultaneous Plan, map and declaration custody.
/// The caller discards the writer on any error and rechecks current and
/// egress before handing out any bytes.
pub fn write_client_static_effect_explanation_context(
  original : ClientStaticEffectExplanationOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  writer : @encode.Writer,
  max_work : Int,
) -> Result[Unit, ClientStaticExplanationSourceIssue] {
  if !client_static_effect_explanation_matches(original, prepared, compiled) {
    return Err(ForeignOriginal)
  }
  if max_work <= 0 {
    return Err(WorkLimit)
  }
  guard @canonical.object_field(original.map, "steps")
    is Some(@canonical.Array(steps)) else {
    return Err(ForeignOriginal)
  }
  let checked = @strategy.graph_program(compiled.compiled.owner.graph)
  let identity = @checked.source_identity(checked)
  let remaining = Ref(max_work)
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "binding")
    write_static_explanation_binding(writer, original)
    explanation_text(writer, "disclosure", "structural")
    @encode.key(writer, "items")
    @encode.begin_array(writer)
    for i in 0..<@checked.source_execution_count(checked) {
      spend_static_explanation_work(remaining)
      let check = @checked.source_execution_at(checked, i).unwrap()
      if @checked.source_execution_kind(check) is @checked.CarrierResponse {
        let subject = @checked.source_execution_subject(check)
        if !physical_equal(subject.owner, identity) {
          return Err(ForeignOriginal)
        }
        write_static_explanation_source(writer, steps, subject, remaining)
      }
    }
    write_static_explanation_models(writer, steps, original, remaining)
    write_static_explanation_results(writer, steps, compiled, remaining)
    write_static_explanation_effect(writer, original, remaining)
    @encode.end_array(writer)
    explanation_text(writer, "version", "actql-explanation-context/0.1")
    @encode.end_object(writer)
    Ok(())
  } catch {
    StaticExplanationWorkLimited => Err(WorkLimit)
    @encode.InvalidStructure => Err(Encoding(@encode.InvalidStructure))
    @encode.InvalidUnicode => Err(Encoding(@encode.InvalidUnicode))
    @encode.InvalidNumber => Err(Encoding(@encode.InvalidNumber))
    @encode.OutputLimit => Err(Encoding(@encode.OutputLimit))
    @encode.ClosedWriter => Err(Encoding(@encode.ClosedWriter))
    _ => Err(ForeignOriginal)
  }
}

///|
fn write_static_explanation_source(
  writer : @encode.Writer,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  subject : @checked.SourceExecutionSubject,
  remaining : Ref[Int],
) -> Unit raise {
  let source = subject.source
  let (mode, input) = match subject.request {
    @acquisition.Direct(mode, _) => ("direct", @acquisition.mode_input(mode))
    @acquisition.Keyed(mode, _) =>
      ("keyed", @acquisition.keyed_mode_input(mode))
  }
  let declaration = @acquisition.declaration(source)
  if !physical_equal(input, source) || declaration.stage_index != subject.stage {
    raise StaticExplanationForeignSubject
  }
  let contract = @acquisition.selected_contract(source)
  let catalog = @environment.reference_catalog(
    @environment.source_request_reference(contract),
  )
  let (_, _, catalog_cid) = @environment.catalog_identity(catalog)
  @encode.begin_object(writer)
  @encode.key(writer, "consuming_ports")
  let linked = write_static_explanation_consumers(
    writer,
    steps,
    subject.stage,
    subject.input,
    remaining,
  )
  explanation_text(writer, "kind", "source")
  explanation_text(
    writer,
    "link_state",
    if linked {
      "linked"
    } else {
      "not_projected"
    },
  )
  explanation_text(writer, "request_kind", mode)
  @encode.key(writer, "source_view")
  @encode.begin_object(writer)
  explanation_text(writer, "catalog_cid", catalog_cid)
  explanation_text(writer, "connector", declaration.connector)
  explanation_text(writer, "contract_cid", @acquisition.selected_cid(source))
  explanation_text(writer, "resource", declaration.resource)
  explanation_text(
    writer,
    "selection",
    match @acquisition.selection(source) {
      Explicit => "explicit"
      SoleView => "sole_view"
    },
  )
  explanation_text(writer, "view", @acquisition.selected_name(source))
  @encode.end_object(writer)
  @encode.key(writer, "stage_input")
  @encode.begin_object(writer)
  @encode.key(writer, "input_port_ordinal")
  @encode.number_value(writer, subject.input.to_double())
  explanation_text(writer, "kind", "stage_input")
  @encode.key(writer, "stage_ordinal")
  @encode.number_value(writer, subject.stage.to_double())
  @encode.end_object(writer)
  @encode.end_object(writer)
}
