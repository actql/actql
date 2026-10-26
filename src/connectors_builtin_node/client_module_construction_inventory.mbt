///|
// Enumerate the SAME composition used by installed_client_family_providers.
// Policies and callback environments are constructed per Run, not shared by
// a profile CID. This projection runs no provider callback or kernel.
fn installed_client_family_construction_inventory() -> @execution.PreparationRepresentationUnits {
  // selected_record_limits: one eleven-scalar record, shared by all families.
  let units : Array[@execution.PreparationRepresentationUnits] = [
    {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 11L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]
  for family in installed_client_family_composition {
    let (headers, references, words) = match family {
      // Five selected policy trees, provider record and two callback
      // environments. Delta's temporary None-policy copies do not escape.
      Graph => (20L, 30L, 53L)
      Events | Vectors => (3L, 5L, 4L)
      TimeSeries | CalendarSeries | IntervalJoin => (4L, 6L, 2L)
      CalendarBucket | AsofJoin | SequenceMatch => (3L, 5L, 2L)
    }
    units.push({
      record_headers: headers,
      reference_slots: references,
      scalar_words: words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  @execution.compose_preparation_representation(units).unwrap()
}

///|
let installed_client_family_construction_retained : @execution.PreparationRepresentationUnits = installed_client_family_construction_inventory()

///|
// map's returned exact-length Array remains beside the Local module's copied
// snapshot until prepare_client_local_configuration returns. Count it apart
// from those four module arrays already held by the initial reservation.
let installed_client_family_construction_array : @execution.PreparationRepresentationUnits = {
  record_headers: 2L,
  reference_slots: installed_client_family_provider_count().to_int64() + 1L,
  scalar_words: 2L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// For one closed Values sequence, family eligibility allocates at most7H14R14W
// (generated step/owner views and bounded scalar pattern carriers). This also
// dominates the disjoint factory peak4H5R11W: Delta snapshot copies plus map's
// callback environment. These callbacks construct no execution/retained rows.
let installed_client_family_construction_temporary : @execution.PreparationRepresentationUnits = {
  record_headers: 7L,
  reference_slots: 14L,
  scalar_words: 14L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}
