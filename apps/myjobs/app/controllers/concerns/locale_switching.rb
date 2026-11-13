# frozen_string_literal: true

require 'yaml'

# Per-request locale switching for Job Composer following the shared OOD locale contract:
# 1. User's saved locale in ~/.config/ondemand/settings.yml
# 2. Same-origin ood_locale cookie
# 3. Browser Accept-Language negotiation
# 4. Site default (Configuration.locale / I18n.default_locale)
module LocaleSwitching
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  def switch_locale(&action)
    saved_locale = read_user_settings_locale
    locale = OodLocale.resolve(
      user_locale:     saved_locale,
      cookie_locale:   cookies[OodLocale::COOKIE_KEY],
      accept_language: request.headers['Accept-Language']
    )

    publish_locale_cookie(locale, persistent: !saved_locale.nil?)
    I18n.with_locale(locale, &action)
  rescue I18n::InvalidLocale => e
    logger.warn "I18n::InvalidLocale #{locale}: #{e.message}"
    I18n.with_locale(I18n.default_locale, &action)
  end

  private

  def read_user_settings_locale
    path = ::Configuration.user_settings_file
    return nil unless path && path.file? && path.readable?

    data = YAML.safe_load(path.read) || {}
    return nil unless data.is_a?(Hash)

    (data['locale'] || data[:locale])&.to_s
  rescue StandardError => e
    logger.warn "Unable to read user locale from #{path}: #{e.message}"
    nil
  end

  def publish_locale_cookie(locale, persistent: false)
    desired = OodLocale.to_bcp47(locale)
    return if cookies[OodLocale::COOKIE_KEY] == desired && !persistent

    cookies[OodLocale::COOKIE_KEY] = OodLocale.cookie_options(
      locale,
      ssl:        request.ssl?,
      persistent: persistent
    )
  end
end
