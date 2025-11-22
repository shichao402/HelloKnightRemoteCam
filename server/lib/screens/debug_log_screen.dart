import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';
import '../services/logger_service.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({Key? key}) : super(key: key);

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final LoggerService _logger = LoggerService();
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // 定期刷新
    Future.delayed(const Duration(milliseconds: 500), _autoRefresh);
  }

  void _autoRefresh() {
    if (mounted) {
      setState(() {
        if (_autoScroll && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      Future.delayed(const Duration(milliseconds: 500), _autoRefresh);
    }
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.request:
        return Colors.green;
      case LogLevel.response:
        return Colors.teal;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logger.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            tooltip: _autoScroll ? '暂停滚动' : '继续滚动',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              _logger.clearLogs();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清除')),
              );
            },
            tooltip: '清除日志',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final text = logs.map((log) {
                return '[${log.timeString}] [${log.level.levelString}] ${log.tag != null ? "[${log.tag}] " : ""}${log.message}';
              }).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('日志已复制到剪贴板')),
                );
              }
            },
            tooltip: '复制日志',
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('暂无日志'),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getLevelColor(log.level),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.level.levelString,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      log.message,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          log.timeString,
                          style: const TextStyle(fontSize: 10),
                        ),
                        if (log.tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              log.tag!,
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

