///|
priv type Reader

///|
#borrow(reader)
extern "C" fn reader_ready_ffi(reader : Reader) -> Bool = "actql_native_process_image_reader_ready"

///|
#borrow(reader)
extern "C" fn reader_error_ffi(reader : Reader) -> Bytes = "actql_native_process_image_reader_error"

///|
extern "C" fn open_reader_ffi(max_bytes : Int64) -> Reader = "actql_native_process_image_open_reader"

///|
#borrow(reader)
extern "C" fn reader_next_ffi(reader : Reader, max_bytes : Int) -> Int = "actql_native_process_image_reader_next"

///|
#borrow(reader)
extern "C" fn reader_chunk_ffi(reader : Reader) -> Bytes = "actql_native_process_image_reader_chunk"

///|
#borrow(reader)
extern "C" fn reader_eof_ffi(reader : Reader) -> Bool = "actql_native_process_image_reader_eof"

///|
#borrow(reader)
extern "C" fn reader_close_ffi(reader : Reader) -> Int = "actql_native_process_image_reader_close"

///|
fn reader_message(reader : Reader) -> String {
  @utf8.decode_lossy(reader_error_ffi(reader))
}

///|
pub fn current_executable_cid(
  max_bytes : Int64,
  max_chunk_bytes : Int,
) -> Result[String, NativeProcessImageIssue] {
  if max_bytes < 1L || max_chunk_bytes < 1 || max_chunk_bytes > 1048576 {
    return Err(InvalidLimit)
  }
  let reader = open_reader_ffi(max_bytes)
  if !reader_ready_ffi(reader) {
    let message = reader_message(reader)
    ignore(reader_close_ffi(reader))
    if message == "capacity exceeded" {
      return Err(CapacityExceeded)
    }
    return Err(Open(message))
  }
  let hash = @sha.hasher()
  let mut total = 0L
  let mut issue : NativeProcessImageIssue? = None
  while issue is None && !reader_eof_ffi(reader) {
    match reader_next_ffi(reader, max_chunk_bytes) {
      0 => {
        let chunk = reader_chunk_ffi(reader)
        if chunk.length() > max_chunk_bytes {
          issue = Some(Read("oversized process image chunk"))
        } else if chunk.length() == 0 && !reader_eof_ffi(reader) {
          issue = Some(Read("empty process image chunk"))
        } else {
          total += chunk.length().to_int64()
          if total > max_bytes {
            issue = Some(CapacityExceeded)
          } else {
            @sha.update(hash, chunk) catch {
              _ => issue = Some(Read("process image hash failed"))
            }
          }
        }
      }
      _ => issue = Some(Read(reader_message(reader)))
    }
  }
  let close_code = reader_close_ffi(reader)
  match issue {
    Some(value) => Err(value)
    None if close_code != 0 => Err(Close(reader_message(reader)))
    None if total == 0L => Err(EmptyImage)
    None =>
      Ok("sha256:" + @sha.finish_hex(hash)) catch {
        _ => Err(Read("process image hash failed"))
      }
  }
}
