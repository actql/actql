// Generated from the registered Client–Host machine contract.
// Run: node scripts/generate-client-host-wire.mjs --write
const schemas = {
  "run_ref": {
    "type": "object",
    "required": [
      "tenantId",
      "authorityScopeCid",
      "runDefinitionCid"
    ],
    "additionalProperties": false,
    "properties": {
      "tenantId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "authorityScopeCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "runDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    }
  },
  "connection": {
    "type": "object",
    "required": [
      "mode",
      "owner",
      "consentRefs",
      "runners"
    ],
    "additionalProperties": false,
    "properties": {
      "mode": {
        "enum": [
          "local",
          "remote",
          "hybrid"
        ]
      },
      "owner": {
        "enum": [
          "local",
          "remote",
          "cloud"
        ]
      },
      "consentRefs": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "runners": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "movementPolicyRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "cloudConnectionRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "profile": {
    "type": "object",
    "required": [
      "version",
      "mode",
      "owner",
      "durability",
      "scopeRef",
      "capabilities",
      "limits"
    ],
    "additionalProperties": false,
    "properties": {
      "version": {
        "const": "actql-client-host/0.1"
      },
      "mode": {
        "enum": [
          "local",
          "remote",
          "hybrid"
        ]
      },
      "owner": {
        "enum": [
          "local",
          "remote",
          "cloud"
        ]
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "scopeRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "capabilities": {
        "type": "array",
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "limits": {
        "type": "object",
        "required": [
          "maxReadWireBytes",
          "maxRowWireBytes",
          "maxRowRetainedValueBytes",
          "maxRetainedValueBytes",
          "maxRows",
          "maxBatchRows",
          "maxBatchRetainedValueBytes"
        ],
        "additionalProperties": false,
        "properties": {
          "maxReadWireBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRowWireBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRowRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRows": {
            "type": "integer",
            "minimum": 1
          },
          "maxBatchRows": {
            "type": "integer",
            "minimum": 1
          },
          "maxBatchRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          }
        }
      }
    }
  },
  "admission": {
    "type": "object",
    "required": [
      "ref",
      "durability",
      "revision"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "tenantId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "tenantId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "runDefinitionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "revision": {
        "type": "integer",
        "minimum": 0
      }
    }
  },
  "lookup_found": {
    "type": "object",
    "required": [
      "kind",
      "requestId",
      "ref",
      "durability",
      "lookupExpiresAt"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "found"
      },
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "ref": {
        "type": "object",
        "required": [
          "tenantId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "tenantId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "runDefinitionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "lookupExpiresAt": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "lookup_not_found": {
    "type": "object",
    "required": [
      "kind"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "not_found"
      }
    }
  },
  "lookup_unknown": {
    "type": "object",
    "required": [
      "kind",
      "reason"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "unknown"
      },
      "reason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "submit_preparation_error": {
    "type": "object",
    "required": [
      "code"
    ],
    "additionalProperties": false,
    "properties": {
      "code": {
        "enum": [
          "ClientProgramInvalidInput",
          "ClientParametersInvalid",
          "ClientParametersTooLarge",
          "ClientProgramUnsupported",
          "ClientProgramNeedsInputs",
          "ClientProgramRejected"
        ]
      }
    }
  },
  "run_state": {
    "type": "object",
    "required": [
      "version",
      "run_id",
      "status",
      "updated_at",
      "next_action",
      "result_available",
      "result_availability"
    ],
    "additionalProperties": false,
    "properties": {
      "version": {
        "const": "actql-run-state/0.1"
      },
      "run_id": {
        "type": "string",
        "minLength": 1
      },
      "status": {
        "enum": [
          "preparing",
          "running",
          "waiting_checkpoint",
          "resuming",
          "needs_reconciliation",
          "succeeded",
          "failed",
          "cancelled"
        ]
      },
      "updated_at": {
        "type": "string",
        "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
      },
      "checkpoint": {
        "type": "object",
        "required": [
          "checkpoint_id",
          "checkpoint_cid",
          "kind"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpoint_id": {
            "type": "string",
            "minLength": 1
          },
          "checkpoint_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "enum": [
              "run_scope",
              "read_access",
              "data_egress",
              "cost_scope",
              "effect_set"
            ]
          }
        }
      },
      "next_action": {
        "oneOf": [
          {
            "type": "object",
            "required": [
              "kind",
              "checkpoint_id"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "resolve_checkpoint"
              },
              "checkpoint_id": {
                "type": "string",
                "minLength": 1
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "effects"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "reconcile"
              },
              "effects": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "results"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "read_result"
              },
              "results": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "results"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "refresh_availability"
              },
              "results": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "none"
              }
            }
          }
        ]
      },
      "result_available": {
        "type": "boolean"
      },
      "terminal_error": {
        "type": "object",
        "required": [
          "code",
          "message"
        ],
        "additionalProperties": false,
        "properties": {
          "code": {
            "type": "string",
            "pattern": "^ACTQL_E_[A-Z0-9_]+$"
          },
          "message": {
            "type": "string",
            "minLength": 1
          }
        }
      },
      "result_availability": {
        "type": "object",
        "minProperties": 1,
        "additionalProperties": {
          "type": "object",
          "required": [
            "state",
            "observed_at",
            "reason"
          ],
          "additionalProperties": false,
          "properties": {
            "state": {
              "enum": [
                "available",
                "unavailable",
                "unknown"
              ]
            },
            "observed_at": {
              "type": "string",
              "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
            },
            "reason": {
              "enum": [
                "confirmed_present",
                "retention_expired",
                "deleted",
                "policy_unavailable",
                "integrity_failed",
                "not_published",
                "store_query_failed",
                "clock_uncertain",
                "verification_pending"
              ]
            },
            "cause_cid": {
              "type": "string",
              "pattern": "^sha256:[0-9a-f]{64}$"
            }
          },
          "allOf": [
            {
              "if": {
                "required": [
                  "state"
                ],
                "properties": {
                  "state": {
                    "const": "available"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "const": "confirmed_present"
                  }
                }
              }
            },
            {
              "if": {
                "required": [
                  "state"
                ],
                "properties": {
                  "state": {
                    "const": "unavailable"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "enum": [
                      "retention_expired",
                      "deleted",
                      "policy_unavailable",
                      "integrity_failed",
                      "not_published"
                    ]
                  }
                }
              }
            },
            {
              "if": {
                "required": [
                  "state"
                ],
                "properties": {
                  "state": {
                    "const": "unknown"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "enum": [
                      "store_query_failed",
                      "clock_uncertain",
                      "verification_pending"
                    ]
                  }
                }
              }
            }
          ]
        },
        "propertyNames": {
          "minLength": 1
        }
      }
    },
    "allOf": [
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "waiting_checkpoint"
            }
          }
        },
        "then": {
          "required": [
            "checkpoint"
          ],
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind",
                "checkpoint_id"
              ],
              "properties": {
                "kind": {
                  "const": "resolve_checkpoint"
                }
              }
            }
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "needs_reconciliation"
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind",
                "effects"
              ],
              "properties": {
                "kind": {
                  "const": "reconcile"
                }
              }
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "succeeded"
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind"
              ],
              "properties": {
                "kind": {
                  "enum": [
                    "read_result",
                    "refresh_availability",
                    "none"
                  ]
                }
              }
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "enum": [
                "preparing",
                "running",
                "resuming",
                "failed",
                "cancelled"
              ]
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind"
              ],
              "properties": {
                "kind": {
                  "const": "none"
                }
              }
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      }
    ]
  }
};
const operationKeys = {
  "connect": [
    "connection"
  ],
  "submit": [
    "connection",
    "requestId",
    "kind",
    "input",
    "parameters"
  ],
  "attach": [
    "connection",
    "ref"
  ],
  "lookup-request": [
    "connection",
    "requestId"
  ],
  "status": [
    "connection",
    "ref"
  ],
  "wait": [
    "connection",
    "ref",
    "until"
  ],
  "cancel": [
    "connection",
    "ref"
  ],
  "reconcile": [
    "connection",
    "ref"
  ],
  "read": [
    "connection",
    "ref",
    "resultName",
    "format",
    "attemptId"
  ],
  "delivery-attempt": [
    "connection",
    "ref",
    "resultName",
    "attemptId"
  ]
};

