///|
// Fact input/expansion/temp/result25H5R55W, original work-bound Some1H2W,
// two conversions2H10W/tariffs10H20W, returned pair2H1R3W, original body
// add/phase quote/storage8H2R14W:48H8R104W.
let parameter_binding_inventory_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 48L,
  reference_slots: 8L,
  scalar_words: 104L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Selection extent/final/Some alternatives8H2R17W, conversion/tariff6H15W,
// returned pair2H1R3W and original body/phase/storage8H2R14W:24H5R49W.
let parameter_binding_selection_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 24L,
  reference_slots: 5L,
  scalar_words: 49L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// SAME preflight recipe67H13R147W, binding Origin/sum6H1R13W and original
// descriptor copy/Some2H4R1W:75H18R161W. Three conversions3H15W/tariffs
//15H30W, temporary sums2H4W, returned pair2H1R3W, original body/phase/
//storage8H2R14W:105H21R227W.
let parameter_binding_preflight_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 105L,
  reference_slots: 21L,
  scalar_words: 227L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Value's SAME complete recipe136H27R301W, entry/final7H1R16W, default
// alternative3H4R4W, binding Issue7H1R16W, two sums10H2R20W, path23H2R53W,
// SAME constraints33H4R76W, binding Origin/sum6H1R13W, original Value copy/
//Some2H4R3W and result2H4R1W:229H50R503W. Four conversions4H20W/tariffs
//20H40W, normalization sum1H2W, returned pair2H1R3W and original body/
//phase/storage8H2R14W:264H53R582W. Sequential constructor peak, not values.
let parameter_binding_value_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 264L,
  reference_slots: 53L,
  scalar_words: 582L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let parameter_binding_quote_controls : @execution.PreparationRepresentationUnits = {
  record_headers: Int64::max(
    parameter_binding_value_quote_controls.record_headers,
    Int64::max(
      parameter_binding_preflight_quote_controls.record_headers,
      Int64::max(
        parameter_binding_selection_quote_controls.record_headers,
        Int64::max(
          parameter_binding_inventory_quote_controls.record_headers,
          parameter_binding_header_quote_controls.record_headers,
        ),
      ),
    ),
  ),
  reference_slots: Int64::max(
    parameter_binding_value_quote_controls.reference_slots,
    Int64::max(
      parameter_binding_preflight_quote_controls.reference_slots,
      Int64::max(
        parameter_binding_selection_quote_controls.reference_slots,
        Int64::max(
          parameter_binding_inventory_quote_controls.reference_slots,
          parameter_binding_header_quote_controls.reference_slots,
        ),
      ),
    ),
  ),
  scalar_words: Int64::max(
    parameter_binding_value_quote_controls.scalar_words,
    Int64::max(
      parameter_binding_preflight_quote_controls.scalar_words,
      Int64::max(
        parameter_binding_selection_quote_controls.scalar_words,
        Int64::max(
          parameter_binding_inventory_quote_controls.scalar_words,
          parameter_binding_header_quote_controls.scalar_words,
        ),
      ),
    ),
  ),
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Mechanical projection of constructor-owned units. The unchanged common
// tariff remains the sole conversion; this adds no policy or extra dimension.
fn parameter_binding_units(
  value : @execution.PreparationRepresentationUnits,
) -> Int64? {
  @execution.preparation_representation_cost(value)
}

///|
fn parameter_binding_inventory_construction_bytes(
  original : @parameters.BindingReadInput,
) -> (Int64, Int64)? {
  guard @parameters.binding_read_construction_inventory(original) is Some(v) &&
    parameter_binding_units({
      record_headers: v.retained.record_headers,
      reference_slots: v.retained.reference_slots,
      scalar_words: v.retained.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(r) &&
    parameter_binding_units({
      record_headers: v.temporary.record_headers,
      reference_slots: v.temporary.reference_slots,
      scalar_words: v.temporary.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(t) else {
    return None
  }
  Some((r, t))
}

///|
fn parameter_binding_step_construction_bytes(
  original : @parameters.BindingReadInput,
  step : @parameters.BindingReadPhase,
) -> (Int64, Int64)? {
  match step {
    @parameters.BindingSelection => {
      guard @parameters.binding_selection_construction_extent(original)
        is Some(v) &&
        parameter_binding_units({
          record_headers: v.record_headers,
          reference_slots: v.reference_slots,
          scalar_words: v.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(r) else {
        return None
      }
      Some((r, 0L))
    }
    @parameters.BindingPreflight => {
      guard @parameters.binding_preflight_construction_inventory(original)
        is Some(v) &&
        parameter_binding_units({
          record_headers: v.traversal.record_headers,
          reference_slots: v.traversal.reference_slots,
          scalar_words: v.traversal.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(a) &&
        parameter_binding_units({
          record_headers: v.refusal.record_headers,
          reference_slots: v.refusal.reference_slots,
          scalar_words: v.refusal.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(b) else {
        return None
      }
      let normalization : @execution.PreparationRepresentationUnits = match
        v.key_normalization {
        None =>
          {
            record_headers: 0L,
            reference_slots: 0L,
            scalar_words: 0L,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          }
        Some(n) =>
          {
            record_headers: n.record_headers,
            reference_slots: n.reference_slots,
            scalar_words: n.scalar_words,
            owned_utf16_units: n.owned_utf16_units,
            owned_wire_bytes: 0L,
          }
      }
      guard parameter_binding_units(normalization) is Some(n) &&
        @execution.checked_preparation_add_product(a, b, 1L) is Some(t) &&
        @execution.checked_preparation_add_product(t, n, 1L) is Some(t) else {
        return None
      }
      Some((0L, t))
    }
    @parameters.BindingValue => {
      guard @parameters.binding_value_construction_inventory(original)
        is Some(v) &&
        parameter_binding_units({
          record_headers: v.returned.record_headers,
          reference_slots: v.returned.reference_slots,
          scalar_words: v.returned.scalar_words,
          owned_utf16_units: match v.value {
            None => 0L
            Some(x) => x.returned_utf16_units
          },
          owned_wire_bytes: 0L,
        })
        is Some(r) &&
        parameter_binding_units({
          record_headers: v.constraints.record_headers,
          reference_slots: v.constraints.reference_slots,
          scalar_words: v.constraints.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(c) else {
        return None
      }
      let temporary = match v.value {
        None => 0L
        Some(value) => {
          let normalization : @execution.PreparationRepresentationUnits = match
            value.normalization {
            None =>
              {
                record_headers: 0L,
                reference_slots: 0L,
                scalar_words: 0L,
                owned_utf16_units: 0L,
                owned_wire_bytes: 0L,
              }
            Some(n) =>
              {
                record_headers: n.record_headers,
                reference_slots: n.reference_slots,
                scalar_words: n.scalar_words,
                owned_utf16_units: n.owned_utf16_units,
                owned_wire_bytes: 0L,
              }
          }
          guard parameter_binding_units({
              record_headers: value.temporary.record_headers,
              reference_slots: value.temporary.reference_slots,
              scalar_words: value.temporary.scalar_words,
              owned_utf16_units: value.temporary_utf16_units,
              owned_wire_bytes: 0L,
            })
            is Some(t) &&
            parameter_binding_units(normalization) is Some(n) &&
            @execution.checked_preparation_add_product(t, n, 1L) is Some(t) else {
            return None
          }
          t
        }
      }
      Some((r, Int64::max(c, temporary)))
    }
    _ => None
  }
}

///|
fn[I, P] parameter_binding_phase_quote(
  owner : ClientParameterBindingPreparation[I, P],
  body : Int64,
  temporary : Int64,
) -> (Int64, Int64)? {
  guard @execution.checked_preparation_add_product(body, temporary, 1L)
    is Some(peak) &&
    @execution.checked_preparation_add_product(
      parameter_binding_initial_bytes, peak, 1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(owner.base_retained, total, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(owner.base_execution, total, 1L)
    is Some(e) else {
    return None
  }
  let quote = match owner.quote {
    None => (r, e)
    Some((prior_r, prior_e)) => (Int64::max(r, prior_r), Int64::max(e, prior_e))
  }
  Some(quote)
}

///|
fn[I, P] parameter_binding_retained_quote(
  owner : ClientParameterBindingPreparation[I, P],
) -> (Int64, Int64)? {
  guard @execution.checked_preparation_add_product(
      parameter_binding_initial_bytes,
      owner.body_bytes,
      1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(owner.base_retained, total, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(owner.base_execution, total, 1L)
    is Some(e) else {
    return None
  }
  Some((r, e))
}
