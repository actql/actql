///|
/// Fund complete UPDATE/STORE original DATA on its SAME checked Request before
/// the Host constructs the outer JSON. No new preparation, compiler, selection
/// or authority is issued. Each actually retained projection coexists; scratch
/// is a sequential peak. A refused grow leaves the original debit/cleanup live.
pub fn[I] reserve_request_effect_original_material(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientEffectComputation,
  count : Int,
  wire_at : (Int) -> String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let (old_r, old_e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      guard @publication_host.client_effect_target_original_envelope_capacity(
          count, wire_at,
        )
        is Some(required) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_retained_bytes(required),
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_execution_bytes(required),
          1L,
        )
        is Some(e) else {
        return Err(Policy)
      }
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_effect is Some(current) &&
        physical_equal(current, prepared) else {
        return Err(ForeignOriginal)
      }
      let result = @resources.reserve_working_preparation_phase(
        capacity,
        input,
        r,
        Int64::max(old_e, e),
      )
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_effect is Some(current) &&
        physical_equal(current, prepared) else {
        return Err(ForeignOriginal)
      }
      result.map_err(issue => Capacity(issue))
    },
    () => if owner.phase == Selecting { owner.phase = EffectPlanReserved },
  )
}
