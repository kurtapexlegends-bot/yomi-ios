import Foundation
import YomiCore

/// Generates compliant JavaScriptCore scraper scripts for community repository extensions.
enum ScraperScriptGenerator {
    
    static func generateScraperScript(for package: RemoteExtensionPackage) -> String {
        let isMangakakalot = package.baseUrl.lowercased().contains("mangakakalot") || package.name.lowercased().contains("mangakakalot")
        var baseUrl = package.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseUrl.hasSuffix("/") { baseUrl.removeLast() }

        if isMangakakalot {
            baseUrl = "https://www.mangakakalove.com"
            return generateMangakakalotScript(baseUrl: baseUrl)
        }

        if baseUrl.isEmpty { baseUrl = "https://mangapill.com" }
        return generateGenericScript(baseUrl: baseUrl)
    }

    private static func generateMangakakalotScript(baseUrl: String) -> String {
        """
        const BASE_URL = "\(baseUrl)";

        const Extension = {
            getFilters: function() {
                return [
                    {
                        type: 'select',
                        id: 'genre',
                        name: 'Genre',
                        values: [
                            "All", "Action", "Adaptation", "Adult", "Adventure", "Comedy", "Demons",
                            "Drama", "Ecchi", "Fantasy", "Gender Bender", "Harem", "Historical",
                            "Isekai", "Josei", "Magic", "Manga", "Manhua", "Manhwa", "Martial Arts",
                            "Mature", "Mecha", "Mystery", "Psychological", "Romance", "School Life",
                            "Sci-Fi", "Shoujo", "Shounen", "Slice of Life", "Supernatural", "Tragedy", "Webtoons"
                        ],
                        selectedIndex: 0
                    },
                    {
                        type: 'select',
                        id: 'status',
                        name: 'Status',
                        values: ["All", "Ongoing", "Completed"],
                        selectedIndex: 0
                    },
                    {
                        type: 'select',
                        id: 'sort',
                        name: 'Sort By',
                        values: ["Latest", "Top View", "Newest"],
                        selectedIndex: 0
                    }
                ];
            },

            getPopularManga: async function(page) {
                const url = (page <= 1) ? BASE_URL : `${BASE_URL}/manga-list/hot-manga?page=${page}`;
                const resp = await fetch(url, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                return this.parseMangaList(html);
            },

            getLatestUpdates: async function(page) {
                const url = (page <= 1) ? BASE_URL : `${BASE_URL}/manga-list/latest-manga?page=${page}`;
                const resp = await fetch(url, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                return this.parseMangaList(html);
            },

            searchManga: async function(query, filters, page) {
                if (typeof filters === "number") {
                    page = filters;
                    filters = [];
                }
                const p = page || 1;
                const trimmed = (query || "").trim();

                let genreParam = "all";
                let statusParam = "all";
                let sortParam = "latest";

                if (Array.isArray(filters)) {
                    for (const f of filters) {
                        if (f.id === "genre" && f.selectedIndex > 0 && f.values && f.values[f.selectedIndex]) {
                            const val = f.values[f.selectedIndex].toLowerCase().replace(/\\s+/g, "-");
                            genreParam = val;
                        } else if (f.id === "status" && f.selectedIndex > 0 && f.values && f.values[f.selectedIndex]) {
                            statusParam = f.values[f.selectedIndex].toLowerCase();
                        } else if (f.id === "sort" && f.selectedIndex > 0 && f.values && f.values[f.selectedIndex]) {
                            const sVal = f.values[f.selectedIndex];
                            if (sVal === "Top View") sortParam = "topview";
                            else if (sVal === "Newest") sortParam = "newest";
                            else sortParam = "latest";
                        }
                    }
                }

                if (trimmed.length > 0) {
                    const slug = encodeURIComponent(trimmed.toLowerCase().replace(/[^\\w\\s-]/g, "").trim().replace(/\\s+/g, "_"));
                    const resp = await fetch(`${BASE_URL}/search/story/${slug}?page=${p}`, {
                        headers: { "Referer": BASE_URL + "/" }
                    });
                    const html = await resp.text();
                    return this.parseMangaList(html);
                }

                // Filter search mode
                const url = `${BASE_URL}/genre/${genreParam}?type=${sortParam}&state=${statusParam}&page=${p}`;
                const resp = await fetch(url, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                return this.parseMangaList(html);
            },

            parseMangaList: function(html) {
                const items = __yomi_selectAll(html, ".itemupdate, .list-truyen-item-wrap, .list-comic-item-wrap, .list-story-item, .content-genres-item, .story_item, .item");
                const mangas = [];
                const seen = new Set();
                for (const item of items) {
                    let link = __yomi_attr(item, "a[href*='/manga/']", "href") ||
                               __yomi_attr(item, "a.cover", "href") ||
                               __yomi_attr(item, "a.tooltip", "href") ||
                               __yomi_attr(item, "h3 a", "href") ||
                               __yomi_attr(item, "a", "href");
                    if (!link || link.includes("/chapter") || seen.has(link)) continue;
                    if (!link.startsWith("http")) {
                        link = `${BASE_URL}${link.startsWith('/') ? '' : '/'}${link}`;
                    }
                    seen.add(link);

                    let title = __yomi_attr(item, "a[href*='/manga/']", "title") ||
                                __yomi_text(item, "h3 a, a.item-title, h3, h4, .title, .story_name a") ||
                                __yomi_attr(item, "img", "alt") ||
                                __yomi_attr(item, "", "title") ||
                                __yomi_text(item, "");
                    title = (title || "").trim();
                    if (!title) continue;

                    let thumb = __yomi_attr(item, "img", "data-src") ||
                                __yomi_attr(item, "img", "data-lazy-src") ||
                                __yomi_attr(item, "img", "src");
                    if (thumb && !thumb.startsWith("http")) {
                        thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                    }

                    mangas.push({ url: link, title: title, thumbnailUrl: thumb });
                }
                return { mangas, hasNextPage: mangas.length >= 15 };
            },

            getMangaDetails: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                const title = __yomi_text(html, "h1, .story-info-right h1, .manga-info-top h1") || "Manga";
                const desc = __yomi_text(html, ".description, #panel-story-info-description, .panel-story-info-description, .story-info-right-extent") || "";
                let thumb = __yomi_attr(html, ".story-info-left img, .info-image img, .manga-info-top img", "src");
                if (thumb && !thumb.startsWith("http")) {
                    thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                }
                return {
                    title: title.trim(),
                    description: desc.trim(),
                    thumbnailUrl: thumb,
                    status: 1
                };
            },

            getChapterList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                let slug = "";
                const slugMatch = fullUrl.match(/\\/manga\\/([^\\/\\?#]+)/);
                if (slugMatch && slugMatch[1]) {
                    slug = slugMatch[1];
                }

                if (slug) {
                    try {
                        const apiUrl = `https://www.mangakakalove.com/api/manga/${slug}/chapters?limit=-1`;
                        const apiResp = await fetch(apiUrl, {
                            headers: {
                                "Referer": fullUrl,
                                "Accept": "application/json"
                            }
                        });
                        const apiData = await apiResp.json();
                        if (apiData && apiData.success && apiData.data && Array.isArray(apiData.data.chapters)) {
                            const chapters = [];
                            const list = apiData.data.chapters;
                            for (let i = 0; i < list.length; i++) {
                                const ch = list[i];
                                const chSlug = ch.chapter_slug || `chapter-${ch.chapter_num || (list.length - i)}`;
                                const chUrl = `https://www.mangakakalove.com/manga/${slug}/${chSlug}`;
                                const name = ch.chapter_name || `Chapter ${ch.chapter_num || (list.length - i)}`;
                                let dateUpload = Date.now();
                                if (ch.updated_at) {
                                    const parsed = Date.parse(ch.updated_at);
                                    if (!isNaN(parsed)) dateUpload = parsed;
                                }
                                chapters.push({
                                    url: chUrl,
                                    name: name.trim(),
                                    chapterNumber: typeof ch.chapter_num === "number" ? ch.chapter_num : (list.length - i),
                                    dateUpload: dateUpload
                                });
                            }
                            if (chapters.length > 0) {
                                return chapters;
                            }
                        }
                    } catch(e) {}
                }

                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                if (!slug) {
                    const comicSlug = __yomi_attr(html, "#chapter-list-container", "data-comic-slug");
                    if (comicSlug) {
                        try {
                            const apiUrl = `https://www.mangakakalove.com/api/manga/${comicSlug}/chapters?limit=-1`;
                            const apiResp = await fetch(apiUrl, {
                                headers: {
                                    "Referer": fullUrl,
                                    "Accept": "application/json"
                                }
                            });
                            const apiData = await apiResp.json();
                            if (apiData && apiData.success && apiData.data && Array.isArray(apiData.data.chapters)) {
                                const chapters = [];
                                const list = apiData.data.chapters;
                                for (let i = 0; i < list.length; i++) {
                                    const ch = list[i];
                                    const chSlug = ch.chapter_slug || `chapter-${ch.chapter_num || (list.length - i)}`;
                                    const chUrl = `https://www.mangakakalove.com/manga/${comicSlug}/${chSlug}`;
                                    const name = ch.chapter_name || `Chapter ${ch.chapter_num || (list.length - i)}`;
                                    let dateUpload = Date.now();
                                    if (ch.updated_at) {
                                        const parsed = Date.parse(ch.updated_at);
                                        if (!isNaN(parsed)) dateUpload = parsed;
                                    }
                                    chapters.push({
                                        url: chUrl,
                                        name: name.trim(),
                                        chapterNumber: typeof ch.chapter_num === "number" ? ch.chapter_num : (list.length - i),
                                        dateUpload: dateUpload
                                    });
                                }
                                if (chapters.length > 0) {
                                    return chapters;
                                }
                            }
                        } catch(e) {}
                    }
                }

                const links = __yomi_selectAll(html, ".row-content-chapter li a, .chapter-list a, .chapter-name, a[href*='/chapter']");
                const chapters = [];
                const seen = new Set();

                for (let idx = 0; idx < links.length; idx++) {
                    const link = links[idx];
                    let chUrl = __yomi_attr(link, "", "href");
                    if (!chUrl || seen.has(chUrl)) continue;
                    if (!chUrl.startsWith("http")) {
                        chUrl = `${BASE_URL}${chUrl.startsWith('/') ? '' : '/'}${chUrl}`;
                    }
                    seen.add(chUrl);

                    const name = __yomi_text(link, "") || `Chapter ${links.length - idx}`;
                    chapters.push({
                        url: chUrl,
                        name: name.trim(),
                        chapterNumber: links.length - idx,
                        dateUpload: Date.now()
                    });
                }
                return chapters;
            },

            getPageList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                const images = __yomi_selectAll(html, ".container-chapter-reader img, img.img-loading, #readerarea img");
                return images.map(img => {
                    const pageUrl = __yomi_attr(img, "", "data-src") || __yomi_attr(img, "", "src");
                    return {
                        url: pageUrl,
                        headers: { "Referer": "https://www.mangakakalove.com/" }
                    };
                }).filter(p => p.url && p.url.length > 0);
            }
        };
        """
    }

