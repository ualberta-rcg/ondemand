'use strict';

import bg from 'datatables.net-plugins/i18n/bg.mjs';
import cs from 'datatables.net-plugins/i18n/cs.mjs';
import da from 'datatables.net-plugins/i18n/da.mjs';
import deDE from 'datatables.net-plugins/i18n/de-DE.mjs';
import el from 'datatables.net-plugins/i18n/el.mjs';
import enGB from 'datatables.net-plugins/i18n/en-GB.mjs';
import esES from 'datatables.net-plugins/i18n/es-ES.mjs';
import et from 'datatables.net-plugins/i18n/et.mjs';
import fa from 'datatables.net-plugins/i18n/fa.mjs';
import fi from 'datatables.net-plugins/i18n/fi.mjs';
import frFR from 'datatables.net-plugins/i18n/fr-FR.mjs';
import ga from 'datatables.net-plugins/i18n/ga.mjs';
import hr from 'datatables.net-plugins/i18n/hr.mjs';
import hu from 'datatables.net-plugins/i18n/hu.mjs';
import itIT from 'datatables.net-plugins/i18n/it-IT.mjs';
import ja from 'datatables.net-plugins/i18n/ja.mjs';
import lt from 'datatables.net-plugins/i18n/lt.mjs';
import lv from 'datatables.net-plugins/i18n/lv.mjs';
import nlNL from 'datatables.net-plugins/i18n/nl-NL.mjs';
import pl from 'datatables.net-plugins/i18n/pl.mjs';
import ptPT from 'datatables.net-plugins/i18n/pt-PT.mjs';
import ro from 'datatables.net-plugins/i18n/ro.mjs';
import sk from 'datatables.net-plugins/i18n/sk.mjs';
import sl from 'datatables.net-plugins/i18n/sl.mjs';
import svSE from 'datatables.net-plugins/i18n/sv-SE.mjs';
import zh from 'datatables.net-plugins/i18n/zh.mjs';
import zhHant from 'datatables.net-plugins/i18n/zh-HANT.mjs';
import { oodLocale } from './i18n.js';

const mtMT = {
  emptyTable: "L-ebda dejta disponibbli fit-tabella",
  info: "Qed jintwerew _START_ sa _END_ minn _TOTAL_ entrati",
  infoEmpty: "Qed jintwerew 0 sa 0 minn 0 entrati",
  infoFiltered: "(iffiltrat minn _MAX_ entrati b'kollox)",
  lengthMenu: "Uri _MENU_ entrati",
  loadingRecords: "Qed jillowdja...",
  processing: "Qed jipproċessa...",
  search: "Fittex:",
  zeroRecords: "Ma nstab l-ebda rekord li jaqbel",
  paginate: {
    first: "L-ewwel",
    last: "L-aħħar",
    next: "Li jmiss",
    previous: "Ta' qabel",
  },
  aria: {
    paginate: {
      first: "L-ewwel",
      last: "L-aħħar",
      next: "Li jmiss",
      previous: "Ta' qabel",
    },
  },
};

const enHG = {
  emptyTable: "Don't Panic — no entries found in this sector of the Guide",
  info: "Displaying entries _START_ to _END_ of _TOTAL_ (Answer: 42)",
  infoEmpty: "Displaying 0 entries across the Sub-Etha",
  infoFiltered: "(improbability-filtered from _MAX_ total entries)",
  lengthMenu: "Consult _MENU_ Guide entries",
  loadingRecords: "Consulting Deep Thought...",
  processing: "Engaging Infinite Improbability Drive...",
  search: "Sub-Etha Scan:",
  zeroRecords: "Nothing found — mostly harmless",
  paginate: {
    first: "Big Bang",
    last: "Milliways",
    next: "Onward",
    previous: "Backtrack",
  },
  aria: {
    paginate: {
      first: "Big Bang",
      last: "Milliways",
      next: "Onward",
      previous: "Backtrack",
    },
  },
};

const enCP = {
  emptyTable: "Zero shards in this datapool, choom",
  info: "Streaming _START_–_END_ of _TOTAL_ shards",
  infoEmpty: "0 shards on the net",
  infoFiltered: "(ICE-filtered from _MAX_ total shards)",
  lengthMenu: "Stream _MENU_ shards",
  loadingRecords: "Jacking into subnet...",
  processing: "Decrypting ICE...",
  search: "Net-Scan:",
  zeroRecords: "Flatlined — no matching shards",
  paginate: {
    first: "Boot",
    last: "Endline",
    next: "Next Hop",
    previous: "Backtrace",
  },
  aria: {
    paginate: {
      first: "Boot",
      last: "Endline",
      next: "Next Hop",
      previous: "Backtrace",
    },
  },
};

function buildFrCAPack(base) {
  const pack = JSON.parse(JSON.stringify(base || {}));
  if (pack.buttons) {
    pack.buttons = {
      ...pack.buttons,
      copyKeys:
        "Appuyez sur Ctrl ou \u2318 + C pour copier les données du tableau dans votre presse-papiers.",
      copySuccess: {
        _: "%d lignes copiées dans le presse-papiers",
        "1": "1 ligne copiée dans le presse-papiers",
      },
      copyTitle: "Copier dans le presse-papiers",
      savedStates: "États enregistrés",
    };
  }
  if (pack.editor) {
    pack.editor = {
      ...pack.editor,
      edit: {
        ...(pack.editor.edit || {}),
        button: "Modifier",
        title: "Modifier l'entrée",
      },
      remove: {
        ...(pack.editor.remove || {}),
        confirm: {
          _: "Voulez-vous vraiment supprimer %d lignes?",
          "1": "Voulez-vous vraiment supprimer 1 ligne?",
        },
      },
    };
  }
  if (pack.stateRestore) {
    pack.stateRestore = {
      ...pack.stateRestore,
      emptyStates: "Aucun état enregistré",
      removeConfirm: "Voulez-vous vraiment supprimer %s?",
    };
  }
  return pack;
}

const frCA = buildFrCAPack(frFR);

const EXACT_PACKS = {
  'bg-bg': bg,
  'cs-cz': cs,
  'da-dk': da,
  'de-de': deDE,
  'el-gr': el,
  'en-cp': enCP,
  'en-gb': enGB,
  'en-hg': enHG,
  'es-es': esES,
  'et-ee': et,
  'fa-ir': fa,
  'fi-fi': fi,
  'fr-ca': frCA,
  'fr-fr': frFR,
  'ga-ie': ga,
  'hr-hr': hr,
  'hu-hu': hu,
  'it-it': itIT,
  'ja-jp': ja,
  'lt-lt': lt,
  'lv-lv': lv,
  'mt-mt': mtMT,
  'nl-nl': nlNL,
  'pl-pl': pl,
  'pt-pt': ptPT,
  'ro-ro': ro,
  'sk-sk': sk,
  'sl-si': sl,
  'sv-se': svSE,
  'zh-cn': zh,
  'zh-hans': zh,
  'zh-hant': zhHant,
  'zh-tw': zhHant,
};

const PRIMARY_PACKS = {
  bg,
  cs,
  da,
  de: deDE,
  el,
  es: esES,
  et,
  fa,
  fi,
  fr: frFR,
  ga,
  hr,
  hu,
  it: itIT,
  ja,
  lt,
  lv,
  mt: mtMT,
  nl: nlNL,
  pl,
  pt: ptPT,
  ro,
  sk,
  sl,
  sv: svSE,
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
