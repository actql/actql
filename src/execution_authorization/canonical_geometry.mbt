///|
// Finite representation bounds observed by the existing identifier-validation
// pass. They neither reserve memory nor authorize an Account decision.
priv struct AccountCanonicalBounds {
  nodes : Int
  utf16_units : Int
  encoded_bytes : Int
}

///|
priv struct AccountCanonicalGeometry {
  mut nodes : Int64
  mut utf16_units : Int64
  mut encoded_bytes : Int64
}

///|
fn new_account_canonical_geometry() -> AccountCanonicalGeometry {
  { nodes: 0L, utf16_units: 0L, encoded_bytes: 0L, }
}

///|
// Existing canonical writer/parser counters use Int. Saturation keeps that
// representation ceiling; the original writer still checks actual usage.
fn account_representation_limit(value : Int64) -> Int {
  Int64::min(value, 2147483647L).to_int()
}

///|
fn AccountCanonicalGeometry::observe(
  self : AccountCanonicalGeometry,
  nodes : Int64,
  units : Int64,
  bytes : Int64,
) -> Unit {
  self.nodes = account_representation_limit(self.nodes + nodes).to_int64()
  self.utf16_units = account_representation_limit(self.utf16_units + units).to_int64()
  self.encoded_bytes = account_representation_limit(self.encoded_bytes + bytes).to_int64()
}

///|
fn AccountCanonicalGeometry::observe_object(
  self : AccountCanonicalGeometry,
  fields : Int,
  key_units : Int,
) -> Unit {
  // Braces, commas, colon/key quotes and at most six JSON bytes per key unit.
  self.observe(
    1L,
    key_units.to_int64(),
    2L +
    Int::max(0, fields - 1).to_int64() +
    3L * fields.to_int64() +
    6L * key_units.to_int64(),
  )
}

///|
fn AccountCanonicalGeometry::observe_array(
  self : AccountCanonicalGeometry,
  count : Int,
) -> Unit {
  self.observe(1L, 0L, 2L + Int::max(0, count - 1).to_int64())
}

///|
fn AccountCanonicalGeometry::observe_text(
  self : AccountCanonicalGeometry,
  value : String,
) -> Unit {
  // Every caller has already checked the SAME NFC/LF original. This is the
  // JSON escape bound, not a normalization expansion or an ASCII assumption.
  self.observe(
    1L,
    value.length().to_int64(),
    2L + 6L * value.length().to_int64(),
  )
}

///|
fn AccountCanonicalGeometry::observe_true(
  self : AccountCanonicalGeometry,
) -> Unit {
  self.observe(1L, 0L, 4L)
}

///|
fn AccountCanonicalGeometry::bounds(
  self : AccountCanonicalGeometry,
) -> AccountCanonicalBounds {
  {
    nodes: self.nodes.to_int(),
    utf16_units: self.utf16_units.to_int(),
    encoded_bytes: self.encoded_bytes.to_int(),
  }
}

///|
// Wire-order comparison precedes typed admission. Reuse the original wire
// size and the canonical Owner's normalization expansion, without another
// parse/tree walk. Typed admission obtains tighter geometry in its existing
// NFC validation pass. Neither path allocates a buffer of this maximum size.
fn account_canonical_wire_bounds(input_bytes : Int) -> AccountCanonicalBounds {
  let units = @canonical.nfc_lf_retained_output_units(input_bytes.to_int64()).unwrap()
  {
    nodes: input_bytes,
    utf16_units: account_representation_limit(units),
    encoded_bytes: account_representation_limit(
      input_bytes.to_int64() + 6L * units,
    ),
  }
}

///|
// Only the two fixed, independently pinned bootstrap profile documents use
// these existing bounds. All selected Account documents supply observed DATA.
let account_profile_literal_bounds : AccountCanonicalBounds = {
  nodes: CANONICAL_MAX_NODES,
  utf16_units: CANONICAL_MAX_BYTES,
  encoded_bytes: CANONICAL_MAX_BYTES,
}
