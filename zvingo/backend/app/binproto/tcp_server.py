import asyncio
import structlog
import redis.asyncio as aioredis
from app.config import settings
from app.binproto.codec import BinProtoCodec, PTYPE_LOCATION, PTYPE_ACK
from app.rate_limiter import RateLimiter

logger = structlog.get_logger()


async def resolve_driver_id(session_id: bytes) -> str | None:
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        return await r.get(f"binproto_session:{session_id.hex()}")
    finally:
        await r.close()


async def handle_tcp_client(reader, writer):
    addr = writer.get_extra_info('peername')
    logger.debug("TCP Connection", addr=addr)

    try:
        while True:
            header_data = await reader.readexactly(BinProtoCodec.HEADER_SIZE)
            header = BinProtoCodec.decode_header(header_data)

            if header['payload_len'] > 0:
                payload_data = await reader.readexactly(header['payload_len'])

                if header['type'] == PTYPE_LOCATION:
                    loc = BinProtoCodec.decode_location(payload_data)

                    driver_id = await resolve_driver_id(header['session_id'])
                    if driver_id:
                        from app.dispatch.service import dispatch_service
                        from app.dispatch.schemas import DriverLocationUpdate
                        from datetime import datetime

                        # Apply rate limiting
                        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
                        try:
                            limiter = RateLimiter(r)
                            allowed, error_msg = await limiter.check_location_update(driver_id)
                            if allowed:
                                update = DriverLocationUpdate(
                                    driver_id=driver_id,
                                    lat=loc.lat,
                                    lng=loc.lng,
                                    status="ONLINE",
                                    battery=loc.battery,
                                    timestamp=datetime.utcnow()
                                )
                                await dispatch_service.update_location(update)
                            else:
                                logger.warn("Location update rate limited", driver_id=driver_id, error=error_msg)
                        finally:
                            await r.close()

                    logger.debug("TCP Location", session=header['session_id'].hex(),
                                 lat=loc.lat, lng=loc.lng)

            # Send ACK
            ack = BinProtoCodec.encode_ack(header['seq'])
            writer.write(ack)
            await writer.drain()

    except asyncio.IncompleteReadError:
        pass
    except Exception as e:
        logger.warn("TCP Error", error=str(e))
    finally:
        writer.close()
        await writer.wait_closed()


async def start_tcp_server():
    server = await asyncio.start_server(
        handle_tcp_client, "0.0.0.0", settings.BINPROTO_TCP_PORT
    )
    logger.info("TCP Server started", port=settings.BINPROTO_TCP_PORT)
    async with server:
        await server.serve_forever()
