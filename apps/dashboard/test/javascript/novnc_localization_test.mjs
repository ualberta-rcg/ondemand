import assert from 'node:assert/strict';
import test from 'node:test';
import { Localizer } from '../../public/noVNC-1.3.0/app/localization.js';

const SUPPORTED = [
  'cs', 'de', 'el', 'es', 'fr', 'it', 'ja', 'ko',
  'nl', 'pl', 'pt_BR', 'ru', 'sv', 'tr', 'zh_CN', 'zh_TW',
];

function withBrowserEnv({ cookie = '', languages = ['en-US', 'en'] }, fn) {
  const prevWindow = globalThis.window;
  const prevDocument = globalThis.document;
  const prevNavigator = globalThis.navigator;

  const nav = { languages, language: languages[0] || 'en-US' };
  globalThis.window = { navigator: nav };
  globalThis.document = { cookie };
  Object.defineProperty(globalThis, 'navigator', {
    value: nav,
    configurable: true,
    writable: true,
  });

  try {
    fn();
  } finally {
    globalThis.window = prevWindow;
    globalThis.document = prevDocument;
    if (prevNavigator !== undefined) {
      Object.defineProperty(globalThis, 'navigator', {
        value: prevNavigator,
        configurable: true,
        writable: true,
      });
    }
  }
}

test('noVNC Localizer honors ood_locale cookie over navigator.languages', () => {
  withBrowserEnv({ cookie: 'other=1; ood_locale=fr-CA', languages: ['en-US', 'en'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'fr');
  });

  withBrowserEnv({ cookie: 'ood_locale=ja-JP', languages: ['en-US'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'ja');
  });

  withBrowserEnv({ cookie: 'ood_locale=zh-CN', languages: ['en-US'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'zh_CN');
  });
});

test('noVNC Localizer keeps English for en-CA even when secondary browser language is French', () => {
  withBrowserEnv({ cookie: 'ood_locale=en-CA', languages: ['en-CA', 'fr-CA'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'en');
  });
});

test('noVNC Localizer falls back to browser language or English when ood_locale is absent or unsupported', () => {
  withBrowserEnv({ cookie: '', languages: ['fr-CA', 'en'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'fr');
  });

  withBrowserEnv({ cookie: 'ood_locale=fa-IR', languages: ['en-US'] }, () => {
    const loc = new Localizer();
    loc.setup(SUPPORTED);
    assert.equal(loc.language, 'en');
  });
});
