// Original writable, option-valued and computed Form fields shared by the
// request, standard initialization and loopback provider fixtures.
export const form = {revision: '7', properties: {
  Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT', expression: ''},
  Tags: {code: 'Tags', type: 'MULTI_SELECT', options: {red: {label: 'red', index: '0'}}},
  Computed: {code: 'Computed', type: 'SINGLE_LINE_TEXT', expression: 'server'},
}};
