// Generated from the registered Client–Host machine contract.
// Run: node scripts/generate-client-host-wire.mjs --write
const schemas = {
  "run_ref": {
    "type": "object",
    "required": [
      "namespaceId",
      "authorityScopeCid",
      "runDefinitionCid"
    ],
    "additionalProperties": false,
    "properties": {
      "namespaceId": {
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
    },
    "allOf": [
      {
        "oneOf": [
          {
            "properties": {
              "mode": {
                "const": "remote"
              },
              "owner": {
                "const": "remote"
              },
              "runners": {
                "type": "array",
                "maxItems": 0,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "movementPolicyRef"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "cloudConnectionRef"
                  ]
                }
              }
            ]
          },
          {
            "properties": {
              "mode": {
                "const": "local"
              },
              "owner": {
                "const": "local"
              },
              "runners": {
                "type": "array",
                "maxItems": 0,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "movementPolicyRef"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "cloudConnectionRef"
                  ]
                }
              }
            ]
          },
          {
            "required": [
              "movementPolicyRef",
              "cloudConnectionRef"
            ],
            "properties": {
              "mode": {
                "const": "hybrid"
              },
              "owner": {
                "const": "local"
              }
            }
          },
          {
            "required": [
              "movementPolicyRef"
            ],
            "properties": {
              "mode": {
                "const": "hybrid"
              },
              "owner": {
                "const": "cloud"
              },
              "runners": {
                "type": "array",
                "minItems": 1,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "not": {
              "required": [
                "cloudConnectionRef"
              ]
            }
          }
        ]
      }
    ]
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
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
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
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
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
  "held": {
    "type": "object",
    "required": [
      "kind",
      "requestId",
      "prepareAttemptId",
      "state",
      "durability",
      "lookupExpiresAt"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "held"
      },
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "prepareAttemptId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "state": {
        "enum": [
          "waiting_checkpoint",
          "resuming",
          "ended"
        ]
      },
      "durability": {
        "const": "durable"
      },
      "lookupExpiresAt": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "checkpoint": {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "expiresAt"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
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
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          }
        }
      },
      "endReason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "terminalErrorCode": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    },
    "allOf": [
      {
        "oneOf": [
          {
            "required": [
              "checkpoint"
            ],
            "properties": {
              "state": {
                "const": "waiting_checkpoint"
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "endReason"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "terminalErrorCode"
                  ]
                }
              }
            ]
          },
          {
            "properties": {
              "state": {
                "const": "resuming"
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "endReason"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "terminalErrorCode"
                  ]
                }
              }
            ]
          },
          {
            "required": [
              "endReason"
            ],
            "properties": {
              "state": {
                "const": "ended"
              }
            }
          }
        ]
      }
    ]
  },
  "checkpoint_summary": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "phase",
          "subject",
          "requiredArtifact",
          "reviewProjectionCid",
          "requirements",
          "createdAt",
          "expiresAt",
          "humanSummary"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
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
          },
          "phase": {
            "enum": [
              "preflight",
              "commit"
            ]
          },
          "subject": {
            "oneOf": [
              {
                "type": "object",
                "required": [
                  "kind",
                  "prepareAttemptId",
                  "requestId"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "prepare_attempt"
                  },
                  "prepareAttemptId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "requestId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "runId",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "run_unit"
                  },
                  "runId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "runDefinitionCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  }
                }
              }
            ]
          },
          "requiredArtifact": {
            "type": "object",
            "required": [
              "type",
              "cid"
            ],
            "additionalProperties": false,
            "properties": {
              "type": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                "minLength": 1,
                "maxLength": 256
              },
              "cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "reviewProjectionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "requirements": {
            "type": "array",
            "uniqueItems": true,
            "items": {
              "type": "string",
              "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
              "minLength": 1,
              "maxLength": 256
            }
          },
          "createdAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "humanSummary": {
            "type": "string",
            "maxLength": 1024
          }
        }
      },
      {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "phase",
          "subject",
          "requiredArtifact",
          "reviewProjectionCid",
          "requirements",
          "createdAt",
          "expiresAt",
          "humanSummary",
          "preparedInvocationCid"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "const": "model_invocation"
          },
          "phase": {
            "const": "preflight"
          },
          "subject": {
            "type": "object",
            "required": [
              "kind",
              "runId",
              "runDefinitionCid"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "run_unit"
              },
              "runId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
                "minLength": 1,
                "maxLength": 256
              },
              "runDefinitionCid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "requiredArtifact": {
            "type": "object",
            "required": [
              "type",
              "cid"
            ],
            "additionalProperties": false,
            "properties": {
              "type": {
                "const": "model_invocation_scope"
              },
              "cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "reviewProjectionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "requirements": {
            "type": "array",
            "uniqueItems": true,
            "minItems": 1,
            "maxItems": 1,
            "items": {
              "type": "string",
              "const": "invocation_scope_approved"
            }
          },
          "createdAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "humanSummary": {
            "type": "string",
            "maxLength": 1024
          },
          "preparedInvocationCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      }
    ]
  },
  "checkpoint_review": {
    "type": "object",
    "required": [
      "kind",
      "checkpointCid",
      "artifactCid",
      "byteLength",
      "contentBase64"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "review"
      },
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "artifactCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "byteLength": {
        "type": "integer",
        "minimum": 1
      },
      "contentBase64": {
        "type": "string",
        "pattern": "^[A-Za-z0-9+/]+={0,2}$",
        "minLength": 1
      }
    }
  },
  "resolve_item": {
    "type": "object",
    "required": [
      "checkpointCid",
      "resolutionWire",
      "approvalEvidenceWire"
    ],
    "additionalProperties": false,
    "properties": {
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resolutionWire": {
        "type": "string",
        "minLength": 1,
        "maxLength": 16384
      },
      "approvalEvidenceWire": {
        "type": "string",
        "maxLength": 16384
      }
    }
  },
  "resolve_result": {
    "type": "object",
    "required": [
      "checkpointCid",
      "status"
    ],
    "additionalProperties": false,
    "properties": {
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "status": {
        "enum": [
          "committed",
          "duplicate",
          "conflicting",
          "expired",
          "cancelled",
          "invalid"
        ]
      },
      "decision": {
        "enum": [
          "approved",
          "rejected"
        ]
      },
      "resolutionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
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
  "cancellation": {
    "type": "object",
    "required": [
      "ref",
      "kind",
      "revision"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
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
      "kind": {
        "enum": [
          "accepted",
          "already_requested",
          "already_terminal"
        ]
      },
      "revision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 2147483647
      }
    }
  },
  "request_cancellation": {
    "type": "object",
    "required": [
      "requestId",
      "kind"
    ],
    "additionalProperties": false,
    "properties": {
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "kind": {
        "enum": [
          "accepted",
          "already_requested",
          "already_terminal"
        ]
      },
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
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
      "revision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 2147483647
      }
    }
  },
  "resource_listing": {
    "type": "object",
    "required": [
      "resourceConnection",
      "observationCid",
      "resources",
      "snapshotComplete",
      "snapshotTruncated",
      "resultTruncated"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resources": {
        "type": "array",
        "items": {
          "type": "object",
          "required": [
            "name",
            "outcome"
          ],
          "additionalProperties": false,
          "properties": {
            "name": {
              "type": "string",
              "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
              "minLength": 1,
              "maxLength": 256
            },
            "outcome": {
              "type": "string",
              "pattern": "^[a-z_]+$",
              "minLength": 1,
              "maxLength": 64
            }
          }
        }
      },
      "snapshotComplete": {
        "type": "boolean"
      },
      "snapshotTruncated": {
        "type": "boolean"
      },
      "resultTruncated": {
        "type": "boolean"
      }
    }
  },
  "resource_inspection": {
    "type": "object",
    "required": [
      "resourceConnection",
      "resource",
      "observationCid",
      "status"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "resource": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "status": {
        "enum": [
          "ready",
          "catalog_required"
        ]
      },
      "reason": {
        "enum": [
          "listing_truncated",
          "not_visible",
          "not_observed",
          "not_found",
          "describe_unavailable"
        ]
      },
      "summaryJson": {
        "type": "string",
        "minLength": 2,
        "maxLength": 1048576
      }
    }
  },
  "resource_peek": {
    "type": "object",
    "required": [
      "resourceConnection",
      "resource",
      "observationCid",
      "fields",
      "rowsJson",
      "limited"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "resource": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "fields": {
        "type": "array",
        "uniqueItems": true,
        "minItems": 1,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "rowsJson": {
        "type": "string",
        "minLength": 2,
        "maxLength": 4194304
      },
      "limited": {
        "type": "boolean"
      }
    }
  },
  "result_description": {
    "type": "object",
    "required": [
      "ref",
      "resultName",
      "programDefinitionCid",
      "resultDefinitionCid",
      "resultArtifactCid",
      "resultSchemaCid",
      "columns",
      "serialization"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
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
      "resultName": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "programDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultArtifactCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultSchemaCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "columns": {
        "type": "array",
        "minItems": 1,
        "items": {
          "type": "object",
          "required": [
            "name",
            "contract"
          ],
          "additionalProperties": false,
          "properties": {
            "name": {
              "type": "string",
              "minLength": 1
            },
            "contract": {
              "$ref": "value_contract"
            }
          }
        }
      },
      "serialization": {
        "type": "object",
        "required": [
          "format",
          "version",
          "contractCid"
        ],
        "additionalProperties": false,
        "properties": {
          "format": {
            "enum": [
              "json",
              "jsonl",
              "csv"
            ]
          },
          "version": {
            "enum": [
              "actql-json/0.1",
              "actql-jsonl/0.1",
              "actql-csv/0.1"
            ]
          },
          "contractCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
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
              "effect_set",
              "model_invocation"
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
          },
          {
            "type": "object",
            "required": [
              "kind",
              "reason"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "reconcile_run"
              },
              "reason": {
                "const": "execution_unknown"
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
      },
      "control": {
        "type": "object",
        "required": [
          "revision",
          "cancellation_requested",
          "physical_stop"
        ],
        "additionalProperties": false,
        "properties": {
          "revision": {
            "type": "integer",
            "minimum": 0,
            "maximum": 2147483647
          },
          "cancellation_requested": {
            "type": "boolean"
          },
          "physical_stop": {
            "enum": [
              "unknown",
              "confirmed"
            ]
          }
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
              "oneOf": [
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
                    "reason"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "const": "reconcile_run"
                    },
                    "reason": {
                      "const": "execution_unknown"
                    }
                  }
                }
              ]
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
  },
  "check_outcome": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "outcome",
          "report",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid"
        ],
        "additionalProperties": false,
        "properties": {
          "outcome": {
            "const": "completed"
          },
          "report": {
            "type": "object",
            "required": [
              "context_ref",
              "coverage",
              "inputs",
              "reasons",
              "requirements",
              "scope",
              "verdict"
            ],
            "additionalProperties": false,
            "properties": {
              "context_ref": {
                "type": "string",
                "pattern": "^[A-Za-z0-9:_-]+$",
                "minLength": 1,
                "maxLength": 128
              },
              "omissions": {
                "type": "object",
                "required": [
                  "requirements"
                ],
                "additionalProperties": false,
                "properties": {
                  "requirements": {
                    "const": true
                  }
                }
              },
              "inputs": {
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "required": [
                    "document_id",
                    "revision",
                    "kind",
                    "byte_length"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "document_id": {
                      "enum": [
                        "source",
                        "parameter_declarations",
                        "parameters"
                      ]
                    },
                    "revision": {
                      "type": "string",
                      "pattern": "^rev:[0-9a-f]{64}$"
                    },
                    "kind": {
                      "enum": [
                        "text",
                        "structured"
                      ]
                    },
                    "byte_length": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    }
                  }
                }
              },
              "coverage": {
                "type": "object",
                "required": [
                  "limits",
                  "unresolved"
                ],
                "additionalProperties": false,
                "properties": {
                  "limits": {
                    "type": "array",
                    "items": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "code"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "type": "string",
                              "pattern": "^[a-z][a-z0-9_]{0,63}$"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "facts"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "const": "implementation_limit"
                            },
                            "facts": {
                              "type": "object",
                              "required": [
                                "issue"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "issue": {
                                  "const": "function_lowering_unresolved"
                                }
                              }
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "start_byte",
                                "end_byte",
                                "precision"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "text"
                                },
                                "document_id": {
                                  "const": "source"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "precision": {
                                  "enum": [
                                    "exact",
                                    "approximate"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  "unresolved": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "boundary",
                        "reason"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "boundary": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        },
                        "reason": {
                          "const": "unresolved_protected"
                        }
                      }
                    }
                  }
                }
              },
              "reasons": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "type": "string",
                      "pattern": "^[a-z][a-z0-9_]{0,63}$"
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                            },
                            "schema_cid": {
                              "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                              },
                              "schema_cid": {
                                "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "not": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_value_required",
                              "host_capacity_policy_required"
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "requirements": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code",
                    "facts"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "enum": [
                        "parameter_value_required",
                        "host_capacity_policy_required"
                      ]
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                            },
                            "schema_cid": {
                              "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                              },
                              "schema_cid": {
                                "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    }
                  ]
                }
              },
              "scope": {
                "type": "object",
                "required": [
                  "kind"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "bound_input"
                  }
                }
              },
              "verdict": {
                "enum": [
                  "invalid",
                  "undetermined",
                  "verified"
                ]
              }
            },
            "allOf": [
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "verified"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "requirements": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "properties": {
                        "limits": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        },
                        "unresolved": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        }
                      }
                    }
                  },
                  "not": {
                    "required": [
                      "omissions"
                    ]
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "minItems": 1,
                      "items": {}
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "not": {
                        "properties": {
                          "limits": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          },
                          "unresolved": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "outcome",
          "problem",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid",
          "correlation_ref"
        ],
        "additionalProperties": false,
        "properties": {
          "outcome": {
            "const": "failed"
          },
          "partial_report": {
            "type": "object",
            "required": [
              "context_ref",
              "coverage",
              "inputs",
              "reasons",
              "requirements",
              "scope",
              "verdict"
            ],
            "additionalProperties": false,
            "properties": {
              "context_ref": {
                "type": "string",
                "pattern": "^[A-Za-z0-9:_-]+$",
                "minLength": 1,
                "maxLength": 128
              },
              "omissions": {
                "type": "object",
                "required": [
                  "requirements"
                ],
                "additionalProperties": false,
                "properties": {
                  "requirements": {
                    "const": true
                  }
                }
              },
              "inputs": {
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "required": [
                    "document_id",
                    "revision",
                    "kind",
                    "byte_length"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "document_id": {
                      "enum": [
                        "source",
                        "parameter_declarations",
                        "parameters"
                      ]
                    },
                    "revision": {
                      "type": "string",
                      "pattern": "^rev:[0-9a-f]{64}$"
                    },
                    "kind": {
                      "enum": [
                        "text",
                        "structured"
                      ]
                    },
                    "byte_length": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    }
                  }
                }
              },
              "coverage": {
                "type": "object",
                "required": [
                  "limits",
                  "unresolved"
                ],
                "additionalProperties": false,
                "properties": {
                  "limits": {
                    "type": "array",
                    "items": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "code"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "type": "string",
                              "pattern": "^[a-z][a-z0-9_]{0,63}$"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "facts"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "const": "implementation_limit"
                            },
                            "facts": {
                              "type": "object",
                              "required": [
                                "issue"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "issue": {
                                  "const": "function_lowering_unresolved"
                                }
                              }
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "start_byte",
                                "end_byte",
                                "precision"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "text"
                                },
                                "document_id": {
                                  "const": "source"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "precision": {
                                  "enum": [
                                    "exact",
                                    "approximate"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  "unresolved": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "boundary",
                        "reason"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "boundary": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        },
                        "reason": {
                          "const": "unresolved_protected"
                        }
                      }
                    }
                  }
                }
              },
              "reasons": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "type": "string",
                      "pattern": "^[a-z][a-z0-9_]{0,63}$"
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                            },
                            "schema_cid": {
                              "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                              },
                              "schema_cid": {
                                "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "not": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_value_required",
                              "host_capacity_policy_required"
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "requirements": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code",
                    "facts"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "enum": [
                        "parameter_value_required",
                        "host_capacity_policy_required"
                      ]
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "artifact_ref"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
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
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                            },
                            "schema_cid": {
                              "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:5de69acac624586723a7efad500d0caf13c21ad2ed6e2252df0aaacf32dfc164"
                              },
                              "schema_cid": {
                                "const": "sha256:f23dbd7096c73975276d79dc163c8b3ae7dbae662ade242a3f1789cf07b854f3"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameter_declarations"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    }
                  ]
                }
              },
              "scope": {
                "type": "object",
                "required": [
                  "kind"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "bound_input"
                  }
                }
              },
              "verdict": {
                "enum": [
                  "invalid",
                  "undetermined"
                ]
              }
            },
            "allOf": [
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "verified"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "requirements": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "properties": {
                        "limits": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        },
                        "unresolved": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        }
                      }
                    }
                  },
                  "not": {
                    "required": [
                      "omissions"
                    ]
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "minItems": 1,
                      "items": {}
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "not": {
                        "properties": {
                          "limits": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          },
                          "unresolved": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "problem": {
            "type": "object",
            "required": [
              "code"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[a-z][a-z0-9_]{0,63}$"
              }
            }
          },
          "correlation_ref": {
            "type": "string",
            "pattern": "^[A-Za-z0-9:_-]+$",
            "minLength": 1,
            "maxLength": 128
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "correlation_ref",
          "outcome",
          "problem",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid"
        ],
        "additionalProperties": false,
        "properties": {
          "correlation_ref": {
            "type": "string",
            "pattern": "^[A-Za-z0-9:_-]+$",
            "minLength": 1,
            "maxLength": 128
          },
          "outcome": {
            "const": "unavailable"
          },
          "problem": {
            "type": "object",
            "required": [
              "code"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[a-z][a-z0-9_]{0,63}$"
              }
            }
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      }
    ]
  },
  "value_contract": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "precision",
          "scale"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "decimal"
          },
          "nullable": {
            "type": "boolean"
          },
          "precision": {
            "type": "integer",
            "minimum": 1,
            "maximum": 38
          },
          "scale": {
            "type": "integer",
            "minimum": 0,
            "maximum": 38
          }
        },
        "allOf": [
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 1
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 1
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 2
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 2
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 3
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 3
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 4
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 4
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 5
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 5
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 6
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 6
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 7
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 7
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 8
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 8
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 9
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 9
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 10
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 10
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 11
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 11
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 12
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 12
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 13
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 13
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 14
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 14
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 15
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 15
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 16
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 16
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 17
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 17
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 18
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 18
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 19
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 19
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 20
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 20
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 21
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 21
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 22
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 22
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 23
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 23
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 24
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 24
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 25
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 25
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 26
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 26
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 27
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 27
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 28
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 28
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 29
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 29
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 30
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 30
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 31
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 31
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 32
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 32
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 33
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 33
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 34
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 34
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 35
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 35
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 36
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 36
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 37
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 37
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 38
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 38
                }
              }
            }
          }
        ]
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "string"
          },
          "nullable": {
            "type": "boolean"
          },
          "min_length": {
            "type": "integer",
            "minimum": 0
          },
          "max_codepoints": {
            "type": "integer",
            "minimum": 0
          },
          "max_utf8_bytes": {
            "type": "integer",
            "minimum": 0
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "enum": [
              "number",
              "boolean",
              "timestamp",
              "date",
              "json"
            ]
          },
          "nullable": {
            "type": "boolean"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "items"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "array"
          },
          "nullable": {
            "type": "boolean"
          },
          "items": {
            "$ref": "value_contract"
          },
          "max_items": {
            "type": "integer",
            "minimum": 0
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "additional_properties",
          "fields"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "object"
          },
          "nullable": {
            "type": "boolean"
          },
          "additional_properties": {
            "const": false
          },
          "fields": {
            "type": "object",
            "additionalProperties": {
              "$ref": "value_contract"
            },
            "propertyNames": {
              "pattern": "^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "dimensions",
          "element_type"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "vector"
          },
          "nullable": {
            "type": "boolean"
          },
          "dimensions": {
            "type": "integer",
            "minimum": 1
          },
          "element_type": {
            "const": "f32"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "resource_kind"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "resource_ref"
          },
          "nullable": {
            "type": "boolean"
          },
          "resource_kind": {
            "type": "string",
            "minLength": 1
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "artifact_ref"
          },
          "nullable": {
            "type": "boolean"
          },
          "media_type": {
            "type": "string",
            "minLength": 1
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
  "check": [
    "connection",
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
  "result-describe": [
    "connection",
    "ref",
    "resultName",
    "format",
    "attemptId",
    "maxWireBytes",
    "maxNodes",
    "maxDepth"
  ],
  "delivery-attempt": [
    "connection",
    "ref",
    "resultName",
    "attemptId"
  ],
  "checkpoints": [
    "connection",
    "after",
    "limit"
  ],
  "checkpoint-review": [
    "connection",
    "checkpointCid",
    "maxBytes"
  ],
  "resolve": [
    "connection",
    "items"
  ],
  "cancel-request": [
    "connection",
    "requestId"
  ],
  "resources": [
    "connection",
    "resourceConnection",
    "query",
    "limit"
  ],
  "resource-inspect": [
    "connection",
    "resourceConnection",
    "resource",
    "maxBytes"
  ],
  "resource-peek": [
    "connection",
    "resourceConnection",
    "resource",
    "fields",
    "maxRows",
    "maxBytes"
  ]
};

export const checkReasonSchemaCid = "sha256:672a0158dfe91c7525eb7d02efbcf80b0094a05ecfa2b42fe08df945dd26fa53";
export const checkOutcomeSchemaCid = "sha256:2ceacaa6c399d8020b76c14ebd27a7f2ca5d975137dcdaff6b1907c9b4ef6311";
export const checkOutcomeProtocol = Object.freeze({version: "actql-check-outcome/0.1", reasonSchemaCid: checkReasonSchemaCid, outcomeSchemaCid: checkOutcomeSchemaCid, outcomes: Object.freeze(["completed","failed","unavailable"])});
export const runStateProtocol = Object.freeze({version: "actql-run-state/0.1", statuses: Object.freeze(["preparing","running","waiting_checkpoint","resuming","needs_reconciliation","succeeded","failed","cancelled"])});
function valid(value, schema) {
  if (schema.$ref) return valid(value, schemas[schema.$ref]);
  if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1) return false;
  if (schema.not && valid(value, schema.not)) return false;
  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;
  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (typeof value === 'number' &&
      (schema.minimum !== undefined && value < schema.minimum ||
       schema.maximum !== undefined && value > schema.maximum)) return false;
  if (typeof value === 'string' &&
      ((schema.minLength !== undefined && [...value].length < schema.minLength) ||
        (schema.maxLength !== undefined && value.length > schema.maxLength) ||
        (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value))))
    return false;
  if (schema.type === 'string') return typeof value === 'string';
  if (schema.type === 'number') return typeof value === 'number' && Number.isFinite(value) && !Object.is(value, -0);
  if (schema.type === 'integer') return Number.isSafeInteger(value) &&
    (schema.minimum === undefined || value >= schema.minimum) &&
    (schema.maximum === undefined || value <= schema.maximum);
  if (schema.type === 'boolean') return typeof value === 'boolean';
  if (schema.type === 'array') return Array.isArray(value) &&
    (schema.minItems === undefined || value.length >= schema.minItems) &&
    (schema.maxItems === undefined || value.length <= schema.maxItems) &&
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
export const validHeldShape = value => valid(value, schemas.held);
export const validCheckpointSummaryShape = value => valid(value, schemas.checkpoint_summary);
export const validCheckpointReviewShape = value => valid(value, schemas.checkpoint_review);
export const validResolveItemShape = value => valid(value, schemas.resolve_item);
export const validResolveResultShape = value => valid(value, schemas.resolve_result);
export const validSubmitPreparationErrorShape = value => valid(value, schemas.submit_preparation_error);
export const validCancellationShape = value => valid(value, schemas.cancellation);
export const validRequestCancellationShape = value => valid(value, schemas.request_cancellation);
export const validResourceListingShape = value => valid(value, schemas.resource_listing);
export const validResourceInspectionShape = value => valid(value, schemas.resource_inspection);
export const validResourcePeekShape = value => valid(value, schemas.resource_peek);
export const validResultDescriptionShape = value => valid(value, schemas.result_description);
export const validRunStateShape = value => valid(value, schemas.run_state);
export const validCheckOutcomeShape = value => valid(value, schemas.check_outcome) && value.outcome_schema_cid === checkOutcomeSchemaCid;
export const validProfileContract = (value, selected) =>
  validConnectionShape(selected) && validProfileShape(value) &&
  value.mode === selected.mode &&
  value.owner === selected.owner &&
  !(selected.durability === "durable" && value.durability !== "durable");
export const validAdmissionContract = (value, selected) =>
  validConnectionShape(selected) && validAdmissionShape(value) &&
  !(selected.durability === "durable" && value.durability !== "durable");
export const validHeldContract = (value, expected) =>
  valid(expected, schemas.held.properties.requestId) &&
  ((valid(value, schemas.held) && value.requestId === expected));
export const validRequestLookupContract = (value, expected) =>
  valid(expected, schemas.lookup_found.properties.requestId) &&
  ((valid(value, schemas.lookup_found) && value.requestId === expected) ||
   valid(value, schemas.lookup_not_found) ||
   valid(value, schemas.lookup_unknown) ||
   (valid(value, schemas.held) && value.requestId === expected));
