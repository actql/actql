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

///|
pub fn Root::open_child_with_custody(
  _self : Root,
  _name : String,
) -> Result[Root, NativeRootOpenFailure] {
  Err({ original_issue: UnsupportedTarget, root: None, })
}
