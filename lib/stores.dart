import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:AnsarPortal/store_details.dart';

class Store {
  final int id;
  final String name;
  final String description;
  final List<String> categories;
  int totalLikes;
  final List<String> images;
  bool isLiked;
  final bool archived; // Add archived property

  Store({
    required this.id,
    required this.name,
    required this.description,
    required this.categories,
    required this.totalLikes,
    required this.images,
    this.isLiked = false,
    required this.archived, // Initialize archived property
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: int.parse(json['store_id'].toString()),
      name: json['store_name'] ?? '',
      description: json['description'] ?? '',
      categories: List<String>.from(json['categories'] ?? []),
      totalLikes: int.tryParse(json['total_likes'].toString()) ?? 0,
      images: List<String>.from(json['images'] ?? []),
      isLiked: false, // Initialize isLiked property
      archived: json['archived'] == true, // Parse archived property from JSON
    );
  }
}

class StoresPage extends StatefulWidget {
  const StoresPage({Key? key}) : super(key: key);

  @override
  _StoresPageState createState() => _StoresPageState();
}

class _StoresPageState extends State<StoresPage> {
  List<Store> stores = [];
  List<Store> filteredStores = [];
  List<String> categories = [];
  String? selectedCategory;
  String? userId;
  final storage = const FlutterSecureStorage();


  Future<void> fetchStores() async {
    try {
      final response = await http.get(Uri.parse('https://ansarportal-deaa9ded50c7.herokuapp.com/api/view_stores.php'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        setState(() {
          // Filter out archived stores
          stores = jsonResponse.map((store) {
            final parsedStore = Store.fromJson(store);
            print('Store ${parsedStore.id}: archived=${parsedStore.archived}');
            return parsedStore;
          })
              .where((store) => !store.archived) // Exclude archived stores
              .toList();
          filteredStores = List.from(stores);
        });
        await getUserId();
        await fetchUserLikes();
      } else {
        throw Exception('Failed to load stores');
      }
    } catch (error) {
      print('Error fetching stores: $error');
    }
  }



  Future<void> fetchCategories() async {
    try {
      final response = await http.get(Uri.parse('https://ansarportal-deaa9ded50c7.herokuapp.com/api/view_categories.php'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        setState(() {
          categories = jsonResponse.map((category) => category['category_name'].toString()).toList();
        });
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (error) {
      print('Error fetching categories: $error');
    }
  }


  // Method to retrieve user ID from Flutter Secure Storage
  Future<void> getUserId() async {
    userId = await storage.read(key: 'userId');
    print('User ID: $userId'); // Print user ID
  }

  Future<void> fetchUserLikes() async {
    try {
      // Make POST request to fetch user likes with user ID from session
      final response = await http.post(
        Uri.parse('https://ansarportal-deaa9ded50c7.herokuapp.com/api/fetch_user_likes.php'),
        body: {'user_id': userId!},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        print('Fetch User Likes Response: $jsonResponse'); // Print response
        setState(() {
          // Convert the list of liked store IDs to a set for efficient lookup
          final likedStoreIdsSet = Set<int>.from(jsonResponse['liked_stores']);

          // Update isLiked property for each store based on user likes
          for (var store in stores) {
            final isLiked = likedStoreIdsSet.contains(store.id);
            print('Store ${store.id} isLiked: $isLiked');
            store.isLiked = isLiked;
          }
        });
      } else {
        throw Exception('Failed to load user likes');
      }
    } catch (error) {
      print('Error fetching user likes: $error');
      // Handle error accordingly
    }
  }

  // Method to toggle like/unlike a store
  Future<void> toggleLike(Store store) async {
    try {
      // Make POST request to like/unlike a store with user ID from session
      final response = await http.post(
        Uri.parse('https://ansarportal-deaa9ded50c7.herokuapp.com/api/like_store.php'),
        body: {
          'user_id': userId!,
          'store_id': store.id.toString(),
          'action': store.isLiked ? 'unlike' : 'like',
        },
      );
      if (response.statusCode == 200) {
        // Toggle isLiked property based on the response
        setState(() {
          store.isLiked = !store.isLiked;
          print('Store ${store.id} isLiked toggled: ${store.isLiked}');
          // Update totalLikes based on the response
          if (store.isLiked) {
            store.totalLikes++;
          } else {
            store.totalLikes--;
          }
        });

        // Save the updated liked status locally
        await saveLikedStatus(store.id.toString(), store.isLiked);
      } else {
        throw Exception('Failed to toggle like');
      }
    } catch (error) {
      print('Error toggling like: $error');
      // Handle error accordingly
    }
  }

  // Method to save the liked status locally
  Future<void> saveLikedStatus(String storeId, bool isLiked) async {
    await storage.write(key: 'liked_$storeId', value: isLiked.toString());
  }

  // Method to retrieve the liked status locally
  Future<bool?> getLikedStatus(String storeId) async {
    final likedStatus = await storage.read(key: 'liked_$storeId');
    return likedStatus != null ? likedStatus == 'true' : null;
  }

  void handleSearch(String query) async {
    setState(() async {
      if (query.isNotEmpty) {
        // Make GET request to search stores
        http.Response response = await http.get(
          Uri.parse(
              'https://ansarportal-deaa9ded50c7.herokuapp.com/api/search_stores.php?query=$query'),
        );
        if (response.statusCode == 200) {
          final List<dynamic> jsonResponse = json.decode(response.body);
          setState(() {
            // Update filteredStores with search results
            filteredStores =
                jsonResponse.map((store) => Store.fromJson(store)).toList();
          });
          // Fetch user ID
          await getUserId();
          // Fetch user likes after loading stores
          await fetchUserLikes();
        } else {
          throw Exception('Failed to load stores');
        }
      } else {
        // If query is empty, show all stores
        setState(() {
          filteredStores = List.from(stores);
        });
      }
    });
  }


  // Define a TextEditingController
  late TextEditingController _searchController;

  // Override initState() method to fetch stores, user ID, and liked status when widget is initialized
  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    fetchStores(); // Fetch stores and user ID
    fetchCategories();
  }

  @override
  void dispose() {
    // Dispose the TextEditingController
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('STORES', style: TextStyle(color: Colors.white,
            fontFamily: 'kuro',
            fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange[700], // Dark orange background color
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
      ),

      body:Column(
        children: [
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              cursorColor: Colors.deepOrange[700],
              style: TextStyle(fontFamily: 'kuro'),
              onChanged: (value) {
                setState(() {
                  handleSearch(value);
                });
              },
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(vertical: 15.0),
                hintStyle: TextStyle(fontFamily: 'kuro'),
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear(); // Clear the search text
                    setState(() {
                      handleSearch(
                          ''); // Reset the filtered stores to show all stores
                    });
                  },
                ),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.deepOrange[700]!), // Set border color to deepOrange[700]
                ),
              ),
            ),
          ),

