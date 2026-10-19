# Yomi Extension Specification (v1.0)

This document describes the JavaScript extension protocol for writing third-party manga scrapers for **Yomi iOS**.

---

## 1. Extension Runtime Environment

Yomi runs extensions inside Apple's native `JavaScriptCore` virtual machine with direct Swift-bridged capabilities.

### Built-in Globals & Polyfills

1. **`fetch(url, options)`**:
   - Standard Promise-based HTTP client backed by iOS native `URLSession`.
   - Supports `method`, `headers`, `body`.
   - Automatically injects iOS Safari User-Agent and handles cookies.
   - Throws `__CLOUDFLARE_BLOCKED__` when an anti-bot challenge is encountered, triggering Yomi's native captcha solver.

2. **`__yomi_selectAll(html, cssSelector)`**:
   - Queries `html` string using fast native `SwiftSoup` parser and returns an array of matched HTML elements as strings.

3. **`__yomi_text(html, cssSelector)`**:
   - Returns inner text content of the first element matching `cssSelector`.

4. **`__yomi_attr(html, cssSelector, attribute)`**:
   - Returns attribute value (e.g. `href`, `src`, `data-src`) of the first matching element.

5. **`__yomi_attrAll(html, cssSelector, attribute)`**:
   - Returns attribute array for all matching elements.

6. **`__yomi_sha256(string)` / `__yomi_md5(string)` / `__yomi_base64Decode(string)`**:
   - Cryptographic helpers for scrambled image or API signature decoding.

---

## 2. Extension Object Contract

Every `.js` scraper script must register a global `Extension` object implementing the following asynchronous methods:

```javascript
const Extension = {
    // Optional: Return dynamic source filters (select, triState, sort, text)
    getFilters: function() {
        return [
            { type: "select", id: "genre", name: "Genre", values: ["All", "Action", "Drama"], selectedIndex: 0 },
            { type: "triState", id: "completed", name: "Completed", state: 0 },
            { type: "sort", id: "sort", name: "Sort By", values: ["Popularity", "Latest"], selectedIndex: 0, ascending: false },
            { type: "text", id: "author", name: "Author", state: "" }
        ];
    },

    // Return paginated list of popular manga
    getPopularManga: async function(page) {
        // Returns: { mangas: [{ url, title, thumbnailUrl }], hasNextPage: boolean }
    },

    // Return paginated list of latest updated manga
    getLatestUpdates: async function(page) {
        // Returns: { mangas: [{ url, title, thumbnailUrl }], hasNextPage: boolean }
    },

    // Search manga with text query (supports both (query, page) and (query, filters, page))
    searchManga: async function(query, filters, page) {
        // Returns: { mangas: [{ url, title, thumbnailUrl }], hasNextPage: boolean }
    },

    // Return detailed metadata for a manga
    getMangaDetails: async function(url) {
        // Returns: { title, author, artist, description, genres, status, thumbnailUrl }
    },

    // Return list of chapters for a manga
    getChapterList: async function(url) {
        // Returns: [{ url, name, scanlator, chapterNumber, dateUpload }]
    },

    // Return list of page image URLs for a chapter
    getPageList: async function(url) {
        // Returns: [{ url, headers }]
    }
};
```

---

## 3. Sample Scraper Implementation

```javascript
const BASE_URL = "https://example-manga.com";

const Extension = {
    getPopularManga: async function(page) {
        const resp = await fetch(`${BASE_URL}/popular?page=${page}`);
        const html = await resp.text();
        const items = __yomi_selectAll(html, ".manga-card");

        const mangas = items.map(item => {
            const title = __yomi_text(item, ".manga-title");
            const url = __yomi_attr(item, "a", "href");
            const thumb = __yomi_attr(item, "img", "data-src") || __yomi_attr(item, "img", "src");
            return { url, title, thumbnailUrl: thumb };
        });

        return { mangas, hasNextPage: mangas.length > 0 };
    },

    getLatestUpdates: async function(page) {
        return this.getPopularManga(page);
    },

    searchManga: async function(query, page) {
        const resp = await fetch(`${BASE_URL}/search?q=${encodeURIComponent(query)}&p=${page}`);
        const html = await resp.text();
        const items = __yomi_selectAll(html, ".search-item");

        const mangas = items.map(item => ({
            title: __yomi_text(item, ".title"),
            url: __yomi_attr(item, "a", "href"),
            thumbnailUrl: __yomi_attr(item, "img", "src")
        }));

        return { mangas, hasNextPage: mangas.length > 0 };
    },

    getMangaDetails: async function(url) {
        const resp = await fetch(url);
        const html = await resp.text();

        return {
            title: __yomi_text(html, "h1.entry-title"),
            author: __yomi_text(html, ".author-name"),
            description: __yomi_text(html, ".synopsis"),
            genres: __yomi_attrAll(html, ".genre-tags a", "text"),
            status: 1 // 1 = Ongoing, 2 = Completed
        };
    },

    getChapterList: async function(url) {
        const resp = await fetch(url);
        const html = await resp.text();
        const rows = __yomi_selectAll(html, ".chapter-list li");

        return rows.map((row, idx) => {
            const name = __yomi_text(row, ".chapter-title");
            const chUrl = __yomi_attr(row, "a", "href");
            return {
                url: chUrl,
                name: name,
                chapterNumber: rows.length - idx,
                dateUpload: Date.now()
            };
        });
    },

    getPageList: async function(url) {
        const resp = await fetch(url);
        const html = await resp.text();
        const images = __yomi_selectAll(html, "#reader-area img");

        return images.map(img => {
            const pageUrl = __yomi_attr(img, "", "data-src") || __yomi_attr(img, "", "src");
            return {
                url: pageUrl,
                headers: { "Referer": BASE_URL }
            };
        });
    }
};
```

---

## 4. Repository Structure (`index.json`)

To distribute your extensions, host a static `index.json` file on GitHub Pages or any HTTPS host:

```json
{
  "name": "Community Yomi Extensions",
  "website": "https://github.com/my-repo/yomi-extensions",
  "extensions": [
    {
      "id": 20001,
      "name": "ExampleManga",
      "lang": "en",
      "baseUrl": "https://example-manga.com",
      "iconUrl": "https://example-manga.com/icon.png",
      "version": "1.0.0",
      "scriptUrl": "https://raw.githubusercontent.com/my-repo/yomi-extensions/main/example.js",
      "isNsfw": false
    }
  ]
}
```
