///|
/// Select a Site candidate by known duration and then by its stable key.
/// Negative return values are adapter-facing validation results, not durable
/// protocol state.
pub fn select_site_candidate_index(
  durations : Array[Int64],
  selection_keys : Array[String],
) -> Int {
  if durations.length() != selection_keys.length() {
    return -2
  }
  let mut selected = -1
  for index = 0; index < durations.length(); index = index + 1 {
    if durations[index] < 0L || selection_keys[index].length() == 0 {
      return -2
    }
    for prior = 0; prior < index; prior = prior + 1 {
      if selection_keys[prior] == selection_keys[index] {
        return -3
      }
    }
    if selected < 0 ||
      durations[index] < durations[selected] ||
      (
        durations[index] == durations[selected] &&
        selection_keys[index].lexical_compare(selection_keys[selected]) < 0
      ) {
      selected = index
    }
  }
  selected
}
