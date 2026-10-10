class ClientError(Exception):
    """A public transport or Client-contract failure, never a retry permission."""

    def __init__(self, code: str, **facts):
        super().__init__(code)
        self.code = code
        self.cleanup_client = None
        self.submission_ref = None
        self.attempt_ref = None
        self.cancel_ref = None
        self.outcome = None
        self.signed = None
        self.attempt_id = None
        self.rows_yielded = None
        self.original_error = None
        self.cleanup_error = None
        for key, value in facts.items():
            setattr(self, key, value)
