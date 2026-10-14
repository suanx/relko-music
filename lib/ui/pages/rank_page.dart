import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../design_tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/song_action_sheets.dart';

/// 排行榜目录页：按分类展示全部榜单（星耀榜/地区榜/特色榜/全球榜/曲风榜）。
///
/// 对应后端接口 `/rank/list`，点击榜单进入 [RankSongsPage]。
class RankPage extends StatefulWidget {
  const RankPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  List<RankBoard> _boards = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await widget.api.rankList();
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _openBoard(RankBoard board) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankSongsPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          board: board,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '排行榜',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Center(child: Text('排行榜加载失败\n$_error')),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonal(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_boards.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无榜单数据')),
        ],
      );
    }

    // 按分类分组展示，保持接口返回顺序
    final grouped = <String, List<RankBoard>>{};
    for (final board in _boards) {
      grouped.putIfAbsent(board.classifyLabel, () => []).add(board);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          for (final board in entry.value)
            _RankBoardTile(
              board: board,
              onTap: () => _openBoard(board),
            ),
        ],
      ],
    );
  }
}

class _RankBoardTile extends StatelessWidget {
  const _RankBoardTile({required this.board, required this.onTap});

  final RankBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Artwork(url: board.coverUrl, size: 52, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        board.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        board.classifyLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个榜单的歌曲列表页（对应接口 `/rank/audio`，滚动分页）。
class RankSongsPage extends StatefulWidget {
  const RankSongsPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.board,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final RankBoard board;

  @override
  State<RankSongsPage> createState() => _RankSongsPageState();
}

class _RankSongsPageState extends State<RankSongsPage> {
  final _scrollController = ScrollController();
  final _songs = <Song>[];
  var _page = 1;
  var _total = 0;
  var _hasMore = true;
  var _loading = true;
  var _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.rankSongs(widget.board.id, page: 1);
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(result.songs);
        _total = result.total;
        _page = 2;
        _hasMore = result.songs.length >= 30 && result.songs.length < result.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || !_hasMore || _loadingMore) return;
    if (_scrollController.position.extentAfter < 500) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.api.rankSongs(widget.board.id, page: _page);
      if (!mounted) return;
      setState(() {
        _songs.addAll(result.songs);
        _page++;
        _hasMore = result.songs.length >= 30 && _songs.length < result.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _play(int index) {
    widget.player.playSong(_songs[index], queue: List<Song>.of(_songs));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.board.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: _songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                widget.player.playSong(
                  _songs.first,
                  queue: List<Song>.of(_songs),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放全部'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败\n$_error'),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadFirstPage,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_songs.isEmpty) {
      return const Center(child: Text('该榜单暂无歌曲'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: _songs.length + 1,
      itemBuilder: (context, index) {
        if (index == _songs.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                _hasMore ? '' : '已加载全部 $_total 首歌',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }
        final song = _songs[index];
        return _RankSongTile(
          song: song,
          index: index + 1,
          player: widget.player,
          auth: widget.auth,
          onTap: () => _play(index),
        );
      },
    );
  }
}

class _RankSongTile extends StatelessWidget {
  const _RankSongTile({
    required this.song,
    required this.index,
    required this.player,
    required this.auth,
    required this.onTap,
  });

  final Song song;
  final int index;
  final PlayerController player;
  final AuthController auth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final active = player.currentSong?.hash == song.hash;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          onLongPress: () => showSongActionSheet(
            context: context,
            song: song,
            actions: [
              SongSheetAction(
                icon: Icons.playlist_add_rounded,
                title: '下一首播放',
                onTap: () => player.addToQueue(song),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$index',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: active
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Artwork(url: song.coverUrl, size: 44, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: active
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (active && player.isPlaying)
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}