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
// Use the normal original for lowering and borrow only a disposable Debug
// topology. The first task must be ready and every operation independently
// controllable, as required at actual Effect start.
fn[I, P] static_effect_debug_entry_probe(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  prepared : @publication_host.PreparedClientEffectComputation,
  max_tasks : Int,
  work : Int,
) -> Result[(Bool, Int), @resources.PreparationCapacityIssue] {
  let limits = @publication_host.client_standard_effect_computation_limits().program
  let tasks = Int::min(max_tasks, limits.max_tasks)
  let graph_work = Int::min(work / 2, limits.max_graph_work)
  let time_work = work - graph_work
  let (stoppable, spent) = match
    with_static_debug_graph_probe(
      capacity,
      input,
      1,
      tasks,
      graph_work,
      observed => {
        @publication_host.measure_client_static_effect_debug_graph_construction(
          prepared, tasks, graph_work, observed,
        )
      },
      (remaining, boundary_work) => {
        guard @publication_host.prepare_client_static_effect_debug_graph(
            prepared, tasks, remaining,
          )
          is Ok(graph) else {
          return false
        }
        let tasks = @strategy.graph_task_count(graph)
        let extent = 1L +
          7L * tasks.to_int64() +
          2L * @strategy.graph_data_count(graph).to_int64() +
          2L * @strategy.graph_control_count(graph).to_int64()
        if extent > boundary_work ||
          !@strategy.graph_source_free_inputs_complete(graph) ||
          !@strategy.checked_source_free_effect_control_has_entry(graph) {
          return false
        }
        // The admitted Effect geometry has one Unit with one task per
        // operation. Match the original forward coordinate for every task.
        for operation in 0..<tasks {
          if @strategy.checked_task_control_operation_task(graph, 0, operation) !=
            Some(operation) {
            return false
          }
        }
        true
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !stoppable {
    return Ok((false, spent))
  }
  // QueryTime inspection retains a temporary checked expression-slot vector.
  // It runs after the split is released. Back its records and array growth
  // before collecting at most one slot per unit of bounded inspection work.
  let base = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let slots = time_work.to_int64()
  guard @execution.preparation_representation_cost({
      record_headers: 16L + 4L * slots,
      reference_slots: 32L + 8L * slots,
      scalar_words: 24L + 4L * slots,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) &&
    @execution.checked_preparation_add_product(base.0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(base.1, bytes, 1L) is Some(e) &&
    @resources.reserve_working_preparation_phase(capacity, input, r, e) is Ok(_) else {
    return Ok((false, spent))
  }
  let independent = @publication_host.prepared_client_effect_requires_query_time(
      prepared, time_work, time_work,
    )
    is Ok(false)
  @resources.reconcile_current_working_preparation_phase(
    capacity,
    input,
    base.0,
    base.1,
  ).map(_ => (independent, spent + time_work))
}

///|
// The deepest Context branch is root/items/Effect set/members/member/
// declaration/contract. Its simultaneous object keys are bounded by the
// complete records: root(5), set(3), member(2), declaration(8), contract(4).
// Siblings reuse the frames. Ordinary measuring output still uses key Maps.
let static_context_measurement_bytes : Int64 = {
  let writer = @encode.measuring_writer_construction_extent(22, 7).unwrap()
  @execution.preparation_representation_cost({
    // Geometry sink and its counters, the nine-word result, and live original
    // source/step/port and output/Effect lookup frames. Include the bound
    // measurement call, remaining-work Ref, typed Options and Result carriers.
    // Include the import, predecessor and exact output lookup frames.
    // Loops borrow each checked item in order.
    record_headers: writer.record_headers + 40L,
    reference_slots: writer.reference_slots + 84L,
    scalar_words: writer.scalar_words + 60L,
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
  construct_static_context_working(
    capacity,
    input,
    EffectProjection(original, prepared, compiled),
    original_current,
    limits,
    max_work,
  )
}

///|
fn[I, P] construct_static_context_working(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  projection : StaticExplanationProjection,
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
  let measured = try {
    let writer = @encode.construction_measuring_writer(bytes, nodes, depth)
    match write_static_context_projection(projection, writer, max_work) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(@encode.finish_construction_measurement(writer))
    }
  } catch {
    issue => Err(@publication_host.Encoding(issue))
  }
  let geometry = match measured {
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
    match write_static_context_projection(projection, writer, max_work) {
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
fn write_static_context_projection(
  projection : StaticExplanationProjection,
  writer : @encode.Writer,
  max_work : Int,
) -> Result[Unit, @publication_host.ClientStaticExplanationSourceIssue] {
  match projection {
    EffectProjection(original, prepared, compiled) =>
      @publication_host.write_client_static_effect_explanation_context(
        original, prepared, compiled, writer, max_work,
      )
    PureProjection(original) =>
      @publication_host.write_client_static_pure_explanation_context(
        original, writer, max_work,
      )
  }
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
priv enum StaticExplanationProjection {
  EffectProjection(
    @publication_host.ClientStaticEffectExplanationOriginal,
    @publication_host.PreparedClientEffectComputation,
    @publication_host.ClientEffectCompilation
  )
  PureProjection(@publication_host.ClientStaticPureExplanationOriginal)
}

///|
// Facts keep their existing closed envelope and storage identity. The paired
// Context remains charged after its construction while both Facts writers,
// admitted geometry and sealed bytes are allocated on the same Request.
fn[I, P] construct_static_facts_working(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  projection : StaticExplanationProjection,
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
  let measured = match projection {
    EffectProjection(original, prepared, compiled) =>
      @publication_host.measure_client_static_effect_explanation_facts(
        original, prepared, compiled, bytes, nodes, depth,
      )
    PureProjection(original) =>
      @publication_host.measure_client_static_pure_explanation_facts(
        original, bytes, nodes, depth,
      )
  }
  let geometry = match measured {
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
  let result = match projection {
    EffectProjection(original, prepared, compiled) =>
      @publication_host.seal_client_static_effect_explanation_facts(
        original, prepared, compiled, bytes, nodes, depth,
      )
    PureProjection(original) =>
      @publication_host.seal_client_static_pure_explanation_facts(
        original, bytes, nodes, depth,
      )
  }
  result
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
  construct_static_facts_working(
    capacity,
    input,
    EffectProjection(original, prepared, compiled),
    current,
    limits,
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
    // Seven root keys and eight capability keys can overlap. The
    // quantity object's three keys also fit within the same three frames.
    @encode.measuring_writer_construction_extent(15, 3) is Some(measure) &&
    @execution.preparation_representation_cost(
      // Original computation wire and bounded map accounting stay live
      // while measuring the whole view over the sealed map's exact geometry.
      static_plan_quote_units(
        measure.record_headers + 12L,
        measure.reference_slots + 29L,
        measure.scalar_words + 18L,
      ),
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
  debug_entry_installed? : Bool = false,
) -> Result[
  ClientRequestStaticEffectExplanation,
  ClientRequestStaticContextIssue,
] {
  prepare_static_effect_explanation_facets(
    owner,
    input,
    manifests,
    max_bytes,
    max_nodes,
    max_depth,
    max_work,
    infers,
    true,
    debug_entry_installed~,
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
  debug_entry_installed? : Bool = false,
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
      let (debug_entry, probe_work) = if debug_entry_installed &&
        infers.is_empty() {
        match
          static_effect_debug_entry_probe(
            capacity,
            input,
            prepared,
            nodes,
            Int::min(nodes, max_work / 4),
          ) {
          Ok(value) => value
          Err(issue) => return Err(Preparation(Capacity(issue)))
        }
      } else {
        (false, 0)
      }
      guard current() else { return Err(Preparation(ForeignOriginal)) }
      let (original, plan) = match
        @publication_host.capture_client_static_effect_explanation_original(
          prepared,
          compiled,
          bytes,
          nodes,
          depth,
          debug_entry~,
        ) {
        Err(issue) => return Err(Context(issue))
        Ok(value) => value
      }
      construct_static_explanation_facets_working(
        capacity,
        input,
        EffectProjection(original, prepared, compiled),
        plan,
        current,
        limits,
        max_work - probe_work,
        max_bytes,
        reserve_js_delivery,
      )
    },
  )
}

///|
fn[I, P] construct_static_explanation_facets_working(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  projection : StaticExplanationProjection,
  plan : String,
  current : () -> Bool,
  limits : (Int, Int, Int),
  max_work : Int,
  max_bytes : Int,
  reserve_js_delivery : Bool,
) -> Result[
  ClientRequestStaticEffectExplanation,
  ClientRequestStaticContextIssue,
] {
  let context = match
    construct_static_context_working(
      capacity, input, projection, current, limits, max_work,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let facts = match
    construct_static_facts_working(capacity, input, projection, current, limits) {
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
      finish_request_static_explanation_output(
        capacity, input, facets, current, limits, language,
      )
    },
  )
}

///|
fn[I, P] finish_request_static_explanation_output(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  facets : ClientRequestStaticEffectExplanation,
  current : () -> Bool,
  limits : (Int, Int, Int),
  language : @publication_host.ClientExplanationLanguage?,
) -> Result[String, ClientRequestStaticContextIssue] {
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
    explanation_read_codec_cost("static_explanation_view", extent, nodes, depth)
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
}

///|
fn[I, P] render_working_static_explanation(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  view : @identity.CanonicalValue,
  current : () -> Bool,
  bytes : Int,
  nodes : Int,
  depth : Int,
  language : @publication_host.ClientExplanationLanguage,
) -> Result[String, ClientRequestStaticContextIssue] {
  guard @identity.object_field(view, "facts") is Some(facts) &&
    @identity.object_field(view, "context") is Some(context) &&
    @identity.object_field(facts, "steps") is Some(@identity.Array(steps)) &&
    @identity.object_field(context, "items") is Some(@identity.Array(items)) &&
    @identity.object_field(view, "plan") is Some(plan) &&
    @publication_host.explanation_narrative_map(plan) is Some(map) else {
    return Err(Presentation(InvalidExplanation))
  }
  // Bound the separate Context/step buffers, predicate cache/active/depth
  // vectors, join port/source indices and recursive frames from the admitted
  // tree. Each append debits
  // the character budget before copying. Include the builder and final text
  // for the complete CLI reply while the original wires and decoded view live.
  let originals = @identity.array_count(steps).to_int64() +
    @identity.array_count(items).to_int64()
  guard result_read_data_cost(
      12L * nodes.to_int64() + 4L * depth.to_int64() + 20L * originals + 192L,
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
    facts,
    Some(context),
    language,
    bytes,
    logical_map=Some(map),
  ) catch {
    issue => return Err(Presentation(issue))
  }
  let heading = match language {
    English => "Logical dependencies"
    Japanese => "論理的な依存関係"
  }
  let mut extent = static_explanation_utf8_bytes(heading) +
    static_explanation_utf8_bytes(narrative.summary) +
    1
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
  report.write_string(narrative.summary)
  report.write_char('\n')
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
