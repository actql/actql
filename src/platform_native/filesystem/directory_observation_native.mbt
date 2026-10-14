///|
priv type NativeObservedDirectoryStat

///|
/// Named namespace facts captured only through the existing opened Root.
/// This transient physical value is not restoration, authority or compatibility.
struct NativeDirectoryObservation {
  root : Root
  stat : NativeObservedDirectoryStat
}

///|
#borrow(root)
extern "C" fn observe_directory_ffi(root : Root) -> NativeObservedDirectoryStat = "actql_native_filesystem_observe_directory"

///|
#borrow(stat)
extern "C" fn observed_directory_kind_ffi(
  stat : NativeObservedDirectoryStat,
) -> Int = "actql_native_filesystem_observed_directory_kind"

///|
#borrow(root, stat)
extern "C" fn observed_directory_current_ffi(
  root : Root,
  stat : NativeObservedDirectoryStat,
) -> Int = "actql_native_filesystem_observed_directory_current"

///|
fn directory_observation_issue(
  root : Root,
  kind : Int,
) -> NativeFilesystemIssue {
  if kind == 3 {
    Cleanup(decode_diagnostic_message(root_error_ffi(root)))
  } else {
    GenerationMismatch
  }
}

///|
/// Check the Root's retained path by a bounded no-follow walk, compare the actual
/// named directory and opened Root, and acknowledge all temporary closes.
pub fn Root::observe_directory(
  self : Root,
) -> Result[NativeDirectoryObservation, NativeFilesystemIssue] {
  let stat = observe_directory_ffi(self)
  let kind = observed_directory_kind_ffi(stat)
  if kind == 0 {
    Ok({ root: self, stat, })
  } else {
    Err(directory_observation_issue(self, kind))
  }
}

///|
pub fn NativeDirectoryObservation::check_current(
  self : NativeDirectoryObservation,
) -> Result[Unit, NativeFilesystemIssue] {
  let kind = observed_directory_current_ffi(self.root, self.stat)
  if kind == 0 {
    Ok(())
  } else {
    Err(directory_observation_issue(self.root, kind))
  }
}
