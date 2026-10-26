///|
/// The selected standard JSON Source implementation's codec rejection bounds.
/// Metadata responses are declared by the installed sequence; the checked
/// original Run still owns real attempts, transfer and preparation admission.
/// The URI bound covers percent-encoded object, field and cursor text plus
/// the original origin and fixed path/query syntax. It grants no HTTP use.
pub fn installed_json_source_reader_profile(
  metadata_responses : Int,
  origin_units : Int,
) -> Array[Int]? {
  if metadata_responses < 0 || origin_units < 0 {
    return None
  }
  let record = installed_record_effect_profile()
  let requests = record[2].to_int64() + metadata_responses.to_int64()
  // The existing Site issuer's finite use law, not a whole-Run budget.
  if requests > 10000L {
    return None
  }
  let total = requests * record[7].to_int64()
  let cursor_bytes = 4L * record[15].to_int64()
  let target = origin_units.to_int64() +
    9L * (2L * record[5].to_int64() + record[15].to_int64()) +
    3L * record[4].to_int64() +
    128L
  if total > 2147483647L || cursor_bytes > 2147483647L || target > 2147483647L {
    return None
  }
  // Sixteen existing reader fields, then seven installation/schema bounds.
  Some([
    record[7],
    total.to_int(),
    record[10],
    record[11],
    record[2],
    record[2],
    requests.to_int(),
    record[2],
    cursor_bytes.to_int(),
    record[13],
    target.to_int(),
    record[12],
    record[13],
    record[16],
    record[10],
    record[18],
    record[4],
    record[3],
    record[5],
    record[0],
    record[16],
    record[10],
    record[20],
  ])
}
