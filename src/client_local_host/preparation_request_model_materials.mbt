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
// These original readers admit Source/typed contract representations. Borrowed
// input Strings are not copies. Native prompt/retry/backoff/media UTF-8 inputs
// coexist, so their TOTAL backing is retained in addition to active parse
// scratch. No codec ceiling is multiplied by the number of operations.
fn request_model_material_body_bytes(
  count : Int,
  wire_at : (Int) -> String,
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
    guard program_artifact_parse_layout(
        (bytes.to_int(), bytes.to_int(), Int::min(100, bytes.to_int())),
      )
      is Some(parse) &&
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
    guard @execution.checked_preparation_add_product(wire_bytes, bytes, 1L)
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
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(_) &&
    (
      owner.program_domain_compilation_inputs is None ||
      owner.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, _))
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
  let material_profile = if installed_managed_run_shape_supported(
      prepared, true,
    ) ||
    (
      @publication_host.prepared_client_composed_infer_occurrences(prepared)
      is Some([occurrence]) &&
      installed_managed_owner_shape_supported(
        Pure(prepared),
        true,
        model_occurrence=Some(occurrence),
      )
    ) {
    true
  } else {
    match
      (
        @publication_host.prepared_client_composed_infer_occurrences(prepared),
        @publication_host.prepared_client_serialization_occurrences(prepared),
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
        reserve_request_domain_graph_construction(
          owner, input, prepared, collections,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard request_model_material_body_bytes(count, wire_at) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // Every distinct original reader grows for its actual inputs before entry.
      // Retain the actual capacity debit; drop only this completed quote alias.
      // The later Graph/Scope grows independently from that SAME actual debit.
      owner.program_domain_quote = None
      owner.phase = ModelPlanReserved
      Ok(())
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}
