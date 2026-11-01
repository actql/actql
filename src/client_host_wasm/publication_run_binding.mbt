///|
/// Check the original physical Run loan behind this publication. This is only
/// a nominal routing fence; current Account read and publisher checks remain
/// in the original RunState export. No admission, state or ACK is issued here.
pub fn validate_publication_run(
  nonce : Int64,
  handle : Int,
  run : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(publication) &&
    value.runs.get(run) is Some(original_run) &&
    value.run_invocations.get(publication.source) is Some(invocation) &&
    value.computes.get(invocation.compute) is Some(compute) &&
    stored_compute_original_run(value, compute) is Some(compute_run) &&
    physical_equal(original_run, compute_run) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  match publication_commit_export_view(value, publication, current.account) {
    Err(code) => code
    Ok(_) => 0
  }
}
