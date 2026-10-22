import Foundation

enum MangaKatanaScraper {
    static func generateScript(baseUrl: String = "https://mangakatana.com") -> String {
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
                    },
                    {
                        type: 'select',
                        id: 'sort',
                        name: 'Sort By',
                        values: ["Latest Update", "New Manga", "Manga Directory"],
                        selectedIndex: 0
                    }
                ];
            },

            getPopularManga: async function(page) {
                const p = page || 1;
                const url = (p <= 1) ? `${BASE_URL}/manga` : `${BASE_URL}/manga/page/${p}`;
                const resp = await fetch(url, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();
                return this.parseMangaList(html);
            },

            getLatestUpdates: async function(page) {
                const p = page || 1;
                const url = (p <= 1) ? `${BASE_URL}/latest` : `${BASE_URL}/latest/page/${p}`;
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

                if (trimmed.length > 0) {
                    // MangaKatana delivers all search results in a single AJAX response
                    if (p > 1) {
                        return { mangas: [], hasNextPage: false };
                    }

                    try {
                        const bodyData = `s=${encodeURIComponent(trimmed)}&search_by=m_name`;
                        const resp = await fetch(`${BASE_URL}/`, {
                            method: "POST",
                            headers: {
                                "Content-Type": "application/x-www-form-urlencoded",
                                "X-Requested-With": "XMLHttpRequest",
                                "Referer": BASE_URL + "/"
                            },
                            body: bodyData
                        });
                        const html = await resp.text();
                        return this.parseSearchResults(html);
                    } catch(e) {
                        return { mangas: [], hasNextPage: false };
                    }
                }

                // If no search query, fall back to directory pagination
                return this.getPopularManga(p);
            },

            parseSearchResults: function(html) {
                const items = __yomi_selectAll(html, ".item");
                const mangas = [];
                const seen = new Set();

                for (const item of items) {
                    let link = __yomi_attr(item, ".text a.title, .d-cell.text a.title, a.title", "href") ||
                               __yomi_attr(item, "a[href*='/manga/']", "href");
                    if (!link || link.includes("/chapter") || link.match(/\\/c\\d+/) || seen.has(link)) continue;
                    if (!link.startsWith("http")) {
                        link = `${BASE_URL}${link.startsWith('/') ? '' : '/'}${link}`;
                    }
                    seen.add(link);

                    let title = __yomi_text(item, ".d-cell.text a.title, .text a.title, .text a, h3.title a") ||
                                __yomi_text(item, "a.title") ||
                                __yomi_attr(item, "a.title", "title") || "";
                    title = title.replace(/\\[Cover\\]/gi, "").trim();
                    if (!title) continue;

                    let thumb = __yomi_attr(item, "img", "src") ||
                                __yomi_attr(item, "img", "data-src");
                    if (thumb && !thumb.startsWith("http")) {
                        thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                    }

                    mangas.push({ url: link, title: title, thumbnailUrl: thumb || "" });
                }

                return { mangas: mangas, hasNextPage: false };
            },

            parseMangaList: function(html) {
                const items = __yomi_selectAll(html, "#book_list .item, .uk-grid .item, .item");
                const mangas = [];
                const seen = new Set();

                for (const item of items) {
                    let link = __yomi_attr(item, "h3.title a", "href") ||
                               __yomi_attr(item, "a[href*='/manga/']", "href") ||
                               __yomi_attr(item, "a", "href");
                    if (!link || link.includes("/chapter") || link.endsWith("/manga") || seen.has(link)) continue;
                    if (!link.startsWith("http")) {
                        link = `${BASE_URL}${link.startsWith('/') ? '' : '/'}${link}`;
                    }
                    seen.add(link);

                    let title = __yomi_text(item, "h3.title a") ||
                                __yomi_attr(item, "h3.title a", "title") ||
                                __yomi_text(item, ".title a") ||
                                __yomi_attr(item, "img", "alt") || "";
                    title = title.replace(/\\[Cover\\]/gi, "").trim();
                    if (!title) continue;

                    let thumb = __yomi_attr(item, "picture source", "srcset") ||
                                __yomi_attr(item, "img", "data-src") ||
                                __yomi_attr(item, "img", "src");
                    if (thumb && !thumb.startsWith("http")) {
                        thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                    }

                    mangas.push({ url: link, title: title, thumbnailUrl: thumb || "" });
                }

                return { mangas: mangas, hasNextPage: mangas.length >= 20 };
            },

            getMangaDetails: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url.startsWith('/') ? '' : '/'}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                const title = __yomi_text(html, "h1.heading, h1") || "Manga";
                const desc = __yomi_text(html, ".summary, .description, p.description") || "";
                let thumb = __yomi_attr(html, ".cover img, .media .wrap_img img", "src") ||
                            __yomi_attr(html, ".cover img, .media .wrap_img img", "data-src");
                if (thumb && !thumb.startsWith("http")) {
                    thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                }

                let status = 1;
                const statusText = __yomi_text(html, ".status, .meta");
                if (statusText && statusText.toLowerCase().includes("completed")) {
                    status = 2;
                }

                return {
                    title: title.trim(),
                    description: desc.trim(),
                    thumbnailUrl: thumb || "",
                    status: status
                };
            },

            getChapterList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url.startsWith('/') ? '' : '/'}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                const links = __yomi_selectAll(html, ".chapters .chapter a, .uk-table tr .chapter a, tr .chapter a, a[href*='/c']");
                const chapters = [];
                const seen = new Set();

                for (let idx = 0; idx < links.length; idx++) {
                    const el = links[idx];
                    let chUrl = __yomi_attr(el, "", "href");
                    if (!chUrl || seen.has(chUrl)) continue;
                    if (!chUrl.startsWith("http")) {
                        chUrl = `${BASE_URL}${chUrl.startsWith('/') ? '' : '/'}${chUrl}`;
                    }
                    // Filter out non-chapter links
                    if (!chUrl.match(/\\/c\\d+/)) continue;
                    seen.add(chUrl);

                    const name = __yomi_text(el, "") || `Chapter ${links.length - idx}`;
                    const numMatch = chUrl.match(/\\/c(\\d+(?:\\.\\d+)?)/) || name.match(/(?:chapter|ch\\.?)\\s*(\\d+(?:\\.\\d+)?)/i);
                    const chNum = numMatch ? parseFloat(numMatch[1]) : (links.length - idx);

                    chapters.push({
                        url: chUrl,
                        name: name.trim(),
                        chapterNumber: isNaN(chNum) ? (links.length - idx) : chNum,
                        dateUpload: Date.now()
                    });
                }

                return chapters;
            },

            getPageList: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url.startsWith('/') ? '' : '/'}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                // 1. Primary: Extract thzq JS image array (contains all pages)
                const thzqMatch = html.match(/var\\s+thzq\\s*=\\s*\\[(.*?)\\];/s);
                if (thzqMatch && thzqMatch[1]) {
                    const raw = thzqMatch[1];
                    const urls = raw.match(/https?:\\/\\/[^\\s"'<>,\\\\]+/g);
                    if (urls && urls.length > 0) {
                        return urls.map(u => ({
                            url: u.replace(/\\\\/g, ''),
                            headers: { "Referer": "https://mangakatana.com/" }
                        }));
                    }
                }

                // 2. Secondary fallback: Extract ytaw or any array with token image URLs
                const arrayMatch = html.match(/var\\s+(?:ytaw|[a-zA-Z0-9_]+)\\s*=\\s*\\[(.*?)\\];/s);
                if (arrayMatch && arrayMatch[1]) {
                    const raw = arrayMatch[1];
                    const urls = raw.match(/https?:\\/\\/[^\\s"'<>,\\\\]+/g);
                    if (urls && urls.length > 0) {
                        return urls.map(u => ({
                            url: u.replace(/\\\\/g, ''),
                            headers: { "Referer": "https://mangakatana.com/" }
                        }));
                    }
                }

                // 3. Fallback: Direct regex extraction of token URLs in HTML
                const tokenMatches = html.match(/https?:\\/\\/i\\d*\\.mangakatana\\.com\\/token\\/[^\\s"'<>,\\\\]+/g);
                if (tokenMatches && tokenMatches.length > 0) {
                    const unique = Array.from(new Set(tokenMatches));
                    return unique.map(u => ({
                        url: u.replace(/\\\\/g, ''),
                        headers: { "Referer": "https://mangakatana.com/" }
                    }));
                }

                return [];
            }
        };
        """
    }
}
