# frozen_string_literal: true

require 'test_helper'

class OodLocaleTest < ActiveSupport::TestCase
  test 'to_bcp47 converts underscore and mixed-case tags to canonical BCP 47' do
    assert_equal 'en', OodLocale.to_bcp47(:en)
    assert_equal 'ja-JP', OodLocale.to_bcp47(:ja_JP)
    assert_equal 'ja-JP', OodLocale.to_bcp47('ja_jp')
    assert_equal 'fr-CA', OodLocale.to_bcp47('fr_ca')
    assert_equal 'zh-CN', OodLocale.to_bcp47(:'zh-CN')
    assert_equal 'zh-Hans-CN', OodLocale.to_bcp47('zh_hans_cn')
    assert_equal 'en', OodLocale.to_bcp47('')
  end

  test 'normalize matches locale codes and file paths case- and separator-insensitively' do
    allowed = [:en, :'en-CA', :'fr-CA', :ja_JP, :'zh-CN']

    assert_equal :ja_JP, OodLocale.normalize('ja-JP', allowed: allowed)
    assert_equal :ja_JP, OodLocale.normalize('ja_JP', allowed: allowed)
    assert_equal :'fr-CA', OodLocale.normalize('fr_ca', allowed: allowed)
    assert_equal :'fr-CA', OodLocale.normalize('/etc/ood/config/locales/fr-CA.yml', allowed: allowed)
    assert_equal :'en-CA', OodLocale.normalize('/custom/en_ca.rb', allowed: allowed)
    assert_nil OodLocale.normalize('de-DE', allowed: allowed)
    assert_nil OodLocale.normalize('', allowed: allowed)
    assert_nil OodLocale.normalize(nil, allowed: allowed)
  end

  test 'negotiate_accept_language honors quality weights, exact match, and language prefix' do
    supported = [:en, :'en-CA', :'fr-CA', :ja_JP]

    assert_equal :'fr-CA', OodLocale.negotiate_accept_language('fr-CA,fr;q=0.9,en;q=0.8', supported: supported)
    assert_equal :'fr-CA', OodLocale.negotiate_accept_language('fr-FR,fr;q=0.9,en;q=0.8', supported: supported)
    assert_equal :ja_JP, OodLocale.negotiate_accept_language('de-DE;q=0.9,ja;q=0.95,en;q=0.8', supported: supported)
    assert_equal :'en-CA', OodLocale.negotiate_accept_language('en-CA;q=0.9,en;q=0.8', supported: supported)
    assert_nil OodLocale.negotiate_accept_language('de-DE,es;q=0.8', supported: supported)
    assert_nil OodLocale.negotiate_accept_language('fr-CA;q=0', supported: supported)
    assert_nil OodLocale.negotiate_accept_language('*', supported: supported)
  end

  test 'BCP 47 alias ja-JP resolves translations from ja_JP locale file' do
    assert_includes I18n.available_locales, :'ja-JP'
    assert_equal I18n.t('dashboard.active_jobs', locale: :ja_JP), I18n.t('dashboard.active_jobs', locale: :'ja-JP')
  end

  test 'dashboard_locales includes shipped OOD locales and excludes gem-only locales' do
    locales = OodLocale.dashboard_locales
    assert_includes locales, :en
    assert_includes locales, :'en-CA'
    assert_includes locales, :'fr-CA'
    assert_includes locales, :ja_JP
    assert_includes locales, :'zh-CN'
    refute_includes locales, :de
  end

  test 'supported_locales filters out unsupported and gem-only locales' do
    Configuration.stubs(:supported_locales).returns([:en, :de, :klingon, :'fr-CA', :'ja-JP'])
    assert_equal [:en, :'fr-CA', :ja_JP], OodLocale.supported_locales
  end

  test 'resolve follows user_locale -> cookie_locale -> accept_language -> default_locale precedence' do
    Configuration.stubs(:locale).returns(:en)
    Configuration.stubs(:supported_locales).returns([:en, :'en-CA', :'fr-CA', :ja_JP])

    assert_equal :ja_JP, OodLocale.resolve(
      user_locale:     'ja-JP',
      cookie_locale:   'fr-CA',
      accept_language: 'en-CA,en;q=0.9'
    )

    assert_equal :'fr-CA', OodLocale.resolve(
      user_locale:     nil,
      cookie_locale:   'fr-CA',
      accept_language: 'en-CA,en;q=0.9'
    )

    assert_equal :'en-CA', OodLocale.resolve(
      user_locale:     nil,
      cookie_locale:   nil,
      accept_language: 'en-CA,en;q=0.9'
    )

    assert_equal :en, OodLocale.resolve(
      user_locale:     'klingon',
      cookie_locale:   'de',
      accept_language: 'es-ES'
    )
  end

  test 'locale_name returns native language name without English fallback' do
    assert_equal 'English', OodLocale.locale_name(:en)
    assert_equal 'Français (Canada)', OodLocale.locale_name(:'fr-CA')
    assert_equal '日本語', OodLocale.locale_name(:ja_JP)
  end
end
