import assert from 'node:assert/strict';

// Preserve the author's input bytes. JSON numeric tokens above 2^53 may not
// be materialized as JavaScript Numbers when building the fixture.

const projectFiles = {
  'actql.config.json': `{
  "version": "actql-config/0.1",
  "profile": "mock",
  "connectors": "./connectors.json",
  "model_tasks": "./model-tasks.json",
  "state_dir": "./.actql",
  "mock": {
    "catalog": "./mock/catalog.json",
    "data": "./mock/data.json",
    "answers": {}
  }
}
`,
  'connectors.json': `{
  "version": "actql-connectors/0.1",
  "connections": {
    "salesforce": {
      "connector": "salesforce"
    }
  }
}
`,
  'model-tasks.json': `{
  "version": "actql-model-tasks/0.1",
  "tasks": {},
  "providers": {}
}
`,
} as const;

const mixedProgram = 'ordered-update-delete.program.json';
const mixedData = `{"salesforce":{"Account":{"key":["site","serial"],"rows":[{"label":"before update","serial":9007199254740993,"site":"west"},{"label":"before delete","serial":9007199254740994,"site":"east"},{"label":"retain","serial":9007199254740994,"site":"north"}]},"Proposals":{"key":["site","serial"],"rows":[{"delete_serial":9007199254740994,"delete_site":"east","label":"updated","serial":9007199254740993,"site":"west"}]}},"control":{"unchanged":"outside both collections"}}
`;
const mixedFiles = {...projectFiles, 'mock/data.json': mixedData,
  'mock/catalog.json': `{
  "connections": {
    "salesforce": {
      "views": [
        {
          "resource": "Account",
          "resource_kind": "record",
          "data_classification": "internal",
          "schema": {
            "label": {
              "nullable": false,
              "type": "string"
            },
            "serial": {
              "nullable": false,
              "type": "int64"
            },
            "site": {
              "nullable": false,
              "type": "string"
            }
          },
          "facts": {
            "relation_keys": {
              "candidate_keys": [
                [
                  "site",
                  "serial"
                ]
              ]
            }
          }
        },
        {
          "resource": "Proposals",
          "resource_kind": "record",
          "data_classification": "internal",
          "schema": {
            "label": {
              "nullable": false,
              "type": "string"
            },
            "serial": {
              "nullable": false,
              "type": "int64"
            },
            "site": {
              "nullable": false,
              "type": "string"
            },
            "delete_site": {
              "nullable": false,
              "type": "string"
            },
            "delete_serial": {
              "nullable": false,
              "type": "int64"
            }
          },
          "facts": {
            "relation_keys": {
              "candidate_keys": [
                [
                  "site",
                  "serial"
                ]
              ]
            }
          }
        }
      ],
      "query_aliases": [
        {
          "name": "salesforce.proposals",
          "resource": "Proposals"
        }
      ],
      "data": [
        {
          "resource": "Account",
          "items_path": [
            "salesforce",
            "Account",
            "rows"
          ],
          "key_path": [
            "salesforce",
            "Account",
            "key"
          ],
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          }
        },
        {
          "resource": "Proposals",
          "items_path": [
            "salesforce",
            "Proposals",
            "rows"
          ],
          "key_path": [
            "salesforce",
            "Proposals",
            "key"
          ],
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          }
        }
      ],
      "writes": [
        {
          "resource": "Account",
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          },
          "approval": "required",
          "observe_permission": "fixture:account:observe",
          "operation": "update",
          "writable_fields": [
            "label"
          ],
          "permission": "fixture:account:update",
          "aliases": [
            "salesforce.AccountUpdate"
          ]
        },
        {
          "resource": "Account",
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          },
          "approval": "required",
          "observe_permission": "fixture:account:observe",
          "operation": "delete",
          "permission": "fixture:account:delete",
          "aliases": [
            "salesforce.AccountDelete"
          ]
        }
      ]
    }
  }
}
`,
  [mixedProgram]: `{
  "version": "actql/0.1",
  "id": "fixture.mock-ordered-update-delete",
  "stages": [
    {
      "id": "apply",
      "inputs": {
        "proposals": {
          "connector": "salesforce",
          "resource": "Proposals"
        }
      },
      "from": "proposals",
      "steps": [
        {
          "select": [
            "site",
            "serial",
            "delete_site",
            "delete_serial",
            "label"
          ],
          "as": "selected"
        }
      ],
      "results": {
        "rows": {
          "from": "selected",
          "fields": [
            "site",
            "serial",
            "delete_site",
            "delete_serial",
            "label"
          ]
        }
      },
      "effects": {
        "a_update": {
          "update": {
            "target": "connector://salesforce/Account",
            "from": {
              "result": "rows"
            },
            "mapping": "mapping:salesforce/Account/update-064e0591f4c574a7.v1",
            "match_tuple": [
              {
                "target_field": "site",
                "result_field": "site"
              },
              {
                "target_field": "serial",
                "result_field": "serial"
              }
            ],
            "set": {
              "label": {
                "field": "label"
              }
            }
          }
        },
        "b_delete": {
          "delete": {
            "target": "connector://salesforce/Account",
            "from": {
              "result": "rows"
            },
            "mapping": "mapping:salesforce/Account/delete-bfda941e34806894.v1",
            "match_tuple": [
              {
                "target_field": "site",
                "result_field": "delete_site"
              },
              {
                "target_field": "serial",
                "result_field": "delete_serial"
              }
            ]
          }
        }
      }
    }
  ],
  "results": {
    "main": {
      "from": {
        "stage": "apply",
        "result": "rows"
      }
    }
  }
}
`} as const;

