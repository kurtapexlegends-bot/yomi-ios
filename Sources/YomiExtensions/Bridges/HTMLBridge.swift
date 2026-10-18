import Foundation
import JavaScriptCore
import SwiftSoup

public enum HTMLBridge {
    /// Injects native DOM querying functions into a JavaScriptCore JSContext.
    public static func inject(into context: JSContext) {
        
        // Query elements and return their inner HTML array
        let querySelectorAll: @convention(block) (String, String) -> [String] = { html, selector in
            do {
                let doc = try SwiftSoup.parse(html)
                let elements = try doc.select(selector)
                return elements.array().compactMap { try? $0.outerHtml() }
            } catch {
                return []
            }
        }
        context.setObject(querySelectorAll, forKeyedSubscript: "__yomi_selectAll" as NSString)

        // Query element text
        let queryText: @convention(block) (String, String) -> String = { html, selector in
            do {
                let doc = try SwiftSoup.parse(html)
                if selector.isEmpty {
                    return try doc.text()
                }
                return try doc.select(selector).first()?.text() ?? ""
            } catch {
                return ""
            }
        }
        context.setObject(queryText, forKeyedSubscript: "__yomi_text" as NSString)

        // Query element attribute value (e.g. href, src, data-src)
        let queryAttr: @convention(block) (String, String, String) -> String = { html, selector, attribute in
            do {
                let doc = try SwiftSoup.parse(html)
                let element = selector.isEmpty ? doc.body() : try doc.select(selector).first()
                return try element?.attr(attribute) ?? ""
            } catch {
                return ""
            }
        }
        context.setObject(queryAttr, forKeyedSubscript: "__yomi_attr" as NSString)

        // Query multiple attribute values across matching elements
        let queryAttrAll: @convention(block) (String, String, String) -> [String] = { html, selector, attribute in
            do {
                let doc = try SwiftSoup.parse(html)
                let elements = try doc.select(selector)
                return elements.array().compactMap { try? $0.attr(attribute) }
            } catch {
                return []
            }
        }
        context.setObject(queryAttrAll, forKeyedSubscript: "__yomi_attrAll" as NSString)
    }
}
