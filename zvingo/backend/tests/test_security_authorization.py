"""Authorization primitives and the WebSocket authentication dependency."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.auth.authorization import (
    Role,
    has_role,
    is_admin,
    is_order_participant,
    is_restaurant_owner,
    is_same_user,
    owning_merchant_id,
    require_any_role,
    require_order_consumer,
    require_order_driver,
    require_order_merchant,
    require_order_participant,
    require_restaurant_owner,
    require_self,
)
from app.auth.tokens import create_access_token, create_refresh_token
from app.auth.ws import WS_POLICY_VIOLATION, authenticate_websocket, authenticate_ws


def user(uid="user-1", role=Role.CONSUMER, is_active=True, tokens_valid_from=None):
    return SimpleNamespace(
        id=uid, role=role, is_active=is_active, tokens_valid_from=tokens_valid_from
    )


def order(**overrides):
    values = {
        "id": "order-1",
        "consumer_id": "consumer-1",
        "driver_id": "driver-1",
        "merchant_id": "restaurant-1",  # a *restaurant* id, not a user id
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.fixture
def restaurant_lookup(monkeypatch):
    """Point Restaurant.get at a controllable stub."""
    import app.catalog.models as models

    store = {"restaurant-1": SimpleNamespace(id="restaurant-1", merchant_id="merchant-1")}
    monkeypatch.setattr(
        models.Restaurant, "get", AsyncMock(side_effect=lambda rid: store.get(rid))
    )
    return store


# --- Roles --------------------------------------------------------------------


def test_role_predicates():
    assert has_role(user(role=Role.DRIVER), Role.DRIVER)
    assert not has_role(user(role=Role.DRIVER), Role.MERCHANT)
    assert is_admin(user(role=Role.ADMIN))
    assert not is_admin(user(role=Role.MERCHANT))


def test_require_any_role_admits_the_listed_roles():
    merchant = user(role=Role.MERCHANT)
    assert require_any_role(merchant, Role.MERCHANT) is merchant
    assert require_any_role(merchant, Role.DRIVER, Role.MERCHANT) is merchant


def test_require_any_role_rejects_everyone_else():
    with pytest.raises(HTTPException) as exc:
        require_any_role(user(role=Role.CONSUMER), Role.MERCHANT)
    assert exc.value.status_code == 403
    assert "merchant" in exc.value.detail


def test_admins_pass_a_role_check_only_when_that_is_asked_for():
    """`allow_admin` is opt-in, so no route grants admin access by accident."""
    admin = user(role=Role.ADMIN)
    with pytest.raises(HTTPException):
        require_any_role(admin, Role.MERCHANT)
    assert require_any_role(admin, Role.MERCHANT, allow_admin=True) is admin


# --- Identity -----------------------------------------------------------------


def test_identity_comparison_normalises_id_shapes():
    """ObjectId vs str is the classic way an ownership check silently fails."""

    class ObjectIdLike:
        def __str__(self):
            return "user-1"

    assert is_same_user(user("user-1"), "user-1")
    assert is_same_user(user("user-1"), ObjectIdLike())
    assert not is_same_user(user("user-1"), "user-2")
    assert not is_same_user(user("user-1"), None)


def test_require_self_blocks_reading_another_users_data():
    caller = user("driver-1", role=Role.DRIVER)
    assert require_self(caller, "driver-1") is caller
    with pytest.raises(HTTPException) as exc:
        require_self(caller, "driver-2")
    assert exc.value.status_code == 403


def test_require_self_can_admit_an_admin_when_asked():
    admin = user("admin-1", role=Role.ADMIN)
    with pytest.raises(HTTPException):
        require_self(admin, "driver-2")
    assert require_self(admin, "driver-2", allow_admin=True) is admin


# --- Orders -------------------------------------------------------------------


@pytest.mark.asyncio
async def test_the_three_parties_to_an_order_can_see_it(restaurant_lookup):
    target = order()
    assert await is_order_participant(target, user("consumer-1"))
    assert await is_order_participant(target, user("driver-1", role=Role.DRIVER))
    assert await is_order_participant(target, user("merchant-1", role=Role.MERCHANT))


@pytest.mark.asyncio
async def test_a_stranger_cannot_see_an_order(restaurant_lookup):
    assert not await is_order_participant(order(), user("someone-else"))
    with pytest.raises(HTTPException) as exc:
        await require_order_participant(order(), user("someone-else"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_merchant_who_owns_a_different_restaurant_is_not_a_participant(
    restaurant_lookup,
):
    """The check must resolve restaurant -> owner, not compare ids directly."""
    assert not await is_order_participant(order(), user("restaurant-1", role=Role.MERCHANT))


@pytest.mark.asyncio
async def test_participation_is_false_for_missing_inputs(restaurant_lookup):
    assert not await is_order_participant(None, user("consumer-1"))
    assert not await is_order_participant(order(), None)


@pytest.mark.asyncio
async def test_an_unassigned_order_has_no_driver_participant(restaurant_lookup):
    unassigned = order(driver_id=None)
    assert not await is_order_participant(unassigned, user(None))
    with pytest.raises(HTTPException):
        await require_order_driver(unassigned, user("driver-1"))


@pytest.mark.asyncio
async def test_buyer_only_actions_reject_the_driver_and_the_merchant(restaurant_lookup):
    target = order()
    assert await require_order_consumer(target, user("consumer-1")) is target
    for other in (user("driver-1", role=Role.DRIVER), user("merchant-1", role=Role.MERCHANT)):
        with pytest.raises(HTTPException) as exc:
            await require_order_consumer(target, other)
        assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_driver_only_and_merchant_only_actions(restaurant_lookup):
    target = order()
    assert await require_order_driver(target, user("driver-1")) is target
    assert await require_order_merchant(target, user("merchant-1")) is target
    with pytest.raises(HTTPException):
        await require_order_merchant(target, user("consumer-1"))


@pytest.mark.asyncio
async def test_admins_can_be_admitted_to_an_order_explicitly(restaurant_lookup):
    admin = user("admin-1", role=Role.ADMIN)
    with pytest.raises(HTTPException):
        await require_order_participant(order(), admin)
    assert await require_order_participant(order(), admin, allow_admin=True) is not None


@pytest.mark.asyncio
async def test_an_unresolvable_restaurant_denies_rather_than_grants(monkeypatch):
    """A lookup failure must not be read as "everyone is the merchant"."""
    import app.catalog.models as models

    monkeypatch.setattr(models.Restaurant, "get", AsyncMock(side_effect=RuntimeError("db")))
    assert await owning_merchant_id(order()) is None
    assert not await is_order_participant(order(), user("merchant-1"))


@pytest.mark.asyncio
async def test_the_legacy_facade_still_answers_the_same(restaurant_lookup):
    from app.order.access import can_access_order

    assert await can_access_order(order(), user("consumer-1"))
    assert not await can_access_order(order(), user("nobody"))


# --- Restaurants --------------------------------------------------------------


def test_restaurant_ownership():
    shop = SimpleNamespace(id="restaurant-1", merchant_id="merchant-1")
    assert is_restaurant_owner(shop, user("merchant-1", role=Role.MERCHANT))
    assert not is_restaurant_owner(shop, user("merchant-2", role=Role.MERCHANT))
    assert not is_restaurant_owner(None, user("merchant-1"))
    assert require_restaurant_owner(shop, user("merchant-1")) is shop
    with pytest.raises(HTTPException) as exc:
        require_restaurant_owner(shop, user("merchant-2"))
    assert exc.value.status_code == 403


# --- WebSocket authentication -------------------------------------------------


class FakeWebSocket:
    def __init__(self, token=None, header=None):
        self.query_params = {"token": token} if token else {}
        self.headers = {"authorization": header} if header else {}
        self.closed_code = None
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def close(self, code):
        self.closed_code = code


@pytest.fixture
def ws_user(monkeypatch):
    """Make `User.get` return a controllable account for the WS handshake."""
    import app.auth.models as models

    state = {"user": user("driver-1", role=Role.DRIVER)}
    monkeypatch.setattr(
        models.User, "get", AsyncMock(side_effect=lambda _id: state["user"])
    )
    return state


@pytest.mark.asyncio
async def test_a_socket_with_no_token_is_closed(ws_user):
    socket = FakeWebSocket()
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code == WS_POLICY_VIOLATION
    assert not socket.accepted


@pytest.mark.asyncio
async def test_a_socket_with_a_forged_token_is_closed(ws_user):
    socket = FakeWebSocket(token="not-a-jwt")
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_refresh_token_cannot_open_a_socket(ws_user):
    refresh, _jti, _ttl = create_refresh_token("driver-1")
    socket = FakeWebSocket(token=refresh)
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_driver_cannot_open_another_drivers_channel(ws_user):
    """The path parameter is attacker-controlled; the token is not."""
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    assert await authenticate_websocket(socket, expected_user_id="driver-2") is None
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_valid_handshake_yields_a_principal(ws_user):
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    principal = await authenticate_websocket(socket, expected_user_id="driver-1")
    assert principal is not None
    assert principal.user_id == "driver-1"
    assert principal.role == Role.DRIVER
    assert principal.owns("driver-1") and not principal.owns("driver-2")
    # Authentication does not accept the socket; the handler still decides.
    assert socket.closed_code is None and not socket.accepted


@pytest.mark.asyncio
async def test_the_token_may_also_arrive_in_a_header(ws_user):
    token = create_access_token({"sub": "driver-1"})
    socket = FakeWebSocket(header=f"Bearer {token}")
    principal = await authenticate_websocket(socket, expected_user_id="driver-1")
    assert principal is not None and principal.user_id == "driver-1"


@pytest.mark.asyncio
async def test_a_deactivated_driver_cannot_open_a_socket(ws_user):
    ws_user["user"] = user("driver-1", role=Role.DRIVER, is_active=False)
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_deleted_user_cannot_open_a_socket(ws_user):
    ws_user["user"] = None
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_role_restricted_channel_rejects_the_wrong_role(ws_user):
    ws_user["user"] = user("driver-1", role=Role.CONSUMER)
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    assert (
        await authenticate_websocket(
            socket, expected_user_id="driver-1", roles=(Role.DRIVER,)
        )
        is None
    )
    assert socket.closed_code == WS_POLICY_VIOLATION


@pytest.mark.asyncio
async def test_a_database_failure_closes_the_socket_rather_than_admitting_it(monkeypatch):
    import app.auth.models as models

    monkeypatch.setattr(models.User, "get", AsyncMock(side_effect=RuntimeError("mongo")))
    socket = FakeWebSocket(token=create_access_token({"sub": "driver-1"}))
    assert await authenticate_websocket(socket, expected_user_id="driver-1") is None
    assert socket.closed_code is not None


@pytest.mark.asyncio
async def test_the_claims_only_helper_still_works_for_simple_channels():
    token = create_access_token({"sub": "driver-1"})
    assert authenticate_ws(FakeWebSocket(token=token)) == "driver-1"
    assert authenticate_ws(FakeWebSocket(header=f"Bearer {token}")) == "driver-1"
    assert authenticate_ws(FakeWebSocket()) is None
    assert authenticate_ws(FakeWebSocket(token="bad")) is None
    assert authenticate_ws(FakeWebSocket(header="Basic abc")) is None
