from enum import Enum


class OrderState(str, Enum):
    CREATED = "CREATED"
    PICKED_UP = "PICKED_UP"
    ARRIVED_AT_CUSTOMER = "ARRIVED_AT_CUSTOMER"
    DELIVERED = "DELIVERED"


print("PICKED_UP == 'PICKED_UP':", OrderState.PICKED_UP == "PICKED_UP")
print(
    "PICKED_UP in ['ARRIVED_AT_CUSTOMER', 'PICKED_UP']:",
    OrderState.PICKED_UP in ["ARRIVED_AT_CUSTOMER", "PICKED_UP"],
)
print(
    "PICKED_UP in [OrderState.ARRIVED_AT_CUSTOMER, OrderState.PICKED_UP]:",
    OrderState.PICKED_UP in [OrderState.ARRIVED_AT_CUSTOMER, OrderState.PICKED_UP],
)
print(
    "[s.value for s in [ARRIVED_AT_CUSTOMER, PICKED_UP]]:",
    [s.value for s in [OrderState.ARRIVED_AT_CUSTOMER, OrderState.PICKED_UP]],
)
print("str(PICKED_UP):", str(OrderState.PICKED_UP))
print("PICKED_UP.value:", OrderState.PICKED_UP.value)
