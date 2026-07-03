// Update restaurant location to California (emulator default)
db.restaurants.updateOne(
  {_id: ObjectId("699689194afb27eeeb912d26")},
  {$set: {"location.coordinates": [-122.084, 37.4219983]}}
);

// Also update any pending orders with this restaurant
db.orders.updateMany(
  {"restaurant_id": "699689194afb27eeeb912d26"},
  {$set: {"pickup_location.coordinates": [-122.084, 37.4219983]}}
);

print("Updated restaurant and orders to California coordinates");
