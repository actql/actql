///|
pub fn open_root_in_current_read_context_with_custody(
  _path : String,
  diagnostic_ceiling : Int,
) -> Result[Root, NativeRootOpenFailure] {
  Err({
    original_issue: if diagnostic_ceiling <= 0 {
      InvalidLimit
    } else {
      UnsupportedTarget
    },
    root: None,
  })
}
