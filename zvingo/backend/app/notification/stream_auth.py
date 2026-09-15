"""Authorization for Server-Sent Event streams.

An ``EventSource`` cannot send an ``Authorization`` header, which is why the
event stream ended up unauthenticated: it was reachable by anyone who knew a
channel name. Channel names are not secret -- ``merchant_{restaurant_id}`` keys
on a restaurant id handed out by the public catalog listing -- so the stream was
effectively a public firehose of order events, chat messages and driver GPS.

Putting a JWT in the query string would fix authentication and create a new
problem: the token lands in nginx access logs, browser history and any referrer.

So a client exchanges its JWT for a **single-use, short-lived ticket** bound to
one channel, and connects with that. A leaked ticket is worth one subscription
for at most a minute, to a channel the requester was already entitled to.
"""

from __future__ import annotations

import secrets
from typing import Any, Optional

import structlog

from app.auth.authorization import (
    _uid,
    forbidden,
    is_admin,
    is_order_participant,
    is_restaurant_owner,
    is_same_user,
)
from app.db.redis import redis_client

logger = structlog.get_logger()

#: Long enough to cover a slow handshake, short enough that a leaked ticket in a
#: log line is worthless by the time anyone reads it.
TICKET_TTL_SECONDS = 60

_TICKET_PREFIX = "sse_ticket:"


async def authorize_channel(channel: str, user: Any) -> None:
    """Raise 403 unless ``user`` may subscribe to ``channel``.

    Deny by default: an unrecognised channel prefix is refused rather than
    allowed, so adding a new publish channel cannot silently open a hole.
    """
    if not channel or "\n" in channel or "\r" in channel:
        raise forbidden("Invalid channel")

    prefix, _, subject = channel.partition("_")

    # driver_loc_{id} partitions as ("driver", "loc_{id}") -- handle it first.
    if channel.startswith("driver_loc_"):
        await _authorize_driver_location(channel[len("driver_loc_"):], user)
        return

    if prefix == "consumer" or prefix == "driver":
        if is_admin(user) or is_same_user(user, subject):
            return
        raise forbidden("Not your event stream")

    if prefix == "merchant":
        # The subject is a RESTAURANT id, not a merchant user id.
        from app.catalog.models import Restaurant

        restaurant = await Restaurant.get(subject)
        if restaurant is None:
            raise forbidden("Not your event stream")
        if is_admin(user) or is_restaurant_owner(restaurant, user):
            return
        raise forbidden("Not your event stream")

    if prefix == "chat":
        from app.order.models import Order

        order = await Order.get(subject)
        if order is None:
            raise forbidden("Not your event stream")
        if is_admin(user) or await is_order_participant(order, user):
            return
        raise forbidden("Not your event stream")

    # Internal channels (for example the ops alert stream) are never client
    # subscribable, and anything unknown is refused.
    raise forbidden("Not your event stream")


async def _authorize_driver_location(driver_id: str, user: Any) -> None:
    """A driver's live position is visible to the driver, an admin, or the
    consumer and merchant of an order that driver is *currently* delivering.

    Without the active-order constraint this endpoint is a stalking primitive
    aimed at gig workers: any signed-in account could follow any named driver.
    """
    if is_admin(user) or is_same_user(user, driver_id):
        return

    from app.order.models import Order
    from app.order.state_machine import OrderState

    in_flight = [
        OrderState.ACCEPTED,
        OrderState.PICKED_UP,
    ]
    orders = await Order.find(
        {
            "driver_id": driver_id,
            "state": {"$in": [s.value for s in in_flight]},
        }
    ).limit(20).to_list()

    for order in orders:
        if await is_order_participant(order, user):
            return

    raise forbidden("Not your event stream")


async def issue_ticket(channel: str, user: Any) -> tuple[str, int]:
    """Authorize ``channel`` for ``user`` and mint a single-use ticket."""
    await authorize_channel(channel, user)

    ticket = secrets.token_urlsafe(32)
    async with redis_client() as r:
        await r.setex(
            f"{_TICKET_PREFIX}{ticket}",
            TICKET_TTL_SECONDS,
            f"{_uid(getattr(user, 'id', None))}|{channel}",
        )

    logger.info(
        "SSE ticket issued",
        channel=channel,
        user_id=_uid(getattr(user, "id", None)),
    )
    return ticket, TICKET_TTL_SECONDS


async def redeem_ticket(ticket: Optional[str], channel: str) -> str:
    """Consume ``ticket`` and return the user id it was issued to.

    Single-use: the key is deleted as it is read, so a ticket captured from a
    log cannot be replayed. Raises 403 if absent, expired, already used, or
    issued for a different channel.
    """
    if not ticket:
        raise forbidden("A stream ticket is required")

    key = f"{_TICKET_PREFIX}{ticket}"
    async with redis_client() as r:
        stored = None
        try:
            # Atomic read-and-delete where the server supports it.
            stored = await r.getdel(key)
        except AttributeError:  # pragma: no cover - older redis-py
            stored = await r.get(key)
            if stored is not None:
                await r.delete(key)

    if not stored:
        raise forbidden("Stream ticket is invalid or has expired")

    if isinstance(stored, bytes):
        stored = stored.decode()

    user_id, _, issued_channel = str(stored).partition("|")
    if issued_channel != channel:
        logger.warning(
            "SSE ticket channel mismatch",
            issued_for=issued_channel,
            requested=channel,
        )
        raise forbidden("Stream ticket is not valid for this channel")

    return user_id

async def authorize_stream(
    channel: str,
    ticket: Optional[str],
    authorization: Optional[str],
) -> str:
    """Authorize an SSE subscription by ticket **or** bearer header.

    Browsers need the ticket: ``EventSource`` cannot set a header. Native
    clients (both Flutter apps use Dio) can send ``Authorization`` normally, and
    for them a header is strictly better than a ticket -- no credential in a
    URL, and no extra round trip before every reconnect.

    Returns the authorized user id.
    """
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() == "bearer" and token:
            from app.auth.models import User
            from app.auth.tokens import decode_token

            try:
                claims = decode_token(token)
            except Exception:
                raise forbidden("Invalid credentials for this stream")

            user = await User.get(claims.get("sub"))
            if user is None or not getattr(user, "is_active", True):
                raise forbidden("Invalid credentials for this stream")

            await authorize_channel(channel, user)
            return _uid(user.id)

    return await redeem_ticket(ticket, channel)
