/*
 * noVNC: HTML5 VNC client
 * Copyright (C) 2018 The noVNC Authors
 * Licensed under MPL 2.0 (see LICENSE.txt)
 *
 * See README.md for usage and integration instructions.
 */

/*
 * Localization Utilities
 */

export class Localizer {
    constructor() {
        // Currently configured language
        this.language = 'en';

        // Current dictionary of translations
        this.dictionary = undefined;
    }

    // Read same-origin Open OnDemand `ood_locale` cookie when present
    _oodCookieLocale() {
        if (typeof document === 'undefined' || typeof document.cookie !== 'string' || !document.cookie) {
            return null;
        }
        const pairs = document.cookie.split(';');
        for (let i = 0; i < pairs.length; i++) {
            const idx = pairs[i].indexOf('=');
            if (idx <= 0) {
                continue;
            }
            const key = pairs[i].slice(0, idx).trim();
            if (key !== 'ood_locale') {
                continue;
            }
            const raw = pairs[i].slice(idx + 1).trim();
            if (!raw) {
                return null;
            }
            try {
                return decodeURIComponent(raw);
            } catch (_err) {
                return raw;
            }
        }
        return null;
    }

    // Configure suitable language based on Open OnDemand cookie or browser preferences
    setup(supportedLanguages) {
        this.language = 'en'; // Default: US English

        /*
         * Navigator.languages only available in Chrome (32+) and FireFox (32+)
         * Fall back to navigator.language for other browsers
         */
        let browserLanguages = [];
        if (typeof window !== 'undefined' && window.navigator) {
            if (typeof window.navigator.languages == 'object' && window.navigator.languages !== null) {
                browserLanguages = Array.from(window.navigator.languages);
            } else if (window.navigator.language || window.navigator.userLanguage) {
                browserLanguages = [window.navigator.language || window.navigator.userLanguage];
            }
        }

        const cookieLocale = this._oodCookieLocale();
        const userLanguages = (cookieLocale ? [cookieLocale].concat(browserLanguages) : browserLanguages)
            .filter(Boolean);

        for (let i = 0;i < userLanguages.length;i++) {
            const userLang = userLanguages[i]
                .toLowerCase()
                .replace("_", "-")
                .split("-");

            // First pass: perfect match (language + region)
            for (let j = 0; j < supportedLanguages.length; j++) {
                const supLang = supportedLanguages[j]
                    .toLowerCase()
                    .replace("_", "-")
                    .split("-");

                if (userLang[0] !== supLang[0]) {
                    continue;
                }
                if (userLang[1] !== supLang[1]) {
                    continue;
                }

                this.language = supportedLanguages[j];
                return;
            }

            // Built-in default for English variants (en, en-US, en-CA, etc.) when no regional pack matched
            if (userLang[0] === 'en') {
                return;
            }

            // Second pass: primary-language fallback (e.g. fr-CA -> fr, ja-JP -> ja)
            for (let j = 0;j < supportedLanguages.length;j++) {
                const supLang = supportedLanguages[j]
                    .toLowerCase()
                    .replace("_", "-")
                    .split("-");

                if (userLang[0] !== supLang[0]) {
                    continue;
                }
                if (supLang[1] !== undefined) {
                    continue;
                }

                this.language = supportedLanguages[j];
                return;
            }
        }
    }

    // Retrieve localised text
    get(id) {
        if (typeof this.dictionary !== 'undefined' && this.dictionary[id]) {
            return this.dictionary[id];
        } else {
            return id;
        }
    }

    // Traverses the DOM and translates relevant fields
    // See https://html.spec.whatwg.org/multipage/dom.html#attr-translate
    translateDOM() {
        const self = this;

        function process(elem, enabled) {
            function isAnyOf(searchElement, items) {
                return items.indexOf(searchElement) !== -1;
            }

            function translateAttribute(elem, attr) {
                const str = self.get(elem.getAttribute(attr));
                elem.setAttribute(attr, str);
            }

            function translateTextNode(node) {
                const str = self.get(node.data.trim());
                node.data = str;
            }

            if (elem.hasAttribute("translate")) {
                if (isAnyOf(elem.getAttribute("translate"), ["", "yes"])) {
                    enabled = true;
                } else if (isAnyOf(elem.getAttribute("translate"), ["no"])) {
                    enabled = false;
                }
            }

            if (enabled) {
                if (elem.hasAttribute("abbr") &&
                    elem.tagName === "TH") {
                    translateAttribute(elem, "abbr");
                }
                if (elem.hasAttribute("alt") &&
                    isAnyOf(elem.tagName, ["AREA", "IMG", "INPUT"])) {
                    translateAttribute(elem, "alt");
                }
                if (elem.hasAttribute("download") &&
                    isAnyOf(elem.tagName, ["A", "AREA"])) {
                    translateAttribute(elem, "download");
                }
                if (elem.hasAttribute("label") &&
                    isAnyOf(elem.tagName, ["MENUITEM", "MENU", "OPTGROUP",
                                           "OPTION", "TRACK"])) {
                    translateAttribute(elem, "label");
                }
                // FIXME: Should update "lang"
                if (elem.hasAttribute("placeholder") &&
                    isAnyOf(elem.tagName, ["INPUT", "TEXTAREA"])) {
                    translateAttribute(elem, "placeholder");
                }
                if (elem.hasAttribute("title")) {
                    translateAttribute(elem, "title");
                }
                if (elem.hasAttribute("value") &&
                    elem.tagName === "INPUT" &&
                    isAnyOf(elem.getAttribute("type"), ["reset", "button", "submit"])) {
                    translateAttribute(elem, "value");
                }
            }

            for (let i = 0; i < elem.childNodes.length; i++) {
                const node = elem.childNodes[i];
                if (node.nodeType === node.ELEMENT_NODE) {
                    process(node, enabled);
                } else if (node.nodeType === node.TEXT_NODE && enabled) {
                    translateTextNode(node);
                }
            }
        }

        process(document.body, true);
    }
}

export const l10n = new Localizer();
export default l10n.get.bind(l10n);
