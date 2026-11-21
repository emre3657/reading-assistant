import 'package:flutter/material.dart';

enum AddPageSource { camera, gallery }

Future<AddPageSource?> chooseAddPageSource(BuildContext context) =>
    showDialog<AddPageSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sayfa ekle'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AddPageSource.camera),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: const Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: Text('Fotoğraf çek'),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AddPageSource.gallery),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: const Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: Text('Galeriden seç'),
              ),
            ),
          ),
        ],
      ),
    );