const upsertProgram = 'ordered-upsert.program.json';
const upsertData = `{
  "salesforce": {
    "Account": {"key":["site","serial"],"rows":[{"label":"before","serial":9007199254740993,"site":"west"},{"label":"keep","serial":9007199254740994,"site":"north"}]},
    "Proposals": {"key":["site","serial"],"rows":[{"label":"updated","serial":9007199254740993,"site":"west"},{"label":"inserted","serial":9007199254740994,"site":"east"}]}
  },
  "control":{"unchanged":"outside both collections"}
}
`;
const upsertFiles = {...projectFiles, 'mock/data.json': upsertData,
  'mock/catalog.json': `{
  "connections": {
    "salesforce": {
      "views": [
        {
          "resource": "Account",
          "resource_kind": "record",
          "data_classification": "internal",
          "schema": {
            "label": {
              "nullable": false,
              "type": "string"
            },
            "serial": {
              "nullable": false,
              "type": "int64"
            },
            "site": {
              "nullable": false,
              "type": "string"
            }
          },
          "facts": {
            "relation_keys": {
              "candidate_keys": [
                [
                  "site",
                  "serial"
                ]
              ]
            }
          }
        },
        {
          "resource": "Proposals",
          "resource_kind": "record",
          "data_classification": "internal",
          "schema": {
            "label": {
              "nullable": false,
              "type": "string"
            },
            "serial": {
              "nullable": false,
              "type": "int64"
            },
            "site": {
              "nullable": false,
              "type": "string"
            }
          },
          "facts": {
            "relation_keys": {
              "candidate_keys": [
                [
                  "site",
                  "serial"
                ]
              ]
            }
          }
        }
      ],
      "query_aliases": [
        {
          "name": "salesforce.proposals",
          "resource": "Proposals"
        }
      ],
      "data": [
        {
          "resource": "Account",
          "items_path": [
            "salesforce",
            "Account",
            "rows"
          ],
          "key_path": [
            "salesforce",
            "Account",
            "key"
          ],
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          }
        },
        {
          "resource": "Proposals",
          "items_path": [
            "salesforce",
            "Proposals",
            "rows"
          ],
          "key_path": [
            "salesforce",
            "Proposals",
            "key"
          ],
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          }
        }
      ],
      "writes": [
        {
          "resource": "Account",
          "operation": "upsert",
          "primary_identity": {
            "fields": [
              "site",
              "serial"
            ],
            "kind": "tuple"
          },
          "writable_fields": [
            "label"
          ],
          "permission": "fixture:account:upsert",
          "observe_permission": "fixture:account:observe",
          "approval": "required",
          "aliases": [
            "salesforce.Account"
          ]
        }
      ]
    }
  }
}
`,
  [upsertProgram]: `{
  "version": "actql/0.1",
  "id": "fixture.mock-ordered-upsert",
  "stages": [
    {
      "id": "apply",
      "inputs": {
        "proposals": {
          "connector": "salesforce",
          "resource": "Proposals"
        }
      },
      "from": "proposals",
      "steps": [
        {
          "select": [
            "site",
            "serial",
            "label"
          ],
          "as": "selected"
        }
      ],
      "results": {
        "rows": {
          "from": "selected",
          "fields": [
            "site",
            "serial",
            "label"
          ]
        }
      },
      "effects": {
        "mutate": {
          "upsert": {
            "target": "connector://salesforce/Account",
            "mapping": "mapping:salesforce/Account/upsert-e23aa27688427d0e.v1",
            "from": {
              "result": "rows"
            },
            "key_tuple": [
              {
                "target_field": "site",
                "result_field": "site"
              },
              {
                "target_field": "serial",
                "result_field": "serial"
              }
            ],
            "set": {
              "label": {
                "field": "label"
              }
            }
          }
        }
      }
    }
  ],
  "results": {
    "main": {
      "from": {
        "stage": "apply",
        "result": "rows"
      }
    }
  }
}
`} as const;

