///|
// One growing borrowed-key connection Map. The owned result String and
// payload-bearing Ok/Some are retained; candidate+decimal suffix are scratch.
// No candidate history, copied source labels, policy or new resource owner.
fn local_mock_control_construction(
  preferred : String,
  sources : Array[(String, String)],
  targets : Array[(String, String)],
) -> AccountConfigurationConstruction? {
  let count = sources.length().to_int64() + targets.length().to_int64() + 1L
  if count > 2147483646L {
    return None
  }
  guard @shape.map_construction_extent(1L, count) is Some(index) &&
    @canonical.nfc_lf_construction_extent(preferred.length()) is Some(nfc) else {
    return None
  }
  Some({
    // String1H; Ok/Some2H2R2W, including their logical tags.
    retained: account_construction_units(
      3L,
      2L,
      2L,
      Int::max(preferred.length(), 30).to_int64(),
    ),
    // Result wrappers2H2R2W, candidate/suffix2H40U; loop/map controls2H2R2W.
    // Canonical validation's normalization coexists with the borrowed-key Map.
    execution: account_construction_units(
      index.record_headers + nfc.record_headers + 6L,
      index.reference_slots + nfc.reference_slots + 4L,
      index.scalar_words + nfc.scalar_words + 4L,
      nfc.owned_utf16_units + 40L,
    ),
  })
}

///|
// Constructor DATA for the existing Mock Account initializer, priced by its
// SAME Account Read. This does not establish a budget, installation or grant.
fn local_mock_inventory_construction(
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_targets : Array[(String, String)],
) -> AccountConfigurationConstruction? {
  guard @shape.map_construction_extent(1L, sources.length().to_int64())
    is Some(source_map) &&
    @shape.map_construction_extent(1L, model_tasks.length().to_int64())
    is Some(task_map) &&
    @shape.map_construction_extent(1L, update_targets.length().to_int64())
    is Some(target_map) else {
    return None
  }
  let mut longest = control_connection.length()
  for pair in sources {
    longest = Int::max(longest, Int::max(pair.0.length(), pair.1.length()))
  }
  if request_target is Some(pair) {
    longest = Int::max(longest, Int::max(pair.0.length(), pair.1.length()))
  }
  guard @canonical.nfc_lf_construction_extent(longest) is Some(nfc) else {
    return None
  }
  Some({
    retained: account_construction_zero,
    execution: account_construction_units(
      source_map.record_headers +
      task_map.record_headers +
      target_map.record_headers +
      nfc.record_headers +
      8L,
      source_map.reference_slots +
      task_map.reference_slots +
      target_map.reference_slots +
      nfc.reference_slots +
      16L,
      source_map.scalar_words +
      task_map.scalar_words +
      target_map.scalar_words +
      nfc.scalar_words +
      8L,
      nfc.owned_utf16_units,
    ),
  })
}

///|
fn local_mock_account_construction(
  subjects : LocalMockAccountSubjects,
  update_targets : Array[(String, String)],
  signing_key_units? : Int? = None,
) -> AccountConfigurationConstruction? {
  let signing_units = match subjects.signing_key_resource {
    Some(value) => Some(value.length())
    None => signing_key_units
  }
  let entries = subjects.sources.length().to_int64() +
    subjects.model_tasks.length().to_int64() +
    update_targets.length().to_int64() +
    2L +
    (if subjects.request_target is Some(_) { 1L } else { 0L }) +
    (if signing_units is Some(_) { 1L } else { 0L })
  if entries > 2147483647L {
    return None
  }
  // The same Account codec builds four selector positions and fixed tokens
  // per entry. Count each actual borrowed name occurrence, including every
  // distinct target, before duplicate maps, sorting or policy arrays exist.
  guard @counts.checked_nonnegative_add_product(
      subjects.account_id.length().to_int64(),
      entries,
      subjects.principal.length().to_int64() +
      subjects.control_connection.length().to_int64() +
      256L,
    )
    is Some(initial_text) else {
    return None
  }
  let mut text = initial_text
  let mut longest = Int::max(
    subjects.account_id.length(),
    Int::max(subjects.principal.length(), subjects.control_connection.length()),
  )
  for value in subjects.sources {
    guard @counts.checked_nonnegative_add_product(
        text,
        value.0.length().to_int64() + value.1.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, Int::max(value.0.length(), value.1.length()))
  }
  for task in subjects.model_tasks {
    guard @counts.checked_nonnegative_add_product(
        text,
        task.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, task.length())
  }
  for target in update_targets {
    guard @counts.checked_nonnegative_add_product(
        text,
        target.0.length().to_int64() + target.1.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, Int::max(target.0.length(), target.1.length()))
  }
  if subjects.request_target is Some(value) {
    guard @counts.checked_nonnegative_add_product(
        text,
        value.0.length().to_int64() + value.1.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, Int::max(value.0.length(), value.1.length()))
  }
  if signing_units is Some(units) {
    guard @counts.checked_nonnegative_add_product(text, units.to_int64(), 1L)
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, units)
  }
  guard @canonical.nfc_lf_retained_output_units(text) is Some(normalized) &&
    @canonical.nfc_lf_construction_scratch_extent(Int::max(longest, 128))
    is Some(nfc) &&
    @shape.collection_construction_extent({
      records: 96L * entries + 64L,
      record_references: 256L * entries + 128L,
      record_words: 128L * entries + 64L,
      // Two additional backing arrays cover the target copy and stable-sort
      // workspace. The original input vector is already held by the caller.
      reference_arrays: 80L * entries + 34L,
      reference_items: 256L * entries +
      128L +
      2L * update_targets.length().to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 16L * entries + 4L,
      map_entries: 64L * entries + 16L,
    })
    is Some(forest) else {
    return None
  }
  // Native Json + canonical frozen forests, compiled selectors, keyed/sorted
  // entries and the returned canonical String coexist. The fixed standard
  // policy uses no exclusions, so overlap has one pair region, not an n² forest.
  guard @counts.checked_nonnegative_add_product(512L * entries, normalized, 6L)
    is Some(output_bound) else {
    return None
  }
  let output = account_representation_limit(output_bound)
  guard @encode.text_writer_construction_inventory(
      output,
      account_representation_limit(64L * entries + 16L),
      CANONICAL_MAX_DEPTH,
    )
    is Some(writer) else {
    return None
  }
  let retained = account_construction_units(1L, 0L, 0L, output.to_int64())
  Some({
    retained,
    execution: account_construction_units(
      forest.record_headers + nfc.record_headers + writer.record_headers + 32L,
      forest.reference_slots +
      nfc.reference_slots +
      writer.reference_slots +
      64L,
      forest.scalar_words + nfc.scalar_words + writer.scalar_words + 128L,
      4L * normalized + nfc.owned_utf16_units + writer.owned_utf16_units,
      wire=256L,
    ),
  })
}

///|
/// Constructor DATA before a physical key exists. The caller supplies the
/// existing key codec's actual finite output-name bound, never a fake key,
/// grant or Account. The installing Host still constructs/adopts the real key.
pub fn local_mock_account_construction_before_signing(
  subjects : LocalMockAccountSubjects,
  update_targets : Array[(String, String)],
  signing_key_units : Int,
) -> AccountConfigurationConstruction? {
  if subjects.signing_key_resource is Some(_) || signing_key_units < 1 {
    return None
  }
  local_mock_account_construction(
    subjects,
    update_targets,
    signing_key_units=Some(signing_key_units),
  )
}
