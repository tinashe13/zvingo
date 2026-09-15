"""Every Beanie Document must be registered with init_beanie.

An unregistered Document does not fail at import, and it does not fail in a
test suite that mocks the database. It raises the first time real code touches
it against a real MongoDB -- which, for the money-path models, means in
production on a live order.

This test walks the whole app package, finds every Document subclass, and
asserts it appears in the ``document_models`` list in ``app/db/session.py``.
Adding a Document without registering it fails here instead of at 2am.
"""

import ast
import importlib
import pkgutil
from pathlib import Path

from beanie import Document

APP_ROOT = Path(__file__).resolve().parents[1] / "app"
SESSION_FILE = APP_ROOT / "db" / "session.py"


def _import_every_app_module() -> None:
    """Import all of app.* so every Document subclass is defined."""
    import app

    for mod in pkgutil.walk_packages(app.__path__, prefix="app."):
        # Socket servers bind ports at import; nothing there defines a Document.
        if ".binproto" in mod.name:
            continue
        importlib.import_module(mod.name)


def _defined_documents() -> set[str]:
    _import_every_app_module()

    seen: set[str] = set()
    stack = list(Document.__subclasses__())
    while stack:
        cls = stack.pop()
        module = getattr(cls, "__module__", "")
        if module.startswith("app."):
            seen.add(cls.__name__)
        stack.extend(cls.__subclasses__())
    return seen


def _registered_documents() -> set[str]:
    """Read the document_models list out of session.py without running it."""
    tree = ast.parse(SESSION_FILE.read_text())

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", "")
        if name != "init_beanie":
            continue
        for kw in node.keywords:
            if kw.arg == "document_models" and isinstance(kw.value, ast.List):
                return {
                    el.id for el in kw.value.elts if isinstance(el, ast.Name)
                }

    raise AssertionError("no init_beanie(document_models=[...]) call found in session.py")


def test_every_document_model_is_registered_with_beanie():
    defined = _defined_documents()
    registered = _registered_documents()

    missing = sorted(defined - registered)
    assert not missing, (
        "These Beanie Documents are defined but never passed to init_beanie, so "
        "they will raise the first time they are used against a real MongoDB: "
        f"{missing}. Register them in app/db/session.py."
    )


def test_registered_models_all_exist():
    """A name in the list that no longer exists would crash init_db at startup."""
    defined = _defined_documents()
    registered = _registered_documents()

    unknown = sorted(registered - defined)
    assert not unknown, (
        f"session.py registers models that are not defined Documents: {unknown}"
    )
