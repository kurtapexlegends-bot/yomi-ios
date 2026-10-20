import Foundation

enum MadaraScraper {
    static func generateScript(baseUrl: String) -> String {
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
                        values: ["Latest", "Most Views", "Newest"],
                        selectedIndex: 0
                    }
                ];
            },

            getPopularManga: async function(page) {
                const p = page || 1;
                // 1. Try homepage for page 1
                if (p <= 1) {
                    try {
                        const resp = await fetch(`${BASE_URL}/`);
                        const html = await resp.text();
                        const parsed = this.parseMangaList(html);
                        if (parsed.mangas && parsed.mangas.length >= 6) {
                            return parsed;
                        }
                    } catch(e) {}
                }

                // 2. Try standard directory endpoints
                const endpoints = [
                    `${BASE_URL}/manga/?m_orderby=views&page=${p}`,
                    `${BASE_URL}/series/?page=${p}`,
                    `${BASE_URL}/comics?page=${p}`,
                    `${BASE_URL}/browse?page=${p}`
                ];

                for (const ep of endpoints) {
                    try {
                        const resp = await fetch(ep);
                        const html = await resp.text();
                        const parsed = this.parseMangaList(html);
                        if (parsed.mangas && parsed.mangas.length > 0) {
                            return parsed;
                        }
                    } catch(e) {}
                }

                return { mangas: [], hasNextPage: false };
            },

            getLatestUpdates: async function(page) {
                const p = page || 1;
                const endpoints = [
                    `${BASE_URL}/manga/?m_orderby=latest&page=${p}`,
                    `${BASE_URL}/latest?page=${p}`,
                    `${BASE_URL}/`
                ];

                for (const ep of endpoints) {
                    try {
                        const resp = await fetch(ep);
                        const html = await resp.text();
                        const parsed = this.parseMangaList(html);
                        if (parsed.mangas && parsed.mangas.length > 0) {
                            return parsed;
                        }
                    } catch(e) {}
                }

                return this.getPopularManga(page);
            },

            searchManga: async function(query, filters, page) {
                const p = page || 1;
                const q = encodeURIComponent((query || "").trim());
                if (!q) return this.getPopularManga(p);

                const endpoints = [
                    `${BASE_URL}/?s=${q}&post_type=wp-manga&page=${p}`,
                    `${BASE_URL}/search?q=${q}&page=${p}`,
                    `${BASE_URL}/browse?q=${q}&page=${p}`
                ];

                for (const ep of endpoints) {
                    try {
                        const resp = await fetch(ep);
                        const html = await resp.text();
                        const parsed = this.parseMangaList(html);
                        if (parsed.mangas && parsed.mangas.length > 0) {
                            return parsed;
                        }
                    } catch(e) {}
                }

                return { mangas: [], hasNextPage: false };
            },

            parseMangaList: function(html) {
                const selector = ".page-item-detail, .c-tabs-item__content, .manga-item, .post-title, a[href*='/comics/'], a[href*='/series/'], a[href*='/manga/']";
                const elements = __yomi_selectAll(html, selector);
                const mangas = [];
                const seen = new Set();

                for (const el of elements) {
                    let link = __yomi_attr(el, "a[href*='/comics/']", "href") ||
                               __yomi_attr(el, "a[href*='/series/']", "href") ||
                               __yomi_attr(el, "a[href*='/manga/']", "href") ||
                               __yomi_attr(el, "", "href");
                    if (!link) continue;

                    // Filter out navigation or chapter sub-links
                    if (link.includes("/chapter") || link.endsWith("/comics") || link.endsWith("/series") || link.endsWith("/browse")) {
                        continue;
                    }
                    if (!link.startsWith("http")) {
                        link = `${BASE_URL}${link.startsWith('/') ? '' : '/'}${link}`;
                    }
                    if (seen.has(link)) continue;
                    seen.add(link);

                    let title = __yomi_text(el, ".post-title, .title, .series-title, h3, h4, h2") ||
                                __yomi_attr(el, "a", "title") ||
                                __yomi_attr(el, "img", "alt") ||
                                __yomi_text(el, "");
                    title = (title || "").trim();
                    if (!title || title.length > 120) continue;

                    let thumb = __yomi_attr(el, "img", "data-src") ||
                                __yomi_attr(el, "img", "data-lazy-src") ||
                                __yomi_attr(el, "img", "src");
                    if (thumb && !thumb.startsWith("http")) {
                        thumb = `${BASE_URL}${thumb.startsWith('/') ? '' : '/'}${thumb}`;
                    }

                    mangas.push({ url: link, title: title, thumbnailUrl: thumb || "" });
                }

                return { mangas, hasNextPage: mangas.length >= 10 };
            },

            getMangaDetails: async function(url) {
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                const title = __yomi_text(html, "h1, .post-title h1, .entry-title, .series-title") || "Manga";
                const desc = __yomi_text(html, ".description-summary, .manga-excerpt, .post-content, .synopsis, p.text--secondary") || "";
                let thumb = __yomi_attr(html, ".summary_image img, figure img, .thumb img, .series-cover img", "data-src") ||
                            __yomi_attr(html, ".summary_image img, figure img, .thumb img, .series-cover img", "src");
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
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                const links = __yomi_selectAll(html, "a[href*='/chapter'], a[href*='/series/'], .wp-manga-chapter a, ul.main.version-chap li a, .chapter-item a");
                const chapters = [];
                const seen = new Set();

                for (let idx = 0; idx < links.length; idx++) {
                    const el = links[idx];
                    let chUrl = __yomi_attr(el, "", "href");
                    if (!chUrl || seen.has(chUrl)) continue;

                    // Match chapter pattern in link
                    const isChapterLink = chUrl.includes("/chapter") ||
                                          chUrl.match(/\\/series\\/[^\\/]+\\/[a-zA-Z0-9_-]+$/) ||
                                          chUrl.includes("/ch-") || chUrl.includes("/chapters/");
                    if (!isChapterLink) continue;

                    if (!chUrl.startsWith("http")) {
                        chUrl = `${BASE_URL}${chUrl.startsWith('/') ? '' : '/'}${chUrl}`;
                    }
                    seen.add(chUrl);

                    const name = __yomi_text(el, "") || `Chapter ${links.length - idx}`;
                    const numMatch = name.match(/(?:chapter|ch\\.?)\\s*(\\d+(?:\\.\\d+)?)/i);
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
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                let urls = [];
                // 1. Target reader image selectors
                const selector = ".page-break img, .reading-content img, #readerarea img, .chapter-image img, .reader-images img";
                const images = __yomi_selectAll(html, selector);
                for (const img of images) {
                    const pageUrl = __yomi_attr(img, "img", "data-src") ||
                                   __yomi_attr(img, "img", "data-lazy-src") ||
                                   __yomi_attr(img, "img", "data-original") ||
                                   __yomi_attr(img, "img", "src") ||
                                   __yomi_attr(img, "", "data-src") ||
                                   __yomi_attr(img, "", "src");
                    if (pageUrl && pageUrl.length > 0 && !urls.includes(pageUrl)) {
                        if (!pageUrl.includes("logo") && !pageUrl.includes("banner") && !pageUrl.endsWith(".gif") && !pageUrl.endsWith(".svg")) {
                            urls.push(pageUrl);
                        }
                    }
                }

                // 2. Direct CDN regex extraction fallback
                if (urls.length === 0) {
                    const regex = /https?:\\/\\/[^\\s"'<>]+(?:asura-images|uploads\\/images|chapters|reader|storage)[^\\s"'<>]+\\.(?:webp|jpg|jpeg|png)(?:\\?[^\\s"'<>]*)?/gi;
                    let m;
                    while ((m = regex.exec(html)) !== null) {
                        const link = m[0];
                        if (!urls.includes(link) && !link.includes("thumbnail") && !link.includes("cover") && !link.includes("logo") && !link.includes("banner")) {
                            urls.push(link);
                        }
                    }
                }

                return urls.map(pageUrl => ({
                    url: pageUrl,
                    headers: { "Referer": BASE_URL + "/" }
                }));
            }
        };
        """
    }
}
