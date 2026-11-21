///|
pub(all) enum ClientRequestStaticContextIssue {
  Preparation(ClientRequestPreparationIssue)
  Context(@publication_host.ClientStaticExplanationSourceIssue)
  Facts(@publication_host.ClientExplanationFactsIssue)
  Encoding(@encode.EncodeFailure)
  Contract(@publication.PublicationContractIssue)
  Presentation(@publication_host.ClientExplanationNarrativeIssue)
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
      // One extra original computation-wire reference in the issuer return.
      static_plan_quote_units(8L, 19L, 10L),
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
  let decoded_nodes = 3L * nodes.to_int64() + 9L
  // These are the Host's ASCII member names and delimiters, without values.
  let envelope_bytes = static_explanation_shell_bytes().to_int64()
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
let static_explanation_context_prefix = "{\"context\":"

///|
let static_explanation_facts_prefix = ",\"facts\":"

///|
let static_explanation_plan_prefix = ",\"plan\":"

///|
let static_explanation_version_suffix = ",\"version\":\"actql-static-explanation/0.1\"}"

///|
fn static_explanation_shell_bytes() -> Int {
  static_explanation_context_prefix.length() +
  static_explanation_facts_prefix.length() +
  static_explanation_plan_prefix.length() +
  static_explanation_version_suffix.length()
}

///|
// Count the UTF-8 wire without allocating another copy of any facet.
fn static_explanation_utf8_bytes(wire : String) -> Int {
  let mut bytes = 0
  for character in wire {
    let value = character.to_int()
    bytes += if value < 128 {
      1
    } else if value < 2048 {
      2
    } else if value < 65536 {
      3
    } else {
      4
    }
  }
  bytes
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
  prepare_static_effect_explanation_facets(
    owner, input, manifests, max_bytes, max_nodes, max_depth, max_work, infers, true,
  )
}

///|
fn[I] prepare_static_effect_explanation_facets(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  infers : Array[@publication_host.ClientInferPlanGraph],
  reserve_js_delivery : Bool,
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
      if reserve_js_delivery {
        guard static_effect_explanation_delivery_construction(limits, max_bytes)
          is Some(delivery) else {
          return Err(Preparation(Policy))
        }
        match reserve_static_context_construction(capacity, input, delivery) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      Ok({ plan, facts, context, })
    },
  )
}

