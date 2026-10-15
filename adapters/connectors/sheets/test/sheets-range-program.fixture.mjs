// Independently authored Program: acquire a current range Ref, join one
// explicitly typed rectangle, and approve it through the ordinary Command.
export function rangeProgram(contract, rows, connectorId = 'sheet-book') {
  const rowFields = {text: {type: 'string', nullable: false},
    number: {type: 'number', nullable: false}, flag: {type: 'boolean', nullable: false}};
  return JSON.stringify({version: 'actql/0.1', id: 'sheets-range-update', stages: [{
    id: 'capture', inputs: {range: {connector: connectorId, resource: 'range_target'}},
    steps: [{filter: 'true', as: 'scanned'}, {select: ['target'], as: 'out'}],
    results: {r: {from: 'out', fields: ['target']}},
  }, {id: 'replace', inputs: {captured: {result: {stage: 'capture', result: 'r'}}},
    steps: [{values: {schema: {rows: {type: 'array', nullable: false, max_items: 2,
      items: {type: 'object', nullable: false, fields: rowFields}}},
    rows: [{rows}]}, as: 'values'},
    {from: 'values', cross_join: {with: 'captured', max_output_rows: 1,
      select: {target: 'right.target', rows: 'left.rows'}}, as: 'out'}],
    results: {r: {from: 'out', fields: ['target', 'rows']}, answer: {from: 'out', fields: ['rows']}},
    effects: {replace: {command: {from: {result: 'r'}, target: {field: 'target'}, contract,
      input: {rows: {field: 'rows'}}}}},
  }], results: {answer: {from: {stage: 'replace', result: 'answer'}}}});
}
