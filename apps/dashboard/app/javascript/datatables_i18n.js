'use strict';

import enGB from 'datatables.net-plugins/i18n/en-GB.mjs';
import fa from 'datatables.net-plugins/i18n/fa.mjs';
import frFR from 'datatables.net-plugins/i18n/fr-FR.mjs';
import ja from 'datatables.net-plugins/i18n/ja.mjs';
import zh from 'datatables.net-plugins/i18n/zh.mjs';
import zhHant from 'datatables.net-plugins/i18n/zh-HANT.mjs';
import { oodLocale } from './i18n.js';

const EXACT_PACKS = {
  'en-gb': enGB,
  'fa-ir': fa,
  'fr-ca': frFR,
  'fr-fr': frFR,
  'ja-jp': ja,
  'zh-cn': zh,
  'zh-hans': zh,
  'zh-hant': zhHant,
  'zh-tw': zhHant,
};

const PRIMARY_PACKS = {
  fa,
  fr: frFR,
  ja,
  zh,
};

function clonePlain(obj) {
  return obj ? JSON.parse(JSON.stringify(obj)) : {};
}

export function dataTablesLanguage(overrides = {}, locale = oodLocale()) {
  const tag = String(locale || 'en').trim().replace(/_/g, '-').toLowerCase();
  const primary = tag.split('-')[0];

  const basePack = EXACT_PACKS[tag] || PRIMARY_PACKS[primary] || {};
  const result = clonePlain(basePack);

  if (overrides && typeof overrides === 'object') {
    for (const [key, value] of Object.entries(overrides)) {
      if (
        value &&
        typeof value === 'object' &&
        !Array.isArray(value) &&
        result[key] &&
        typeof result[key] === 'object' &&
        !Array.isArray(result[key])
      ) {
        result[key] = { ...result[key], ...value };
      } else {
        result[key] = value;
      }
    }
  }

  return result;
}
