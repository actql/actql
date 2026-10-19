///|
// Observe only this failed original after its cleanup returned. Counts are
// immutable diagnostic DATA, never release, capacity or inactivity evidence.
// Unknown observation remains unavailable; no child is acquired or retried.
fn LocalCommandPreparationOriginal::cleanup_read_observation(
  self : LocalCommandPreparationOriginal,
) -> String {
  guard self.host is Some(host) && self.read is Some(read) else {
    return "; read-census-unavailable"
  }
  match host.observe_domain_original_read_cleanup(read) {
    Err(_) => "; read-census-unavailable"
    Ok(value) =>
      "; read-census(users=" +
      value.users.to_string() +
      ",active=" +
      value.active.to_string() +
      ",generic-extents=" +
      value.generic_live_extents.to_string() +
      ",generic-pages=" +
      value.generic_live_pages.to_string() +
      ",managed-pages=" +
      value.managed_live_pages.to_string() +
      ",managed-blocks=" +
      value.managed_live_blocks.to_string() +
      ",managed-requested=" +
      value.managed_requested_bytes.to_string() +
      ",managed-slot-bytes=" +
      value.managed_payload_capacity_bytes.to_string() +
      ",pending-extents=" +
      value.pending_extents.to_string() +
      ",pending-pages=" +
      value.pending_pages.to_string() +
      ",minimum-request=" +
      value.minimum_managed_request.to_string() +
      ",maximum-request=" +
      value.maximum_managed_request.to_string() +
      ",closing=" +
      (if value.closing { "1" } else { "0" }) +
      ",thread-read=" +
      (if value.calling_thread_read { "1" } else { "0" }) +
      ",thread-owned=" +
      (if value.calling_thread_owned { "1" } else { "0" }) +
      ",context-payload=" +
      value.context_payload_bytes.to_string() +
      ")"
  }
}
