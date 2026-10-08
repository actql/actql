// Compile the existing received-report relationships for both Client consumers.
// These rules admit wire evidence; they do not check or execute a query.
const rules = {
  unique_document_ids: {
    js: `if (documents.size !== report.inputs.length) return false;`,
    native: `if documents.size() != inputs.length() { return false }`,
  },
  input_document_kinds: {
    js: `const program = documents.get('program');
    if (program ? program.kind !== 'structured' || documents.has('source') ||
        documents.has('parameter_declarations') : documents.get('source')?.kind !== 'text') return false;
    if (report.inputs.some(input => input.document_id !== 'source' && input.kind !== 'structured')) return false;`,
    native: `if documents.get("program") is Some(program) {
      guard program is Object(fields) &&
        fields.get("kind") == Some(Json::string("structured")) &&
        !documents.contains("source") && !documents.contains("parameter_declarations") else { return false }
    } else {
      guard documents.get("source") is Some(Object(source)) &&
        source.get("kind") == Some(Json::string("text")) else { return false }
    }
    for id, input in documents {
      guard input is Object(fields) else { return false }
      if id != "source" && fields.get("kind") != Some(Json::string("structured")) { return false }
    }`,
  },
  locations_match_input: {
    js: `for (const reason of occurrences) {
      const location = reason.location;
      if (!location) continue;
      const input = documents.get(location.document_id);
      if (!input || input.revision !== location.revision || input.kind !== location.kind) return false;
      if (location.kind === 'text' && (location.start_byte > location.end_byte ||
          location.end_byte > input.byte_length)) return false;
    }`,
    native: `for reason in occurrences {
      guard reason is Object(fields) else { return false }
      if fields.get("location") is Some(location) {
        guard location is Object(location_fields) &&
          location_fields.get("document_id") is Some(String(id)) &&
          documents.get(id) is Some(Object(input)) &&
          input.get("revision") == location_fields.get("revision") &&
          input.get("kind") == location_fields.get("kind") else { return false }
        if location_fields.get("kind") == Some(Json::string("text")) {
          guard location_fields.get("start_byte") is Some(Number(start, ..)) &&
            location_fields.get("end_byte") is Some(Number(end, ..)) &&
            input.get("byte_length") is Some(Number(bytes, ..)) else { return false }
          if start > end || end > bytes { return false }
        }
      }
    }`,
  },
  fix_targets_match_exact_eof: {
    js: `for (const reason of occurrences) for (const fix of reason.fixes ?? []) {
      const input = documents.get(fix.target.document_id);
      if (!input || input.kind !== 'text' || input.revision !== fix.target.revision) return false;
      if (fix.edits.some(edit => edit.start_byte !== input.byte_length ||
          edit.end_byte !== input.byte_length)) return false;
    }`,
    native: `for reason in occurrences {
      guard reason is Object(fields) else { return false }
      if fields.get("fixes") is Some(fixes) {
        guard fixes is Array(fixes) else { return false }
        for fix in fixes {
          guard fix is Object(fix_fields) &&
            fix_fields.get("target") is Some(Object(target)) &&
            target.get("document_id") is Some(String(id)) &&
            documents.get(id) is Some(Object(input)) &&
            input.get("kind") == Some(Json::string("text")) &&
            input.get("revision") == target.get("revision") &&
            input.get("byte_length") is Some(Number(bytes, ..)) &&
            fix_fields.get("edits") is Some(Array(edits)) else { return false }
          for edit in edits {
            guard edit is Object(edit_fields) &&
              edit_fields.get("start_byte") is Some(Number(start, ..)) &&
              edit_fields.get("end_byte") is Some(Number(end, ..)) else { return false }
            if start != bytes || end != bytes { return false }
          }
        }
      }
    }`,
  },
};

export function checkReportRules(registry) {
  const selected = registry.check_report_rules;
  if (!Array.isArray(selected) || selected.length !== Object.keys(rules).length ||
      new Set(selected).size !== selected.length ||
      selected.some(name => !Object.hasOwn(rules, name))) {
    throw new Error('InvalidClientCheckReportRules');
  }
  return selected;
}

export function jsCheckReportRules(selected) {
  return `export const validCheckOutcomeContract = value => {
  if (!validCheckOutcomeShape(value)) return false;
  const report = value.report ?? value.partial_report;
  if (!report) return true;
  const documents = new Map(report.inputs.map(input => [input.document_id, input]));
  const occurrences = [...report.reasons, ...report.requirements, ...report.coverage.limits];
  ${selected.map(name => rules[name].js).join('\n  ')}
  return true;
};\n`;
}

export function nativeCheckReportRules(selected) {
  return `///|
fn wire_check_report_contract(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  let report = match fields.get("report") {
    Some(report) => Some(report)
    None => fields.get("partial_report")
  }
  guard report is Some(report) else { return true }
  guard report is Object(report_fields) &&
    report_fields.get("inputs") is Some(Array(inputs)) &&
    report_fields.get("reasons") is Some(Array(reasons)) &&
    report_fields.get("requirements") is Some(Array(requirements)) &&
    report_fields.get("coverage") is Some(Object(coverage)) &&
    coverage.get("limits") is Some(Array(limits)) else { return false }
  let documents : Map[String, Json] = Map([])
  for input in inputs {
    guard input is Object(fields) && fields.get("document_id") is Some(String(id)) else { return false }
    documents[id] = input
  }
  let occurrences = reasons.copy()
  for reason in requirements { occurrences.push(reason) }
  for reason in limits { occurrences.push(reason) }
  ${selected.map(name => rules[name].native).join('\n  ')}
  true
}\n`;
}
