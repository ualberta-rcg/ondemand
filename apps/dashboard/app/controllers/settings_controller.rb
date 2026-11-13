# frozen_string_literal: true

# The Controller for user level settings /dashboard/settings.
# Current supported settings: profile, locale, announcements
class SettingsController < ApplicationController
  include UserSettingStore
  ALLOWED_SETTINGS = [:profile, :locale, { announcements: {} }].freeze

  def update
    new_settings = sanitize_settings(read_settings(settings_param))
    update_user_settings(new_settings) unless new_settings.empty?
    apply_locale_setting(new_settings[:locale]) if new_settings.key?(:locale)

    logger.info "settings: updated user settings to: #{new_settings}"
    respond_to do |format|
      format.html do
        if back_param == 'true'
          redirect_back allow_other_host: false, fallback_location: root_url, notice: I18n.t('dashboard.settings_updated')
        else
          redirect_to root_url, notice: I18n.t('dashboard.settings_updated')
        end
      end
      format.json { head :no_content }
    end
  end

  private

  def settings_param
    params.require(:settings).permit(ALLOWED_SETTINGS) if params[:settings].present?
  end

  def back_param
    params.permit(:back)[:back]
  end

  def read_settings(params)
    params.to_h
  end

  # Only persist a locale that is in the admin-configured supported_locales list.
  def sanitize_settings(settings)
    return settings unless settings.key?(:locale)

    normalized = OodLocale.normalize(settings[:locale], allowed: OodLocale.supported_locales)
    if normalized
      settings[:locale] = normalized.to_s
    else
      settings.delete(:locale)
    end
    settings
  end

  # Switch the active locale and cookie immediately so the flash notice and
  # response cookies reflect the newly saved language on this response.
  def apply_locale_setting(locale)
    normalized = locale.to_sym
    I18n.locale = normalized
    sync_locale_cookie(normalized, persistent: true)
  rescue I18n::InvalidLocale => e
    logger.warn "I18n::InvalidLocale #{locale}: #{e.message}"
  end
end
