# frozen_string_literal: true

require 'test_helper'

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test 'should get not_found resource' do
    get '/404'
    assert_response :success
  end

  test 'should get internal_server_error resource' do
    get '/500'
    assert_response :success
  end

  test 'should render localized unprocessable_entity page on GET and unverified POST' do
    get '/422'
    assert_response :success

    get '/errors/unprocessable_entity'
    assert_response :unprocessable_entity
    assert_includes @response.body, I18n.t('dashboard.settings_unprocessable_title')

    Configuration.stubs(:supported_locales).returns([:en, :'fr-CA'])
    cookies.delete('ood_locale')
    post '/422',
         headers: { 'X-CSRF-Token' => 'expired-token', 'Accept-Language' => 'fr-CA' }
    assert_response :unprocessable_entity
    assert_includes @response.body, I18n.t('dashboard.settings_unprocessable_title', locale: :'fr-CA')
  end
end
