///|
// The fixed installing Host supplies the actual number of retained contract
// originals. Validation Sets, dependency maps, media/reference pairs and old/
// new Array backing are priced by their existing collection owner. No parser
// or callback executes before this same Request grows for those containers.
fn request_model_material_collection_bytes(count : Int) -> Int64? {
  if count < 0 {
    return None
  }
  let n = count.to_int64()
  guard @shape.collection_construction_extent({
      records: 8L * n,
      record_references: 24L * n,
      record_words: 16L * n,
      reference_arrays: 5L,
      reference_items: 4L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 6L,
      map_entries: 6L * n,
    })
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Existing Source preflight observes only the original wire geometry. It
// builds no contract tree and decides no admission. Its cursor is cancelled
// before the real native parser, including every refused/incomplete preflight.
fn request_model_material_source_geometry(wire : String) -> (Int, Int, Int)? {
  let maximum = 3L * wire.length().to_int64()
  if maximum < 1L || maximum > 2147483647L {
    return None
  }
  let cursor = match
    @source.start_json_source_preflight(
      wire,
      {
        max_input_bytes: maximum.to_int(),
        max_nodes: maximum.to_int(),
        max_depth: Int::min(100, maximum.to_int()),
      },
      data_keys=true,
    ) {
    Err(_) => return None
    Ok(value) => value
  }
  fn observe() -> (Int, Int, Int)? {
    while true {
      match @source.advance_json_source_preflight(cursor, 4096) {
        Err(_) => return None
        Ok(@source.JsonSourceFailed(_, ..)) => return None
        Ok(@source.JsonSourceContinue(..)) => ()
        Ok(@source.JsonSourceReady(geometry, ..)) => {
          if geometry.input_bytes < 1 || geometry.node_upper < 1 {
            return None
          }
          return Some(
            (geometry.input_bytes, geometry.node_upper, geometry.depth_upper),
          )
        }
      }
    } nobreak {
      None
    }
  }
  let result = observe()
  @source.cancel_json_source_preflight(cursor)
  result
}

///|
// One fixed cursor and its bounded Source geometry, plus ParseLimits (1H3W),
// returned triple (1H3W), Some (1H1R1W) and fallback triple (1H3W).
// Original wire Strings are borrowed; no decoded tree or new policy is here.
let request_model_material_preflight_control_bytes : Int64 = {
  let source = @source.json_source_preflight_control_extent()
  @execution.preparation_representation_cost({
    record_headers: source.record_headers + 4L,
    reference_slots: source.reference_slots + 1L,
    scalar_words: source.scalar_words + 10L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// These original readers admit Source/typed contract representations. Borrowed
// input Strings are not copies. Native prompt/retry/backoff/media UTF-8 inputs
// coexist, so their TOTAL backing is retained in addition to active parse
// scratch. No codec ceiling is multiplied by the number of operations.
fn request_model_material_body_bytes(
  count : Int,
  wire_at : (Int) -> String,
  source_geometry? : Bool = false,
) -> Int64? {
  let mut retained : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut scratch = retained
  let mut wire_bytes = 0L
  for index in 0..<count {
    // Exactly one original read per occurrence. The installed closure reads
    // immutable own data slots, without parsing, copying or invoking Provider.
    let wire = wire_at(index)
    let bytes = Int64::max(1L, 3L * wire.length().to_int64())
    if bytes < 1L || bytes > 2147483647L {
      return None
    }
    // A protocol's long schema String is not one decoded node per byte.
    // Refused preflight keeps the old conservative quote and the native
    // reader's original semantic/error boundary; sizing never admits it.
    let geometry = if source_geometry {
      request_model_material_source_geometry(wire).unwrap_or(
        (bytes.to_int(), bytes.to_int(), Int::min(100, bytes.to_int())),
      )
    } else {
      (bytes.to_int(), bytes.to_int(), Int::min(100, bytes.to_int()))
    }
    guard program_artifact_parse_layout(geometry) is Some(parse) &&
      @execution.compose_preparation_representation([
        retained,
        parse.value,
        parse.value,
      ])
      is Some(next) else {
      return None
    }
    retained = next
    scratch = compilation_scratch_max(scratch, parse.temporary)
    guard @execution.checked_preparation_add_product(
        wire_bytes,
        geometry.0.to_int64(),
        1L,
      )
      is Some(total) else {
      return None
    }
    wire_bytes = total
  }
  guard @execution.compose_preparation_representation([
      retained,
      scratch,
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: wire_bytes,
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_representation_cost(peak)
}

///|
/// Before the installed Model's execution/dependency/provider readers enter,
/// grow this SAME original Request for their complete material overlap. This
/// only reserves constructor space; original contract/Task/Account/current
/// checks still admit the actual bodies. A foreign callback throw leaves the
/// same parent failed, with all grown capacity retained for original abort.
pub fn[I] prepare_request_model_contract_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  count : Int,
  wire_at : (Int) -> String,
  container_count : Int,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  let prepared : ClientLocalSequenceOwner = match owner.phase {
    ModelPlanReserved => {
      guard owner.compiled_program is Some(original) &&
        owner.program_capacity is Some(_) else {
        return Err(Preparation(ForeignOriginal))
      }
      Pure(original)
    }
    EffectPlanReserved => {
      guard owner.compiled_effect is Some(original) &&
        owner.effect_capacity is Some(_) &&
        owner.effect_plan is None else {
        return Err(Preparation(ForeignOriginal))
      }
      Effect(original)
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  let original_phase = owner.phase
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    (
      owner.program_domain_compilation_inputs is None ||
      owner.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, _)) ||
      owner.program_domain_compilation_inputs
      is Some(RequestModelGraphs(_, _, _, _))
    ) &&
    owner.program_compilation is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  // This selects only the original material-construction purpose before a
  // Graph exists. Its checked Serialize/Infer coordinates are DATA inventory;
  // the later same-Request Graph/module/Scope entries retain their own guards.
  // A single captured prefix needs its checked original occurrence here too,
  // before the material reader can enter or the backed Graph can be built.
  let material_profile = match prepared {
    Pure(original) =>
      if installed_managed_run_shape_supported(original, true) ||
        (
          @publication_host.prepared_client_composed_infer_occurrences(original)
          is Some(occurrences) &&
          occurrences.length() > 1 &&
          installed_managed_owner_shape_supported(
            Pure(original),
            true,
            model_occurrence=occurrences.get(0),
            model_occurrences=Some(occurrences),
          )
        ) ||
        (
          @publication_host.prepared_client_composed_infer_occurrences(original)
          is Some([occurrence]) &&
          installed_managed_owner_shape_supported(
            Pure(original),
            true,
            model_occurrence=Some(occurrence),
          )
        ) {
        true
      } else {
        match
          (
            @publication_host.prepared_client_composed_infer_occurrences(
              original,
            ),
            @publication_host.prepared_client_serialization_occurrences(
              original,
            ),
          ) {
          (Some([occurrence]), [(task, step)]) => {
            let coordinates = @publication_host.client_infer_occurrence_coordinates(
              occurrence,
            )
            task == coordinates.1 && step < coordinates.2
          }
          _ => false
        }
      }
    Effect(original) =>
      match
        @publication_host.prepared_client_effect_infer_occurrence(original) {
        None => false
        Some(occurrence) => {
          let serialized = @publication_host.prepared_client_effect_serialization_occurrences(
            original,
          )
          match serialized {
            [] => true
            [(task, step)] => {
              let coordinates = @publication_host.client_infer_occurrence_coordinates(
                occurrence,
              )
              task == coordinates.1 && step < coordinates.2
            }
            _ => false
          }
        }
      }
  }
  guard count >= 0 &&
    container_count >= 0 &&
    count.to_int64() + container_count.to_int64() <= 2147483647L &&
    material_profile &&
    request_model_material_collection_bytes(count + container_count)
    is Some(collections) else {
    return Err(Installed(Unsupported))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        reserve_request_model_graph_construction(
          owner, input, prepared, collections,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard request_model_material_body_bytes(count, wire_at) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // Every distinct original reader grows for its actual inputs before entry.
      // Retain the actual capacity debit; drop only this completed quote alias.
      // The later Graph/Scope grows independently from that SAME actual debit.
      owner.program_domain_quote = None
      owner.phase = original_phase
      Ok(())
    },
    () => {
      if owner.phase == Selecting {
        owner.phase = if original_phase == EffectPlanReserved {
          EffectBodyFailed
        } else {
          ProgramBodyFailed
        }
      }
    },
  )
}
