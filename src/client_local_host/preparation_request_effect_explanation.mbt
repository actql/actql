///|
// Available only for the original Definition used to construct the facets.
// The Request's working reservation holds every new wire through first
// admission and the same owner's retirement on failure or unknown outcome.
priv struct ClientRequestEffectRunExplanationData[I] {
  owner : ClientRequestPreparation[I]
  input : I
  prepared : @publication_host.PreparedClientEffectComputation
  definition : @publication.PublicationContract
  limits : (Int, Int, Int)
  max_work : Int
  facets : ClientRequestEffectRunExplanationFacets
}

///|
/// The original Journal Plan wire is the computation, not the static Effect
/// envelope. The Invocation Template anchors the checked environment on a
/// later cold read via the existing Definition's template CID.
pub struct ClientRequestEffectRunExplanationFacets {
  plan : String
  compiled_plan : String
  invocation_template : String
  facts : String
  context : String
}

///|
struct ClientRequestEffectRunExplanation[I] {
  mut original : ClientRequestEffectRunExplanationData[I]?
}

///|
/// Project the original Effect compiler selected by the first-Run issuer
/// under the same Request's working reservation, before Plan adoption.
/// The Journal caller owns durable admission and the actual return/ACK.
pub fn[I] capture_request_effect_run_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[
  ClientRequestEffectRunExplanation[I],
  ClientRequestStaticContextIssue,
] {
  guard owner.program_data is Some(data) else {
    return Err(Preparation(WrongPhase))
  }
  with_request_static_effect_explanation(
    owner,
    input,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    (capacity, prepared, current, limits) => {
      guard @publication_host.client_effect_explanation_compilation_for_run(
          prepared, allowed, definition,
        )
        is Some(compiled) else {
        return Err(Preparation(ForeignOriginal))
      }
      let graph = @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      )
      let (bytes, nodes, depth) = limits
      // Reuse the Plan's existing projection quote. The already compiled
      // original is borrowed for the writer, with no compiler call here.
      match
        reserve_native_static_plan_capacity(
          capacity, input, data, graph, bytes, nodes, depth,
        ) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      guard static_effect_plan_capture_construction(limits) is Some(overlap) &&
        @execution.preparation_representation_cost(
          static_plan_quote_units(9L, 23L, 6L),
        )
        is Some(binding) &&
        @execution.checked_preparation_add_product(
          client_static_plan_quote_construction_bytes(),
          overlap,
          1L,
        )
        is Some(projection) &&
        @execution.checked_preparation_add_product(projection, binding, 1L)
        is Some(held) else {
        return Err(Preparation(Policy))
      }
      match reserve_static_context_construction(capacity, input, held) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard current() else { return Err(Preparation(ForeignOriginal)) }
      let computation_wire = Ref(None)
      let (original, _) = match
        @publication_host.capture_client_static_effect_explanation_original(
          prepared,
          compiled,
          bytes,
          nodes,
          depth,
          computation_wire=Some(computation_wire),
        ) {
        Err(issue) => return Err(Context(issue))
        Ok(value) => value
      }
      let (facts, context) = match
        construct_static_effect_explanation_working(
          capacity, input, original, prepared, compiled, current, limits, max_work,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      guard computation_wire.val is Some(plan) else {
        return Err(Preparation(ForeignOriginal))
      }
      Ok({
        original: Some({
          owner,
          input,
          prepared,
          definition,
          limits,
          max_work,
          facets: {
            plan,
            // Both already have immutable encoder output in the original
            // compiler owner. Carry the strings without copying or encoding.
            compiled_plan: @publication.publication_contract_json(
              @publication_host.client_effect_compilation_compiled_plan(
                compiled,
              ),
            ),
            invocation_template: @publication.run_evidence_value_json(
              @publication_host.client_effect_compilation_template(compiled),
            ),
            facts,
            context,
          },
        }),
      })
    },
  )
}

///|
/// Borrow the original Plan, binding and facets on the working Request.
/// The caller carries this funded data through that same Run's admission.
pub fn[I] original_effect_run_explanation_facets(
  original : ClientRequestEffectRunExplanation[I],
  definition : @publication.PublicationContract,
) -> Result[
  ClientRequestEffectRunExplanationFacets,
  ClientRequestStaticContextIssue,
] {
  guard original.original is Some(selected) else {
    return Err(Preparation(WrongPhase))
  }
  if !physical_equal(selected.definition, definition) {
    return Err(Preparation(ForeignOriginal))
  }
  let (bytes, nodes, depth) = selected.limits
  with_request_static_effect_explanation(
    selected.owner,
    selected.input,
    bytes,
    nodes,
    depth,
    selected.max_work,
    (_, prepared, _, _) => {
      guard physical_equal(prepared, selected.prepared) else {
        return Err(Preparation(ForeignOriginal))
      }
      Ok(selected.facets)
    },
  ).bind(value => {
    guard original.original is Some(live) && physical_equal(live, selected) else {
      return Err(Preparation(WrongPhase))
    }
    Ok(value)
  })
}

///|
/// Drop the original facet aliases after the Journal has dropped its copies,
/// before returning the parent capacity. This does not acknowledge a commit
/// or return any capacity itself.
pub fn[I] discard_original_effect_run_explanation(
  original : ClientRequestEffectRunExplanation[I],
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientRequestStaticContextIssue] {
  guard original.original is Some(selected) else {
    return Err(Preparation(WrongPhase))
  }
  if !physical_equal(selected.definition, definition) {
    return Err(Preparation(ForeignOriginal))
  }
  if selected.owner.phase == Selecting {
    return Err(Preparation(WrongPhase))
  }
  original.original = None
  Ok(())
}
