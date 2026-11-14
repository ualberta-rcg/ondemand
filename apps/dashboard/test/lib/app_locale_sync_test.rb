# frozen_string_literal: true

require 'test_helper'

class AppLocaleSyncTest < ActiveSupport::TestCase
  setup do
    OodAppkit.stubs(:clusters).returns(OodCore::Clusters.load_file('test/fixtures/config/clusters.d'))
  end

  test 'extracts app manifest and form YAML, preserves manual edits, and translates numeric/string options' do
    Dir.mktmpdir do |dir|
      File.write(
        File.join(dir, 'manifest.yml'),
        <<~YAML
          ---
          name: Sample Solver
          description: Launch an interactive solver session.
          category: Interactive Apps
        YAML
      )
      File.write(
        File.join(dir, 'form.yml'),
        <<~YAML
          ---
          title: Sample Solver
          cluster: '*'
          form:
            - bc_num_hours
            - mem_gb
          attributes:
            secret_token:
              widget: hidden_field
              value: "xyz"
            bc_num_hours:
              widget: number_field
              label: Number of hours
              help: Maximum runtime in hours.
            mem_gb:
              widget: select
              label: Memory
              options:
                - ["2 GB", "2"]
                - ["16 GB", "16"]
        YAML
      )

      locales_dir = File.join(dir, 'locales')
      Dir.mkdir(locales_dir)
      File.write(
        File.join(locales_dir, 'fr-CA.yml'),
        YAML.dump('fr-CA' => { 'manifest' => { 'description' => 'Description manuelle conservée.' } })
      )

      converter = OodLocaleConverter.new(
        google_api_key: '',
        translate_url:  '',
        translator:     ->(txt, loc, _src) { "[#{loc}] #{txt}" }
      )
      sync = AppLocaleSync.new(converter: converter)
      sync.sync_app(dir, locales: %w[en fr-CA])

      fr_data = YAML.safe_load(File.read(File.join(locales_dir, 'fr-CA.yml')))['fr-CA']
      # Manual translation preserved
      assert_equal 'Description manuelle conservée.', fr_data.dig('manifest', 'description')
      # Hidden field excluded
      assert_nil fr_data.dig('form', 'attributes', 'secret_token')
      # Standard OOD dictionary used for bc_num_hours label; converter used for custom help & options
      assert_equal I18n.t('dashboard.smart_attributes.num_hours', locale: :'fr-CA'),
                   fr_data.dig('form', 'attributes', 'bc_num_hours', 'label')
      assert_equal '[fr-CA] Maximum runtime in hours.',
                   fr_data.dig('form', 'attributes', 'bc_num_hours', 'help')
      assert_equal '[fr-CA] 2 GB',
                   fr_data.dig('form', 'attributes', 'mem_gb', 'options', '2')

      # Verify BatchConnect::App resolves numeric-string option keys in fr-CA
      I18n.with_locale(:'fr-CA') do
        app = BatchConnect::App.new(router: PathRouter.new(dir))
        mem_attr = app.attributes.find { |a| a.id == 'mem_gb' }
        assert_equal ['[fr-CA] 2 GB', '2'], mem_attr.select_choices.first
      end
    end
  end

  test 'sync_motd writes sibling file once and skips unchanged source via sha256 marker' do
    Dir.mktmpdir do |dir|
      motd = File.join(dir, 'motd')
      File.write(motd, 'System ready.')

      call_count = 0
      converter = OodLocaleConverter.new(
        google_api_key: '',
        translate_url:  '',
        translator:     lambda do |txt, _loc, _src|
          call_count += 1
          "Système prêt : #{txt}"
        end
      )
      sync = AppLocaleSync.new(converter: converter)

      written1 = sync.sync_motd(motd, locales: %w[en-CA fr-CA], format: 'markdown')
      assert_equal [File.join(dir, 'motd.fr-CA')], written1
      assert_equal 1, call_count
      assert_equal 'Système prêt : System ready.', File.read(File.join(dir, 'motd.fr-CA'))

      # Second run with identical source skips re-translation
      written2 = sync.sync_motd(motd, locales: %w[en-CA fr-CA], format: 'markdown')
      assert_empty written2
      assert_equal 1, call_count

      # Updating English MOTD triggers update
      File.write(motd, 'Maintenance tonight.')
      written3 = sync.sync_motd(motd, locales: %w[en-CA fr-CA], format: 'markdown')
      assert_equal [File.join(dir, 'motd.fr-CA')], written3
      assert_equal 2, call_count
    end
  end
end
