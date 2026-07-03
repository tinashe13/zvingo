import pytest
from httpx import AsyncClient
from app.main import app
from app.auth.models import User
from app.auth.service import create_access_token
from app.order.models import Order, OrderItem
from app.order.state_machine import OrderState
from app.dispatch.service import dispatch_service
from datetime import datetime

@pytest.mark.asyncio
async def test_get_driver_state_active_order(client: AsyncClient, test_user: User):
    # 1. Setup: Create driver and order
    driver = test_user
    driver.role = "DRIVER"
    await driver.save()
    
    token = create_access_token({"sub": str(driver.id)})
    headers = {"Authorization": f"Bearer {token}"}
    
    # Create order
    order = Order(
        merchant_id="merchant_123",
        consumer_id="consumer_456",
        driver_id=str(driver.id),
        state=OrderState.ACCEPTED,
        items=[OrderItem(name="Burger", quantity=1, price=10.0)],
        total_amount=10.0,
        pickup_location={"lat": 10.0, "lng": 20.0},
        dropoff_location={"lat": 10.1, "lng": 20.1}
    )
    await order.insert()
    
    # Set driver online
    await dispatch_service.redis.hset(
        f"driver:{driver.id}",
        mapping={"status": "ONLINE"}
    )
    
    # 2. Action: Get state
    response = await client.get("/dispatch/state", headers=headers)
    
    # 3. Assert
    assert response.status_code == 200
    data = response.json()
    
    assert data["status"] == "ONLINE"
    assert data["active_order"] is not None
    assert data["active_order"]["order_id"] == str(order.id)
    assert data["active_order"]["state"] == "ACCEPTED"
    # Check short_id format
    assert data["active_order"]["short_id"].startswith("ZV")

@pytest.mark.asyncio
async def test_get_driver_state_no_order(client: AsyncClient, test_user: User):
    # 1. Setup: Driver with no active order
    driver = test_user
    driver.role = "DRIVER"
    await driver.save()
    
    token = create_access_token({"sub": str(driver.id)})
    headers = {"Authorization": f"Bearer {token}"}
    
    # 2. Action: Get state
    response = await client.get("/dispatch/state", headers=headers)
    
    # 3. Assert
    assert response.status_code == 200
    data = response.json()
    assert data["active_order"] is None
