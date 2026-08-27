import 'package:hotissue_collector/src/google_trends.dart';
import 'package:hotissue_collector/src/match.dart';
import 'package:hotissue_collector/src/news_rss.dart';
import 'package:hotissue_collector/src/normalize.dart';
import 'package:test/test.dart';

/// 실제 피드에서 잘라온 구조. 네임스페이스 접두사와 태그 이름이 그대로다.
const _trendsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<rss xmlns:ht="https://trends.google.com/trending/rss" version="2.0">
  <channel>
    <title>Daily Search Trends</title>
    <item>
      <title>기후동행카드</title>
      <ht:approx_traffic>500+</ht:approx_traffic>
      <pubDate>Wed, 26 Aug 2026 21:50:00 -0700</pubDate>
      <ht:picture>https://example.com/p.jpg</ht:picture>
      <ht:news_item>
        <ht:news_item_title>다음달 1일 &#39;기후동행패스&#39; 출시</ht:news_item_title>
        <ht:news_item_url>https://example.com/a</ht:news_item_url>
        <ht:news_item_source>경향신문</ht:news_item_source>
        <ht:news_item_snippet>신규카드 무료로 교환해준다</ht:news_item_snippet>
      </ht:news_item>
      <ht:news_item>
        <ht:news_item_title>두 번째 기사</ht:news_item_title>
      </ht:news_item>
    </item>
    <item>
      <title>대장내시경</title>
      <ht:approx_traffic>5000+</ht:approx_traffic>
    </item>
  </channel>
</rss>
''';

const _newsXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>연합뉴스</title>
    <item>
      <title>한국은행, 기준금리 동결</title>
      <link>https://example.com/1</link>
    </item>
    <item>
      <title><![CDATA[다음달 1일 기후동행패스 출시…신규카드 무료 교환]]></title>
      <link>https://example.com/2</link>
    </item>
  </channel>
</rss>
''';

void main() {
  group('구글 트렌드 파서', () {
    final entries = parseGoogleTrends(_trendsXml);

    test('항목 수와 순서', () {
      expect(entries, hasLength(2));
      expect(entries[0].keyword, '기후동행카드');
      expect(entries[0].rank, 1);
      expect(entries[1].rank, 2);
    });

    test('검색량을 가져온다', () {
      expect(entries[0].approxTraffic, '500+');
      expect(entries[1].approxTraffic, '5000+');
    });

    test('첫 번째 뉴스 항목을 대표로 쓴다', () {
      expect(entries[0].newsOutlet, '경향신문');
      expect(entries[0].newsUrl, 'https://example.com/a');
      expect(entries[0].newsSnippet, '신규카드 무료로 교환해준다');
      // HTML 엔티티가 풀려야 한다
      expect(entries[0].newsTitle, contains("'기후동행패스'"));
    });

    test('뉴스 항목이 없어도 죽지 않는다', () {
      expect(entries[1].newsTitle, isNull);
      expect(entries[1].newsOutlet, isNull);
    });

    test('채널 제목을 항목으로 오인하지 않는다', () {
      expect(entries.map((e) => e.keyword), isNot(contains('Daily Search Trends')));
    });
  });

  group('언론사 RSS 파서', () {
    final headlines = parseNewsRss(_newsXml);

    test('제목과 순서', () {
      expect(headlines, hasLength(2));
      expect(headlines[0].title, '한국은행, 기준금리 동결');
      expect(headlines[0].rank, 1);
    });

    test('CDATA 를 벗겨낸다', () {
      expect(headlines[1].title, startsWith('다음달 1일 기후동행패스'));
    });
  });

  group('정규화', () {
    test('공백과 문장부호를 지운다', () {
      expect(normalize('한국은행, 기준금리 동결'), '한국은행기준금리동결');
    });

    test('부분 포함을 잡는다', () {
      expect(mentions('한국은행, 기준금리 동결', '기준금리'), isTrue);
    });

    test('여러 토큰이 흩어져 있어도 잡는다', () {
      expect(mentions('골 넣은 손흥민, 경기 뒤집었다', '손흥민 골'), isTrue);
    });

    test('한 글자 키워드는 오탐이 많아 건너뛴다', () {
      expect(mentions('아무 기사 제목', '아'), isFalse);
    });

    test('이슈 ID 는 표기가 달라도 같은 값을 준다', () {
      expect(issueIdFor('기준 금리'), issueIdFor('기준금리'));
      expect(issueIdFor('기준금리'), isNot(issueIdFor('대출금리')));
    });
  });

  group('같은 기사 판정', () {
    const matcher = StoryMatcher();

    test('표기가 달라도 같은 사건이면 잡는다', () {
      // 검색어는 `기후동행카드`, 기사 표기는 `기후동행패스` — 직접 매칭은 실패한다.
      // 트렌드가 물고 온 기사 제목과 겹치는 헤드라인으로 잡아낸다.
      expect(
        matcher.matches(
          '다음달 1일 기후동행패스 출시…신규카드 무료 교환',
          '기후동행카드',
          "다음달 1일 '기후동행패스' 출시",
        ),
        isTrue,
      );
    });

    test('무관한 기사는 엮지 않는다', () {
      expect(
        matcher.matches(
          '한국은행, 기준금리 동결',
          '기후동행카드',
          "다음달 1일 '기후동행패스' 출시",
        ),
        isFalse,
      );
    });

    test('토큰 한 개만 겹치는 건 같은 기사가 아니다', () {
      expect(matcher.sameStory('출시 임박한 신차', '다음달 출시'), isFalse);
    });
  });
}
