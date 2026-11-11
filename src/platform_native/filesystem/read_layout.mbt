///|
/// Static representation facts of this compiled filesystem implementation.
/// Payload sizes exclude referenced path/diagnostic/chunk storage. External
/// overhead is the pinned runtime's object header and finalizer pointer, not
/// allocator charge, descriptor custody, retirement, authority or a baseline.
/// The returned facts record and caller scratch require separate funding.
pub(all) struct NativeFilesystemReadLayout {
  root_payload_bytes : Int64
  reader_payload_bytes : Int64
  observation_payload_bytes : Int64
  acquisition_payload_bytes : Int64
  external_object_overhead_bytes : Int64
} derive(Eq, Debug)

///|
/// Static representation of this compiled implementation's original Writer.
/// Names, diagnostics and append bytes are separate simultaneous backing; the
/// borrowed Root is not copied. These facts neither create a Writer nor fund it.
pub(all) struct NativeFilesystemWriteLayout {
  writer_payload_bytes : Int64
  external_object_overhead_bytes : Int64
} derive(Eq, Debug)
