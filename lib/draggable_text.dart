import 'package:flutter/material.dart';

class EditableItem {
  final String id;
  String text;
  Offset position;
  Color color;

  EditableItem({required this.id, required this.text, required this.position, required this.color});
}

class EditableTextWidget extends StatefulWidget {
  final EditableItem item;

  const EditableTextWidget({required this.item, Key? key}) : super(key: key);

  @override
  State<EditableTextWidget> createState() => _EditableTextWidgetState();
}

class _EditableTextWidgetState extends State<EditableTextWidget> {
  late Offset position;
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    position = widget.item.position;
    _controller = TextEditingController(text: widget.item.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
            widget.item.position = position;
          });
        },
        onTap: () {
          setState(() {
            _isEditing = true;
          });
        },
        child: _isEditing
            ? SizedBox(
                width: 200,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onSubmitted: (value) {
                    setState(() {
                      widget.item.text = value;
                      _isEditing = false;
                    });
                  },
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: widget.item.color,
                  ),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              )
            : Text(
                widget.item.text,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: widget.item.color,
                  shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                ),
              ),
      ),
    );
  }
}
