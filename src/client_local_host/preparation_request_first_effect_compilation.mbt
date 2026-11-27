///|
/// Build the first installed compiler and normalization originals for the
/// exact selected Plan, with measured artifact extents on the same Request.
pub fn[I] construct_request_first_effect_compilation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[
  (
    @publication_host.ClientEffectCompilation,
    @publication_host.ClientEffectNormalization,
  ),
  ClientRequestPreparationIssue,
] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_effect is Some(prepared) &&
    physical_equal(prepared, plan.prepared) &&
    plan.model is None &&
    plan.direct_occurrences is Some(occurrences) &&
    @publication_host.client_direct_acquisition_occurrence_count(occurrences) >
    0 else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      fn current() -> Bool {
        owner.phase == Selecting &&
        owner.input is Some(actual) &&
        physical_equal(actual, input) &&
        owner.compiled_effect is Some(current) &&
        physical_equal(current, prepared)
      }
      let (r, e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      guard @encode.text_writer_construction_inventory(1024, 32, 8)
        is Some(writer) &&
        @execution.preparation_representation_cost({
          record_headers: writer.record_headers,
          reference_slots: writer.reference_slots,
          scalar_words: writer.scalar_words,
          owned_utf16_units: writer.owned_utf16_units,
          owned_wire_bytes: 0L,
        })
        is Some(writer_bytes) &&
        request_effect_material_body_layout(
          1024,
          32,
          8,
          true,
          purpose="normalization_read",
        )
        is Some((normalization_r, normalization_e)) &&
        @execution.checked_preparation_add_product(r, normalization_r, 1L)
        is Some(normalized_r) &&
        @execution.checked_preparation_add_product(e, normalization_r, 1L)
        is Some(normalized_e) &&
        @execution.checked_preparation_add_product(
          normalized_e,
          normalization_e + writer_bytes,
          1L,
        )
        is Some(normalization_peak) else {
        return Err(Policy)
      }
      match
        @resources.reserve_working_preparation_phase(
          capacity, input, normalized_r, normalization_peak,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      guard current() else { return Err(ForeignOriginal) }
      let refusal : Ref[ClientRequestPreparationIssue?] = Ref(None)
      let retained : Ref[Int64?] = Ref(None)
      let manifests = @publication_host.packaged_client_compilation_manifests()
      let compiled = @publication_host.issue_first_local_effect_compilation(
        prepared,
        manifests,
        [],
        before_compilation=Some(normalization => {
          let quote = fund_measured_first_effect_compilation(
            capacity, input, prepared, normalization, manifests, normalized_r, normalized_e,
            normalization_peak, current,
          )
          match quote {
            Err(issue) => {
              refusal.val = Some(issue)
              false
            }
            Ok(bytes) => {
              retained.val = Some(bytes)
              true
            }
          }
        }),
      )
      if refusal.val is Some(issue) {
        return Err(issue)
      }
      guard compiled is Ok(original) &&
        retained.val is Some(retained) &&
        @execution.checked_preparation_add_product(normalized_r, retained, 1L)
        is Some(r) &&
        @execution.checked_preparation_add_product(normalized_e, retained, 1L)
        is Some(e) else {
        return Err(Policy)
      }
      guard current() else { return Err(ForeignOriginal) }
      // The measurement and compiler scratch no longer escape their calls.
      @resources.reconcile_current_working_preparation_phase(
        capacity, input, r, e,
      )
      .map_err(issue => ClientRequestPreparationIssue::Capacity(issue))
      .map(_ => original)
    },
    () => if owner.phase == Selecting { owner.phase = EffectPlanReserved },
  )
}

///|
fn[I] fund_measured_first_effect_compilation(
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  input : I,
  prepared : @publication_host.PreparedClientEffectComputation,
  normalization : @publication_host.ClientEffectNormalization,
  manifests : @publication_host.ClientCompilationManifests,
  retained_base : Int64,
  execution_base : Int64,
  normalization_peak : Int64,
  current : () -> Bool,
) -> Result[Int64, ClientRequestPreparationIssue] {
  let limits : @publication_host.ClientPureCompilationLimits = {
    max_facts: 1000,
    max_witnesses: 1000,
    max_wire_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }
  guard current() &&
    @publication_host.client_first_file_effect_compilation_measurement(
      prepared, normalization,
    )
    is Some(original) &&
    @publication_host.prepared_client_effect_measurement_storage(
      original, limits,
    )
    is Ok(units) &&
    @execution.preparation_representation_cost(units) is Some(measurement) else {
    return Err(Policy)
  }
  match
    @resources.reserve_working_preparation_phase(
      capacity,
      input,
      retained_base + measurement,
      Int64::max(normalization_peak, execution_base + measurement),
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard current() else { return Err(ForeignOriginal) }
  guard @publication_host.measure_prepared_client_effect_compilation_construction(
      original,
      manifests,
      @publication_host.client_standard_values_sequence_limits(),
      limits,
    )
    is Ok(geometry) &&
    program_artifact_construction_extents(
      @publication_host.client_effect_compilation_construction_geometry(
        geometry,
      ),
    )
    is Some((retained, scratch)) &&
    @execution.checked_preparation_add_product(
      retained_base + measurement,
      retained,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      execution_base + measurement,
      retained + scratch,
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  match
    @resources.reserve_working_preparation_phase(
      capacity,
      input,
      r,
      Int64::max(normalization_peak, e),
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard current() else { return Err(ForeignOriginal) }
  Ok(retained)
}
