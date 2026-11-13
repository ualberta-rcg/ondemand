# frozen_string_literal: true

require 'test_helper'

class DashboardErbI18nTest < ActionView::TestCase
  include ApplicationHelper
  include BatchConnect::SessionsHelper
  include FilesHelper
  include PermissionsHelper
  include ProductsHelper
  include SystemStatusHelper

  test 'status_text localizes job status labels in fr-CA' do
    I18n.with_locale(:'fr-CA') do
      assert_equal I18n.t('dashboard.status_running'), status_text('running')
      assert_equal I18n.t('dashboard.status_queued'), status_text('queued')
      assert_equal I18n.t('dashboard.status_completed'), status_text('completed')
      assert_equal I18n.t('dashboard.status_undetermined'), status_text('unknown_state')
    end
  end

  test 'permissions_title localizes user and group titles in fr-CA' do
    I18n.with_locale(:'fr-CA') do
      assert_equal 'Autorisations d\'utilisateur', permissions_title(:user)
      assert_equal 'Autorisations de groupe', permissions_title(:group)
      assert_equal 'Titre non défini', permissions_title(:other)
    end
  end

  test 'SystemStatusHelper localizes cluster status strings in fr-CA' do
    cluster = stub(title: 'Eureka')
    adapter = Object.new
    I18n.with_locale(:'fr-CA') do
      assert_equal 'État de la grappe Eureka', title(cluster)
      res = not_slurm_hash(adapter)
      assert_includes res[:message], 'Object'
      assert_includes res[:message], 'Slurm'
    end
  end

  test 'all Loop 10 keys resolve cleanly in en, en-CA, and fr-CA without missing translations' do
    keys = %w[
      announcements_parse_error
      announcements_render_error
      batch_connect_active_sessions_aria
      batch_connect_app_version
      batch_connect_sessions_novnc_tab
      breadcrumb_aria
      browser_warning
      editor_key_bindings
      error_internal_title
      error_not_found_title
      favorites
      file_editor
      files_change_directory
      files_copy_move
      files_exceeds_editor_limit
      footer_version
      jobs_project_manager
      jobs_workflow_add_launcher
      loading
      loading_short
      logout_title
      module_browser_showing_results
      nav_main_menu
      permissions_created
      products_created
      select_all
      status_running
      support_ticket_add_attachment
      system_status_nodes
      toggle_push_notifications
    ]

    %i[en en-CA fr-CA].each do |loc|
      I18n.with_locale(loc) do
        keys.each do |k|
          val = I18n.t("dashboard.#{k}", name: 'test', version: '4.1', path: '/tmp/a', limit: '5 MB', count: 3, raise: true)
          assert val.present?, "Expected dashboard.#{k} to be present for #{loc}"
        end
      end
    end
  end
end
