///|
test "structured Program diagnostic pointers preserve owned keys and missing parents" {
  let body = "{\"stages\":[{}],\"é/😀~\":null}"
  assert_eq(
    check_program_original_pointer(body, [Key("stages"), Index(0), Key("steps")]),
    Some("/stages/0"),
  )
  assert_eq(check_program_original_pointer(body, [Key("absent")]), Some(""))
  // Admission owns the canonical key; the location retains the original spelling.
  assert_eq(
    check_program_original_pointer(body, [Key("é/😀~")]),
    Some("/é~1😀~0"),
  )
}
