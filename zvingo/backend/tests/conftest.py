import pytest
import asyncio
from typing import Generator

# Helper to manage event loop in pytest-asyncio
@pytest.fixture(scope="session")
def event_loop() -> Generator:
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()
