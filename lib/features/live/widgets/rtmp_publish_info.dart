import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/srs_service.dart';

/// Displays publish URLs (RTMP/WHIP/SRT) the seller can use to push their
/// stream to SRS from OBS, Streamlabs, Larix Broadcaster, or another tool.
///
/// For an in-app camera publisher we'd add an RTMP plugin
/// (e.g. apivideo_live_stream); the MVP keeps it external.
class RtmpPublishInfo extends StatelessWidget {
  final PublishURLs publish;
  final String streamId;

  const RtmpPublishInfo({
    super.key,
    required this.publish,
    required this.streamId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Phát livestream của bạn',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mở OBS / Larix Broadcaster và push lên một trong các URL sau:',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _UrlRow(label: 'RTMP', value: publish.rtmp),
          const SizedBox(height: 8),
          _UrlRow(label: 'WHIP (WebRTC)', value: publish.whip),
          const SizedBox(height: 8),
          _UrlRow(label: 'SRT', value: publish.srt),
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  final String label;
  final String value;

  const _UrlRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã copy $label')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
