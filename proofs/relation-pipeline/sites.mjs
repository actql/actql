import assert from 'node:assert/strict';
export const sites = [
  { name: 'handoff-wrong-port', path: 'src/connectors/local/relation_chain_input_preparation.mbt',
    before: '            cursor.owner,\n            cursor.step,\n            cursor.port,\n            cursor.owner,\n            output,',
    after: '            cursor.owner,\n            cursor.step,\n            cursor.port + 1,\n            cursor.owner,\n            output,',
    instrument: '        let bound = match\n          @execution.bind_completed_operation_input(',
    trace: '        println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"wrong checked handoff port\\",\\"receiver\\":" + cursor.step.to_string() + ",\\"expectedPort\\":" + cursor.port.to_string() + ",\\"usedPort\\":" + (cursor.port + 1).to_string() + "}")\n',
  },
  { name: 'stable-tie-reversed', path: 'src/execution_relation/bounded_index_sort.mbt',
    before: 'Ok(Some(value)) => value <= 0', after: 'Ok(Some(value)) => value < 0',
  },
];

export function applyMutation(original, site) {
  assert.equal(original.split(site.before).length, 2, 'Mutation site must be unique');
  let changed = original.replace(site.before, site.after);
  if (site.instrument) {
    assert.equal(changed.split(site.instrument).length, 2);
    changed = changed.replace(site.instrument, site.trace + site.instrument);
  }
  return changed;
}
