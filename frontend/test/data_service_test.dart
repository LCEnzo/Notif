import 'package:flutter_test/flutter_test.dart';
import 'package:notif/services/data.dart';

void main() {
  group('LinkSort', () {
    test('apiValue sends correct DRF ordering strings', () {
      expect(LinkSort.newest.apiValue, '-pk');
      expect(LinkSort.oldest.apiValue, 'pk');
      expect(LinkSort.recentlyScraped.apiValue, '-last_scraped,-pk');
      expect(LinkSort.leastRecentlyScraped.apiValue, 'last_scraped,pk');
    });

    test('label is human-readable', () {
      expect(LinkSort.newest.label, 'Newest');
      expect(LinkSort.oldest.label, 'Oldest');
      expect(LinkSort.recentlyScraped.label, 'Recently scraped');
      expect(LinkSort.leastRecentlyScraped.label, 'Least recently scraped');
    });
  });

  group('NotifSort', () {
    test('apiValue sends combined DRF ordering with tiebreaker', () {
      expect(NotifSort.newest.apiValue, '-update__created_at,-pk');
      expect(NotifSort.oldest.apiValue, 'update__created_at,pk');
    });

    test('label is human-readable', () {
      expect(NotifSort.newest.label, 'Newest');
      expect(NotifSort.oldest.label, 'Oldest');
    });
  });

  group('pagination math', () {
    test('totalPages for link pagination (page_size=100)', () {
      int linkPages(int count) => count == 0 ? 1 : (count / 100).ceil();
      expect(linkPages(0), 1);
      expect(linkPages(1), 1);
      expect(linkPages(99), 1);
      expect(linkPages(100), 1);
      expect(linkPages(101), 2);
      expect(linkPages(500), 5);
    });

    test('totalPages for notification pagination (page_size=50)', () {
      int notifPages(int count) => count == 0 ? 1 : (count / 50).ceil();
      expect(notifPages(0), 1);
      expect(notifPages(1), 1);
      expect(notifPages(49), 1);
      expect(notifPages(50), 1);
      expect(notifPages(51), 2);
      expect(notifPages(1000), 20);
    });
  });

  group('pagination window algorithm', () {
    /// Pure-function replica of _PageNumbers._buildPageList for testing.
    List<_PageItem> buildPageList(int currentPage, int totalPages) {
      if (totalPages <= 7) {
        return [
          for (var p = 1; p <= totalPages; p++)
            _PageItem(label: p.toString(), page: p, isActive: p == currentPage),
        ];
      }

      final items = <_PageItem>[];
      items.add(_PageItem(
        label: '1',
        page: 1,
        isActive: currentPage == 1,
      ));

      if (currentPage > 1) {
        items.add(_PageItem(label: 'prev', page: currentPage - 1));
      }

      final start = (currentPage - 2).clamp(2, totalPages - 4);
      final end = (currentPage + 2).clamp(5, totalPages - 1);

      if (start > 2) items.add(const _PageItem(label: '...'));

      for (var p = start; p <= end; p++) {
        items.add(_PageItem(
          label: p.toString(),
          page: p,
          isActive: p == currentPage,
        ));
      }

      if (end < totalPages - 1) items.add(const _PageItem(label: '...'));

      if (currentPage < totalPages - 1) {
        items.add(_PageItem(label: 'next', page: currentPage + 1));
      }

      items.add(_PageItem(
        label: totalPages.toString(),
        page: totalPages,
        isActive: currentPage == totalPages,
      ));

      return items;
    }

    test('small page count shows all pages, no ellipsis', () {
      final pages = buildPageList(3, 7);
      final labels = pages.map((p) => p.label).toList();
      expect(labels, ['1', '2', '3', '4', '5', '6', '7']);
      expect(pages[2].isActive, isTrue);
    });

    test('on page 1 of 20, no prev button, has next and ellipsis', () {
      final pages = buildPageList(1, 20);
      final labels = pages.map((p) => p.label).toList();
      expect(labels.first, '1');
      expect(labels.last, '20');
      expect(labels, contains('...'));
      expect(labels, isNot(contains('prev')));
      expect(labels, contains('next'));
    });

    test('on page 10 of 20, has prev, next, and both ellipses', () {
      final pages = buildPageList(10, 20);
      final labels = pages.map((p) => p.label).toList();
      expect(labels.first, '1');
      expect(labels.last, '20');
      expect(labels, contains('prev'));
      expect(labels, contains('next'));
      final dots = labels.where((l) => l == '...').length;
      expect(dots, 2);
      expect(labels, contains('10'));
    });

    test('on last page, no next button, has prev', () {
      final pages = buildPageList(20, 20);
      final labels = pages.map((p) => p.label).toList();
      expect(labels, isNot(contains('next')));
      expect(labels, contains('prev'));
    });

    test('page 2 of 20 has prev button', () {
      final pages = buildPageList(2, 20);
      final labels = pages.map((p) => p.label).toList();
      expect(labels, contains('prev'));
    });

    test('active page is marked isActive', () {
      final pages = buildPageList(5, 10);
      final active = pages.where((p) => p.isActive).toList();
      expect(active.length, 1);
      expect(active.first.label, '5');
    });

    test('totalPages=1 returns just page 1', () {
      final pages = buildPageList(1, 1);
      expect(pages.length, 1);
      expect(pages.first.label, '1');
      expect(pages.first.isActive, isTrue);
    });
  });
}

class _PageItem {
  const _PageItem({required this.label, this.page, this.isActive = false});
  final String label;
  final int? page;
  final bool isActive;
}
