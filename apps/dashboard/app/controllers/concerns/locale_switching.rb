# frozen_string_literal: true

# Per-request locale resolution and same-origin `ood_locale` cookie sync.
module LocaleSwitching
  extend ActiveSupport::Concern

  private

  def switch_locale(&action)
    saved_locale = @user_configuration&.user_settings&.dig(:locale)
    resolved = OodLocale.resolve(
      user_locale:     saved_locale,
      cookie_locale:   cookies[OodLocale::COOKIE_KEY],
      accept_language: request.headers['Accept-Language']
    )
    sync_locale_cookie(resolved, persistent: saved_locale.present?)
    I18n.with_locale(resolved, &action)
  rescue I18n::InvalidLocale => e
    logger.warn "I18n::InvalidLocale #{resolved}: #{e.message}"
    I18n.with_locale(I18n.default_locale, &action)
  end

  def sync_locale_cookie(locale, persistent: false)
    cookies[OodLocale::COOKIE_KEY] = OodLocale.cookie_options(
      locale,
      ssl:        request.ssl?,
      persistent: persistent
    )
  end
end
