# frozen_string_literal: true

require 'test_helper'

class OodLocaleConverterTest < ActiveSupport::TestCase
  setup do
    @calls = []
    @converter = OodLocaleConverter.new(
      google_api_key: '',
      translate_url:  '',
      translator:     lambda do |text, target, _source|
        @calls << [text, target]
        "[#{target}] #{text}"
      end
    )
  end

  test 'protects ERB tags, fenced/inline code, HTML, interpolations, and Markdown link URLs' do
    src = <<~MD
      Welcome %{user} to `sbatch --gpus=1`!
      <% if Time.now %>Hello <%= CurrentUser.name %><% end %>
      See [Support Portal](https://docs.example.org/help) and <strong>notice</strong>.
      ```bash
      module load python/3.11
      ```
    MD

    out = @converter.convert_motd(src, target_locale: 'fr-CA', format: 'markdown_erb')

    assert_includes out, '%{user}'
    assert_includes out, '`sbatch --gpus=1`'
    assert_includes out, '<% if Time.now %>'
    assert_includes out, '<%= CurrentUser.name %>'
    assert_includes out, '[fr-CA] Support Portal'
    assert_includes out, '(https://docs.example.org/help)'
    assert_includes out, '<strong>'
    assert_includes out, "```bash\nmodule load python/3.11\n```"
  end

  test 'preserves OSC MOTD delimiters and date headers so MotdFormatter::Osc parses cleanly' do
    osc_src = <<~OSC
      2026/11/14
      --- Scheduled Maintenance
      Compute nodes will be offline at 08:00.
      ******
      2026/11/01
      --- New Storage Available
      Scratch quota increased.
    OSC

    converted = @converter.convert_motd(osc_src, target_locale: 'fr-CA', format: 'osc')

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'motd.fr-CA')
      File.write(path, converted)
      with_modified_env({ 'MOTD_FORMAT' => 'osc' }) do
        formatter = MotdFile.new(path, locale: :'fr-CA').formatter
        assert_instance_of MotdFormatter::Osc, formatter
        assert_equal 2, formatter.messages.size
        assert_equal '[fr-CA] Scheduled Maintenance', formatter.messages.first.title
        assert_match(/\[fr-CA\] Compute nodes/, formatter.messages.first.body)
      end
    end
  end

  test 'preserves RSS XML structure and links so MotdFormatter::Rss parses cleanly' do
    rss_src = <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0">
        <channel>
          <title>System Status</title>
          <link>https://status.example.org</link>
          <description>Cluster updates</description>
          <item>
            <title>GPU Upgrade</title>
            <link>https://status.example.org/1</link>
            <description><![CDATA[Added 4 nodes &amp; interconnects]]></description>
          </item>
        </channel>
      </rss>
    XML

    converted = @converter.convert_motd(rss_src, target_locale: 'fr-CA', format: 'rss')

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'motd.fr-CA.rss')
      File.write(path, converted)
      with_modified_env({ 'MOTD_FORMAT' => 'rss' }) do
        formatter = MotdFile.new(path, locale: :'fr-CA').formatter
        assert_instance_of MotdFormatter::Rss, formatter
        assert_equal '[fr-CA] System Status', formatter.content.channel.title
        assert_equal 'https://status.example.org/1', formatter.content.items.first.link
        assert_equal '[fr-CA] GPU Upgrade', formatter.content.items.first.title
      end
    end
  end
end
