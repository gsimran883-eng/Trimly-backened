import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'my_app',
      home: Scaffold(
        appBar: AppBar(title: Text('my_app')),
        body: Center(child: Text('Hello, world!')),
      ),
    );
  }
}
