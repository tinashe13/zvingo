"""Shared pytest setup.

`app.config.Settings` requires MONGODB_URL and REDIS_URL, and it is
instantiated at import time — so without them every test module fails to
collect. The suite never touches a real database or Redis (both are faked per
test), so supply harmless defaults here when the environment has none. A real
value in the environment always wins, which keeps integration runs possible.
"""

import os

os.environ.setdefault("MONGODB_URL", "mongodb://localhost:27017/zvingo_test")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("ENVIRONMENT", "development")
