///|
pub(all) enum ClientRequestStaticContextIssue {
  Preparation(ClientRequestPreparationIssue)
  Context(@publication_host.ClientStaticExplanationSourceIssue)
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
  guard owner.input is Some(held) && physical_equal(held, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard owner.phase == EffectCompiled &&
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
      guard explanation_read_codec_cost(
          "explanation_context", bytes, nodes, depth,
        )
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
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => Err(Preparation(Capacity(issue)))
        Ok(_) =>
          if original_current() {
            Ok(wire)
          } else {
            Err(Preparation(ForeignOriginal))
          }
      }
    },
    () => if owner.phase == Selecting { owner.phase = EffectCompiled },
  )
}