function valid(value, schema) {
  if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1) return false;
  if (schema.not && valid(value, schema.not)) return false;
  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;
  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (typeof value === 'string' &&
      ((schema.minLength !== undefined && [...value].length < schema.minLength) ||
        (schema.maxLength !== undefined && value.length > schema.maxLength) ||
        (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value))))
    return false;
  if (schema.type === 'string') return typeof value === 'string';
  if (schema.type === 'integer') return Number.isSafeInteger(value) &&
    (schema.minimum === undefined || value >= schema.minimum) &&
    (schema.maximum === undefined || value <= schema.maximum);
  if (schema.type === 'boolean') return typeof value === 'boolean';
  if (schema.type === 'array') return Array.isArray(value) &&
    (schema.minItems === undefined || value.length >= schema.minItems) &&
    value.every(item => valid(item, schema.items)) &&
    (!schema.uniqueItems || new Set(value).size === value.length);
  if (schema.type === 'object' || schema.properties || schema.required) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    if (schema.minProperties !== undefined &&
        Object.keys(value).length < schema.minProperties) return false;
    if (schema.propertyNames && Object.keys(value).some(key =>
        !valid(key, schema.propertyNames))) return false;
    if (schema.additionalProperties === false &&
        Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;
    if (schema.additionalProperties &&
        typeof schema.additionalProperties === 'object' &&
        Object.entries(value).some(([key, item]) =>
          !Object.hasOwn(schema.properties ?? {}, key) &&
          !valid(item, schema.additionalProperties))) return false;
    return Object.entries(schema.properties ?? {}).every(([key, field]) =>
      !Object.hasOwn(value, key) || valid(value[key], field));
  }
  return true;
}

export const clientHostOperations = Object.freeze(Object.keys(operationKeys));
export const clientHostRequestKeys = operation => (Object.hasOwn(operationKeys, operation) ? operationKeys[operation] : undefined);
export const validRunRefShape = value => valid(value, schemas.run_ref);
export const validConnectionShape = value => valid(value, schemas.connection);
export const validProfileShape = value => valid(value, schemas.profile);
export const validAdmissionShape = value => valid(value, schemas.admission);
export const validLookupFoundShape = value => valid(value, schemas.lookup_found);
export const validLookupNotFoundShape = value => valid(value, schemas.lookup_not_found);
export const validLookupUnknownShape = value => valid(value, schemas.lookup_unknown);
export const validSubmitPreparationErrorShape = value => valid(value, schemas.submit_preparation_error);
export const validRunStateShape = value => valid(value, schemas.run_state);
