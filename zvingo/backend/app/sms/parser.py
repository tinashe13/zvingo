import structlog
import redis.asyncio as aioredis
from app.config import settings

logger = structlog.get_logger()


class SMSParser:
    @staticmethod
    def parse_command(text: str):
        parts = text.strip().split()
        if not parts:
            return None, None

        command = parts[0].upper()
        args = parts[1:]

        return command, args

    @staticmethod
    async def _get_driver_by_phone(phone: str):
        from app.auth.models import User
        return await User.find_one(User.phone == phone, User.role == "driver")

    @staticmethod
    async def handle_command(phone: str, text: str) -> str:
        command, args = SMSParser.parse_command(text)
        logger.info("Received SMS command", phone=phone, command=command, args=args)

        if command == "ACCEPT":
            if not args:
                return "Invalid format. Use: ACCEPT <ORDER_ID>"
            order_id = args[0]
            driver = await SMSParser._get_driver_by_phone(phone)
            if not driver:
                return "Driver not found for this phone number"
            try:
                from app.order.service import OrderService
                from app.order.state_machine import OrderState
                order = await OrderService.transition_state(
                    order_id, OrderState.ACCEPTED, str(driver.id), driver_id=str(driver.id)
                )
                if order:
                    return f"Order {order_id} accepted. Head to merchant for pickup."
                return f"Order {order_id} not found"
            except Exception as e:
                logger.error("SMS ACCEPT failed", error=str(e), order_id=order_id)
                return f"Cannot accept order {order_id}. It may already be taken."

        elif command == "DECLINE":
            if not args:
                return "Invalid format. Use: DECLINE <ORDER_ID>"
            order_id = args[0]
            driver = await SMSParser._get_driver_by_phone(phone)
            if not driver:
                return "Driver not found for this phone number"
            try:
                # Previously this returned "declined" without telling dispatch,
                # so the offer sat until it timed out and the driver believed
                # they had released it.
                from app.dispatch.service import dispatch_service

                await dispatch_service.decline_offer(str(driver.id), order_id)
                return f"Order {order_id} declined."
            except Exception as e:
                logger.error(
                    "SMS DECLINE failed", error=str(e), order_id=order_id
                )
                return f"Cannot decline order {order_id}. Contact support."

        elif command == "COMPLETE":
            if not args:
                return "Invalid format. Use: COMPLETE <ORDER_ID>"
            order_id = args[0]
            driver = await SMSParser._get_driver_by_phone(phone)
            if not driver:
                return "Driver not found for this phone number"
            try:
                from app.order.service import OrderService
                from app.order.state_machine import OrderState
                # driver_id scopes the write to THIS driver's own delivery.
                # Without it any driver could text COMPLETE with any order id
                # and mark a stranger's delivery done, crediting themselves the
                # earnings. ACCEPT above has always passed it; COMPLETE did not.
                order = await OrderService.transition_state(
                    order_id,
                    OrderState.DELIVERED,
                    str(driver.id),
                    driver_id=str(driver.id),
                )
                if order:
                    return f"Order {order_id} delivered. Earnings updated."
                return f"Order {order_id} not found"
            except Exception as e:
                logger.error(
                    "SMS COMPLETE failed", error=str(e), order_id=order_id
                )
                return f"Cannot complete order {order_id}. Contact support."

        elif command == "STATUS":
            driver = await SMSParser._get_driver_by_phone(phone)
            if not driver:
                return "Driver not found"

            r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
            try:
                meta = await r.hgetall(f"driver:{str(driver.id)}")
                status = meta.get("status", "OFFLINE")

                from app.order.models import Order
                from app.order.state_machine import OrderState
                active = await Order.find(
                    Order.driver_id == str(driver.id),
                    {"state": {"$in": [
                        OrderState.ACCEPTED, OrderState.ARRIVED_AT_MERCHANT,
                        OrderState.PICKED_UP, OrderState.ARRIVED_AT_CUSTOMER
                    ]}}
                ).count()

                return f"Status: {status}. Active orders: {active}"
            finally:
                await r.close()

        return "Commands: ACCEPT <id>, DECLINE <id>, COMPLETE <id>, STATUS"
