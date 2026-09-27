import 'package:pinbench/features/workspace/services/share_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shareLinkFor', () {
    test('points at the /p/:projectId route', () {
      // A share link has to land on the circuit, not a landing page the
      // visitor then has to navigate from.
      expect(shareLinkFor('abc123', origin: 'https://example.com'), 'https://example.com/p/abc123');
    });

    test('does not double up the slash when the origin has a trailing one', () {
      expect(shareLinkFor('abc', origin: 'https://example.com/'), 'https://example.com/p/abc');
      expect(shareLinkFor('abc', origin: 'https://example.com///'), 'https://example.com/p/abc');
    });

    test('preserves a port, so local runs produce openable links', () {
      expect(shareLinkFor('abc', origin: 'http://localhost:8080'), 'http://localhost:8080/p/abc');
    });
  });

  _embedTests();

  _optionsTests();

  group('isProbablyEmail', () {
    test('accepts ordinary addresses', () {
      for (final email in [
        'bob@example.com',
        'bob.smith@example.co.uk',
        'bob+tag@example.com',
        'b@x.io',
        'BOB@EXAMPLE.COM',
      ]) {
        expect(isProbablyEmail(email), isTrue, reason: email);
      }
    });

    test('accepts an address with surrounding whitespace, since it is trimmed', () {
      expect(isProbablyEmail('  bob@example.com  '), isTrue);
    });

    test('rejects the mistakes people actually make', () {
      for (final bad in [
        '', // empty field
        '   ', // whitespace only
        'bob', // forgot the domain
        'bob@', // trailing @
        '@example.com', // missing local part
        'bob@example', // no dot in domain
        'bob@.com', // domain starts with a dot
        'bob@example.', // domain ends with a dot
        'bob@@example.com', // doubled @
        'bob smith@example.com', // internal space
      ]) {
        expect(isProbablyEmail(bad), isFalse, reason: '"$bad" should be rejected');
      }
    });

    test('stays permissive about unusual but legal addresses', () {
      // This check exists to catch typos, not to adjudicate RFC 5322. The
      // authoritative check is the invitee signing in with a verified address,
      // so a false rejection here is worse than a false accept: it blocks a
      // real user, whereas a bad invite just sits unclaimed.
      expect(isProbablyEmail("o'brien@example.com"), isTrue);
      expect(isProbablyEmail('user_name-123@sub.domain.example.museum'), isTrue);
    });
  });
}

/// A link is only correct if the flags the snippet writes are the flags the
/// route reads. These close that loop: the snippet is parsed back the way
/// `ProjectRoute` parses a real URL, so a snippet whose flag nothing acts on
/// cannot pass.
void _optionsTests() {
  ShareLinkOptions parse(String snippet) {
    final src = RegExp('src="([^"]+)"').firstMatch(snippet)!.group(1)!;
    return ShareLinkOptions.fromQuery(Uri.parse(src).queryParameters);
  }

  group('ShareLinkOptions', () {
    test('reads back what the embed snippet wrote', () {
      final snapshot = parse(embedSnippetFor('abc', origin: 'https://x.com'));
      expect(snapshot.embed, isTrue);
      expect(snapshot.live, isFalse);

      final live = parse(embedSnippetFor('abc', origin: 'https://x.com', live: true));
      expect(live.embed, isTrue);
      expect(live.live, isTrue);
    });

    test('a plain share link is neither embedded nor live', () {
      final options = ShareLinkOptions.fromQuery(
        Uri.parse(shareLinkFor('abc', origin: 'https://x.com')).queryParameters,
      );
      expect(options.embed, isFalse);
      expect(options.live, isFalse);
    });

    test('only an exact 1 turns a flag on', () {
      // A flag that changes what a link does should not be spelled loosely —
      // `?live=true` silently behaving as live would make the URL contract a
      // guessing game.
      for (final value in ['true', '0', 'yes', '', '1 ']) {
        final options = ShareLinkOptions.fromQuery({'embed': value, 'live': value});
        expect(options.embed, isFalse, reason: 'embed=$value');
        expect(options.live, isFalse, reason: 'live=$value');
      }
    });
  });
}

/// The embed snippet is pasted into someone else's page, so the parts that
/// matter are the ones a host page depends on: the right URL, the embed flag,
/// and attributes that keep it from misbehaving in an article.
void _embedTests() {
  group('embedSnippetFor', () {
    test('points at the share URL with the embed flag', () {
      final snippet = embedSnippetFor('abc123', origin: 'https://example.com');
      expect(snippet, contains('src="https://example.com/p/abc123?embed=1"'));
    });

    test('is a single self-contained iframe element', () {
      final snippet = embedSnippetFor('abc', origin: 'https://example.com');
      expect(snippet.startsWith('<iframe '), isTrue);
      expect(snippet.trim().endsWith('</iframe>'), isTrue);
      expect('<iframe'.allMatches(snippet).length, 1);
    });

    test('carries the attributes a host page needs', () {
      final snippet = embedSnippetFor('abc', origin: 'https://example.com');
      // Below the fold in most articles.
      expect(snippet, contains('loading="lazy"'));
      // Otherwise the browser mutes the buzzer.
      expect(snippet, contains('allow="autoplay"'));
      // Screen readers land on an unlabelled frame without this.
      expect(snippet, contains('title='));
      expect(snippet, contains('width="100%"'));
    });

    test('height is overridable, since the host owns their layout', () {
      expect(
        embedSnippetFor('abc', origin: 'https://x.com', height: 700),
        contains('height="700"'),
      );
      expect(embedSnippetFor('abc', origin: 'https://x.com'), contains('height="420"'));
    });

    test('live adds the flag; the default stays a snapshot', () {
      final live = embedSnippetFor('abc', origin: 'https://x.com', live: true);
      final snapshot = embedSnippetFor('abc', origin: 'https://x.com');
      expect(live, contains('?embed=1&live=1'));
      expect(snapshot, contains('?embed=1'));
      expect(snapshot, isNot(contains('live=1')));
    });

    test('live keeps embed=1 — the flags compose, they do not replace', () {
      // ?live=1 alone would render the full IDE inside the iframe.
      final live = embedSnippetFor('abc', origin: 'https://x.com', live: true);
      expect(live, contains('embed=1'));
    });

    test('does not break out of its own quoting', () {
      // The snippet is pasted raw into HTML, so a stray quote would let a
      // project id escape the src attribute.
      final snippet = embedSnippetFor('abc', origin: 'https://example.com');
      expect(snippet.split('src="').length, 2);
    });
  });
}
