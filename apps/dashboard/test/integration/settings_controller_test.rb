# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # lot's of setup here to get a valid csrf-token
    get root_path
    assert :success

    doc = Nokogiri::XML(@response.body)
    @token = doc.xpath("/html/head/meta[@name='csrf-token']/@content").to_s
    @headers = { 'X-CSRF-Token' => @token }
  end

  test 'should save and override profile settings when posting profile' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { settings: {} }

      data[:settings][:profile] = 'first_profile'
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_equal 'first_profile', TestUserSettings.new.user_settings[:profile]

      data[:settings][:profile] = 'override_profile'
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_equal 'override_profile', TestUserSettings.new.user_settings[:profile]
    end
  end

  test 'should allow empty or nil profile settings when posting profile' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { settings: {} }

      data[:settings][:profile] = ''
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_equal '', TestUserSettings.new.user_settings[:profile]

      data[:settings][:profile] = nil
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_nil TestUserSettings.new.user_settings[:profile]
    end
  end

  test 'should save announcement settings and allow multiple announcements when posting announcement' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { settings: {} }

      value =  Time.now.localtime.strftime('%Y-%m-%d %H:%M:%S')
      data[:settings] = { announcements: { 'announcement_id' => value } }
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_equal value, TestUserSettings.new.user_settings[:announcements][:announcement_id]

      data[:settings] = { announcements: { 'other_announcement_id' => value } }
      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_equal value, TestUserSettings.new.user_settings[:announcements][:announcement_id]
      assert_equal value, TestUserSettings.new.user_settings[:announcements][:other_announcement_id]
    end
  end

  test 'should not save user_settings when no data' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { settings: {} }

      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_empty TestUserSettings.new.user_settings
    end
  end

  test 'should not save user_settings when parameters are outside the settings namespace' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { profile: 'root_value' }

      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_empty TestUserSettings.new.user_settings
    end
  end

  test 'should not save user_settings when parameters are not in the allowed list' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      data = { settings: { not_allowed: 'root_value' } }

      post settings_path, params: data, headers: @headers
      assert_response :redirect
      assert_equal I18n.t('dashboard.settings_updated'), flash[:notice]
      assert_empty TestUserSettings.new.user_settings
    end
  end

    test 'should redirect to referrer if back param is true' do
      Dir.mktmpdir do |temp_data_dir|
        Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
        data = { settings: {}, back: 'true' }
        referrer_url = '/some-previous-page'

        post settings_path, params: data, headers: @headers.merge('HTTP_REFERER' => referrer_url)

        assert_response :redirect
        assert_redirected_to referrer_url
      end
    end

  test 'should save valid locale, update ood_locale cookie, and translate flash in new locale' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      Configuration.stubs(:supported_locales).returns([:en, :'fr-CA', :ja_JP, :'zh-CN'])

      post settings_path,
           params:  { settings: { locale: 'fr-CA' }, back: 'true' },
           headers: @headers.merge('HTTP_REFERER' => '/apps/show/activejobs')

      assert_response :redirect
      assert_redirected_to '/apps/show/activejobs'
      assert_equal I18n.t('dashboard.settings_updated', locale: :'fr-CA'), flash[:notice]
      assert_equal 'fr-CA', TestUserSettings.new.user_settings[:locale]
      assert_equal 'fr-CA', cookies['ood_locale']
      assert_equal :en, I18n.locale

      post settings_path, params: { settings: { locale: 'ja-JP' } }, headers: @headers
      assert_equal 'ja_JP', TestUserSettings.new.user_settings[:locale]
      assert_equal 'ja-JP', cookies['ood_locale']
    end
  end

  test 'should reject invalid and gem-only locales when saving settings' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      Configuration.stubs(:supported_locales).returns([:en, :'fr-CA'])

      post settings_path, params: { settings: { locale: 'klingon' } }, headers: @headers
      assert_response :redirect
      assert_nil TestUserSettings.new.user_settings[:locale]

      # 'de' is contributed by dotiw gem without dashboard translations
      post settings_path, params: { settings: { locale: 'de' } }, headers: @headers
      assert_response :redirect
      assert_nil TestUserSettings.new.user_settings[:locale]
    end
  end

  test 'should apply saved locale on subsequent requests without leaking I18n.locale' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      Configuration.stubs(:supported_locales).returns([:en, :'zh-CN'])
      TestUserSettings.new.update_user_settings(locale: 'zh-CN')

      get root_path
      assert_response :success
      assert_match(/<html lang="zh-CN">/, @response.body)
      assert_equal 'zh-CN', cookies['ood_locale']
      assert_equal :en, I18n.locale
    end
  end

  test 'should negotiate Accept-Language when multiple locales are supported and no preference is saved' do
    Dir.mktmpdir do |temp_data_dir|
      Configuration.stubs(:user_settings_file).returns("#{temp_data_dir}/settings.yml")
      Configuration.stubs(:supported_locales).returns([:en, :'en-CA', :'fr-CA'])
      cookies.delete('ood_locale')

      get root_path, headers: { 'Accept-Language' => 'fr-CA,fr;q=0.9,en;q=0.8' }
      assert_response :success
      assert_match(/<html lang="fr-CA">/, @response.body)
      assert_equal 'fr-CA', cookies['ood_locale']
    end
  end

  test 'locale switcher is hidden by default and rendered with back=true when multiple locales are supported' do
    Configuration.stubs(:supported_locales).returns([:en])
    get root_path
    assert_response :success
    refute_match(/id="locale-switcher"/, @response.body)

    Configuration.stubs(:supported_locales).returns([:en, :de, :'en-CA', :'fr-CA', :ja_JP])
    get root_path
    assert_response :success
    assert_match(/id="locale-switcher"/, @response.body)
    assert_match(/back=true/, @response.body)

    locale_links = @response.body.scan(/settings%5Blocale%5D=([a-zA-Z_\-]+)/).flatten
    assert_equal %w[en en-CA fr-CA ja_JP], locale_links.sort
    refute_includes locale_links, 'de'
    assert_match(/locale-dropdown-menu/, @response.body)
    assert_match(/<span>EN-CA<\/span>/, @response.body)
    assert_match(/<span>FR-CA<\/span>/, @response.body)
    assert_match(/<span>JA-JP<\/span>/, @response.body)
    assert_match(/title="Français \(Canada\)"/, @response.body)
  end

  class TestUserSettings
    include UserSettingStore
  end
end
