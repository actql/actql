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
  ignore(@source.parse_json_bytes_preserving)
  ignore(@utf8.decode)
  ignore(@env.now)
}