///|
/// Deliver the bounded closed wire through the same working Request. The
/// caller supplies current disclosure before entry and again before egress.
pub fn[I] request_prepared_static_effect_explanation_wire(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> Result[String, ClientRequestStaticContextIssue] {
  request_prepared_static_effect_explanation_output(
    owner,
    input,
    manifests,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    infers,
    None,
  )
}

///|
/// Render the same closed compiler projection on its working Request before
/// returning the command reply. The consumer still owns current disclosure.
pub fn[I] request_prepared_static_effect_explanation_narrative(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  language : @publication_host.ClientExplanationLanguage,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> Result[String, ClientRequestStaticContextIssue] {
  request_prepared_static_effect_explanation_output(
    owner,
    input,
    manifests,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    infers,
    Some(language),
  )
}

///|
fn[I] request_prepared_static_effect_explanation_output(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  infers : Array[@publication_host.ClientInferPlanGraph],
  language : @publication_host.ClientExplanationLanguage?,
) -> Result[String, ClientRequestStaticContextIssue] {
  if max_bytes < 1 {
    return Err(Preparation(Policy))
  }
  // The Native compiler uses its existing artifact ceiling. The delivery
  // limit below applies to the completed aggregate, not private artifacts.
  let facets = match
    prepare_static_effect_explanation_facets(
      owner, input, manifests, 65536, max_nodes, max_depth, max_work, infers, false,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  with_request_static_effect_explanation(
    owner,
    input,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    (capacity, _, current, limits) => {
      let (bytes, nodes, depth) = limits
      let extent = static_explanation_shell_bytes() +
        static_explanation_utf8_bytes(facets.plan) +
        static_explanation_utf8_bytes(facets.facts) +
        static_explanation_utf8_bytes(facets.context)
      if extent > bytes {
        return Err(Encoding(@encode.OutputLimit))
      }
      // The original wires stay held while the aggregate writer, returned
      // text and closed arbitrary-wire validator overlap. Use the same
      // working capacity and keep the additional bound until cleanup.
      guard result_read_data_cost(
          16L,
          6L * extent.to_int64(),
          2L * extent.to_int64(),
        )
        is Some(output) &&
        explanation_read_codec_cost(
          "static_explanation_view", extent, nodes, depth,
        )
        is Some(codec) &&
        @execution.checked_preparation_add_product(output, codec, 1L)
        is Some(delivery) else {
        return Err(Preparation(Policy))
      }
      match reserve_static_context_construction(capacity, input, delivery) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard current() else { return Err(Preparation(ForeignOriginal)) }
      let builder = StringBuilder(size_hint=extent)
      builder.write_string(static_explanation_context_prefix)
      builder.write_string(facets.context)
      builder.write_string(static_explanation_facts_prefix)
      builder.write_string(facets.facts)
      builder.write_string(static_explanation_plan_prefix)
      builder.write_string(facets.plan)
      builder.write_string(static_explanation_version_suffix)
      let wire = builder.to_string()
      let admitted = match
        @publication.parse_interactive_run_control_shape(
          "static_explanation_view", wire, extent, nodes, depth,
        ) {
        Err(issue) => return Err(Contract(issue))
        Ok(value) => value
      }
      match language {
        None => Ok(wire)
        Some(selected) =>
          render_working_static_explanation(
            capacity, input, admitted, current, bytes, nodes, depth, selected,
          )
      }
    },
  )
}

///|
fn[I] render_working_static_explanation(
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  input : I,
  view : @identity.CanonicalValue,
  current : () -> Bool,
  bytes : Int,
  nodes : Int,
  depth : Int,
  language : @publication_host.ClientExplanationLanguage,
) -> Result[String, ClientRequestStaticContextIssue] {
  guard @identity.object_field(view, "facts") is Some(facts) &&
    @identity.object_field(view, "context") is Some(context) else {
    return Err(Presentation(InvalidExplanation))
  }
  // Bound the separate Context/step buffers, predicate cache/active/depth
  // vectors and recursive frames from the admitted tree. Each append debits
  // the character budget before copying. Include the builder and final text
  // for the complete CLI reply while the original wires and decoded view live.
  guard result_read_data_cost(
      4L * nodes.to_int64() + 4L * depth.to_int64() + 128L,
      8L * bytes.to_int64(),
      2L * bytes.to_int64(),
    )
    is Some(layout) else {
    return Err(Preparation(Policy))
  }
  match reserve_static_context_construction(capacity, input, layout) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard current() else { return Err(Preparation(ForeignOriginal)) }
  let narrative = @publication_host.render_client_explanation_narrative(
    facts, context, language, bytes,
  ) catch {
    issue => return Err(Presentation(issue))
  }
  let heading = match language {
    English => "Logical dependencies"
    Japanese => "論理的な依存関係"
  }
  let mut extent = static_explanation_utf8_bytes(heading)
  for line in narrative.context {
    extent += static_explanation_utf8_bytes(line) + 1
  }
  for line in narrative.steps {
    extent += static_explanation_utf8_bytes(line) + 1
  }
  if extent > bytes {
    return Err(Encoding(@encode.OutputLimit))
  }
  let report = StringBuilder(size_hint=extent)
  for line in narrative.context {
    report.write_string(line)
    report.write_char('\n')
  }
  report.write_string(heading)
  for line in narrative.steps {
    report.write_char('\n')
    report.write_string(line)
  }
  Ok(report.to_string())
}
