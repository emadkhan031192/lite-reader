import 'package:flutter/material.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/document.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/press_scale.dart';

/// Picks one PDF from the library. A [documentId] of 0 or null means
/// "none chosen".
class DocPickerField extends StatelessWidget {
  const DocPickerField({
    super.key,
    required this.documentId,
    required this.onChanged,
    this.label = 'Document',
  });

  final int? documentId;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryDocument>>(
      future: AppDatabase.instance.getAllDocuments(),
      builder: (context, snapshot) {
        final pdfs = (snapshot.data ?? const <LibraryDocument>[])
            .where((d) => d.isPdf)
            .toList();
        LibraryDocument? selected;
        if (documentId != null && documentId != 0) {
          for (final d in pdfs) {
            if (d.id == documentId) {
              selected = d;
              break;
            }
          }
        }
        final current = selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label.toUpperCase(), style: AppText.sectionLabel),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: current == null
                  ? 'Choose a PDF'
                  : 'Change document, currently ${current.displayName}',
              child: PressScale(
                onTap: () => _openPicker(context, pdfs),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border.fromBorderSide(BorderSide(color: AppColors.hairline)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: current == null
                            ? const Text(
                                'Choose a PDF…',
                                style: AppText.bodySecondary,
                              )
                            : Text(
                                current.displayName,
                                style: AppText.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 22,
                        color: AppColors.tertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    List<LibraryDocument> pdfs,
  ) async {
    final id = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Choose a PDF', style: AppText.body),
            const SizedBox(height: 8),
            Flexible(
              child: pdfs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No PDFs in the library yet.',
                        style: AppText.bodySecondary,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: pdfs.length,
                      itemBuilder: (context, i) {
                        final d = pdfs[i];
                        return ListTile(
                          title: Text(
                            d.displayName,
                            style: AppText.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${d.pageCount} pages',
                            style: AppText.monoSize(12),
                          ),
                          onTap: () => Navigator.of(sheetContext).pop(d.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (id != null) onChanged(id);
  }
}
