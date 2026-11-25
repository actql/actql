///|
/// The Map returned by the original effect-free Plan issuer.
struct ClientStaticPureExplanationOriginal {
  prepared : PreparedClientProgram
  plan : @publication.PublicationContract
  infers : Array[ClientInferPlanGraph]?
  map : @canonical.CanonicalValue
}

///|
/// Issue the original Plan once and retain its Map without constructing a
/// Run. The Request owner funds this operation and owns disclosure.
pub fn capture_client_static_pure_explanation_original(
  prepared : PreparedClientProgram,
  compiled : ClientRunCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  debug_entry? : Bool = false,
) -> Result[
  (ClientStaticPureExplanationOriginal, String),
  ClientStaticExplanationSourceIssue,
] {
  let plan = match client_pure_compilation_original_plan(prepared, compiled) {
    Ok(value) => value
    Err(_) => return Err(ForeignOriginal)
  }
  let retained = Ref(None)
  let wire = match
    issue_client_static_plan_view(
      prepared,
      plan,
      max_bytes,
      max_nodes,
      max_depth,
      false,
      retained_original=Some(retained),
      bounded_capture=true,
      debug_entry~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ComputationPlan(issue))
  }
  guard retained.val is Some(sealed_map) &&
    @publication.interactive_logical_map_original(sealed_map) is Some(map) else {
    return Err(ForeignOriginal)
  }
  let infers = match compiled {
    Tasks(value) => Some(value.infers)
    _ => None
  }
  Ok(({ prepared, plan, infers, map, }, wire))
}

///|
pub fn measure_client_static_pure_explanation_facts(
  original : ClientStaticPureExplanationOriginal,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  measure_client_explanation_facts_from_map(
    original.prepared,
    original.plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn seal_client_static_pure_explanation_facts(
  original : ClientStaticPureExplanationOriginal,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientExplanationFactsIssue] {
  seal_client_explanation_facts_from_map(
    original.prepared,
    original.plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn write_client_static_pure_explanation_context(
  original : ClientStaticPureExplanationOriginal,
  writer : @encode.Writer,
  max_work : Int,
) -> Result[Unit, ClientStaticExplanationSourceIssue] {
  write_client_static_explanation_context(
    original.map,
    original.prepared,
    original.plan,
    original.infers,
    None,
    writer,
    max_work,
  )
}
