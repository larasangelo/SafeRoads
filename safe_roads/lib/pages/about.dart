import 'package:flutter/material.dart';

class About extends StatelessWidget {
  const About({super.key});
  
  @override
    Widget build(BuildContext context) {
      return Center(
        child: Text(
          "About Page",
          style: TextStyle(fontSize: 24.0),
        ),
      );
    }
}