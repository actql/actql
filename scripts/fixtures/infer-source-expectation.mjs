// Authored from the adopted INFER output contract, not compiler/reader output.
export const source = "SELECT DISTINCT 'ticket-1' AS id " +
  "|> EXTEND 'urgent' AS text " +
  "|> INFER `model-task:packed-risk.v1` ITEM KEY (id) " +
  'INPUT (text = text) AS assessment';
export const expectedRows = [{assessment: {
  input_key: {id: 'ticket-1'}, outcome: 'ok',
  value: {reason: null, risk: 'high'},
}}];
// Literal id has an eight-byte bound; outcome is the common unbounded String
// contract. The ModelTask's closed object is nullable in outcomes publication.
export const expectedColumns = [{name: 'assessment', contract: {
  type: 'object', nullable: false, additional_properties: false, fields: {
    input_key: {type: 'object', nullable: false,
      additional_properties: false, fields: {
        id: {type: 'string', nullable: false, max_utf8_bytes: 8},
      }},
    outcome: {type: 'string', nullable: false},
    value: {type: 'object', nullable: true, additional_properties: false,
      fields: {reason: {type: 'string', nullable: true},
        risk: {type: 'string', nullable: false}}},
  },
}}];
