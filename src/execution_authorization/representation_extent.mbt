///|
/// Readonly retained representation facts from the original Account admission
/// Owner. They neither authorize access nor adopt allocator widths or a funding
/// profile. Array capacity is the selected backend's exposed backing capacity;
/// in particular, JS capacity is not an observation of its engine's heap.
/// Shared records and Strings are conservatively counted per occurrence.
/// Parse, canonicalization, overlap/decision workspace, original file buffers,
/// caller contexts and the returned measurement record are separate holdings.
pub(all) struct AccountConfigurationRepresentationExtent {
  configuration_records : Int64
  bootstrap_records : Int64
  entry_records : Int64
  region_records : Int64
  dimension_records : Int64
  dynamic_array_records : Int64
  dynamic_backing_slots : Int64
  fixed_array_records : Int64
  fixed_backing_slots : Int64
  strings : Int64
  text_utf16_units : Int64
  original_byte_buffers : Int64
  original_bytes : Int64
} derive(Eq, Debug)

///|
/// Observe the admitted immutable fields without copying arrays, re-admitting
/// wire or issuing another authority. Admission's existing entry/selector/name
/// bounds keep these Int64 occurrence counters within range. A rejected raw
/// configuration cannot use this API to claim a retained Account extent.
pub fn AdmittedAccountConfiguration::representation_extent(
  self : AdmittedAccountConfiguration,
) -> AccountConfigurationRepresentationExtent {
  let mut bootstrap_records = 0L
  let mut region_records = 0L
  let mut dimension_records = 0L
  let mut dynamic_array_records = 1L
  let mut dynamic_backing_slots = self.entries.capacity().to_int64()
  let mut fixed_array_records = 0L
  let mut fixed_backing_slots = 0L
  let mut strings = 2L
  let mut text_utf16_units = self.account_id.length().to_int64() +
    self.configuration_cid.length().to_int64()
  match self.bootstrap {
    None => ()
    Some(profile) => {
      bootstrap_records = 1L
      strings += 3L
      text_utf16_units += profile.profile_id.length().to_int64() +
        profile.profile_version.length().to_int64() +
        profile.profile_cid.length().to_int64()
    }
  }
  for entry in self.entries {
    strings += 1L
    text_utf16_units += entry.entry_id.length().to_int64()
    dynamic_array_records += 1L
    dynamic_backing_slots += entry.exclusions.capacity().to_int64()
    // Visit the original scope and exclusions without building a scope array.
    for index in -1..<entry.exclusions.length() {
      let region = if index < 0 { entry.scope } else { entry.exclusions[index] }
      region_records += 1L
      fixed_array_records += 1L
      fixed_backing_slots += region.dims.length().to_int64()
      for dimension in region.dims {
        dimension_records += 1L
        let values = match dimension {
          Finite(values) => values
          Cofinite(values) => values
        }
        dynamic_array_records += 1L
        dynamic_backing_slots += values.capacity().to_int64()
        strings += values.length().to_int64()
        for value in values {
          text_utf16_units += value.length().to_int64()
        }
      }
    }
  }
  {
    configuration_records: 1L,
    bootstrap_records,
    entry_records: self.entries.length().to_int64(),
    region_records,
    dimension_records,
    dynamic_array_records,
    dynamic_backing_slots,
    fixed_array_records,
    fixed_backing_slots,
    strings,
    text_utf16_units,
    original_byte_buffers: if self.original_wire is Some(_) {
      1L
    } else {
      0L
    },
    original_bytes: match self.original_wire {
      Some(bytes) => bytes.length().to_int64()
      None => 0L
    },
  }
}
