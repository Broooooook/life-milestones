import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = store.search(_q);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜尋標題、備註、分類或日期',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: _q.trim().isEmpty
          ? Center(child: Text('例如：輪胎、紅利、綠島、2011', style: TextStyle(color: cs.onSurfaceVariant)))
          : results.isEmpty
              ? Center(child: Text('找不到「$_q」', style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (context, i) {
                    final e = results[i];
                    return EventListTile(
                      e,
                      trailing: e.amount == null ? null : fmtInt(e.amount!),
                      onTap: () => Navigator.of(context).pop(e),
                    );
                  },
                ),
    );
  }
}
