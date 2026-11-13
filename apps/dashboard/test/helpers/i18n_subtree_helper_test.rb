# frozen_string_literal: true

require 'test_helper'

class I18nSubtreeHelperTest < ActionView::TestCase
  include I18nSubtreeHelper

  test 'i18n_deep_subtree returns full English hash when locale is en' do
    subtree = i18n_deep_subtree('dashboard.uppy', locale: :en)
    assert_kind_of Hash, subtree
    assert_equal 'Cancel', subtree.dig('strings', 'cancel')
    assert_equal 'Upload complete', subtree.dig('strings', 'uploadComplete')
  end

  test 'i18n_deep_subtree deep-merges partial locale translations over English defaults' do
    I18n.backend.store_translations(:'es-TEST', {
      dashboard: {
        uppy: {
          strings: {
            cancel: 'Cancelar'
          }
        }
      }
    })
    I18n.available_locales = nil

    subtree = i18n_deep_subtree('dashboard.uppy', locale: :'es-TEST')
    assert_equal 'Cancelar', subtree.dig('strings', 'cancel')
    assert_equal 'Upload complete', subtree.dig('strings', 'uploadComplete')
  end

  test 'i18n_deep_subtree safely ignores corrupted scalar values in locale overrides' do
    I18n.backend.store_translations(:'de-TEST', {
      dashboard: {
        uppy: 'Uppy'
      }
    })
    I18n.available_locales = nil

    subtree = i18n_deep_subtree('dashboard.uppy', locale: :'de-TEST')
    assert_kind_of Hash, subtree
    assert_equal 'Cancel', subtree.dig('strings', 'cancel')
  end

  test 'i18n_deep_subtree returns French Canadian Uppy strings for fr-CA' do
    subtree = i18n_deep_subtree('dashboard.uppy', locale: :'fr-CA')
    assert_equal 'Annuler', subtree.dig('strings', 'cancel')
    assert_equal 'Téléverser', subtree.dig('strings', 'upload')
  end
end
