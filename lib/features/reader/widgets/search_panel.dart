import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/lr_icon_button.dart';

/// In-reader text search card, shown under the top bar.
///
/// Text field submits to [PdfTextSearcher.startTextSearch]; the mono counter
/// shows the current match, and the arrows step through matches with
/// wraparound.
class ReaderSearchPanel extends StatefulWidget {
  const ReaderSearchPanel({
    super.key,
    required this.searcher,
    required this.onClose,
  });

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<ReaderSearchPanel> createState() => _ReaderSearchPanelState();
}

class _ReaderSearchPanelState extends State<ReaderSearchPanel> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.searcher.addListener(_onSearcherChanged);
  }

  @override
  void dispose() {
    widget.searcher.removeListener(_onSearcherChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSearcherChanged() {
    if (mounted) setState(() {});
  }

  void _submit(String pattern) {
    widget.searcher.startTextSearch(
      pattern,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _step(int delta) {
    final searcher = widget.searcher;
    final total = searcher.matches.length;
    if (total == 0) return;
    final current = searcher.currentIndex ?? (delta > 0 ? -1 : 0);
    var next = (current + delta) % total;
    if (next < 0) next += total;
    searcher.goToMatchOfIndex(next);
  }

  @override
  Widget build(BuildContext context) {
    final searcher = widget.searcher;
    final total = searcher.matches.length;
    final counter = searcher.isSearching && total == 0
        ? '…'
        : '${(searcher.currentIndex ?? -1) + 1} / $total';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Search in document',
              textField: true,
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: AppText.body,
                decoration: const InputDecoration(
                  hintText: 'Search in document',
                  hintStyle: AppText.small,
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                onChanged: (value) {
                  if (value.isEmpty) searcher.resetTextSearch();
                },
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              counter,
              textAlign: TextAlign.center,
              style: AppText.monoSize(12),
            ),
          ),
          LrIconButton(
            icon: Icons.keyboard_arrow_up,
            semanticLabel: 'Previous match',
            onPressed: total == 0 ? null : () => _step(-1),
          ),
          LrIconButton(
            icon: Icons.keyboard_arrow_down,
            semanticLabel: 'Next match',
            onPressed: total == 0 ? null : () => _step(1),
          ),
          LrIconButton(
            icon: Icons.close,
            semanticLabel: 'Close search',
            onPressed: () {
              searcher.resetTextSearch();
              widget.onClose();
            },
          ),
        ],
      ),
    );
  }
}
