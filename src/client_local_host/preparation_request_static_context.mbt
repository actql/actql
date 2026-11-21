///|
pub(all) enum ClientRequestStaticContextIssue {
  Preparation(ClientRequestPreparationIssue)
  Context(@publication_host.ClientStaticExplanationSourceIssue)
  Facts(@publication_host.ClientExplanationFactsIssue)
  Encoding(@encode.EncodeFailure)
  Contract(@publication.PublicationContractIssue)
} derive(Debug)

///|
// The deepest Context branch is root/items/Effect set/members/member/
// declaration/contract. Its simultaneous object keys are bounded by the
// complete records: root(4), set(3), member(2), declaration(8), contract(4).
// Siblings reuse the frames. Ordinary measuring output still uses key Maps.
let static_context_measurement_bytes : Int64 = {
  let writer = @encode.measuring_writer_construction_extent(21, 7).unwrap()
  @execution.preparation_representation_cost({
    // Geometry sink and its counters, the nine-word result, and live original
    // source/step/port and output/Effect lookup frames. Include the bound
    // measurement call, remaining-work Ref, typed Options and Result carriers.
    // Loops borrow each checked item in order; no traversal vector is built.
    record_headers: writer.record_headers + 28L,
    reference_slots: writer.reference_slots + 56L,
    scalar_words: writer.scalar_words + 44L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// Use the same working reservation, including the still-live Plan/Map and
// previous measurement. Current callbacks cannot replace the input or owner
// while the enclosing Request has its existing Selecting latch.
fn[I, P] reserve_static_context_construction(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  bytes : Int64,
) -> Result[Unit, ClientRequestStaticContextIssue] {
  let (retained, execution) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(Capacity(issue)))
  }
  guard @execution.checked_preparation_add_product(retained, bytes, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(execution, bytes, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  @resources.reserve_working_preparation_phase(capacity, input, r, e).map_err(issue => {
    Preparation(Capacity(issue))
  })
}

///|
fn[I, T] with_request_static_effect_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  project : (
    @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
    @publication_host.PreparedClientEffectComputation,
    () -> Bool,
    (Int, Int, Int),
  ) -> Result[T, ClientRequestStaticContextIssue],
) -> Result[T, ClientRequestStaticContextIssue] {
  guard owner.input is Some(held) && physical_equal(held, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  let phase = owner.phase
  guard (
      phase == EffectCompiled ||
      (phase == EffectPlanReserved && owner.effect_plan is None)
    ) &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) else {
    return Err(Preparation(WrongPhase))
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 || max_work < 1 {
    return Err(Preparation(Policy))
  }
  let bytes = Int::min(max_bytes, 65536)
  let nodes = Int::min(max_nodes, 8192)
  let depth = Int::min(max_depth, 64)
  owner.phase = Selecting
  let original_current = () => {
    owner.phase == Selecting &&
    owner.input is Some(held) &&
    physical_equal(held, input) &&
    owner.effect_capacity is Some(working) &&
    physical_equal(working, capacity) &&
    owner.compiled_effect is Some(checked) &&
    physical_equal(checked, prepared)
  }
  preparation_module_call(
    () => {
      let value = match
        project(capacity, prepared, original_current, (bytes, nodes, depth)) {
        Err(issue) => return Err(issue)
        Ok(result) => result
      }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => Err(Preparation(Capacity(issue)))
        Ok(_) =>
          if original_current() {
            Ok(value)
          } else {
            Err(Preparation(ForeignOriginal))
          }
      }
    },
    () => if owner.phase == Selecting { owner.phase = phase },
  )
}

///|
fn[I] construct_static_effect_context_working(
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  input : I,
  original : @publication_host.ClientStaticEffectExplanationOriginal,
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientEffectCompilation,
  original_current : () -> Bool,
  limits : (Int, Int, Int),
  max_work : Int,
) -> Result[String, ClientRequestStaticContextIssue] {
  let (bytes, nodes, depth) = limits
  let entry = static_context_measurement_bytes +
    client_static_plan_quote_construction_bytes()
  match reserve_static_context_construction(capacity, input, entry) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !original_current() {
    return Err(Preparation(ForeignOriginal))
  }
  let geometry = match
    @publication_host.measure_client_static_effect_explanation_context(
      original, prepared, compiled, bytes, nodes, depth, max_work,
    ) {
    Err(issue) => return Err(Context(issue))
    Ok(value) => value
  }
  let (bytes, nodes, depth) = @encode.construction_geometry_usage(geometry)
  guard explanation_read_codec_cost("explanation_context", bytes, nodes, depth)
    is Some(codec) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 1L,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(emission) &&
    @execution.checked_preparation_add_product(codec, emission, 1L)
    is Some(output) else {
    return Err(Preparation(Policy))
  }
  match reserve_static_context_construction(capacity, input, output) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !original_current() {
    return Err(Preparation(ForeignOriginal))
  }
  let wire = try {
    let writer = @encode.writer(bytes, nodes, depth)
    match
      @publication_host.write_client_static_effect_explanation_context(
        original, prepared, compiled, writer, max_work,
      ) {
      Err(issue) => return Err(Context(issue))
      Ok(_) => ()
    }
    @encode.finish(writer)
  } catch {
    issue => return Err(Encoding(issue))
  }
  match
    @publication.parse_interactive_run_control_shape(
      "explanation_context", wire, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Contract(issue))
    Ok(_) => ()
  }
  Ok(wire)
}

///|
/// Construct Context from the retained original static Plan, under the same
/// working Effect Request. The calling Host retains the original Plan backing
/// and authorizes disclosure before entry and again before egress. No payload
/// authority, second compiler, Task, Run or persistence is supplied here.
pub fn[I] construct_request_static_effect_context(
  owner : ClientRequestPreparation[I],
  input : I,
  original : @publication_host.ClientStaticEffectExplanationOriginal,
  compiled : @publication_host.ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[String, ClientRequestStaticContextIssue] {
  with_request_static_effect_explanation(
    owner,
    input,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    (capacity, prepared, current, limits) => {
      construct_static_effect_context_working(
        capacity, input, original, prepared, compiled, current, limits, max_work,
      )
    },
  )
}

///|
// Facts keep their existing closed envelope and storage identity. The paired
// Context remains charged after its construction while both Facts writers,
// admitted geometry and sealed bytes are allocated on the same Request.
fn[I] construct_static_effect_facts_working(
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  input : I,
  original : @publication_host.ClientStaticEffectExplanationOriginal,
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientEffectCompilation,
  original_current : () -> Bool,
  limits : (Int, Int, Int),
) -> Result[String, ClientRequestStaticContextIssue] {
  let (bytes, nodes, depth) = limits
  guard explanation_capture_measurement_bytes(bytes) is Some(measurement) &&
    @execution.checked_preparation_add_product(
      explanation_capture_entry_control_bytes, measurement, 1L,
    )
    is Some(entry) else {
    return Err(Preparation(Policy))
  }
  match reserve_static_context_construction(capacity, input, entry) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !original_current() {
    return Err(Preparation(ForeignOriginal))
  }
  let geometry = match
    @publication_host.measure_client_static_effect_explanation_facts(
      original, prepared, compiled, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Facts(issue))
    Ok(value) => value
  }
  guard explanation_capture_codec_layout(geometry) is Some(codec) &&
    @execution.preparation_representation_cost(codec.retained) is Some(retained) &&
    @execution.preparation_representation_cost(codec.scratch) is Some(scratch) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: geometry.body.0.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(body) &&
    @execution.checked_preparation_add_product(retained, scratch, 1L)
    is Some(codec_bytes) &&
    @execution.checked_preparation_add_product(codec_bytes, body, 1L)
    is Some(needed) else {
    return Err(Preparation(Policy))
  }
  match reserve_static_context_construction(capacity, input, needed) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !original_current() {
    return Err(Preparation(ForeignOriginal))
  }
  let (bytes, nodes, depth) = geometry.complete
  @publication_host.seal_client_static_effect_explanation_facts(
    original, prepared, compiled, bytes, nodes, depth,
  )
  .map(@publication.run_evidence_value_json)
  .map_err(issue => Facts(issue))
}

///|
/// Construct Facts and Context from one original Plan projection. This is an
/// internal component, with no public wire envelope. The Host retains the
/// already backed Plan and applies its authorization and complete egress
/// limit before consuming these two closed wires.
pub fn[I] construct_request_static_effect_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  original : @publication_host.ClientStaticEffectExplanationOriginal,
  compiled : @publication_host.ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, String), ClientRequestStaticContextIssue] {
  with_request_static_effect_explanation(
    owner,
    input,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    (capacity, prepared, current, limits) => {
      construct_static_effect_explanation_working(
        capacity, input, original, prepared, compiled, current, limits, max_work,
      )
    },
  )
}