    private static func generateGenericScript(baseUrl: String) -> String {
        """
        const BASE_URL = "\(baseUrl)";

        const Extension = {
            getFilters: function() {
                return [
                    {
                        type: 'select',
                        id: 'status',
                        name: 'Status',
                        values: ["All", "Ongoing", "Completed"],
                        selectedIndex: 0
                    }
                ];
            },

            getPopularManga: async function(page) {
                const resp = await fetch(`${BASE_URL}/mangas/new?page=${page}`);
                const html = await resp.text();
                const items = __yomi_selectAll(html, ".grid > div, div:has(> a[href*='/manga/']), a[href*='/manga/']");
                const mangas = items.slice(0, 30).map(item => {
                    const title = __yomi_text(item, ".font-black, h3, h4, .post-title, .title") || __yomi_text(item, "");
                    const url = __yomi_attr(item, "a[href*='/manga/']", "href") || __yomi_attr(item, "", "href");
                    const thumb = __yomi_attr(item, "img", "data-src") || __yomi_attr(item, "img", "data-lazy-src") || __yomi_attr(item, "img", "src");
                    return { url, title: title.trim(), thumbnailUrl: thumb };
                }).filter(m => m.title.length > 0 && m.url.length > 0);
                return { mangas, hasNextPage: mangas.length > 0 };
            },

            getLatestUpdates: async function(page) {
                return this.getPopularManga(page);
            },

            searchManga: async function(query, filters, page) {
                if (typeof filters === "number") {
                    page = filters;
                    filters = [];
                }
                const p = page || 1;
                const resp = await fetch(`${BASE_URL}/search?q=${encodeURIComponent(query || "")}&page=${p}`);
                const html = await resp.text();
                const items = __yomi_selectAll(html, ".grid > div, a[href*='/manga/'], div.page-item-detail a");
                const mangas = items.map(item => {
                    const title = __yomi_text(item, ".font-black, h3, h4, .post-title, .title") || __yomi_text(item, "");
                    const url = __yomi_attr(item, "a[href*='/manga/']", "href") || __yomi_attr(item, "", "href");
                    const thumb = __yomi_attr(item, "img", "data-src") || __yomi_attr(item, "img", "data-lazy-src") || __yomi_attr(item, "img", "src");
                    return { url, title: title.trim(), thumbnailUrl: thumb };
                }).filter(m => m.title.length > 0 && m.url.length > 0);
                return { mangas, hasNextPage: mangas.length > 0 };
            },

            getMangaDetails: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl);
                const html = await resp.text();
                return {
                    title: __yomi_text(html, "h1, .entry-title, .post-title"),
                    description: __yomi_text(html, "p.text--secondary, p.description, .description, .synopsis"),
                    thumbnailUrl: __yomi_attr(html, "figure img, .summary_image img", "data-src") || __yomi_attr(html, "figure img, .summary_image img", "src"),
                    status: 1
                };
            },

            getChapterList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl);
                const html = await resp.text();
                const links = __yomi_selectAll(html, "a[href*='/chapters/'], a[href*='/chapter-'], a[href*='/ch-'], .wp-manga-chapter a");
                return links.map((link, idx) => {
                    const name = __yomi_text(link, "") || `Chapter ${idx + 1}`;
                    const chUrl = __yomi_attr(link, "", "href");
                    return {
                        url: chUrl,
                        name: name.trim(),
                        chapterNumber: links.length - idx,
                        dateUpload: Date.now()
                    };
                });
            },

            getPageList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl);
                const html = await resp.text();
                const images = __yomi_selectAll(html, "img.js-page, #readerarea img, .reading-content img, .chapter-image img, #reader-area img");
                return images.map(img => {
                    const pageUrl = __yomi_attr(img, "", "data-src") || __yomi_attr(img, "", "data-lazy-src") || __yomi_attr(img, "", "src");
                    return {
                        url: pageUrl,
                        headers: { "Referer": BASE_URL }
                    };
                }).filter(p => p.url && p.url.length > 0);
            }
        };
        """
    }
}
