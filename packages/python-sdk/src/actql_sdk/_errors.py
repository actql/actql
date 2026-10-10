class ClientError(Exception):
    """A public transport or Client-contract failure, never a retry permission."""

    def __init__(self, code: str, **facts):
        super().__init__(code)
        self.code = code
        self.cleanup_client = None
        for key, value in facts.items():
            setattr(self, key, value)
