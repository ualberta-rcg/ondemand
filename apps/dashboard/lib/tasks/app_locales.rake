# frozen_string_literal: true

namespace :ood do
  namespace :locales do
    desc 'Extract and sync <app>/locales/<locale>.yml catalogs for OOD apps (saves static files on disk)'
    task :sync_apps, [:apps_dir, :locales] => :environment do |_t, args|
      apps_dir    = args[:apps_dir].presence || ENV['APPS_DIR'].presence || '/var/www/ood/apps/sys'
      raw_locales = args[:locales].presence || ENV['LOCALES'].presence
      locales     = if raw_locales.present?
                      raw_locales.split(/[,\s:|]+/).reject(&:empty?)
                    elsif defined?(OodLocale)
                      OodLocale.supported_locales.map(&:to_s)
                    else
                      I18n.available_locales.map(&:to_s)
                    end

      overwrite = ActiveModel::Type::Boolean.new.cast(ENV['OVERWRITE']) || false
      written = AppLocaleSync.new.sync_apps(apps_dir, locales: locales, overwrite: overwrite)
      puts "Synced app locale files (#{written.flatten.size}):"
      written.flatten.each { |f| puts "  - #{f}" }
    end

    desc 'Generate per-language motd.<locale> files alongside MOTD_PATH across all OOD MOTD formats'
    task :sync_motd, [:motd_path, :locales, :format] => :environment do |_t, args|
      motd_path   = args[:motd_path].presence || ENV['MOTD_PATH']
      format      = args[:format].presence || ENV['MOTD_FORMAT']
      raw_locales = args[:locales].presence || ENV['LOCALES'].presence
      locales     = if raw_locales.present?
                      raw_locales.split(/[,\s:|]+/).reject(&:empty?)
                    elsif defined?(OodLocale)
                      OodLocale.supported_locales.map(&:to_s)
                    else
                      I18n.available_locales.map(&:to_s)
                    end

      force = ActiveModel::Type::Boolean.new.cast(ENV['FORCE']) || false
      converter = OodLocaleConverter.new
      written = AppLocaleSync.new(converter: converter).sync_motd(motd_path, locales: locales, format: format, force: force)
      puts "Synced MOTD locale files (#{written.size}):"
      written.each { |f| puts "  - #{f}" }
      if written.empty? && !converter.available?
        puts '  (Note: set OOD_TRANSLATE_URL or GOOGLE_TRANSLATE_API_KEY to auto-translate free-form MOTD prose)'
      end
    end
  end
end
