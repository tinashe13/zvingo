"""The SSE event streams must not be a public firehose.

Before stream tickets existed, ``GET /notification/events/{channel_id}`` and
``GET /location/driver/{driver_id}/track`` took an identifier and nothing else.
Channel names are not secrets: ``merchant_{restaurant_id}`` keys on a restaurant
id that the *public* catalog listing hands out. So anyone could enumerate every
restaurant and subscribe to its live order feed, read any order's chat, or
follow any named driver's GPS in real time.

These tests pin the fix: a caller must present a single-use, short-lived ticket
that was issued to them for that exact channel.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

import app.notification.stream_auth as stream_auth


class FakeRedis:
    """Enough Redis for ticket issue/redeem, with TTLs ignored."""

    def __init__(self):
        self.store = {}

    async def setex(self, key, _ttl, value):
        self.store[key] = value

    async def getdel(self, key):
        return self.store.pop(key, None)


@pytest.fixture
def redis(monkeypatch):
    fake = FakeRedis()

    class _CM:
        async def __aenter__(self):
            return fake

        async def __aexit__(self, *_a):
            return False

    monkeypatch.setattr(stream_auth, "redis_client", lambda **_k: _CM())
    return fake


def user(uid, role="consumer"):
    return SimpleNamespace(id=uid, role=role)


# ── redemption ────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_a_stream_cannot_be_opened_without_a_ticket(redis):
    for missing in ("", None):
        with pytest.raises(HTTPException) as exc:
            await stream_auth.redeem_ticket(missing, "consumer_alice")
        assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_an_unknown_ticket_is_refused(redis):
    with pytest.raises(HTTPException) as exc:
        await stream_auth.redeem_ticket("made-up", "consumer_alice")
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_ticket_is_single_use(redis):
    ticket, _ = await stream_auth.issue_ticket("consumer_alice", user("alice"))

    assert await stream_auth.redeem_ticket(ticket, "consumer_alice") == "alice"

    # A ticket captured from a log or a referrer cannot be replayed.
    with pytest.raises(HTTPException) as exc:
        await stream_auth.redeem_ticket(ticket, "consumer_alice")
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_ticket_is_bound_to_one_channel(redis):
    ticket, _ = await stream_auth.issue_ticket("consumer_alice", user("alice"))

    with pytest.raises(HTTPException) as exc:
        await stream_auth.redeem_ticket(ticket, "consumer_bob")
    assert exc.value.status_code == 403


# ── who may be issued a ticket ────────────────────────────────────────────

@pytest.mark.asyncio
async def test_a_user_cannot_listen_to_another_users_channel(redis):
    for channel in ("consumer_bob", "driver_bob"):
        with pytest.raises(HTTPException) as exc:
            await stream_auth.issue_ticket(channel, user("alice"))
        assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_user_may_listen_to_their_own_channel(redis):
    ticket, ttl = await stream_auth.issue_ticket("consumer_alice", user("alice"))
    assert ticket and ttl > 0


@pytest.mark.asyncio
async def test_an_unknown_channel_prefix_is_denied(redis):
    # Deny by default: the ops alert stream and anything else internal must not
    # become reachable just because a client guessed the name.
    for channel in ("alerts", "internal_metrics", "", "order_123"):
        with pytest.raises(HTTPException) as exc:
            await stream_auth.issue_ticket(channel, user("alice"))
        assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_merchant_channel_requires_owning_that_restaurant(redis, monkeypatch):
    restaurant = SimpleNamespace(id="rest-1", merchant_id="owner-1")

    import app.catalog.models as catalog_models

    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(return_value=restaurant)
    )

    # The restaurant id is public, so this is exactly the enumeration attack.
    with pytest.raises(HTTPException) as exc:
        await stream_auth.issue_ticket("merchant_rest-1", user("stranger", "merchant"))
    assert exc.value.status_code == 403

    ticket, _ = await stream_auth.issue_ticket(
        "merchant_rest-1", user("owner-1", "merchant")
    )
    assert ticket


@pytest.mark.asyncio
async def test_a_chat_channel_requires_being_a_party_to_the_order(redis, monkeypatch):
    order = SimpleNamespace(
        id="o1", consumer_id="alice", driver_id="dave", merchant_id="rest-1"
    )

    import app.order.models as order_models

    monkeypatch.setattr(order_models.Order, "get", AsyncMock(return_value=order))

    with pytest.raises(HTTPException) as exc:
        await stream_auth.issue_ticket("chat_o1", user("stranger"))
    assert exc.value.status_code == 403

    assert await stream_auth.issue_ticket("chat_o1", user("alice"))


# ── driver location: the stalking case ────────────────────────────────────

@pytest.mark.asyncio
async def test_a_stranger_cannot_follow_a_driver(redis, monkeypatch):
    import app.order.models as order_models

    class NoOrders:
        def limit(self, *_a):
            return self

        async def to_list(self):
            return []

    monkeypatch.setattr(
        order_models.Order, "find", classmethod(lambda cls, *_a: NoOrders())
    )

    with pytest.raises(HTTPException) as exc:
        await stream_auth.issue_ticket("driver_loc_dave", user("stranger"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_driver_may_follow_themselves(redis):
    assert await stream_auth.issue_ticket("driver_loc_dave", user("dave", "driver"))


@pytest.mark.asyncio
async def test_the_consumer_of_an_in_flight_order_may_follow_its_driver(
    redis, monkeypatch
):
    order = SimpleNamespace(
        id="o1", consumer_id="alice", driver_id="dave", merchant_id="rest-1"
    )

    import app.order.models as order_models

    class OneOrder:
        def limit(self, *_a):
            return self

        async def to_list(self):
            return [order]

    monkeypatch.setattr(
        order_models.Order, "find", classmethod(lambda cls, *_a: OneOrder())
    )

    assert await stream_auth.issue_ticket("driver_loc_dave", user("alice"))


# ── dual-mode: header for native clients, ticket for browsers ─────────────

@pytest.mark.asyncio
async def test_a_native_client_may_authenticate_with_a_bearer_header(
    redis, monkeypatch
):
    """Both Flutter apps use Dio, which can set Authorization.

    For them a header beats a ticket: no credential in a URL, and no extra
    round trip before every reconnect. Browsers still need the ticket.
    """
    import app.auth.models as auth_models
    import app.auth.tokens as tokens

    monkeypatch.setattr(tokens, "decode_token", lambda _t: {"sub": "alice"})
    monkeypatch.setattr(
        auth_models.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="alice", role="consumer", is_active=True)),
    )

    assert await stream_auth.authorize_stream(
        "consumer_alice", None, "Bearer good-token"
    ) == "alice"


@pytest.mark.asyncio
async def test_a_bearer_header_still_obeys_channel_authorization(redis, monkeypatch):
    """A valid token is not a licence to read someone else's channel."""
    import app.auth.models as auth_models
    import app.auth.tokens as tokens

    monkeypatch.setattr(tokens, "decode_token", lambda _t: {"sub": "alice"})
    monkeypatch.setattr(
        auth_models.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="alice", role="consumer", is_active=True)),
    )

    with pytest.raises(HTTPException) as exc:
        await stream_auth.authorize_stream("consumer_bob", None, "Bearer good-token")
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_deactivated_account_cannot_open_a_stream(redis, monkeypatch):
    import app.auth.models as auth_models
    import app.auth.tokens as tokens

    monkeypatch.setattr(tokens, "decode_token", lambda _t: {"sub": "alice"})
    monkeypatch.setattr(
        auth_models.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="alice", role="consumer", is_active=False)),
    )

    with pytest.raises(HTTPException) as exc:
        await stream_auth.authorize_stream("consumer_alice", None, "Bearer good-token")
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_garbage_header_does_not_fall_through_to_open_access(redis, monkeypatch):
    import app.auth.tokens as tokens

    def _boom(_t):
        raise ValueError("bad signature")

    monkeypatch.setattr(tokens, "decode_token", _boom)

    with pytest.raises(HTTPException) as exc:
        await stream_auth.authorize_stream("consumer_alice", None, "Bearer forged")
    assert exc.value.status_code == 403
