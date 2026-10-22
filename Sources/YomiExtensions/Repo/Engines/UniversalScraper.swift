import Foundation

enum UniversalScraper {
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
                    }
                ];
            },

            getPopularManga: async function(page) {
                const p = page || 1;
                if (p <= 1) {
                    try {
                        const resp = await fetch(`${BASE_URL}/`);
                        const html = await resp.text();
                        const parsed = this.parseMangaList(html);
                        if (parsed.mangas && parsed.mangas.length >= 4) {
                            return parsed;
                        }
                    } catch(e) {}
                }

                const candidates = [
                    `${BASE_URL}/manga?page=${p}`,
                    `${BASE_URL}/mangas?page=${p}`,
                    `${BASE_URL}/series?page=${p}`,
                    `${BASE_URL}/comics?page=${p}`,
                    `${BASE_URL}/latest?page=${p}`,
                    `${BASE_URL}/mangas/new?page=${p}`
                ];

                for (const ep of candidates) {
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
                return this.getPopularManga(page);
            },

            searchManga: async function(query, filters, page) {
                const p = page || 1;
                const q = encodeURIComponent((query || "").trim());
                if (!q) return this.getPopularManga(p);

                const endpoints = [
                    `${BASE_URL}/search?q=${q}&page=${p}`,
                    `${BASE_URL}/?s=${q}&page=${p}`,
                    `${BASE_URL}/browse?q=${q}&page=${p}`,
                    `${BASE_URL}/search/story/${q}?page=${p}`
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
                const selector = ".grid > div, .card, .manga-item, .page-item-detail, .item, a[href*='/manga/'], a[href*='/series/'], a[href*='/comic/']";
                const elements = __yomi_selectAll(html, selector);
                const mangas = [];
                const seen = new Set();

                for (const el of elements) {
                    let link = __yomi_attr(el, "a[href*='/manga/']", "href") ||
                               __yomi_attr(el, "a[href*='/series/']", "href") ||
                               __yomi_attr(el, "a[href*='/comic/']", "href") ||
                               __yomi_attr(el, "a", "href") ||
                               __yomi_attr(el, "", "href");
                    if (!link) continue;
                    if (link.includes("/chapter") || link.endsWith("/comics") || link.endsWith("/series") || link.endsWith("/manga")) {
                        continue;
                    }
                    if (!link.startsWith("http")) {
                        link = `${BASE_URL}${link.startsWith('/') ? '' : '/'}${link}`;
                    }
                    if (seen.has(link)) continue;
                    seen.add(link);

                    let title = __yomi_text(el, "h3, h4, .title, .post-title, .series-title, .name, .font-black") ||
                                __yomi_attr(el, "a", "title") ||
                                __yomi_attr(el, "img", "alt") ||
                                __yomi_text(el, "");
                    title = (title || "").trim();
                    if (!title || title.length > 120) continue;

                    let thumb = __yomi_attr(el, "img", "data-src") ||
                                __yomi_attr(el, "img", "data-lazy-src") ||
                                __yomi_attr(el, "img", "data-original") ||
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

                const title = __yomi_text(html, "h1, .entry-title, .post-title, .title") || "Manga";
                const desc = __yomi_text(html, "p.text--secondary, p.description, .description, .synopsis, #synopsis, .summary") || "";
                let thumb = __yomi_attr(html, "figure img, .summary_image img, .cover img, .thumb img, .manga-info img", "data-src") ||
                            __yomi_attr(html, "figure img, .summary_image img, .cover img, .thumb img, .manga-info img", "src");
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

                const links = __yomi_selectAll(html, "a[href*='/chapters/'], a[href*='/chapter-'], a[href*='/ch-'], a[href*='/chapter/'], .chapter-list a, .list-chapters a, .chapters .chapter a, .uk-table tr .chapter a, a[href*='/c']");
                const chapters = [];
                const seen = new Set();

                for (let idx = 0; idx < links.length; idx++) {
                    const el = links[idx];
                    let chUrl = __yomi_attr(el, "", "href");
                    if (!chUrl || seen.has(chUrl)) continue;
                    if (!chUrl.startsWith("http")) {
                        chUrl = `${BASE_URL}${chUrl.startsWith('/') ? '' : '/'}${chUrl}`;
                    }
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
                const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
                const resp = await fetch(fullUrl, { headers: { "Referer": BASE_URL + "/" } });
                const html = await resp.text();

                let urls = [];
                const selector = "img.js-page, #readerarea img, .reading-content img, .chapter-image img, #reader-area img, .container-chapter-reader img, .page-break img";
                const images = __yomi_selectAll(html, selector);

                for (const img of images) {
                    const pageUrl = __yomi_attr(img, "img", "data-src") ||
                                   __yomi_attr(img, "img", "data-lazy-src") ||
                                   __yomi_attr(img, "img", "data-original") ||
                                   __yomi_attr(img, "img", "src") ||
                                   __yomi_attr(img, "", "data-src") ||
                                   __yomi_attr(img, "", "src");
                    if (pageUrl && pageUrl.length > 1 && pageUrl !== "#" && pageUrl.startsWith("http") && !urls.includes(pageUrl)) {
                        if (!pageUrl.includes("logo") && !pageUrl.includes("banner") && !pageUrl.endsWith(".gif") && !pageUrl.endsWith(".svg")) {
                            urls.push(pageUrl);
                        }
                    }
                }

                if (urls.length === 0) {
                    const regex = /<img[^>]+(?:data-src|src)=["'](https?:\\/\\/[^"']+)["'][^>]*>/gi;
                    let m;
                    while ((m = regex.exec(html)) !== null) {
                        const link = m[1];
                        if (!urls.includes(link) && !link.includes("logo") && !link.includes("banner") && !link.endsWith(".gif") && !link.endsWith(".svg")) {
                            urls.push(link);
                        }
                    }
                }

                // JS array fallback (e.g. thzq, ytaw, ts_reader, pages)
                if (urls.length === 0) {
                    const scriptArrays = html.match(/(?:thzq|ytaw|ts_reader_control\\.buildWebUI|images|pages)\\s*[:=]\\s*(\\[[^;]+\\])/i);
                    if (scriptArrays && scriptArrays[1]) {
                        const found = scriptArrays[1].match(/https?:\\/\\/[^\\s"'<>,\\\\]+/g);
                        if (found) {
                            for (const u of found) {
                                const clean = u.replace(/\\\\/g, '');
                                if (!urls.includes(clean) && !clean.includes("logo") && !clean.endsWith(".gif") && !clean.endsWith(".svg")) {
                                    urls.push(clean);
                                }
                            }
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
