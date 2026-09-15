///|
test "diagnostic readers preserve offset units and absent versus root paths" {
  for
    position in [
      @source.ByteOffset(7),
      @source.Utf16Offset(7),
      @source.Unavailable,
    ] {
    for path in [None, Some([]), Some([@source.Key("x")])] {
      let diagnostic : CheckDiagnostic = {
        category: InvalidInput,
        cause: Program(
          Parse({
            issue: InvalidUnicodeEscape,
            source_path: "same-label",
            location: position,
            path,
          }),
        ),
      }
      let location = diagnostic_location(diagnostic).unwrap()
      assert_eq(diagnostic_location_position(location), position)
      assert_eq(diagnostic_location_path(location), path)
      assert_eq(diagnostic_origin(diagnostic), Some(ProgramDocument))
    }
  }
}
