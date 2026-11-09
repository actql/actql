///|
// The SAME six-field original Mock UPDATE request for warm construction and
// saved application. This mechanical projection grants neither target access
// nor dispatch. Callers fund its existing JSON construction before entry.
fn native_mock_effect_update_request_wire(
  binding : String,
  mapping : String,
  target : Json,
  value : Json,
  before : Json,
  version : String,
) -> Result[String, @row_host.RowHostIssue] {
  local_project_mock_relation_wire({
    "binding": Json::string(binding),
    "mapping": Json::string(mapping),
    "target": target,
    "value": value,
    "version": Json::string(version),
    "before": before,
  })
}