///|
fn[I] construct_static_effect_explanation_working(
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  input : I,
  original : @publication_host.ClientStaticEffectExplanationOriginal,
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientEffectCompilation,
  current : () -> Bool,
  limits : (Int, Int, Int),
  max_work : Int,
) -> Result[(String, String), ClientRequestStaticContextIssue] {
  let context = match
    construct_static_effect_context_working(
      capacity, input, original, prepared, compiled, current, limits, max_work,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  construct_static_effect_facts_working(
    capacity, input, original, prepared, compiled, current, limits,
  ).map(facts => (facts, context))
}

///|
/// Closed structural wires returned together from the original preparation.
/// The Host still owns its disclosure and total transport-byte policy.
pub struct ClientRequestStaticEffectExplanation {
  plan : String
  facts : String
  context : String
}

///|
// During capture both original codecs and their returned wires can coexist.
// Count the retained Map/declared members as part of the same inner value,
// plus fixed capture/return wrappers. The legacy Plan writer has its own
// earlier quote; this is the held projection/validation overlap.
fn static_effect_plan_capture_construction(limits : (Int, Int, Int)) -> Int64? {
  let (bytes, nodes, depth) = limits
  guard explanation_read_codec_cost("plan_view", bytes, nodes, depth)
    is Some(plan) &&
    explanation_read_codec_cost(
      "effectful_static_plan_view", bytes, nodes, depth,
    )
    is Some(effect) &&
    @execution.preparation_representation_cost(
      static_plan_quote_units(8L, 18L, 10L),
    )
    is Some(controls) &&
    @execution.checked_preparation_add_product(plan, effect, 1L) is Some(codecs) else {
    return None
  }
  @execution.checked_preparation_add_product(codecs, controls, 1L)
}

///|
// The Host decodes all three individually bounded originals before checking
// the aggregate tree. Its UTF-8 gate runs before decoding. Allow the decoded
// tree, entry iteration/validation frames, traversal work and its Set to
// overlap, together with response encoding and the fixed delivery controls.
fn static_effect_explanation_delivery_construction(
  limits : (Int, Int, Int),
  max_wire_bytes : Int,
) -> Int64? {
  let (bytes, nodes, depth) = limits
  let decoded_nodes = 3L * nodes.to_int64() + 7L
  // These are the Host's ASCII member names and delimiters, without values.
  let envelope_bytes = "{\"plan\":,\"facts\":,\"context\":}".length().to_int64()
  let delivered_bytes = Int64::min(
    max_wire_bytes.to_int64(),
    3L * bytes.to_int64() + envelope_bytes,
  )
  result_read_data_cost(
    4L * decoded_nodes + 4L * depth.to_int64() + 64L,
    6L * delivered_bytes,
    2L * delivered_bytes,
  )
}

///|
/// Issue one static Plan through the original working Effect Request, retaining
/// that issuer's Map while projecting Facts and Context. The prepared input
/// may carry the same metadata-only Model plans used by the static compiler.
/// This private compiler binding is not a public explanation capability.
pub fn[I] request_prepared_static_effect_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> Result[
  ClientRequestStaticEffectExplanation,
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
      let graph = @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      )
      let (bytes, nodes, depth) = limits
      match
        reserve_native_static_plan_capacity(
          capacity, input, data, graph, bytes, nodes, depth,
        ) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      let entry = client_static_plan_quote_construction_bytes()
      match reserve_static_context_construction(capacity, input, entry) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard current() else { return Err(Preparation(ForeignOriginal)) }
      guard static_effect_plan_capture_construction(limits) is Some(capture) else {
        return Err(Preparation(Policy))
      }
      match reserve_static_context_construction(capacity, input, capture) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard current() else { return Err(Preparation(ForeignOriginal)) }
      let compiled = match
        issue_request_static_effect_plan_compilation(
          prepared, manifests, limits, infers,
        ) {
        Err(issue) => return Err(Preparation(issue))
        Ok(value) => value
      }
      let (original, plan) = match
        @publication_host.capture_client_static_effect_explanation_original(
          prepared, compiled, bytes, nodes, depth,
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
      guard static_effect_explanation_delivery_construction(limits, max_bytes)
        is Some(delivery) else {
        return Err(Preparation(Policy))
      }
      match reserve_static_context_construction(capacity, input, delivery) {
        Err(issue) => Err(issue)
        Ok(_) => Ok({ plan, facts, context, })
      }
    },
  )
}
