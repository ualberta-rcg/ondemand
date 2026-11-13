import test from 'node:test';
import assert from 'node:assert/strict';
import {
  t,
  oodLocale,
  setI18nCatalog,
  resetI18nCatalog,
  formatNumber,
  formatDateTime,
} from '../../app/javascript/i18n.js';
import { dataTablesLanguage } from '../../app/javascript/datatables_i18n.js';

test('oodLocale normalizes underscore locale tags to canonical BCP 47', () => {
  setI18nCatalog({ locale: 'ja_JP', translations: {} });
  assert.equal(oodLocale(), 'ja-JP');

  setI18nCatalog({ locale: 'fr_ca', translations: {} });
  assert.equal(oodLocale(), 'fr-CA');

  setI18nCatalog({ locale: 'invalid locale tag!!!', translations: {} });
  assert.equal(oodLocale(), 'en');

  resetI18nCatalog();
});

test('t resolves nested keys, optional dashboard.js prefix, interpolation, and defaultValue', () => {
  setI18nCatalog({
    locale: 'fr-CA',
    translations: {
      common: { cancel: 'Annuler' },
      files: { error_creating_dir: 'Impossible de créer %{dir} : %{msg}' },
    },
  });

  assert.equal(t('common.cancel'), 'Annuler');
  assert.equal(t('dashboard.js.common.cancel'), 'Annuler');
  assert.equal(
    t('files.error_creating_dir', { dir: '/scratch/a', msg: 'Permission refusée' }),
    'Impossible de créer /scratch/a : Permission refusée'
  );
  assert.equal(t('missing.key', { defaultValue: 'Repli %{n}', n: 3 }), 'Repli 3');
  assert.equal(t('missing.without_default'), 'missing.without_default');

  resetI18nCatalog();
});

test('t handles zero/one/other pluralization using Intl.PluralRules for active locale', () => {
  setI18nCatalog({
    locale: 'en-CA',
    translations: {
      items: {
        zero: 'No items selected',
        one: '%{count} item selected',
        other: '%{count} items selected',
      },
    },
  });

  assert.equal(t('items', { count: 0 }), 'No items selected');
  assert.equal(t('items', { count: 1 }), '1 item selected');
  assert.equal(t('items', { count: 4 }), '4 items selected');

  // In French (fr-CA), Intl.PluralRules(fr-CA).select(0) is "one", while explicit `zero` still wins if provided
  setI18nCatalog({
    locale: 'fr-CA',
    translations: {
      files_count: {
        one: '%{count} fichier',
        other: '%{count} fichiers',
      },
    },
  });
  assert.equal(t('files_count', { count: 0 }), '0 fichier');
  assert.equal(t('files_count', { count: 1 }), '1 fichier');
  assert.equal(t('files_count', { count: 2 }), '2 fichiers');

  resetI18nCatalog();
});

test('t reads catalog from DOM #ood_i18n script element when present', () => {
  const prevDoc = globalThis.document;
  globalThis.document = {
    documentElement: { lang: 'en' },
    getElementById(id) {
      if (id === 'ood_i18n') {
        return {
          textContent: JSON.stringify({
            locale: 'ja_JP',
            translations: { common: { close: '閉じる' } },
          }),
        };
      }
      return null;
    },
  };

  try {
    resetI18nCatalog();
    assert.equal(oodLocale(), 'ja-JP');
    assert.equal(t('common.close'), '閉じる');
  } finally {
    resetI18nCatalog();
    globalThis.document = prevDoc;
  }
});

test('formatNumber and formatDateTime honor oodLocale()', () => {
  setI18nCatalog({ locale: 'en-CA', translations: {} });
  assert.match(formatNumber(1234567), /1,234,567/);
  const formattedDate = formatDateTime(new Date('2026-05-01T12:00:00Z'), { timeZone: 'UTC' });
  assert.ok(formattedDate.length > 0);
  resetI18nCatalog();
});

test('dataTablesLanguage bundles offline language packs for fr-CA, ja-JP, zh-CN, fa-IR, and en-CA', () => {
  setI18nCatalog({ locale: 'fr-CA', translations: {} });
  const frPack = dataTablesLanguage({ search: 'Filtrer :', infoFiltered: '' });
  assert.equal(frPack.search, 'Filtrer :');
  assert.equal(frPack.infoFiltered, '');
  assert.equal(frPack.aria.paginate.next, 'Suivante');

  const jaPack = dataTablesLanguage({}, 'ja_JP');
  assert.ok(jaPack.search && jaPack.search.length > 0);

  const zhPack = dataTablesLanguage({}, 'zh-CN');
  assert.ok(zhPack.search && zhPack.search.length > 0);

  const faPack = dataTablesLanguage({}, 'fa-IR');
  assert.ok(faPack.search && faPack.search.length > 0);

  const enPack = dataTablesLanguage({ search: 'Filter:' }, 'en-CA');
  assert.deepEqual(enPack, { search: 'Filter:' });

  resetI18nCatalog();
});
