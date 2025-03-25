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
  _AlertDistancePageState createState() => _AlertDistancePageState();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.chosen,
                  style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _selectedValue,
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
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              widget.info,
              style: const TextStyle(fontSize: 16.0),
            ),
          ],
        ),
      ),
    );
  }
}