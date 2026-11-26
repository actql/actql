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
  mut facets : ClientRequestEffectRunExplanationFacets?
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
  mut scratch : (
    @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
    @resources.PreparationScratch[I, ClientInstalledEffectManagedPlan],
  )?
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
  journal_bytes? : Int = 0,
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
          static_plan_quote_units(10L, 26L, 8L),
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
      if journal_bytes > 0 {
        // The Journal serializes the accepted evidence and parses it once;
        // a submitted intent can cause a second complete wire to coexist.
        // Include both bounded representations, the five-wire handoff and
        // the native hash/statement wrappers before returning any JS alias.
        let limit = journal_bytes.to_int64()
        guard @execution.preparation_representation_cost({
            record_headers: 2L * limit + 64L,
            reference_slots: 4L * limit + 160L,
            scalar_words: 2L * limit + 96L,
            owned_utf16_units: 8L * limit,
            owned_wire_bytes: 4L * limit,
          })
          is Some(journal_overlap) else {
          return Err(Preparation(Policy))
        }
        match
          reserve_static_context_construction(capacity, input, journal_overlap) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
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
          facets: Some({
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
          }),
        }),
        scratch: None,
      })
    },
  )
}

///|
/// Optional first-capture admission under the same working Effect Request.
/// The fixed installed caller passes its existing Journal limit.
pub fn[I] try_capture_request_effect_run_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  journal_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[
  ClientRequestEffectRunExplanation[I]?,
  ClientRequestStaticContextIssue,
] {
  guard owner.effect_capacity is Some(capacity) &&
    owner.input is Some(held) &&
    physical_equal(held, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  let phase = owner.phase
  guard (
      phase == EffectCompiled ||
      (phase == EffectPlanReserved && owner.effect_plan is None)
    ) &&
    owner.compiled_effect is Some(prepared) else {
    return Err(Preparation(WrongPhase))
  }
  guard @publication_host.client_effect_explanation_compilation_for_run(
      prepared, allowed, definition,
    )
    is Some(_) else {
    return Err(Preparation(ForeignOriginal))
  }
  if journal_bytes < 1 || max_nodes < 1 || max_depth < 1 || max_work < 1 {
    return Err(Preparation(Policy))
  }
  // Bound the measurement receipt, the two owner extents, its returned
  // pair and the retained owner/scratch carriers before construction.
  guard @execution.preparation_representation_cost(
      static_plan_quote_units(10L, 20L, 10L),
    )
    is Some(control_bytes) else {
    return Err(Preparation(Policy))
  }
  let (captured, scratch) = match
    @resources.measure_working_preparation_scratch(
      capacity,
      input,
      control_bytes,
      () => {
        capture_request_effect_run_explanation(
          owner,
          input,
          allowed,
          definition,
          journal_bytes,
          max_nodes,
          max_depth,
          max_work,
          journal_bytes~,
        )
      },
    ) {
    Err(Resource(RetentionLimit | ExecutionLimit)) => return Ok(None)
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  match captured {
    Ok(original) => {
      original.scratch = Some((capacity, scratch))
      Ok(Some(original))
    }
    Err(Preparation(Capacity(Resource(RetentionLimit | ExecutionLimit))))
    | Err(
      Context(
        Plan(Computation(ConstructionRefused | UnsupportedCarrierContract))
      )
    )
    | Err(Context(WorkLimit | Encoding(@encode.OutputLimit)))
    | Err(Facts(Encoding(@encode.OutputLimit)))
    | Err(Encoding(@encode.OutputLimit)) => {
      // The failed constructor has unwound and handed off no wires. Drop
      // only this declined optional increment, under the same live fence.
      guard owner.phase == phase &&
        owner.input is Some(held) &&
        physical_equal(held, input) &&
        owner.effect_capacity is Some(current) &&
        physical_equal(current, capacity) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.phase = Selecting
      return preparation_module_call(
        () => {
          match
            @resources.return_preparation_scratch(capacity, input, scratch) {
            Err(issue) => Err(Preparation(Capacity(issue)))
            Ok(_) =>
              if owner.phase == Selecting &&
                owner.input is Some(held) &&
                physical_equal(held, input) &&
                owner.effect_capacity is Some(current) &&
                physical_equal(current, capacity) {
                Ok(None)
              } else {
                Err(Preparation(ForeignOriginal))
              }
          }
        },
        () => if owner.phase == Selecting { owner.phase = phase },
      )
    }
    Err(issue) => Err(issue)
  }
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
      guard selected.facets is Some(facets) else {
        return Err(Preparation(WrongPhase))
      }
      Ok(facets)
    },
  ).bind(value => {
    guard original.original is Some(live) && physical_equal(live, selected) else {
      return Err(Preparation(WrongPhase))
    }
    Ok(value)
  })
}

///|
/// Drop the original facet aliases after the Journal has dropped its copies.
/// Only a live decline or acknowledged admission returns the measured scratch.
/// Ordinary retirement keeps the charge under the original capacity owner.
pub fn[I] discard_original_effect_run_explanation(
  original : ClientRequestEffectRunExplanation[I],
  definition : @publication.PublicationContract,
  reclaim? : Bool = false,
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
  selected.facets = None
  if reclaim {
    // The JS caller has already unwound its sizing frame and cleared its
    // aliases. Keep the exact cleanup token when current refuses repayment.
    let owner = selected.owner
    let phase = owner.phase
    guard original.scratch is Some((capacity, scratch)) else {
      return Err(Preparation(WrongPhase))
    }
    if phase != Selected {
      guard (phase == EffectCompiled || phase == EffectPlanReserved) &&
        owner.effect_capacity is Some(working) &&
        physical_equal(working, capacity) else {
        return Err(Preparation(WrongPhase))
      }
    }
    owner.phase = Selecting
    let reconciled = preparation_module_call(
      () => {
        @resources.return_preparation_scratch(capacity, selected.input, scratch)
      },
      () => if owner.phase == Selecting { owner.phase = phase },
    )
    match reconciled {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(_) => ()
    }
  }
  original.scratch = None
  original.original = None
  Ok(())
}
