import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PaginationWidget extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PaginationWidget({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  List<Widget> _buildPageButtons() {
    List<Widget> buttons = [];

    void addPage(int page) {
      buttons.add(
        TextButton(
          onPressed: page == currentPage ? null : () => onPageChanged(page),
          child: Text(
            '$page',
            style: TextStyle(
              fontWeight: page == currentPage ? FontWeight.bold : FontWeight.normal,
              color: page == currentPage ? Colors.blue : Colors.white,
            ),
          ),
        ),
      );
    }

    // Always show first page
    addPage(1);

    // Show ellipsis if current page > 3
    if (currentPage > 3) {
      buttons.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('...'),
      ));
    }

    // Show middle pages (currentPage -1, currentPage, currentPage +1)
    for (int i = currentPage - 1; i <= currentPage + 1; i++) {
      if (i > 1 && i < totalPages) {
        addPage(i);
      }
    }

    // Show ellipsis if current page is far from the end
    if (currentPage < totalPages - 2) {
      buttons.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('...'),
      ));
    }

    // Always show last page if more than 1
    if (totalPages > 1) {
      addPage(totalPages);
    }

    return buttons;
  }



  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _buildPageButtons(),
    );
  }
}
