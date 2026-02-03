import 'package:flutter/material.dart';

class VerificationSubmissionSheet extends StatelessWidget {
  const VerificationSubmissionSheet({
    super.key,
    required this.userRow,
    required this.docs,
    this.onApprove,
    this.onReject,
    this.busy = false,
  });

  final Map<String, dynamic> userRow;
  final List<Map<String, dynamic>> docs;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool busy;

  static const _purpleDark = Color(0xFF4B18C9);

  bool _isImage(Map<String, dynamic> d) {
    final mime = (d['mime'] ?? '').toString().toLowerCase();
    final url = (d['url'] ?? '').toString().toLowerCase();
    return mime.startsWith('image/') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png') ||
        url.endsWith('.webp');
  }

  static String _prettyType(String t) {
    switch (t) {
      case 'id_front':
        return 'ID — Front';
      case 'id_back':
        return 'ID — Back';
      case 'selfie':
        return 'Selfie with ID';
      case 'license':
        return 'Driver’s License';
      case 'vehicle_orcr':
        return 'Vehicle OR/CR';
      default:
        return t.isEmpty ? 'Document' : t;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (userRow['name'] ?? 'Unknown').toString();
    final role = (userRow['role'] ?? '—').toString();
    final status = (userRow['verification_status'] ?? '').toString();

    final imageDocs = docs.where(_isImage).toList();
    final fileDocs = docs.where((d) => !_isImage(d)).toList();

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder:
            (_, ctrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Header with actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFF2EEFF),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: _purpleDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 6,
                                children: [
                                  _chip(role.toUpperCase(), Colors.indigo),
                                  _chip(
                                    status.isEmpty ? 'pending' : status,
                                    status == 'approved'
                                        ? Colors.green
                                        : status == 'rejected'
                                        ? Colors.red
                                        : Colors.orange,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (onReject != null || onApprove != null)
                          Row(
                            children: [
                              if (onReject != null)
                                OutlinedButton.icon(
                                  onPressed: busy ? null : onReject,
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  label: const Text('Reject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              if (onApprove != null)
                                FilledButton.icon(
                                  onPressed: busy ? null : onApprove,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label:
                                      busy
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text('Approve'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [
                        if (imageDocs.isNotEmpty) ...[
                          const Text(
                            'Photos',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ImageGrid(
                            docs: imageDocs,
                            onOpenViewer: (index) {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder:
                                      (_) => _ImageGalleryPage(
                                        images: imageDocs,
                                        initialIndex: index,
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (fileDocs.isNotEmpty) ...[
                          const Text(
                            'Other Files',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children:
                                fileDocs.map((d) {
                                  final type = (d['type'] ?? '').toString();
                                  final url = (d['url'] ?? '').toString();
                                  final mime = (d['mime'] ?? '').toString();
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: Color(0xFFF2EEFF),
                                        child: Icon(
                                          Icons.insert_drive_file,
                                          color: _purpleDark,
                                        ),
                                      ),
                                      title: Text(_prettyType(type)),
                                      subtitle: Text(
                                        mime.isEmpty ? url : mime,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: const Text('Open'),
                                      onTap: () {
                                        showDialog<void>(
                                          context: context,
                                          builder:
                                              (_) => AlertDialog(
                                                title: const Text('Open file'),
                                                content: SelectableText(url),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                        ),
                                                    child: const Text('Close'),
                                                  ),
                                                ],
                                              ),
                                        );
                                      },
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],

                        if (imageDocs.isEmpty && fileDocs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'No documents found for this submission.',
                              style: TextStyle(color: Color(0xFF667085)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  static Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.docs, required this.onOpenViewer});
  final List<Map<String, dynamic>> docs;
  final void Function(int) onOpenViewer;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: docs.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final d = docs[i];
        final url = (d['url'] ?? '').toString();
        final type = (d['type'] ?? '').toString();
        return GestureDetector(
          onTap: () => onOpenViewer(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(url, fit: BoxFit.cover),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      VerificationSubmissionSheet._prettyType(type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImageGalleryPage extends StatefulWidget {
  const _ImageGalleryPage({
    required this.images,
    this.initialIndex = 0,
    super.key,
  });
  final List<Map<String, dynamic>> images;
  final int initialIndex;

  @override
  State<_ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<_ImageGalleryPage> {
  late final PageController _pc = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: const Text('Submission Photos'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        itemBuilder: (_, i) {
          final url = (widget.images[i]['url'] ?? '').toString();
          final type = (widget.images[i]['type'] ?? '').toString();
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: Image.network(url, fit: BoxFit.contain)),
                  const SizedBox(height: 8),
                  Text(
                    VerificationSubmissionSheet._prettyType(type),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
