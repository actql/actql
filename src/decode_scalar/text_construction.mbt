///|
// Call-expanded synchronous Int UTF8 admission controls, not name bytes or
// a per-scalar allocation count. One live scalar extent tuple1H2W, its
// Ok1H1R1W, malformed issue1H1W and Err1H1R1W give4H2R5W.
// Window return sites co-count two flat issues2H2W, four Err4H4R4W
// and two Int64 Ok2H4W:8H4R10W. Int projection Ok/Err add2H1R2W.
// Alternative return sites are conservatively co-counted, never multiplied
// by input length or number of names. Borrowed text, VM and call-stack backing
// stay outside these logical constructor units; no byte buffer is allocated.
let utf8_length_admission_units : (Int64, Int64, Int64) = (14L, 7L, 17L)

///|
/// Immutable owner DATA: record headers, reference slots and scalar words.
/// Returned tuple is the SAME installed descriptor; no scan, allocation,
/// admission verdict, byte tariff or Resource ownership is issued here.
pub fn utf8_length_admission_construction_units() -> (Int64, Int64, Int64) {
  utf8_length_admission_units
}
