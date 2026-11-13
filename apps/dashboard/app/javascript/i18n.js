'use strict';

const I18N_ELEMENT_ID = 'ood_i18n';
const KEY_PREFIX = 'dashboard.js.';

let cachedCatalog = null;

function canonicalizeBcp47(raw) {
  if (!raw || typeof raw !== 'string') {
    return 'en';
  }
  const normalized = raw.trim().replace(/_/g, '-');
  if (!normalized) {
    return 'en';
  }
  try {
    const [canonical] = Intl.getCanonicalLocales(normalized);
    return canonical || 'en';
  } catch (_err) {
    return 'en';
  }
}

function readDomCatalog() {
  if (typeof document === 'undefined' || typeof document.getElementById !== 'function') {
    return null;
  }

  const el = document.getElementById(I18N_ELEMENT_ID);
  if (!el || !el.textContent) {
    return null;
  }

  try {
    const parsed = JSON.parse(el.textContent);
    if (parsed && typeof parsed === 'object') {
      return {
        locale: canonicalizeBcp47(parsed.locale),
        translations: parsed.translations && typeof parsed.translations === 'object' ? parsed.translations : {},
      };
    }
  } catch (_err) {
    // Fall back to empty catalog if malformed
  }
  return null;
}

function getCatalog() {
  if (cachedCatalog) {
    return cachedCatalog;
  }

  const fromDom = readDomCatalog();
  if (fromDom) {
    cachedCatalog = fromDom;
    return cachedCatalog;
  }

  const htmlLang =
    typeof document !== 'undefined' && document.documentElement ? document.documentElement.lang : 'en';

  return {
    locale: canonicalizeBcp47(htmlLang),
    translations: {},
  };
}

export function setI18nCatalog(catalog) {
  if (!catalog) {
    cachedCatalog = null;
    return;
  }
  cachedCatalog = {
    locale: canonicalizeBcp47(catalog.locale),
    translations: catalog.translations && typeof catalog.translations === 'object' ? catalog.translations : {},
  };
}

export function resetI18nCatalog() {
  cachedCatalog = null;
}

export function oodLocale() {
  return getCatalog().locale;
}

function lookupEntry(translations, key) {
  if (!key || typeof key !== 'string') {
    return undefined;
  }
  const cleanKey = key.startsWith(KEY_PREFIX) ? key.slice(KEY_PREFIX.length) : key;
  const parts = cleanKey.split('.');
  let cur = translations;

  for (const part of parts) {
    if (!cur || typeof cur !== 'object' || !Object.prototype.hasOwnProperty.call(cur, part)) {
      return undefined;
    }
    cur = cur[part];
  }
  return cur;
}

function resolvePlural(entry, count, locale) {
  if (count === 0 && Object.prototype.hasOwnProperty.call(entry, 'zero')) {
    return entry.zero;
  }

  let category = 'other';
  try {
    category = new Intl.PluralRules(locale).select(count);
  } catch (_err) {
    category = count === 1 ? 'one' : 'other';
  }

  if (Object.prototype.hasOwnProperty.call(entry, category)) {
    return entry[category];
  }
  if (Object.prototype.hasOwnProperty.call(entry, 'other')) {
    return entry.other;
  }
  if (Object.prototype.hasOwnProperty.call(entry, 'one')) {
    return entry.one;
  }
  return undefined;
}

function interpolate(template, params) {
  if (typeof template !== 'string' || !params || typeof params !== 'object') {
    return template;
  }
  return template.replace(/%\{([^}]+)\}/g, (match, name) => {
    if (Object.prototype.hasOwnProperty.call(params, name) && params[name] !== undefined && params[name] !== null) {
      return String(params[name]);
    }
    return match;
  });
}

export function t(key, params = {}) {
  const catalog = getCatalog();
  const entry = lookupEntry(catalog.translations, key);

  let template;
  if (typeof entry === 'string') {
    template = entry;
  } else if (entry && typeof entry === 'object' && params && typeof params.count === 'number') {
    template = resolvePlural(entry, params.count, catalog.locale);
  }

  if (typeof template !== 'string') {
    if (params && typeof params.defaultValue === 'string') {
      template = params.defaultValue;
    } else {
      return String(key);
    }
  }

  return interpolate(template, params);
}

export function formatNumber(value, options) {
  const num = typeof value === 'number' ? value : Number(value);
  if (Number.isNaN(num)) {
    return String(value ?? '');
  }
  return num.toLocaleString(oodLocale(), options);
}

export function formatDateTime(value, options) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value ?? '');
  }
  return date.toLocaleString(oodLocale(), options);
}
