class StoreAisle {
  final String name;
  final String categories;
  final String directions;
  final List<int> coordinates; // [x, y] relative to entrance (0,0)

  StoreAisle({
    required this.name,
    required this.categories,
    required this.directions,
    required this.coordinates,
  });
}

class StoreService {
  final List<StoreAisle> aisles = [
    StoreAisle(
      name: "Grocery & Dairy",
      categories: "Milk, Bread, Eggs, Fruits, Vegetables, Yogurt",
      directions: "Walk 15 paces straight ahead from the entrance.",
      coordinates: [0, 15],
    ),
    StoreAisle(
      name: "Stationery & Office",
      categories: "Pens, Paper, Notebooks, Calculators, Tape",
      directions: "Walk 5 paces forward, then turn left and walk 10 paces.",
      coordinates: [-10, 5],
    ),
    StoreAisle(
      name: "Fashion & Apparel",
      categories: "Clothes, Shoes, Hats, Jackets, Socks",
      directions: "Walk 5 paces forward, then turn right and walk 10 paces.",
      coordinates: [10, 5],
    ),
    StoreAisle(
      name: "Electronics",
      categories: "Phones, Chargers, Headphones, Batteries, Laptops",
      directions: "Walk 15 paces forward, turn right, and walk 15 paces to the back corner.",
      coordinates: [15, 20],
    ),
    StoreAisle(
      name: "Pharmacy & Health",
      categories: "Medicine, Bandages, Vitamins, Soap, Shampoo",
      directions: "Walk 25 paces forward, then turn left and walk 5 paces to the window.",
      coordinates: [-5, 25],
    ),
  ];

  String getMapContext() {
    return aisles.map((a) => "- ${a.name}: Contains ${a.categories}. Directions: ${a.directions}").join("\n");
  }
}
