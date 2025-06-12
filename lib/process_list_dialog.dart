import 'package:flutter/material.dart';

class ProcessListDialog extends StatefulWidget {
  final Function(String pid)? onProcessSelected; // Callback for when a process is selected

  final List<List<String>> processes;
  final List<String> headers;

  const ProcessListDialog({
    this.onProcessSelected,

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
  // int? _selectedRowIndex; // Selected row index might not be needed for card view or handled differently

  // Define a map for header to chinese tooltips
  final Map<String, String> _headerTooltips = {
    'USER': '用户名',
    'PID': '进程ID',
    'PPID': '父进程ID',
    'NAME': '程序包名/进程名',
    'VSZ': '虚拟内存大小',
    'RSS': '实际使用物理内存大小',
  };

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
        int userIndex = widget.headers.indexOf('USER');
        int pidIndex = widget.headers.indexOf('PID');
        int ppidIndex = widget.headers.indexOf('PPID');
        int nameIndex = widget.headers.indexOf('NAME');
        // Assuming VSZ and RSS might not always be present, handle gracefully
        int vszIndex = widget.headers.indexOf('VSZ');
        int rssIndex = widget.headers.indexOf('RSS');

        bool matches = false;
        if (userIndex != -1 && row[userIndex].toLowerCase().contains(query)) matches = true;
        if (pidIndex != -1 && row[pidIndex].toLowerCase().contains(query)) matches = true;
        if (ppidIndex != -1 && row[ppidIndex].toLowerCase().contains(query)) matches = true;
        if (nameIndex != -1 && row[nameIndex].toLowerCase().contains(query)) matches = true;
        if (vszIndex != -1 && row.length > vszIndex && row[vszIndex].toLowerCase().contains(query)) matches = true;
        if (rssIndex != -1 && row.length > rssIndex && row[rssIndex].toLowerCase().contains(query)) matches = true;

        return matches;
      }).toList();
    });
  }

  Widget _buildProcessCard(BuildContext context, List<String> processData) {
    int nameIndex = widget.headers.indexOf('NAME');
    int pidIndex = widget.headers.indexOf('PID');

    String processName = nameIndex != -1 && nameIndex < processData.length ? processData[nameIndex] : 'N/A';
    String pid = pidIndex != -1 && pidIndex < processData.length ? processData[pidIndex] : '';

    List<Widget> cardItems = [];
    // Iterate through desired headers for card content
    List<String> displayHeaders = ['USER', 'PID', 'PPID', 'VSZ', 'RSS'];

    for (String headerKey in displayHeaders) {
      int headerIndex = widget.headers.indexOf(headerKey);
      if (headerIndex != -1 && headerIndex < processData.length) {
        cardItems.add(
          Tooltip(
            message: _headerTooltips[headerKey] ?? headerKey,
            child: Chip(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              label: Text('$headerKey: ${processData[headerIndex]}'),
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 0.0),
              labelStyle: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize),
            ),
          )
        );
      } else if (headerKey == 'VSZ' || headerKey == 'RSS') {
        // Show data unavailable for VSZ/RSS if not present
        cardItems.add(
          Tooltip(
            message: _headerTooltips[headerKey] ?? headerKey,
            child: Chip(
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              label: Text('$headerKey: 数据不可用'),
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 0.0),
              labelStyle: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize, fontStyle: FontStyle.italic),
            ),
          )
        );
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        title: Text(processName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Wrap(
            spacing: 8.0, // Horizontal spacing between chips
            runSpacing: 4.0, // Vertical spacing between lines of chips
            children: cardItems,
          ),
        ),
        onTap: () {
          if (pid.isNotEmpty) {
            if (widget.onProcessSelected != null) {
              widget.onProcessSelected!(pid);
            } else {
              Navigator.of(context).pop(pid); // Default behavior: Return PID when card is tapped
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0), // Added padding around search bar
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索进程',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _filteredProcesses.isEmpty
              ? const Center(child: Text('没有找到进程'))
              : ListView.builder(
                  itemCount: _filteredProcesses.length,
                  itemBuilder: (context, index) {
                    return _buildProcessCard(context, _filteredProcesses[index]);
                  },
                ),
        ),
      ],
    );
  }
}
