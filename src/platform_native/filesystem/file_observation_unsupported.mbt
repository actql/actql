///|
type NativeFileObservation

///|
pub fn Writer::replace_observed_file(
  _self : Writer,
  _original : NativeFileObservation,
  _lock : Lock,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Root::observe_file(
  _self : Root,
  _name : String,
) -> Result[NativeFileObservation, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeFileObservation::generation(
  _self : NativeFileObservation,
) -> Result[NativeFileGeneration, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeFileObservation::mode(
  _self : NativeFileObservation,
) -> Result[Int, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeFileObservation::check_current(
  _self : NativeFileObservation,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeFileObservation::open_reader_with_custody(
  _self : NativeFileObservation,
) -> Result[Reader, NativeReaderOpenFailure] {
  Err(reader_open_failure(UnsupportedTarget))
}

///|
pub fn NativeFileObservation::check_reader(
  _self : NativeFileObservation,
  _reader : Reader,
) -> Result[Unit, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}

///|
type NativeObservedComponentMember

///|
pub fn NativeFileObservation::command_component_member(
  _self : NativeFileObservation,
  _kind : Int,
  _source : String,
  _manifest : String,
  _digest : String,
) -> Result[NativeObservedComponentMember, NativeFilesystemIssue] {
  Err(UnsupportedTarget)
}
