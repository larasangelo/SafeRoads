import 'package:flutter/material.dart';

class AlertDistancePage extends StatefulWidget {
  final String title;
  final String chosen;
  final String info;
  final String selectedValue;
  final Function(String) onValueChanged;

  const AlertDistancePage({
    super.key,
    required this.title,
    required this.chosen,
    required this.info,
    required this.selectedValue,
    required this.onValueChanged,
  });

  @override
  State<AlertDistancePage> createState() => _AlertDistancePageState();
}

class _AlertDistancePageState extends State<AlertDistancePage> {
  late String _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selectedValue;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final horizontalPadding = screenWidth * 0.05;
    final verticalSpacing = screenHeight * 0.02;
    final baseFontSize = screenWidth * 0.04; // Scales with width
    final titleFontSize = baseFontSize * 1.1;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(fontSize: titleFontSize)),
      ),
      body: Padding(
        padding: EdgeInsets.all(horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: verticalSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.chosen,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedValue,
                  style: TextStyle(
                    fontSize: baseFontSize,
                    color: Theme.of(context).colorScheme.onSurface, // Ensures readable text
                  ),
                  dropdownColor: Theme.of(context).colorScheme.surface, // Sets background
                  iconEnabledColor: Theme.of(context).colorScheme.onSurface,
                  items: const [
                    DropdownMenuItem(value: "250 m", child: Text("250 m")),
                    DropdownMenuItem(value: "500 m", child: Text("500 m")),
                    DropdownMenuItem(value: "1 km", child: Text("1 km")),
                  ],
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedValue = newValue;
                      });
                      widget.onValueChanged(newValue);
                    }
                  },
                )
              ],
            ),
            SizedBox(height: verticalSpacing),
            Text(
              widget.info,
              style: TextStyle(fontSize: baseFontSize),
            ),
          ],
        ),
      ),
    );
  }
}