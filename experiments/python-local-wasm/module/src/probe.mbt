// Experimental primitive callback bridge, not a public Client ABI or Run Owner.
///|
fn request_input(ticket : Int) -> Int = "python_probe" "request_input"

///|
fn input_byte(ticket : Int, index : Int) -> Int = "python_probe" "input_byte"

///|
fn output_byte(ticket : Int, value : Int) -> Unit = "python_probe" "output_byte"

///|
#export_name("probe_request")
pub fn request(ticket : Int) -> Int {
  request_input(ticket)
}

///|
#export_name("probe_transfer")
pub fn transfer(ticket : Int, length : Int) -> Int {
  if length < 0 || length > 16384 {
    return -1
  }
  let input = Bytes::makei(length, index => input_byte(ticket, index).to_byte())
  match @source.parse_json_bytes_preserving(input, {
    max_input_bytes: 16384,
    max_nodes: 1024,
    max_depth: 32,
  }) {
    Err(_) => -2
    Ok(node) => {
      try {
        let value = @canonical.from_source(node, 1024, 32, 16384, data_keys=true)
        let wire = @canonical.stringify_value(value, 16384, 32, 16384)
        let bytes = @utf8.encode(wire)
        for byte in bytes {
          output_byte(ticket, byte.to_int())
        }
        bytes.length()
      } catch {
        _ => -3
      }
    }
  }
}

///|
#export_name("probe_cancel_eligible")
pub fn cancel_eligible(bits : Int) -> Int {
  // The caller supplies observations; the common Owner alone judges eligibility.
  if @host.confirm_client_run_cancellation({
    cancellation_requested: (bits land 1) != 0,
    model_fence_required: (bits land 2) != 0,
    model_fenced: (bits land 4) != 0,
    unresolved_model_calls: (bits land 8) != 0,
    unresolved_effects: (bits land 16) != 0,
    reconciliation_required: (bits land 32) != 0,
    publication_committed: (bits land 64) != 0,
    physical_stop_confirmed: (bits land 128) != 0,
    cleanup_confirmed: (bits land 256) != 0,
    revision_unchanged: (bits land 512) != 0,
  }) { 1 } else { 0 }
}
