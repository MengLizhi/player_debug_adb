import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';

class ProcessListDialog extends StatefulWidget {
  final List<List<String>> processes;
  final List<String> headers;

  const ProcessListDialog({
    Key? key,
    required this.processes,
    required this.headers,
  }) : super(key: key);

  @override
  _ProcessListDialogState createState() => _ProcessListDialogState();
}

class _ProcessListDialogState extends State<ProcessListDialog> {
  late List<List<String>> _filteredProcesses;
  final TextEditingController _searchController = TextEditingController();
  int? _selectedRowIndex; // Add state variable for selected row index

  @override
  void initState() {
    super.initState();
    _filteredProcesses = widget.processes;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProcesses = widget.processes.where((row) {
        // Check if any of the relevant columns contain the query
        // Assuming headers are USER, PID, PPID, NAME in that order or can be found by name
        // Need to find the index of USER, PID, PPID, NAME columns
        int userIndex = widget.headers.indexOf('USER');
        int pidIndex = widget.headers.indexOf('PID');
        int ppidIndex = widget.headers.indexOf('PPID');
        int nameIndex = widget.headers.indexOf('NAME');

        bool matches = false;
        if (userIndex != -1 && row[userIndex].toLowerCase().contains(query)) matches = true;
        if (pidIndex != -1 && row[pidIndex].toLowerCase().contains(query)) matches = true;
        if (ppidIndex != -1 && row[ppidIndex].toLowerCase().contains(query)) matches = true;
        if (nameIndex != -1 && row[nameIndex].toLowerCase().contains(query)) matches = true;

        return matches;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column( // Removed AlertDialog
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索进程 (USER, PID, PPID, NAME)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: DataTable2(
            columns: widget.headers.map((header) => DataColumn2(label: Text(header))).toList(),
            rows: _filteredProcesses.asMap().entries.map((entry) { // Use asMap().entries to get index
              int index = entry.key;
              List<String> row = entry.value;
              return DataRow2(
                cells: row.map((cell) => DataCell(Text(cell))).toList(),
                selected: _selectedRowIndex == index, // Highlight selected row
                onSelectChanged: (selected) {
                  if (selected != null && selected) {
                    setState(() {
                      _selectedRowIndex = index;
                    });
                    // Find PID index and return PID
                    int pidIndex = widget.headers.indexOf('PID');
                    if (pidIndex != -1 && pidIndex < row.length) {
                      Navigator.of(context).pop(row[pidIndex]); // Return PID when row is tapped
                    }
                  } else {
                    setState(() {
                      _selectedRowIndex = null;
                    });
                  }
                },
              );
            }).toList(),
            fixedTopRows: 1,
          ),
        ),
      ],
    );
  }
}