          SizedBox(height: 5),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [

                  GestureDetector(
                    onTap: () {
                      setState(() {

                        selectedCategory = null;
                        filteredStores = List.from(stores);
                      });
                    },

                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      margin: EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: selectedCategory == null ? Colors.deepOrange : null,
                        borderRadius: BorderRadius.circular(20),
                        border: selectedCategory == null
                            ? null
                            : Border.all(color: Colors.grey),

                      ),
                      child: Text(
                        'All Stores/ متاجر',
                        style: TextStyle(fontFamily: 'kuro', color: selectedCategory == null ? Colors.white : null),
                      ),
                    ),
                  ),

                  SizedBox(width: 5),
                  ...categories.map((category) {
                    final isSelected = category == selectedCategory;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedCategory = isSelected ? null : category;
                          filteredStores = selectedCategory != null
                              ? stores.where((store) => store.categories.contains(selectedCategory)).toList()
                              : List.from(stores);
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        margin: EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.deepOrange : null,
                          borderRadius: BorderRadius.circular(20),
                          border: isSelected
                              ? null
                              : Border.all(color: Colors.grey),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(fontFamily: 'kuro', color: isSelected ? Colors.white : null),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),

          SizedBox(height: 10),

          filteredStores.isEmpty
              ? Padding(
            padding: EdgeInsets.only(top: 100.0),
            child: Column(
              children: [
                Text(
                  "No available stores",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'kuro',
                  ),
                ),
                const SizedBox(height: 10,),
                Text(
                  "لا يوجد متاجر",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'kuro',
                  ),
                ),
              ],
            ),
          )
              :   Expanded(
            child: ListView.builder(
              itemCount: filteredStores.length,
              itemBuilder: (context, index) {
                final store = filteredStores[index];
                final String firstImage = store.images.isNotEmpty ? store.images
                    .first : '';


                return GestureDetector(
                  onTap: () {
                    if (filteredStores.isNotEmpty && index < filteredStores.length) {
                      final store = filteredStores[index];
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StoreDetailsPage(storeId: store.id),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 16.0),
                    // Adjust padding as needed
                    child: Card(
                      elevation: 4,
                      // Add elevation for a raised effect
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      // Add rounded corners
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            // Set aspect ratio for the image
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10)),
                              child: Image.network(
                                firstImage,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(16),
                            // Add padding inside the card
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      SizedBox(height: 8),
                                      Text(
                                        store.name,
                                        style: TextStyle(fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'kuro'), // Adjust font size and weight
                                      ),
                                      SizedBox(height: 8),
                                      // Add spacing between title and description
                                      Text(
                                        store.description,
                                        style: TextStyle(fontSize: 14,
                                            fontFamily: 'kuro'), // Adjust font size
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      iconSize: 30,
                                      // Increase the size of the IconButton
                                      icon: store.isLiked
                                          ? Icon(
                                          Icons.favorite, color: Colors.red)
                                          : Icon(Icons.favorite_border),
                                      onPressed: () => toggleLike(store),
                                    ),
                                    Text(
                                      '${store.totalLikes} Likes',
                                      style: TextStyle(fontSize: 14,
                                          fontFamily: 'kuro'), // Adjust font size
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white, // White background color
    );
  }
}
// Define main() function to run the app
void main() {
  runApp(const MaterialApp(
    home: StoresPage(),
  ));
}
