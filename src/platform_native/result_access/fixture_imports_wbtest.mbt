///|
/// Moon has no conditional imports. Native-only fixture imports stay typed on
/// portable targets without executing or counting Native fixtures there.
#cfg(not(target="native"))
#warnings("-unused_value")
fn retain_native_fixture_imports() -> Unit {
  ignore(@json.stringify_value)
  ignore(@encode.writer)
  ignore(@sqlite.load_library)
  ignore(@filesystem.open_root)
  ignore(@payload.prepare_publication_payload_request)
  ignore(@sha.hex)
  ignore(
    @source.parse_json_bytes_preserving(b"null", {
      max_input_bytes: 4,
      max_nodes: 1,
      max_depth: 0,
    }),
  )
  ignore(@utf8.decode(b"") catch { _ => "" })
  ignore(@env.now)
}
