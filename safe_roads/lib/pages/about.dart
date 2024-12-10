import 'package:flutter/material.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Why",
                  style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10.0),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    // child: Image.network(
                    //   'https://upload.wikimedia.org/wikipedia/commons/e/e4/Tree_frog_%28Pacific%29_edit.jpg',
                    //   fit: BoxFit.contain,
                    //   height: 120,
                    // ),
                  ),
                ),
                const SizedBox(height: 20.0),
                const Text(
                  "How",
                  style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10.0),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    // child: Image.network(
                    //   'https://upload.wikimedia.org/wikipedia/commons/8/8b/Salamandra_salamandra_MHNT.jpg',
                    //   fit: BoxFit.contain,
                    //   height: 120,
                    // ),
                  ),
                ),
                const SizedBox(height: 20.0),
                const Text(
                  "Who",
                  style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10.0),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    // child: Image.network(
                    //   'https://upload.wikimedia.org/wikipedia/commons/3/3f/Frog_on_rock.jpg',
                    //   fit: BoxFit.contain,
                    //   height: 120,
                    // ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
