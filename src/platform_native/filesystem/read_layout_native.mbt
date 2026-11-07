///|
extern "C" fn read_layout_field_ffi(field : Int) -> Int64 = "actql_native_filesystem_read_layout_field"

///|
extern "C" fn write_layout_field_ffi(field : Int) -> Int64 = "actql_native_filesystem_write_layout_field"

///|
#borrow(root)
extern "C" fn root_diagnostic_ceiling_ffi(root : Root) -> Int = "actql_native_filesystem_root_diagnostic_ceiling"

///|
/// The SAME Root's selected bound, without a read, callback or new authority.
/// Legacy unbounded Roots cannot supply a finite child-construction inventory.
pub fn Root::diagnostic_ceiling(self : Self) -> Int? {
  let limit = root_diagnostic_ceiling_ffi(self)
  if limit > 0 {
    Some(limit)
  } else {
    None
  }
}

///|
/// Read the existing C Owner's actual fields without opening a Root/Reader,
/// allocating an external object, performing I/O or adopting a byte profile.
pub fn native_filesystem_read_layout() -> NativeFilesystemReadLayout? {
  Some({
    root_payload_bytes: read_layout_field_ffi(0),
    reader_payload_bytes: read_layout_field_ffi(1),
    observation_payload_bytes: read_layout_field_ffi(3),
    acquisition_payload_bytes: read_layout_field_ffi(4),
    external_object_overhead_bytes: read_layout_field_ffi(2),
  })
}

///|
/// Read actual Writer payload/header facts before its constructor is entered.
/// No path, descriptor, external object or physical holding is acquired here.
pub fn native_filesystem_write_layout() -> NativeFilesystemWriteLayout? {
  Some({
    writer_payload_bytes: write_layout_field_ffi(0),
    external_object_overhead_bytes: write_layout_field_ffi(1),
  })
}
