# frozen_string_literal: true

# Helper for app permission pages.
module PermissionsHelper
  def permissions_title(context)
    case context
    when :user
      I18n.t('dashboard.permissions_user_title')
    when :group
      I18n.t('dashboard.permissions_group_title')
    else
      I18n.t('dashboard.undefined_title')
    end
  end
end