const target = 'connector://salesforce/Account';
const west = ['west', '9007199254740993'] as const;
const east = ['east', '9007199254740994'] as const;
const northSerial = '9007199254740994';

function accountRow(label: string, [site, serial]: readonly [string, string]) {
  return {label, serial, site};
}

function present(value: unknown) {
  return {state: 'present', value} as const;
}

const absent = {state: 'absent'} as const;

function parseOriginalFile(bytes: string) {
  return JSON.parse(bytes, (key, value: unknown, context?: {source: string}) => {
    if (key !== 'serial' && key !== 'delete_serial') return value;
    assert(typeof value === 'number' && context && /^-?(0|[1-9][0-9]*)$/u.test(context.source),
      'Physical Int64 must use its canonical numeric token');
    return context.source;
  });
}

function assertApprovedFile(bytes: string, before: string, expectedAccount: readonly unknown[]) {
  const expected = parseOriginalFile(before);
  expected.salesforce.Account.rows = expectedAccount;
  assert.deepEqual(parseOriginalFile(bytes), expected,
    'Only the selected Account rows may change; the control and Proposals must remain intact');
}

export function orderedFileMockProjects() {
  return [
    {
      name: 'ordered-update-delete',
      files: mixedFiles,
      before: mixedData,
      programFile: mixedProgram,
      resultName: 'main',
      rows: [{site: west[0], serial: west[1], delete_site: east[0], delete_serial: east[1], label: 'updated'}],
      effects: [
        {kind: 'update', target, rows: [{identity: west,
          before: present(accountRow('before update', west)), after: present({label: 'updated'})}]},
        {kind: 'delete', target, rows: [{identity: east,
          before: present(accountRow('before delete', east)), after: absent}]},
      ],
      checkApprovedFile(bytes: string) {
        assertApprovedFile(bytes, mixedData, [accountRow('updated', west), accountRow('retain', ['north', northSerial])]);
      },
    },
    {
      name: 'ordered-upsert',
      files: upsertFiles,
      before: upsertData,
      programFile: upsertProgram,
      resultName: 'main',
      rows: [accountRow('updated', west), accountRow('inserted', east)],
      effects: [{kind: 'upsert', target, rows: [
        {identity: west, before: present(accountRow('before', west)), after: present({label: 'updated'})},
        {identity: east, before: absent, after: present({label: 'inserted'})},
      ]}],
      checkApprovedFile(bytes: string) {
        assertApprovedFile(bytes, upsertData, [accountRow('updated', west), accountRow('keep', ['north', northSerial]),
          accountRow('inserted', east)]);
      },
    },
  ] as const;
}
