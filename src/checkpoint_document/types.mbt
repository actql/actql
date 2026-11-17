///|
/// Finite pure-document parsing/emission controls. These are not Host resource
/// admission, current eligibility, a sealed Checkpoint or signing permission.
pub(all) struct Limits {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)
