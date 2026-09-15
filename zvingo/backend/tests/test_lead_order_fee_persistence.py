"""Every fee the customer is quoted must survive onto the Order document.

The amount charged is derived from the Order's own fields
(`fee_calculator.breakdown_for_order`). So a fee that is accepted by the API,
validated, carried through checkout and then not assigned when the document is
built does not merely fail to display -- it silently discounts the order.

`service_fee` and `tax_amount` were exactly that: present on `OrderCreate`,
passed by `create_checkout`, and never set on `Order(...)`, so they fell back to
the model default of 0.0. A basket quoted at $16.15 charged $15.50.

Found by placing a real order against a running server and comparing the charge
to the quote.
"""

import inspect

import pytest

from app.order.schemas import CheckoutBasket, OrderCreate
from app.order.service import OrderService

#: Money fields a client can supply that must reach the stored document.
QUOTED_MONEY_FIELDS = (
    "total_amount",
    "delivery_fee",
    "service_fee",
    "tax_amount",
    "tip_amount",
)


def test_every_quoted_money_field_is_assigned_when_the_order_is_built():
    """Guards the whole class of bug, not just the two fields that were wrong.

    Adding a money field to OrderCreate without assigning it in create_order
    fails here instead of quietly undercharging in production.
    """
    src = inspect.getsource(OrderService.create_order)

    for field in QUOTED_MONEY_FIELDS:
        assert field in OrderCreate.model_fields, (
            f"{field} is expected on OrderCreate"
        )
        # Either assigned in the Order(...) call or explicitly computed after it
        # (delivery_fee is derived when the client does not supply one).
        assigned = (
            f"{field}=order_in.{field}" in src
            or f"order.{field} =" in src
        )
        assert assigned, (
            f"OrderCreate.{field} is accepted from the client but never reaches "
            f"the Order document, so the customer is charged as if it were zero"
        )


def test_checkout_basket_exposes_the_same_fee_fields():
    """A fee on the basket with nowhere to land is the same bug one layer up."""
    for field in ("subtotal", "delivery_fee", "service_fee", "tax_amount"):
        assert field in CheckoutBasket.model_fields


@pytest.mark.parametrize(
    ("subtotal", "delivery", "service", "tax", "tip", "expected"),
    [
        (13.00, 2.50, 0.65, 0.00, 0.00, 1615),   # the case found live
        (13.00, 2.50, 0.65, 1.30, 2.00, 1945),
        (0.00, 0.00, 0.00, 0.00, 0.00, 0),
        (9.99, 5.00, 0.50, 0.00, 1.01, 1650),
    ],
)
def test_the_charge_equals_the_sum_of_the_quoted_parts(
    subtotal, delivery, service, tax, tip, expected
):
    from types import SimpleNamespace

    from app.finance.fee_calculator import breakdown_for_order

    order = SimpleNamespace(
        total_amount=subtotal,
        delivery_fee=delivery,
        service_fee=service,
        tax_amount=tax,
        tip_amount=tip,
        discount_amount=0.0,
    )
    assert breakdown_for_order(order).customer_total_minor == expected
