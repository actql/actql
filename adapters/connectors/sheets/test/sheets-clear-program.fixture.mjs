// Independently authored canonical Command. Its target is the acquired original
// range Ref; the empty input cannot borrow update payload or a hidden row ID.
export function clearProgram(contract, connectorId = 'sheet-book') {
  return JSON.stringify({version: 'actql/0.1', id: 'sheets-range-clear', stages: [{
    id: 'capture', inputs: {range: {connector: connectorId, resource: 'range_target'}},
    steps: [{filter: 'true', as: 'scanned'}, {select: ['target'], as: 'out'}],
    results: {r: {from: 'out', fields: ['target']}},
  }, {id: 'clear', inputs: {captured: {result: {stage: 'capture', result: 'r'}}},
    steps: [{values: {schema: {receipt: {type: 'string', nullable: false}},
      rows: [{receipt: 'clear-request'}]}, as: 'values'},
    {from: 'values', cross_join: {with: 'captured', max_output_rows: 1,
      select: {target: 'right.target', receipt: 'left.receipt'}}, as: 'out'}],
    results: {r: {from: 'out', fields: ['target', 'receipt']},
      answer: {from: 'out', fields: ['receipt']}},
    effects: {clear: {command: {from: {result: 'r'}, target: {field: 'target'}, contract, input: {}}}},
  }], results: {answer: {from: {stage: 'clear', result: 'answer'}}}});
}
