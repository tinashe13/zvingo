import asyncio
import structlog
import redis.asyncio as aioredis
from app.config import settings
from app.binproto.codec import BinProtoCodec, PTYPE_LOCATION
from app.rate_limiter import RateLimiter

logger = structlog.get_logger()


async def resolve_driver_id(session_id: bytes) -> str | None:
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        return await r.get(f"binproto_session:{session_id.hex()}")
    finally:
        await r.close()


class BinProtoUDPProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport
        logger.info("UDP Server started", port=settings.BINPROTO_UDP_PORT)

    def datagram_received(self, data, addr):
        try:
            header = BinProtoCodec.decode_header(data)
            payload_data = data[BinProtoCodec.HEADER_SIZE : BinProtoCodec.HEADER_SIZE + header['payload_len']]

            if header['type'] == PTYPE_LOCATION:
                loc = BinProtoCodec.decode_location(payload_data)

                from app.dispatch.service import dispatch_service
                from app.dispatch.schemas import DriverLocationUpdate
                from datetime import datetime

                loop = asyncio.get_running_loop()

                async def handle_location():
                    driver_id = await resolve_driver_id(header['session_id'])
                    if not driver_id:
                        logger.warn("Unknown session", session_id=header['session_id'].hex(), addr=addr)
                        return

                    # Apply rate limiting
                    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
                    try:
                        limiter = RateLimiter(r)
                        allowed, error_msg = await limiter.check_location_update(driver_id)
                        if not allowed:
                            logger.warn("Location update rate limited", driver_id=driver_id, error=error_msg)
                            return
                    finally:
                        await r.close()

                    update = DriverLocationUpdate(
                        driver_id=driver_id,
                        lat=loc.lat,
                        lng=loc.lng,
                        status="ONLINE",
                        battery=loc.battery,
                        timestamp=datetime.utcnow()
                    )
                    await dispatch_service.update_location(update)

                loop.create_task(handle_location())

                ack = BinProtoCodec.encode_ack(header['seq'])
                self.transport.sendto(ack, addr)

                logger.debug("Received location", session=header['session_id'].hex(),
                             lat=loc.lat, lng=loc.lng, battery=loc.battery)

        except Exception as e:
            logger.warn("Invalid UDP packet", error=str(e), addr=addr)


async def start_udp_server():
    loop = asyncio.get_running_loop()
    try:
        transport, protocol = await loop.create_datagram_endpoint(
            lambda: BinProtoUDPProtocol(),
            local_addr=("0.0.0.0", settings.BINPROTO_UDP_PORT),
            reuse_port=False,
        )
        return transport
    except OSError as e:
        logger.error("Failed to start UDP server", error=str(e), port=settings.BINPROTO_UDP_PORT)
        return None
