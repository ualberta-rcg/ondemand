# frozen_string_literal: true

namespace :ood do
  namespace :locales do
    desc 'Extract and sync <app>/locales/<locale>.yml catalogs for OOD apps (saves static files on disk)'
    task :sync_apps, [:apps_dir, :locales] => :environment do |_t, args|
      apps_dir = args[:apps_dir].presence || '/var/www/ood/apps/sys'
      locales  = if args[:locales].present?
                   args[:locales].split(/[,\s:|]+/).reject(&:empty?)
                 elsif defined?(OodLocale)
                   OodLocale.supported_locales.map(&:to_s)
                 else
                   I18n.available_locales.map(&:to_s)
                 end

      written = AppLocaleSync.new.sync_apps(apps_dir, locales: locales)
      puts "Synced app locale files (#{written.flatten.size}):"
      written.flatten.each { |f| puts "  - #{f}" }
    end

    desc 'Generate per-language motd.<locale> files alongside MOTD_PATH across all OOD MOTD formats'
    task :sync_motd, [:motd_path, :locales, :format] => :environment do |_t, args|
      motd_path = args[:motd_path].presence || ENV['MOTD_PATH']
      format    = args[:format].presence || ENV['MOTD_FORMAT']
      locales   = if args[:locales].present?
                    args[:locales].split(/[,\s:|]+/).reject(&:empty?)
                  elsif defined?(OodLocale)
                    OodLocale.supported_locales.map(&:to_s)
                  else
                    I18n.available_locales.map(&:to_s)
                  end

      written = AppLocaleSync.new.sync_motd(motd_path, locales: locales, format: format)
      puts "Synced MOTD locale files (#{written.size}):"
      written.each { |f| puts "  - #{f}" }
    end
  end
end
