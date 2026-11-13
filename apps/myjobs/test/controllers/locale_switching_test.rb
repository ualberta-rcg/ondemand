# frozen_string_literal: true

require 'test_helper'

class LocaleSwitchingTest < ActionController::TestCase
  tests WorkflowsController

  test 'partial locales fall back cleanly to English without missing translations' do
    I18n.with_locale(:'zh-CN') do
      assert_equal 'Skip Navigation', I18n.t('jobcomposer.skip_navigation')
      assert_equal '集群', I18n.t('jobcomposer.options_cluster_title')
    end

    I18n.with_locale(:'fa-IR') do
      assert_equal 'Job Composer', I18n.t('jobcomposer.title')
      assert_equal 'کلاستر', I18n.t('jobcomposer.options_cluster_title')
    end
  end

  test 'resolves locale from user settings.yml first and sets ood_locale cookie' do
    Dir.mktmpdir do |dir|
      settings_path = File.join(dir, 'settings.yml')
      File.write(settings_path, { 'locale' => 'fr-CA' }.to_yaml)

      with_modified_env(OOD_USER_SETTINGS_FILE: settings_path) do
        @request.headers['Accept-Language'] = 'en-US,en;q=0.9'
        get :index
        assert_response :success
        assert_select 'html[lang=?]', 'fr-CA'
        assert_select 'a', text: 'Compositeur de tâches'
        assert_select 'h2', text: 'Tâches'
        assert_equal 'fr-CA', cookies['ood_locale']
      end
    end
  end

  test 'resolves locale from ood_locale cookie when settings.yml has no locale' do
    @request.cookies['ood_locale'] = 'fr-CA'
    get :index
    assert_response :success
    assert_select 'html[lang=?]', 'fr-CA'
    assert_select 'a', text: 'Modèles'
  end

  test 'negotiates Accept-Language against supported_locales' do
    with_modified_env(OOD_SUPPORTED_LOCALES: 'en,en-CA,fr-CA') do
      @request.headers['Accept-Language'] = 'fr-FR,fr;q=0.9,en;q=0.8'
      get :new
      assert_response :success
      assert_select 'html[lang=?]', 'fr-CA'
      assert_equal 'fr-CA', cookies['ood_locale']
    end
  end

  test 'ConfigurationSingleton reads locale and supported_locales from ondemand.d when configured' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'i18n.yml'), {
        'locale'            => 'fr-CA',
        'supported_locales' => %w[en fr-CA]
      }.to_yaml)

      with_modified_env(OOD_CONFIG_D_DIRECTORY: dir, OOD_LOCALE: nil, OOD_SUPPORTED_LOCALES: nil) do
        cfg = ConfigurationSingleton.new
        assert_equal :'fr-CA', cfg.locale
        assert_equal %w[en fr-CA], cfg.supported_locales
      end
    end
  end
end
